<#
.SYNOPSIS
Imports a CSV file into SQLite via the bundled PS-Sqlite module.

.DESCRIPTION
Creates (or replaces) a table in the specified SQLite database, inserts every row from the CSV
as TEXT columns, and outputs a summary object that details the target database, table name,
row count, and the original-to-sanitized column name map. Use the companion
Invoke-SqliteQuery tool to issue ad-hoc SQL once the data is staged.

.PARAMETER CsvPath
Path to the source CSV file. The first row must contain column headers.

.PARAMETER DatabasePath
Destination SQLite database path. Defaults to ./.testoutputs/csv-import.db relative to the repo root.

.PARAMETER TableName
Name of the table that will be created (and overwritten) with the CSV data.

.PARAMETER Force
When set, overwrite an existing table without prompting.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$CsvPath,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$DatabasePath = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath '.testoutputs/csv-import.db'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$TableName = 'CsvImport',

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-SqliteIdentifier {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter()][string]$FallbackPrefix = 'Identifier',
        [Parameter()][int]$FallbackIndex = 0
    )

    $trimmed = $Name.Trim()
    if (-not $trimmed) {
        $trimmed = '{0}{1}' -f $FallbackPrefix, $FallbackIndex
    }

    $safe = $trimmed -replace '[^A-Za-z0-9_]', '_'
    if ($safe -match '^[0-9]') {
        $safe = '_' + $safe
    }

    if (-not $safe) {
        $safe = '{0}{1}' -f $FallbackPrefix, $FallbackIndex
    }

    return $safe
}

function Quote-SqliteIdentifier {
    param([Parameter(Mandatory)][string]$Name)
    return '"{0}"' -f ($Name -replace '"', '""')
}

$resolvedCsvPath = Resolve-Path -Path $CsvPath -ErrorAction Stop
$csvRows = Import-Csv -Path $resolvedCsvPath
if (-not $csvRows) {
    throw "No rows were found in '$resolvedCsvPath'. Ensure the CSV has data."
}

$columnNames = $csvRows[0].PSObject.Properties.Name
if (-not $columnNames) {
    throw 'CSV header row is empty. At least one column is required.'
}

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$modulePath = Join-Path -Path $repoRoot -ChildPath 'PSNessusDB/PS-Sqlite.psm1'
if (-not (Test-Path -Path $modulePath)) {
    throw "PS-Sqlite module not found at '$modulePath'."
}

Import-Module -Name $modulePath -Force

$databaseFullPath = [System.IO.Path]::GetFullPath($DatabasePath)
$dbDirectory = Split-Path -Path $databaseFullPath -Parent
if (-not (Test-Path -Path $dbDirectory)) {
    Write-Verbose "Creating database directory '$dbDirectory'."
    [void](New-Item -ItemType Directory -Path $dbDirectory -Force)
}

$sanitizedTable = ConvertTo-SqliteIdentifier -Name $TableName -FallbackPrefix 'CsvImport'
$tableIdentifier = Quote-SqliteIdentifier -Name $sanitizedTable

$columnMap = [ordered]@{}
$columnIndex = 0
foreach ($column in $columnNames) {
    $columnIndex++
    $sanitized = ConvertTo-SqliteIdentifier -Name $column -FallbackPrefix 'Column' -FallbackIndex $columnIndex
    $columnMap[$column] = $sanitized
    Write-Verbose ("Column '{0}' mapped to '{1}'" -f $column, $sanitized)
}

$columnDefinitions = ($columnMap.Values | ForEach-Object { $(Quote-SqliteIdentifier -Name $_) + ' TEXT' }) -join ', '
$columnsClause = ($columnMap.Values | ForEach-Object { Quote-SqliteIdentifier -Name $_ }) -join ', '
$parameterClause = ($columnMap.Values | ForEach-Object { '@' + $_ }) -join ', '
$insertSql = "INSERT INTO $tableIdentifier ( $columnsClause ) VALUES ( $parameterClause );"

$connection = Open-PSNessusSqliteConnection -Database $databaseFullPath -AsDefault
try {
    $tableExists = Invoke-PSNessusSqliteScalar -Query 'SELECT COUNT(*) FROM sqlite_master WHERE type = ''table'' AND name = @name;' -Parameters @{ name = $sanitizedTable } -Connection $connection
    if ($tableExists -gt 0 -and -not $Force) {
        throw "Table '$sanitizedTable' already exists in '$databaseFullPath'. Rerun with -Force to overwrite it."
    }

    if (-not $PSCmdlet.ShouldProcess($databaseFullPath, "Import CSV into $sanitizedTable")) {
        Write-Verbose 'Operation cancelled by user.'
        return
    }

    Invoke-PSNessusSqliteNonQuery -Query "DROP TABLE IF EXISTS $tableIdentifier;" -Connection $connection | Out-Null
    Invoke-PSNessusSqliteNonQuery -Query "CREATE TABLE $tableIdentifier ( $columnDefinitions );" -Connection $connection | Out-Null

    $transaction = $connection.BeginTransaction()
    $rowCount = 0
    try {
        foreach ($row in $csvRows) {
            $parameters = @{}
            foreach ($entry in $columnMap.GetEnumerator()) {
                $parameters[$entry.Value] = $row.($entry.Key)
            }
            Invoke-PSNessusSqliteNonQuery -Query $insertSql -Parameters $parameters -Connection $connection -Transaction $transaction | Out-Null
            $rowCount++
        }
        $transaction.Commit()
        Write-Verbose ("Imported {0} rows into {1}" -f $rowCount, $sanitizedTable)
    }
    catch {
        $transaction.Rollback()
        throw
    }
    finally {
        $transaction.Dispose()
    }

    [PSCustomObject]@{
        DatabasePath = $databaseFullPath
        TableName    = $sanitizedTable
        RowsInserted = $rowCount
        ColumnMap    = [PSCustomObject]$columnMap
    }
}
finally {
    Close-PSNessusSqliteConnection -Connection $connection
}
