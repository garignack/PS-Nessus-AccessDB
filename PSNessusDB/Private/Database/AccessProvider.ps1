#######################################################################################################################
# File:             Private/Database/AccessProvider.ps1
# Description:      Access (and future SQLite) data access facade supplying CRUD helpers, schema management, and shared
#                   utility functions for the importer.
# Context:          All DB interactions flow through here—extend provider switching, caching, or schema creation in this
#                   file. Coordinate changes with legacy Access functions until they are retired.
#######################################################################################################################

function New-AccessConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $connection = New-Object System.Data.OleDb.OleDbConnection(
        "Provider=Microsoft.ACE.OLEDB.12.0; Data Source=$Path"
    )
    $connection.Open()
    return $connection
}

function Invoke-AccessNonQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Sql,

        [Parameter(Mandatory)]
        [System.Data.OleDb.OleDbConnection]$Connection
    )

    $command = New-Object System.Data.OleDb.OleDbCommand($Sql, $Connection)
    $command.ExecuteNonQuery() | Out-Null
}

function Invoke-AccessQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Sql,

        [Parameter(Mandatory)]
        [System.Data.OleDb.OleDbConnection]$Connection,

        [switch]$Grid
    )

    $dataTable = New-Object System.Data.DataTable
    $adapter = New-Object System.Data.OleDb.OleDbDataAdapter($Sql, $Connection)
    $null = $adapter.Fill($dataTable)

    if ($Grid) {
        $dataTable | Out-GridView -Title $Sql
        return
    }

    return ,$dataTable
}

function Invoke-AccessInsert {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Table,

        [Parameter(Mandatory)]
        [string[]]$Columns,

        [Parameter(Mandatory)]
        [object[]]$Values,

        [Parameter(Mandatory)]
        [System.Data.OleDb.OleDbConnection]$Connection
    )

    if ($Columns.Count -ne $Values.Count) {
        throw "Columns count must match values count."
    }

    $columnList = for ($index = 0; $index -lt $Columns.Count; $index++) {
        "[{0}]" -f $Columns[$index]
    }

    $valueList = for ($index = 0; $index -lt $Values.Count; $index++) {
        "'{0}'" -f $Values[$index]
    }

    $insertSql = "INSERT INTO {0} ({1}) VALUES ({2})" -f $Table, ($columnList -join ', '), ($valueList -join ', ')

    try {
        $insertCommand = New-Object System.Data.OleDb.OleDbCommand($insertSql, $Connection)
        $null = $insertCommand.ExecuteNonQuery()

        $identityCommand = New-Object System.Data.OleDb.OleDbCommand("SELECT @@IDENTITY;", $Connection)
        return [int]$identityCommand.ExecuteScalar()
    }
    catch {
        Write-Warning "Error inserting data into $Table"
        Write-Warning $_.Exception.Message

        for ($index = 0; $index -lt $Columns.Count; $index++) {
            Write-Host "   [$($Columns[$index])]: $($Values[$index])"
        }

        throw
    }
}

function Ensure-AccessColumns {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Table,

        [Parameter(Mandatory)]
        [string[]]$Columns,

        [Parameter(Mandatory)]
        [object[]]$Values,

        [Parameter(Mandatory)]
        [System.Data.OleDb.OleDbConnection]$Connection
    )

    $existingColumns = $Connection.GetSchema("Columns") |
        Where-Object { $_.TABLE_NAME -eq $Table } |
        ForEach-Object { $_.COLUMN_NAME }

    for ($index = 0; $index -lt $Columns.Count; $index++) {
        $column = $Columns[$index]
        if ([string]::IsNullOrWhiteSpace($column)) {
            continue
        }
        if ($existingColumns -contains $column) {
            continue
        }

        $value = $Values[$index]
        $dataType = if ($value -is [string] -and $value.Length -gt 200) { "MEMO" } else { "TEXT(255)" }
        $alterSql = "ALTER TABLE {0} ADD COLUMN [{1}] {2}" -f $Table, $column, $dataType

        try {
            $alterCommand = New-Object System.Data.OleDb.OleDbCommand($alterSql, $Connection)
            $null = $alterCommand.ExecuteNonQuery()
            $existingColumns += $column
        }
        catch {
            Write-Warning ("Failed to add column '{0}' to table '{1}': {2}" -f $column, $Table, $_.Exception.Message)
        }
    }
}

function Import-PSNessusSqliteModule {
    if (Get-Module -Name 'PS-Sqlite' -ErrorAction SilentlyContinue) {
        return
    }

    $privateRoot = Split-Path -Path $PSScriptRoot -Parent
    $moduleRoot = Split-Path -Path $privateRoot -Parent
    $modulePath = Join-Path $moduleRoot 'PS-Sqlite.psm1'

    if (-not (Test-Path -LiteralPath $modulePath)) {
        throw "SQLite support module not found at '$modulePath'."
    }

    Import-Module $modulePath -Force
}

function New-SqliteConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    Import-PSNessusSqliteModule
    return Open-PSNessusSqliteConnection -Database $Path -AsDefault
}

function Invoke-SqliteNonQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Sql,
        [System.Data.SQLite.SQLiteConnection]$Connection,
        [hashtable]$Parameters
    )

    Import-PSNessusSqliteModule
    return Invoke-PSNessusSqliteNonQuery -Query $Sql -Connection $Connection -Parameters $Parameters
}

function Invoke-SqliteQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Sql,
        [System.Data.SQLite.SQLiteConnection]$Connection,
        [hashtable]$Parameters
    )

    Import-PSNessusSqliteModule
    return Invoke-PSNessusSqliteQuery -Query $Sql -Connection $Connection -Parameters $Parameters
}

function Invoke-SqliteInsert {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Table,
        [Parameter(Mandatory)][string[]]$Columns,
        [Parameter(Mandatory)][object[]]$Values,
        [Parameter(Mandatory)][System.Data.SQLite.SQLiteConnection]$Connection
    )

    if ($Columns.Count -ne $Values.Count) {
        throw "Columns count must match values count."
    }

    $parameterNames = @()
    $parameters = @{}
    for ($index = 0; $index -lt $Columns.Count; $index++) {
        $name = "p$index"
        $parameterNames += "@$name"
        $parameters[$name] = $Values[$index]
    }

    $columnList = ($Columns | ForEach-Object { "[{0}]" -f $_ }) -join ', '
    $parameterList = $parameterNames -join ', '
    $insertSql = "INSERT INTO {0} ({1}) VALUES ({2})" -f $Table, $columnList, $parameterList

    Invoke-SqliteNonQuery -Sql $insertSql -Connection $Connection -Parameters $parameters | Out-Null
    $id = Invoke-PSNessusSqliteScalar -Query 'SELECT last_insert_rowid();' -Connection $Connection
    return [int]$id
}

function Ensure-SqliteColumns {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Table,
        [Parameter(Mandatory)][string[]]$Columns,
        [Parameter(Mandatory)][object[]]$Values,
        [Parameter(Mandatory)][System.Data.SQLite.SQLiteConnection]$Connection
    )

    Import-PSNessusSqliteModule

    $info = Invoke-SqliteQuery -Sql ("PRAGMA table_info([{0}]);" -f $Table) -Connection $Connection
    $existing = @($info | ForEach-Object { $_.name })

    for ($index = 0; $index -lt $Columns.Count; $index++) {
        $column = $Columns[$index]
        if ([string]::IsNullOrWhiteSpace($column)) {
            continue
        }
        if ($existing -contains $column) {
            continue
        }

        $value = $Values[$index]
        $dataType = 'TEXT'
        if ($value -is [int] -or $value -is [long]) {
            $dataType = 'INTEGER'
        }
        elseif ($value -is [double] -or $value -is [float] -or $value -is [decimal]) {
            $dataType = 'REAL'
        }

        $alterSql = "ALTER TABLE [{0}] ADD COLUMN [{1}] {2}" -f $Table, $column, $dataType
        try {
            Invoke-SqliteNonQuery -Sql $alterSql -Connection $Connection | Out-Null
        }
        catch {
            Write-Warning ("Failed to add column '{0}' to table '{1}' in SQLite database: {2}" -f $column, $Table, $_.Exception.Message)
        }
    }
}

function Ensure-HostEnumeratedPortsTable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Connection
    )

    if ($Connection -is [System.Data.OleDb.OleDbConnection]) {
        $tableSchema = $Connection.GetSchema('Tables') |
            Where-Object { $_.TABLE_NAME -eq 'HostEnumeratedPorts' -and $_.TABLE_TYPE -eq 'TABLE' }
        if ($tableSchema) {
            return
        }

        $createSql = @"
CREATE TABLE HostEnumeratedPorts (
    ID COUNTER PRIMARY KEY,
    HostID LONG,
    Port LONG,
    Protocol TEXT(10),
    State TEXT(50)
)
"@

        try {
            Invoke-AccessNonQuery -Sql $createSql -Connection $Connection
        }
        catch {
            if ($_.Exception.Message -notlike '*already exists*') {
                throw
            }
        }
    }
    elseif ($Connection -is [System.Data.SQLite.SQLiteConnection]) {
        Import-PSNessusSqliteModule
        $existing = Invoke-SqliteQuery -Sql "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'HostEnumeratedPorts';" -Connection $Connection
        if ($existing.Rows.Count -gt 0) {
            return
        }

        $createSql = @"
CREATE TABLE IF NOT EXISTS HostEnumeratedPorts (
    ID INTEGER PRIMARY KEY AUTOINCREMENT,
    HostID INTEGER,
    Port INTEGER,
    Protocol TEXT,
    State TEXT
);
"@
        Invoke-SqliteNonQuery -Sql $createSql -Connection $Connection | Out-Null
    }
    else {
        throw "Unsupported connection type '$($Connection.GetType().FullName)' for Ensure-HostEnumeratedPortsTable."
    }
}

function Ensure-HostTagsTable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Connection
    )

    if ($Connection -is [System.Data.OleDb.OleDbConnection]) {
        $tableSchema = $Connection.GetSchema('Tables') |
            Where-Object { $_.TABLE_NAME -eq 'HostTags' -and $_.TABLE_TYPE -eq 'TABLE' }
        if ($tableSchema) {
            return
        }

        $createSql = @"
CREATE TABLE HostTags (
    ID COUNTER PRIMARY KEY,
    HostID LONG,
    TagName TEXT(255),
    TagValue MEMO
)
"@

        try {
            Invoke-AccessNonQuery -Sql $createSql -Connection $Connection
        }
        catch {
            if ($_.Exception.Message -notlike '*already exists*') {
                throw
            }
        }
    }
    elseif ($Connection -is [System.Data.SQLite.SQLiteConnection]) {
        Import-PSNessusSqliteModule
        $existing = Invoke-SqliteQuery -Sql "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'HostTags';" -Connection $Connection
        if ($existing.Rows.Count -gt 0) {
            return
        }

        $createSql = @"
CREATE TABLE IF NOT EXISTS HostTags (
    ID INTEGER PRIMARY KEY AUTOINCREMENT,
    HostID INTEGER,
    TagName TEXT,
    TagValue TEXT
);
"@
        Invoke-SqliteNonQuery -Sql $createSql -Connection $Connection | Out-Null
    }
    else {
        throw "Unsupported connection type '$($Connection.GetType().FullName)' for Ensure-HostTagsTable."
    }
}

function ConvertTo-AccessSafeValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    if ($null -eq $Value) {
        return ''
    }

    $escaped = $Value.Replace("`'", "`'`'")
    $escaped = $escaped.Replace("?", "`[?`]")
    $escaped = $escaped.Replace("*", "`[*`]")
    $escaped = $escaped.Replace("#", "`[#`]")

    $escaped = $escaped.Replace("`n", "`r`n")
    $escaped = $escaped.Replace("`r", "`r`n")
    $escaped = $escaped.Replace("`r`n`r`n", "`r`n")

    do {
        $escaped = $escaped.TrimStart("`r").TrimStart("`n").Trim()
    } until (
        -not ($escaped.StartsWith("`r") -or $escaped.StartsWith("`n") -or $escaped.StartsWith(" "))
    )

    return $escaped
}

function Set-AccessRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Table,

        [Parameter(Mandatory)]
        [string]$Id,

        [Parameter(Mandatory)]
        [string[]]$Columns,

        [Parameter(Mandatory)]
        [object[]]$Values,

        [Parameter(Mandatory)]
        [System.Data.OleDb.OleDbConnection]$Connection
    )

    $existing = Invoke-AccessQuery -Sql "SELECT ID FROM $Table WHERE ID = $Id" -Connection $Connection
    if ($existing) {
        $setParts = for ($index = 0; $index -lt $Columns.Count; $index++) {
            "[{0}] = '{1}'" -f $Columns[$index], $Values[$index]
        }

        $updateSql = "UPDATE {0} SET {1} WHERE ID = {2};" -f $Table, ($setParts -join ', '), $Id
        $updateCommand = New-Object System.Data.OleDb.OleDbCommand($updateSql, $Connection)
        $null = $updateCommand.ExecuteNonQuery()

        return [int]$Id
    }

    return Invoke-AccessInsert -Table $Table -Columns $Columns -Values $Values -Connection $Connection
}

function New-PSNessusDbContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [ValidateSet('Access', 'SQLite')]
        [string]$Provider = 'Access',

        [switch]$NewDb
    )

    $resolvedPath = if (Test-Path -LiteralPath $Path) {
        (Resolve-Path -Path $Path).ProviderPath
    }
    else {
        [System.IO.Path]::GetFullPath($Path)
    }

    switch ($Provider) {
        'Access' {
            if ($NewDb) {
                throw "Access provider does not support -NewDb. Provide an existing Access database."
            }

            $context = [pscustomobject]@{
                Provider  = 'Access'
                Path      = $resolvedPath
                Connection = New-AccessConnection -Path $resolvedPath
            }
            $pluginCache = @{}
            $pluginReader = $null
            try {
                $command = $context.Connection.CreateCommand()
                $command.CommandText = 'SELECT ID, PluginHash FROM PluginInfo'
                $pluginReader = $command.ExecuteReader()

                while ($pluginReader.Read()) {
                    $hash = $pluginReader['PluginHash']
                    $idValue = $pluginReader['ID']

                    if ($hash -and $hash -isnot [System.DBNull] -and $idValue -and $idValue -isnot [System.DBNull]) {
                        $pluginCache[[string]$hash] = [int]$idValue
                    }
                }
            }
            catch {
                # ignore cache load failures; logging will handle missing entries
                }
            finally {
                if ($pluginReader) {
                    $pluginReader.Close()
                }
            }

            Add-Member -InputObject $context -NotePropertyName PluginCache -NotePropertyValue $pluginCache -Force
            return $context
        }
        'SQLite' {
            Import-PSNessusSqliteModule

            $isNewDatabase = $NewDb -or -not (Test-Path -LiteralPath $resolvedPath)
            if ($isNewDatabase) {
                $directory = Split-Path -Path $resolvedPath -Parent
                if ($directory -and -not (Test-Path -LiteralPath $directory)) {
                    New-Item -ItemType Directory -Path $directory -Force | Out-Null
                }
                if (Test-Path -LiteralPath $resolvedPath) {
                    Remove-Item -LiteralPath $resolvedPath -Force
                }
            }

            $connection = $null
            try {
                $connection = New-SqliteConnection -Path $resolvedPath

                if ($isNewDatabase) {
                    $privateRoot = Split-Path -Path $PSScriptRoot -Parent
                    $moduleRoot = Split-Path -Path $privateRoot -Parent
                    $repositoryRoot = Split-Path -Path $moduleRoot -Parent
                    $schemaPath = Join-Path $repositoryRoot 'schema_sqlite.sql'
                    if (-not (Test-Path -LiteralPath $schemaPath)) {
                        throw "SQLite schema definition not found at '$schemaPath'."
                    }

                    $schemaContent = Get-Content -Path $schemaPath -Raw
                    $commands = $schemaContent -split ';\s*(\r?\n)+'
                    foreach ($command in $commands) {
                        $text = $command.Trim()
                        if (-not $text) { continue }
                        if ($text -match '^\s*--') { continue }
                        Invoke-SqliteNonQuery -Sql $text -Connection $connection | Out-Null
                    }
                }

                $context = [pscustomobject]@{
                    Provider   = 'SQLite'
                    Path       = $resolvedPath
                    Connection = $connection
                }

                $pluginCache = @{}
                try {
                    $pluginTable = Invoke-SqliteQuery -Sql 'SELECT ID, PluginHash FROM PluginInfo;' -Connection $connection
                    foreach ($row in $pluginTable.Rows) {
                        $hash = $row['PluginHash']
                        $idValue = $row['ID']
                        if ($hash -and $hash -isnot [System.DBNull] -and $idValue -and $idValue -isnot [System.DBNull]) {
                            $pluginCache[[string]$hash] = [int]$idValue
                        }
                    }
                }
                catch {
                    # ignore cache load failures; logging will handle missing entries
                }

                Add-Member -InputObject $context -NotePropertyName PluginCache -NotePropertyValue $pluginCache -Force
                return $context
            }
            catch {
                if ($connection) {
                    Close-PSNessusSqliteConnection -Connection $connection
                }
                throw
            }
        }
    }
}

function Close-PSNessusDbContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Context
    )

    if ($null -eq $Context) {
        return
    }

    if ($Context.Provider -eq 'Access' -and $Context.Connection) {
        $Context.Connection.Close()
        $Context.Connection = $null
    }
    elseif ($Context.Provider -eq 'SQLite' -and $Context.Connection) {
        Close-PSNessusSqliteConnection -Connection $Context.Connection
        $Context.Connection = $null
    }
}

function Add-PSNessusDbRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Context,

        [Parameter(Mandatory)]
        [string]$Table,

        [Parameter(Mandatory)]
        [string[]]$Columns,

        [Parameter(Mandatory)]
        [object[]]$Values
    )

    switch ($Context.Provider) {
        'Access' {
            return Invoke-AccessInsert -Table $Table -Columns $Columns -Values $Values -Connection $Context.Connection
        }
        'SQLite' {
            return Invoke-SqliteInsert -Table $Table -Columns $Columns -Values $Values -Connection $Context.Connection
        }
        default {
            throw "Unsupported provider '$($Context.Provider)'."
        }
    }
}

function Get-PSNessusDbData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Context,

        [Parameter(Mandatory)]
        [string]$Sql
    )

    switch ($Context.Provider) {
        'Access' {
            return ,(Invoke-AccessQuery -Sql $Sql -Connection $Context.Connection)
        }
        'SQLite' {
            return Invoke-SqliteQuery -Sql $Sql -Connection $Context.Connection
        }
        default {
            throw "Unsupported provider '$($Context.Provider)'."
        }
    }
}

function Ensure-PSNessusDbColumns {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Context,

        [Parameter(Mandatory)]
        [string]$Table,

        [Parameter(Mandatory)]
        [string[]]$Columns,

        [Parameter(Mandatory)]
        [object[]]$Values
    )

    switch ($Context.Provider) {
        'Access' {
            Ensure-AccessColumns -Table $Table -Columns $Columns -Values $Values -Connection $Context.Connection
            break
        }
        'SQLite' {
            Ensure-SqliteColumns -Table $Table -Columns $Columns -Values $Values -Connection $Context.Connection
            break
        }
        default {
            throw "Unsupported provider '$($Context.Provider)'."
        }
    }
}

function ConvertTo-PSNessusDbValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Value,

        [string]$Provider = 'Access'
    )

    switch ($Provider) {
        'Access' {
            return ConvertTo-AccessSafeValue -Value $Value
        }
        'SQLite' {
            return $Value
        }
        default {
            return $Value
        }
    }
}

# Backwards-compatible aliases for legacy function names.
Set-Alias -Name run-AccessNoQuery -Value Invoke-AccessNonQuery -Scope Local
Set-Alias -Name Get-AccessData -Value Invoke-AccessQuery -Scope Local
Set-Alias -Name add-AccessData -Value Invoke-AccessInsert -Scope Local
Set-Alias -Name fix-SQLColumns -Value Ensure-AccessColumns -Scope Local
Set-Alias -Name get-SQLEscaping -Value ConvertTo-AccessSafeValue -Scope Local
Set-Alias -Name update_or_create_by_id -Value Set-AccessRecord -Scope Local
