[CmdletBinding()]
param(
    [Parameter()]
    [string]$DatabasePath = '.\.testoutputs\sqlite-bad.db',

    [Parameter()]
    [string]$OutputPath = '.\.testoutputs\TagMatrix-sample.xlsx',

    [Parameter()]
    [ValidateSet('Access', 'SQLite')]
    [string]$Provider = 'SQLite',

    [Parameter()]
    [string[]]$Tags,

    [Parameter()]
    [switch]$UseFQDN
)

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $repoRoot

Import-Module .\PSNessusDB\PSNessusDB.psd1 -Force

$exportParams = @{
    DatabasePath = $DatabasePath
    OutputPath   = $OutputPath
    Provider     = $Provider
    Force        = $true
    Verbose      = $true
}

if ($PSBoundParameters.ContainsKey('Tags') -and $Tags.Count -gt 0) {
    $exportParams.Tags = $Tags
}

if ($UseFQDN) {
    $exportParams.UseFQDN = $true
}

Export-PSNessusTagMatrix @exportParams
