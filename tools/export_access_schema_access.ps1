Param(
    [string]$AccessDbPath = $null,
    [string]$OutputPath = 'schema_access_accessdb.sql'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-AccessColumnDefinition {
    param(
        [System.Data.DataRow]$Row,
        [switch]$IsPrimaryKey
    )

    $code = [int]$Row.DATA_TYPE
    $length = if ($Row.CHARACTER_MAXIMUM_LENGTH -is [DBNull]) { $null } else { [int]$Row.CHARACTER_MAXIMUM_LENGTH }
    $precision = if ($Row.NUMERIC_PRECISION -is [DBNull]) { $null } else { [int]$Row.NUMERIC_PRECISION }
    $scale = if ($Row.NUMERIC_SCALE -is [DBNull]) { $null } else { [int]$Row.NUMERIC_SCALE }
    $flags = if ($Row.COLUMN_FLAGS -is [DBNull]) { 0 } else { [int]$Row.COLUMN_FLAGS }
    $isNullable = ($Row.IS_NULLABLE -eq 'YES')
    $autoFlag = ($flags -eq 90)

    $type = switch ($code) {
        2 { 'SMALLINT' }
        3 {
            if ($autoFlag) { 'AUTOINCREMENT' } else { 'LONG' }
        }
        4 { 'SINGLE' }
        5 { 'DOUBLE' }
        6 { 'CURRENCY' }
        7 { 'DATETIME' }
        11 { 'YESNO' }
        17 { 'BYTE' }
        72 { 'GUID' }
        128 { 'LONGBINARY' }
        130 {
            if (-not $length -or $length -gt 255 -or ($flags -band 0x80)) { 'MEMO' }
            elseif ($length -gt 0) { "TEXT($length)" }
            else { 'TEXT(255)' }
        }
        131 {
            if ($precision -and $scale -ne $null) {
                "DECIMAL($precision,$scale)"
            }
            elseif ($precision) {
                "DECIMAL($precision)"
            }
            else {
                'DECIMAL'
            }
        }
        201 { 'MEMO' }
        202 {
            if ($length -and $length -le 255) { "TEXT($length)" } else { 'MEMO' }
        }
        203 { 'MEMO' }
        default { 'TEXT' }
    }

    if ($type -eq 'AUTOINCREMENT' -and $IsPrimaryKey) {
        $type = 'AUTOINCREMENT PRIMARY KEY'
        $nullText = ''
    }
    elseif ($type -eq 'AUTOINCREMENT') {
        $nullText = ''
    }
    else {
        $nullText = if ($isNullable) { ' NULL' } else { ' NOT NULL' }
    }

    return @(
        ('[{0}] {1}{2}' -f $Row.COLUMN_NAME, $type, $nullText)
    )
}

function New-AccessSchemaScript {
    param(
        [System.Data.OleDb.OleDbConnection]$Connection,
        [string]$OutputPath
    )

    $tablesDt = $Connection.GetOleDbSchemaTable([System.Data.OleDb.OleDbSchemaGuid]::Tables, @($null,$null,$null,'TABLE'))
    $tableNames = $tablesDt |
        Where-Object { $_.TABLE_NAME -and ($_.TABLE_NAME -notmatch '^MSys') } |
        Select-Object -ExpandProperty TABLE_NAME |
        Sort-Object -Unique

    $columns = $Connection.GetSchema('Columns')
    $primary = $Connection.GetOleDbSchemaTable([System.Data.OleDb.OleDbSchemaGuid]::Primary_Keys, $null)
    $foreign = $Connection.GetOleDbSchemaTable([System.Data.OleDb.OleDbSchemaGuid]::Foreign_Keys, $null)

    $columnsByTable = @{}
    foreach ($table in $tableNames) {
        $columnsByTable[$table] = $columns |
            Where-Object { $_.TABLE_NAME -eq $table } |
            Sort-Object ORDINAL_POSITION
    }

    $primaryByTable = @{}
    foreach ($row in $primary) {
        $table = [string]$row.TABLE_NAME
        if (-not $primaryByTable.ContainsKey($table)) {
            $primaryByTable[$table] = [System.Collections.Generic.List[string]]::new()
        }
        $primaryByTable[$table].Add([string]$row.COLUMN_NAME)
    }

    $foreignByTable = @{}
    foreach ($row in $foreign) {
        $fkTable = [string]$row.FK_TABLE_NAME
        if (-not $foreignByTable.ContainsKey($fkTable)) {
            $foreignByTable[$fkTable] = New-Object System.Collections.Generic.List[pscustomobject]
        }
        $foreignByTable[$fkTable].Add([pscustomobject]@{
            FkTable    = $fkTable
            PkTable    = [string]$row.PK_TABLE_NAME
            PkColumn   = [string]$row.PK_COLUMN_NAME
            FkColumn   = [string]$row.FK_COLUMN_NAME
            UpdateRule = [string]$row.UPDATE_RULE
            DeleteRule = [string]$row.DELETE_RULE
        })
    }

    # topological order
    $parentsByChild = @{}
    foreach ($table in $tableNames) {
        $parentsByChild[$table] = [System.Collections.Generic.HashSet[string]]::new()
    }
    foreach ($fk in $foreignByTable.Values) {
        foreach ($ref in $fk) {
            $parentsByChild[$ref.FkTable].Add($ref.PkTable) | Out-Null
        }
    }

    $remaining = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($table in $tableNames) { $remaining.Add($table) | Out-Null }
    $sorted = @()
    while ($remaining.Count -gt 0) {
        $progressed = $false
        foreach ($candidate in @($remaining)) {
            $parents = $parentsByChild[$candidate]
            $ok = $true
            foreach ($parent in $parents) {
                if ($sorted -notcontains $parent) { $ok = $false; break }
            }
            if ($ok) {
                $sorted += $candidate
                $remaining.Remove($candidate) | Out-Null
                $progressed = $true
            }
        }
        if (-not $progressed) {
            $sorted += $remaining
            $remaining.Clear()
        }
    }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('-- Access schema DDL generated from template database')
    [void]$sb.AppendLine()

    foreach ($table in $sorted) {
        $columnRows = @($columnsByTable[$table])
        if ($primaryByTable.ContainsKey($table)) {
            $pkCols = $primaryByTable[$table].ToArray()
        }
        else {
            $pkCols = @()
        }
        if ($foreignByTable.ContainsKey($table)) {
            $fkDefs = $foreignByTable[$table].ToArray()
        }
        else {
            $fkDefs = @()
        }

        $inlineAutoPk = $false
        if ($pkCols.Count -eq 1) {
            $pkName = $pkCols[0]
        $pkRow = $columnRows | Where-Object { $_.COLUMN_NAME -eq $pkName } | Select-Object -First 1
        if ($pkRow -and ([int]$pkRow.DATA_TYPE -eq 3)) {
            $flags = if ($pkRow.COLUMN_FLAGS -is [DBNull]) { 0 } else { [int]$pkRow.COLUMN_FLAGS }
            if ($flags -eq 90) { $inlineAutoPk = $true }
        }
    }

        [void]$sb.AppendLine(("CREATE TABLE [{0}] (" -f $table))
        $defs = New-Object System.Collections.Generic.List[string]

        foreach ($row in $columnRows) {
            $isInlinePkColumn = $inlineAutoPk -and ($pkCols.Count -gt 0) -and ($row.COLUMN_NAME -eq $pkCols[0])
            $definition = Get-AccessColumnDefinition -Row $row -IsPrimaryKey:$isInlinePkColumn
            foreach ($line in $definition) {
                $defs.Add("    $line") | Out-Null
            }
        }

        if (-not $inlineAutoPk -and $pkCols.Count -gt 0) {
            $pkName = "PK_$table"
            $colsText = ($pkCols | ForEach-Object { "[{0}]" -f $_ }) -join ', '
            $defs.Add("    CONSTRAINT [$pkName] PRIMARY KEY ($colsText)") | Out-Null
        }

        $fkIndex = 1
        foreach ($fk in $fkDefs) {
            $constraintName = "FK_{0}_{1}_{2}_{3}" -f $table, $fk.PkTable, $fk.FkColumn, $fkIndex
            $fkIndex++
            $fkText = "    CONSTRAINT [{0}] FOREIGN KEY ([{1}]) REFERENCES [{2}]([{3}])" -f $constraintName, $fk.FkColumn, $fk.PkTable, $fk.PkColumn
            if ($fk.UpdateRule -match 'CASCADE') { $fkText += ' ON UPDATE CASCADE' }
            if ($fk.DeleteRule -match 'CASCADE') { $fkText += ' ON DELETE CASCADE' }
            $defs.Add($fkText) | Out-Null
        }

        for ($i = 0; $i -lt $defs.Count; $i++) {
            $line = $defs[$i]
            if ($i -lt $defs.Count - 1) { $line += ',' }
            [void]$sb.AppendLine($line)
        }

        [void]$sb.AppendLine(');')
        [void]$sb.AppendLine()
    }

    Set-Content -Path $OutputPath -Value $sb.ToString() -Encoding UTF8
}

if (-not $AccessDbPath) {
    $candidates = @('NATemplate-Enumerated.accdb','Test.accdb','Test.accdb.accdb','PSNessusDB.accdb','NATemplate.accdb')
    $AccessDbPath = ($candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1)
}
if (-not $AccessDbPath) {
    throw "Could not find an Access .accdb in current folder. Provide -AccessDbPath."
}
if (-not (Test-Path -LiteralPath $AccessDbPath)) {
    throw "Access DB not found: $AccessDbPath"
}

$connection = New-Object System.Data.OleDb.OleDbConnection("Provider=Microsoft.ACE.OLEDB.12.0;Data Source=$AccessDbPath;Persist Security Info=False;")
$connection.Open()
try {
    New-AccessSchemaScript -Connection $connection -OutputPath $OutputPath
    Write-Host ("Wrote Access DDL to: {0}" -f (Resolve-Path $OutputPath))
}
finally {
    $connection.Close()
    $connection.Dispose()
}
