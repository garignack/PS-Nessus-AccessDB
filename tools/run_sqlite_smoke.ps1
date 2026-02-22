<#
.SYNOPSIS
Runs a repeatable SQLite smoke test by importing a sample Nessus export and capturing summary counts.

.DESCRIPTION
This helper aligns with the Roadmap/sqlite-migration.md "Testing & Validation" checklist.
It imports a Nessus file into SQLite, writes logs under .testoutputs/, and emits a summary
table both to the pipeline and to <DatabaseName>-summary.txt for parity comparisons.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateScript({ Test-Path -LiteralPath $_ })]
    [string]$NessusPath = '.testoutputs\Newest_Export.nessus',

    [Parameter()]
    [string]$DatabasePath = '.testoutputs\sqlite-test.db',

    [Parameter()]
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resolvedRepoRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
Set-Location -Path $resolvedRepoRoot

if (-not (Test-Path -LiteralPath $NessusPath)) {
    throw "Nessus export not found at '$NessusPath'. Adjust -NessusPath or place a sample under .testoutputs/."
}

$outputDirectory = Split-Path -Parent $DatabasePath
if ([string]::IsNullOrWhiteSpace($outputDirectory)) {
    $outputDirectory = '.'
}
if (-not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}

if ($Force -and (Test-Path -LiteralPath $DatabasePath)) {
    Remove-Item -LiteralPath $DatabasePath -Force
}

$logPath = [System.IO.Path]::ChangeExtension($DatabasePath, '.log')
if ($Force -and (Test-Path -LiteralPath $logPath)) {
    Remove-Item -LiteralPath $logPath -Force
}

Import-Module (Join-Path $resolvedRepoRoot 'PSNessusDB\PSNessusDB.psd1') -Force
Import-Module (Join-Path $resolvedRepoRoot 'PSNessusDB\PS-Sqlite.psm1') -Force

Import-PSNessusDB -FullName $NessusPath `
                  -DatabasePath $DatabasePath `
                  -Provider SQLite `
                  -NewDb `
                  -LogFileName $logPath `
                  -Verbose

$summaryTables = @('Files', 'Hosts', 'HostEnumeratedPorts', 'HostTags', 'PluginInfo', 'ReportItem')
$sqliteConnection = Open-PSNessusSqliteConnection -Database (Resolve-Path -LiteralPath $DatabasePath).ProviderPath -AsDefault
try {
    $summaryRows = foreach ($table in $summaryTables) {
        $count = Invoke-PSNessusSqliteScalar -Query "SELECT COUNT(*) FROM [$table];" -Connection $sqliteConnection
        [pscustomobject]@{ Table = $table; Count = [int]$count }
    }
}
finally {
    Close-PSNessusSqliteConnection -Connection $sqliteConnection
}

$summaryFileName = [System.IO.Path]::Combine(
    (Resolve-Path -LiteralPath $outputDirectory).ProviderPath,
    "{0}-summary.txt" -f ([System.IO.Path]::GetFileNameWithoutExtension($DatabasePath))
)

$summaryLines = @(
    ('{0,-22} {1,5}' -f 'Table', 'Count'),
    ('{0,-22} {1,5}' -f '-----', '-----')
)
$summaryLines += $summaryRows | ForEach-Object { '{0,-22} {1,5}' -f $_.Table, $_.Count }
Set-Content -LiteralPath $summaryFileName -Value $summaryLines -Encoding ASCII

$summaryRows
