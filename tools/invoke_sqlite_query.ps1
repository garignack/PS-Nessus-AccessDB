<#
.SYNOPSIS
Runs a user-supplied SQLite query via the bundled PS-Sqlite module and emits PSCustomObjects.

.DESCRIPTION
Opens the specified SQLite database, executes the provided SQL statement with optional parameters,
and converts the first result set into PSCustomObject instances for easy downstream processing.
Use the companion import script to stage CSV data before running this query helper.

.PARAMETER DatabasePath
Path to the SQLite database file. Defaults to ./.testoutputs/csv-import.db relative to the repo root.

.PARAMETER Query
SQL query text to execute.

.PARAMETER Parameters
Hashtable of parameter values keyed by column/parameter name (without the @ prefix).
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$DatabasePath = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath '.testoutputs/csv-import.db'),

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Query,

    [Parameter()]
    [hashtable]$Parameters
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Convert-DataTableToObject {
    param(
        [Parameter(Mandatory)][System.Data.DataTable]$DataTable
    )

    foreach ($row in $DataTable.Rows) {
        $ordered = [ordered]@{}
        foreach ($column in $DataTable.Columns) {
            $ordered[$column.ColumnName] = $row[$column]
        }
        [PSCustomObject]$ordered
    }
}

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$modulePath = Join-Path -Path $repoRoot -ChildPath 'PSNessusDB/PS-Sqlite.psm1'
if (-not (Test-Path -Path $modulePath)) {
    throw "PS-Sqlite module not found at '$modulePath'."
}

$databaseFullPath = [System.IO.Path]::GetFullPath($DatabasePath)
if (-not (Test-Path -Path $databaseFullPath)) {
    throw "SQLite database not found at '$databaseFullPath'."
}

Write-Verbose ("Querying database '{0}'." -f $databaseFullPath)
Import-Module -Name $modulePath -Force

$connection = Open-PSNessusSqliteConnection -Database $databaseFullPath -AsDefault
try {
    $result = Invoke-PSNessusSqliteQuery -Query $Query -Parameters $Parameters -Connection $connection
    if ($result) {
        Write-Verbose ("Invoke-PSNessusSqliteQuery returned type '{0}'." -f $result.GetType().FullName)
    }
    $firstTable = $null
    if ($result -is [System.Data.DataTable]) {
        $firstTable = $result
    }
    elseif ($result -is [System.Collections.IEnumerable]) {
        foreach ($item in $result) {
            if ($item -is [System.Data.DataTable]) {
                $firstTable = $item
                break
            }
        }
    }

    if (-not $firstTable) {
        Write-Verbose 'Invoke-PSNessusSqliteQuery returned no DataTable.'
        return @()
    }

    if (-not $firstTable.Rows.Count) {
        Write-Verbose 'Query returned no rows.'
        return @()
    }

    Write-Verbose ("Query returned {0} row(s)." -f $firstTable.Rows.Count)
    $objects = Convert-DataTableToObject -DataTable $firstTable
    return $objects
}
finally {
    Close-PSNessusSqliteConnection -Connection $connection
}
