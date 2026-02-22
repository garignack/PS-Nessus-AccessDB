<#
.SYNOPSIS
Runs a regression test for malformed/blank host tags during SQLite import.

.DESCRIPTION
Builds a temporary Nessus fixture containing a blank tag entry, imports it with
Import-PSNessusDB, and verifies the import completes (no terminating error) and
basic row counts are present in the output database.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateScript({ Test-Path -LiteralPath $_ })]
    [string]$SourceNessusPath = '.testoutputs\Newest_Export.nessus',

    [Parameter()]
    [string]$BadNessusPath = '.testoutputs\bad_export.regression.nessus',

    [Parameter()]
    [string]$DatabasePath = '.testoutputs\sqlite-bad-host-regression.db',

    [Parameter()]
    [switch]$UseExistingBadExport,

    [Parameter()]
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resolvedRepoRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
Set-Location -Path $resolvedRepoRoot

$resolvedSourceNessusPath = (Resolve-Path -LiteralPath $SourceNessusPath).ProviderPath
$resolvedBadNessusPath = [System.IO.Path]::GetFullPath($BadNessusPath)
$resolvedDatabasePath = [System.IO.Path]::GetFullPath($DatabasePath)
$resolvedBadDirectory = Split-Path -Path $resolvedBadNessusPath -Parent
$resolvedDatabaseDirectory = Split-Path -Path $resolvedDatabasePath -Parent

if ($resolvedBadDirectory -and -not (Test-Path -LiteralPath $resolvedBadDirectory)) {
    New-Item -ItemType Directory -Path $resolvedBadDirectory -Force | Out-Null
}

if ($resolvedDatabaseDirectory -and -not (Test-Path -LiteralPath $resolvedDatabaseDirectory)) {
    New-Item -ItemType Directory -Path $resolvedDatabaseDirectory -Force | Out-Null
}

if ($Force -and (Test-Path -LiteralPath $resolvedDatabasePath)) {
    Remove-Item -LiteralPath $resolvedDatabasePath -Force
}

$logPath = [System.IO.Path]::ChangeExtension($resolvedDatabasePath, '.log')
if ($Force -and (Test-Path -LiteralPath $logPath)) {
    Remove-Item -LiteralPath $logPath -Force
}

if ($UseExistingBadExport) {
    if (-not (Test-Path -LiteralPath $resolvedBadNessusPath)) {
        throw "UseExistingBadExport was specified, but '$resolvedBadNessusPath' does not exist."
    }
}
else {
    $rawNessus = Get-Content -LiteralPath $resolvedSourceNessusPath -Raw

    if ($rawNessus -match '<tag\s+name="Blank_TAG"\s*>\s*</tag>') {
        Set-Content -LiteralPath $resolvedBadNessusPath -Value $rawNessus -Encoding UTF8
    }
    else {
        $hostPropertiesClose = '</HostProperties>'
        $insertIndex = $rawNessus.IndexOf($hostPropertiesClose)
        if ($insertIndex -lt 0) {
            throw "Unable to inject Blank_TAG into '$resolvedSourceNessusPath'. Expected </HostProperties> marker not found."
        }

        $insertText = "    <tag name=""Blank_TAG""></tag>`r`n"
        $insertedNessus = $rawNessus.Substring(0, $insertIndex) + $insertText + $rawNessus.Substring($insertIndex)
        Set-Content -LiteralPath $resolvedBadNessusPath -Value $insertedNessus -Encoding UTF8
    }
}

$badNessusRaw = Get-Content -LiteralPath $resolvedBadNessusPath -Raw
$expectedHostCount = [regex]::Matches($badNessusRaw, '<ReportHost\s+').Count
if ($expectedHostCount -le 0) {
    throw "Regression input '$resolvedBadNessusPath' does not contain any ReportHost entries."
}

Import-Module (Join-Path $resolvedRepoRoot 'PSNessusDB\PSNessusDB.psd1') -Force
Import-Module (Join-Path $resolvedRepoRoot 'PSNessusDB\PS-Sqlite.psm1') -Force

try {
    Import-PSNessusDB -FullName $resolvedBadNessusPath `
                      -DatabasePath $resolvedDatabasePath `
                      -Provider SQLite `
                      -NewDb `
                      -LogFileName $logPath `
                      -Verbose
}
catch {
    throw "Regression FAILED: import terminated for malformed-tag input '$resolvedBadNessusPath'. $_"
}

if (-not (Test-Path -LiteralPath $resolvedDatabasePath)) {
    throw "Regression FAILED: expected output database '$resolvedDatabasePath' was not created."
}

$connection = Open-PSNessusSqliteConnection -Database $resolvedDatabasePath -AsDefault
try {
    $fileCount = [int](Invoke-PSNessusSqliteScalar -Query 'SELECT COUNT(*) FROM [Files];' -Connection $connection)
    $hostCount = [int](Invoke-PSNessusSqliteScalar -Query 'SELECT COUNT(*) FROM [Hosts];' -Connection $connection)
    $pluginCount = [int](Invoke-PSNessusSqliteScalar -Query 'SELECT COUNT(*) FROM [PluginInfo];' -Connection $connection)
    $reportItemCount = [int](Invoke-PSNessusSqliteScalar -Query 'SELECT COUNT(*) FROM [ReportItem];' -Connection $connection)
}
finally {
    Close-PSNessusSqliteConnection -Connection $connection
}

if ($fileCount -lt 1) {
    throw "Regression FAILED: Files count is $fileCount (expected at least 1)."
}

if ($hostCount -lt 1) {
    throw "Regression FAILED: Hosts count is $hostCount (expected at least 1)."
}

if ($hostCount -lt $expectedHostCount) {
    throw "Regression FAILED: only $hostCount hosts were imported, expected at least $expectedHostCount from source."
}

if ($pluginCount -lt 1 -or $reportItemCount -lt 1) {
    throw "Regression FAILED: PluginInfo=$pluginCount, ReportItem=$reportItemCount (expected non-zero counts)."
}

[pscustomobject]@{
    Status            = 'PASS'
    RegressionInput   = $resolvedBadNessusPath
    DatabasePath      = $resolvedDatabasePath
    ExpectedHosts     = $expectedHostCount
    ImportedHosts     = $hostCount
    Files             = $fileCount
    PluginInfo        = $pluginCount
    ReportItem        = $reportItemCount
    LogPath           = $logPath
}
