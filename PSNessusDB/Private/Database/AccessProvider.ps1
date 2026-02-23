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
        [System.Data.OleDb.OleDbConnection]$Connection,

        [System.Data.OleDb.OleDbTransaction]$Transaction
    )

    $command = $Connection.CreateCommand()
    try {
        $command.CommandText = $Sql
        if ($PSBoundParameters.ContainsKey('Transaction') -and $Transaction) {
            $command.Transaction = $Transaction
        }
        $command.ExecuteNonQuery() | Out-Null
    }
    finally {
        $command.Dispose()
    }
}

function Invoke-AccessQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Sql,

        [Parameter(Mandatory)]
        [System.Data.OleDb.OleDbConnection]$Connection,

        [System.Data.OleDb.OleDbTransaction]$Transaction,

        [switch]$Grid
    )

    $command = $Connection.CreateCommand()
    $dataTable = New-Object System.Data.DataTable
    try {
        $command.CommandText = $Sql
        if ($PSBoundParameters.ContainsKey('Transaction') -and $Transaction) {
            $command.Transaction = $Transaction
        }
        $adapter = New-Object System.Data.OleDb.OleDbDataAdapter($command)
        try {
            $null = $adapter.Fill($dataTable)
        }
        finally {
            $adapter.Dispose()
        }
    }
    finally {
        $command.Dispose()
    }

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
        [AllowNull()]
        [object[]]$Values,

        [Parameter(Mandatory)]
        [System.Data.OleDb.OleDbConnection]$Connection,

        [System.Data.OleDb.OleDbTransaction]$Transaction
    )

    if ($Columns.Count -ne $Values.Count) {
        throw "Columns count must match values count."
    }

    $columnList = ($Columns | ForEach-Object { "[{0}]" -f $_ }) -join ', '
    $placeholders = @()
    for ($i = 0; $i -lt $Columns.Count; $i++) {
        $placeholders += '?'
    }
    $insertSql = "INSERT INTO {0} ({1}) VALUES ({2})" -f $Table, $columnList, ($placeholders -join ', ')

    try {
        $insertCommand = $Connection.CreateCommand()
        try {
            $insertCommand.CommandText = $insertSql
            if ($PSBoundParameters.ContainsKey('Transaction') -and $Transaction) {
                $insertCommand.Transaction = $Transaction
            }

            for ($index = 0; $index -lt $Values.Count; $index++) {
                $parameter = $insertCommand.CreateParameter()
                $value = $Values[$index]
                if ($null -eq $value) {
                    $parameter.Value = [DBNull]::Value
                }
                else {
                    switch ($value.GetType().FullName) {
                        'System.DateTime' {
                            $dateValue = [datetime]$value
                            # Access inserts fail when DBTimeStamp parameters include sub-second precision.
                            $dateValue = $dateValue.AddTicks(-($dateValue.Ticks % [TimeSpan]::TicksPerSecond))
                            $parameter.OleDbType = [System.Data.OleDb.OleDbType]::DBTimeStamp
                            $parameter.Value = $dateValue
                            break
                        }
                        'System.Int16' {
                            $parameter.OleDbType = [System.Data.OleDb.OleDbType]::SmallInt
                            $parameter.Value = [int16]$value
                            break
                        }
                        'System.Int32' {
                            $parameter.OleDbType = [System.Data.OleDb.OleDbType]::Integer
                            $parameter.Value = [int]$value
                            break
                        }
                        'System.Int64' {
                            $longValue = [long]$value
                            if ($longValue -ge [int]::MinValue -and $longValue -le [int]::MaxValue) {
                                $parameter.OleDbType = [System.Data.OleDb.OleDbType]::Integer
                                $parameter.Value = [int]$longValue
                            }
                            else {
                                $parameter.OleDbType = [System.Data.OleDb.OleDbType]::Double
                                $parameter.Value = [double]$longValue
                            }
                            break
                        }
                        'System.Boolean' {
                            $parameter.OleDbType = [System.Data.OleDb.OleDbType]::Boolean
                            $parameter.Value = [bool]$value
                            break
                        }
                        'System.Decimal' {
                            $parameter.OleDbType = [System.Data.OleDb.OleDbType]::Decimal
                            $parameter.Value = [decimal]$value
                            break
                        }
                        'System.Double' {
                            $parameter.OleDbType = [System.Data.OleDb.OleDbType]::Double
                            $parameter.Value = [double]$value
                            break
                        }
                        'System.Single' {
                            $parameter.OleDbType = [System.Data.OleDb.OleDbType]::Single
                            $parameter.Value = [single]$value
                            break
                        }
                        'System.Byte[]' {
                            $parameter.OleDbType = [System.Data.OleDb.OleDbType]::VarBinary
                            $parameter.Value = [byte[]]$value
                            break
                        }
                        default {
                            $stringValue = [string]$value
                            if ($stringValue.Length -gt 255) {
                                $parameter.OleDbType = [System.Data.OleDb.OleDbType]::LongVarWChar
                            }
                            else {
                                $parameter.OleDbType = [System.Data.OleDb.OleDbType]::VarWChar
                            }
                            $parameter.Value = $stringValue
                            break
                        }
                    }
                }
                [void]$insertCommand.Parameters.Add($parameter)
            }

            $null = $insertCommand.ExecuteNonQuery()
        }
        finally {
            $insertCommand.Dispose()
        }

        $identityCommand = $Connection.CreateCommand()
        try {
            $identityCommand.CommandText = 'SELECT @@IDENTITY;'
            if ($PSBoundParameters.ContainsKey('Transaction') -and $Transaction) {
                $identityCommand.Transaction = $Transaction
            }
            return [int]$identityCommand.ExecuteScalar()
        }
        finally {
            $identityCommand.Dispose()
        }
    }
    catch {
        Write-Warning "Error inserting data into $Table"
        Write-Warning "SQL: $insertSql"
        Write-Warning $_.Exception.Message

        for ($index = 0; $index -lt $Columns.Count; $index++) {
            $valueType = if ($null -eq $Values[$index]) { '<null>' } else { $Values[$index].GetType().FullName }
            Write-Host "   [$($Columns[$index])]: $($Values[$index]) (Type: $valueType)"
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
        [AllowNull()]
        [object[]]$Values,

        [Parameter(Mandatory)]
        [System.Data.OleDb.OleDbConnection]$Connection
        ,
        [System.Data.OleDb.OleDbTransaction]$Transaction
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
            if ($PSBoundParameters.ContainsKey('Transaction') -and $Transaction) {
                $alterCommand.Transaction = $Transaction
            }
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
        [hashtable]$Parameters,
        [System.Data.SQLite.SQLiteTransaction]$Transaction
    )

    Import-PSNessusSqliteModule
    return Invoke-PSNessusSqliteNonQuery -Query $Sql -Connection $Connection -Parameters $Parameters -Transaction $Transaction
}

function Invoke-SqliteQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Sql,
        [System.Data.SQLite.SQLiteConnection]$Connection,
        [hashtable]$Parameters,
        [System.Data.SQLite.SQLiteTransaction]$Transaction
    )

    Import-PSNessusSqliteModule
    return Invoke-PSNessusSqliteQuery -Query $Sql -Connection $Connection -Parameters $Parameters -Transaction $Transaction
}

function Invoke-SqliteInsert {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Table,
        [Parameter(Mandatory)][string[]]$Columns,
        [Parameter(Mandatory)][AllowNull()][object[]]$Values,
        [Parameter(Mandatory)][System.Data.SQLite.SQLiteConnection]$Connection,
        [System.Data.SQLite.SQLiteTransaction]$Transaction
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

    Invoke-SqliteNonQuery -Sql $insertSql -Connection $Connection -Parameters $parameters -Transaction $Transaction | Out-Null
    $id = Invoke-PSNessusSqliteScalar -Query 'SELECT last_insert_rowid();' -Connection $Connection -Transaction $Transaction
    return [int]$id
}

function Ensure-SqliteColumns {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Table,
        [Parameter(Mandatory)][string[]]$Columns,
        [Parameter(Mandatory)][AllowNull()][object[]]$Values,
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
        [AllowNull()]
        [string]$Value
    )

    return $Value
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
        [AllowNull()]
        [object[]]$Values,

        [Parameter(Mandatory)]
        [System.Data.OleDb.OleDbConnection]$Connection
    )

    $dataTable = New-Object System.Data.DataTable
    $selectCommand = $Connection.CreateCommand()
    try {
        $selectCommand.CommandText = "SELECT ID FROM [$Table] WHERE ID = ?;"
        $idParameter = $selectCommand.CreateParameter()
        $idParameter.Value = [int]$Id
        [void]$selectCommand.Parameters.Add($idParameter)

        $adapter = [System.Data.OleDb.OleDbDataAdapter]::new($selectCommand)
        try {
            [void]$adapter.Fill($dataTable)
        }
        finally {
            $adapter.Dispose()
        }
    }
    finally {
        $selectCommand.Dispose()
    }

    if ($dataTable.Rows.Count -gt 0) {
        $setFragments = for ($index = 0; $index -lt $Columns.Count; $index++) {
            "[{0}] = ?" -f $Columns[$index]
        }

        $updateCommand = $Connection.CreateCommand()
        try {
            $updateCommand.CommandText = "UPDATE [$Table] SET {0} WHERE ID = ?;" -f ($setFragments -join ', ')

            for ($index = 0; $index -lt $Values.Count; $index++) {
                $parameter = $updateCommand.CreateParameter()
                $value = $Values[$index]
                if ($null -eq $value) {
                    $parameter.Value = [DBNull]::Value
                }
                else {
                    $parameter.Value = $value
                }
                [void]$updateCommand.Parameters.Add($parameter)
            }

            $idUpdateParameter = $updateCommand.CreateParameter()
            $idUpdateParameter.Value = [int]$Id
            [void]$updateCommand.Parameters.Add($idUpdateParameter)

            $null = $updateCommand.ExecuteNonQuery()
        }
        finally {
            $updateCommand.Dispose()
        }
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
                Write-Warning ("Plugin cache preload failed for Access database '{0}': {1}" -f $resolvedPath, $_.Exception.Message)
                Write-Verbose $_.Exception.ToString()
            }
            finally {
                if ($pluginReader) {
                    try {
                        $pluginReader.Close()
                    }
                    catch {
                        Write-Verbose ("Failed to close Access plugin cache reader for '{0}': {1}" -f $resolvedPath, $_.Exception.Message)
                    }
                }
                if ($command) {
                    try {
                        $command.Dispose()
                    }
                    catch {
                        Write-Verbose ("Failed to dispose Access plugin cache command for '{0}': {1}" -f $resolvedPath, $_.Exception.Message)
                    }
                }
            }

            Add-Member -InputObject $context -NotePropertyName PluginCache -NotePropertyValue $pluginCache -Force
            Add-Member -InputObject $context -NotePropertyName Transaction -NotePropertyValue $null -Force
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

                    $pragmaStatements = @(
                        'PRAGMA journal_mode = WAL;',
                        'PRAGMA synchronous = NORMAL;',
                        'PRAGMA foreign_keys = ON;'
                    )
                    foreach ($pragma in $pragmaStatements) {
                        Invoke-SqliteNonQuery -Sql $pragma -Connection $connection | Out-Null
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
                    Write-Warning ("Plugin cache preload failed for SQLite database '{0}': {1}" -f $resolvedPath, $_.Exception.Message)
                    Write-Verbose $_.Exception.ToString()
                }

                Add-Member -InputObject $context -NotePropertyName PluginCache -NotePropertyValue $pluginCache -Force
                Add-Member -InputObject $context -NotePropertyName Transaction -NotePropertyValue $null -Force
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

    if ($Context.PSObject.Properties.Name -contains 'Transaction') {
        $transaction = $Context.Transaction
        if ($transaction) {
            try {
                $transaction.Rollback()
            }
            catch {
                Write-Verbose ("Failed to rollback active transaction while closing context '{0}' ({1}): {2}" -f $Context.Path, $Context.Provider, $_.Exception.Message)
            }
            try {
                $transaction.Dispose()
            }
            catch {
                Write-Verbose ("Failed to dispose active transaction while closing context '{0}' ({1}): {2}" -f $Context.Path, $Context.Provider, $_.Exception.Message)
            }
            $Context.Transaction = $null
        }
    }

    if ($Context.Provider -eq 'Access' -and $Context.Connection) {
        try {
            $Context.Connection.Close()
        }
        catch {
            Write-Warning ("Failed to close Access connection '{0}': {1}" -f $Context.Path, $_.Exception.Message)
            Write-Verbose $_.Exception.ToString()
        }
        $Context.Connection = $null
    }
    elseif ($Context.Provider -eq 'SQLite' -and $Context.Connection) {
        try {
            Close-PSNessusSqliteConnection -Connection $Context.Connection
        }
        catch {
            Write-Warning ("Failed to close SQLite connection '{0}': {1}" -f $Context.Path, $_.Exception.Message)
            Write-Verbose $_.Exception.ToString()
        }
        $Context.Connection = $null
    }
}

function Start-PSNessusDbTransaction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Context
    )

    if ($null -eq $Context) {
        throw 'Cannot start a transaction without a database context.'
    }

    if ($Context.PSObject.Properties.Name -contains 'Transaction' -and $Context.Transaction) {
        throw 'A transaction is already active for this context.'
    }

    switch ($Context.Provider) {
        'Access' {
            $transaction = $Context.Connection.BeginTransaction()
            $Context.Transaction = $transaction
            return $transaction
        }
        'SQLite' {
            $transaction = $Context.Connection.BeginTransaction()
            $Context.Transaction = $transaction
            return $transaction
        }
        default {
            throw "Unsupported provider '$($Context.Provider)'."
        }
    }
}

function Complete-PSNessusDbTransaction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Context
    )

    if ($null -eq $Context) {
        return
    }

    if ($Context.PSObject.Properties.Name -notcontains 'Transaction' -or -not $Context.Transaction) {
        return
    }

    try {
        $Context.Transaction.Commit()
    }
    finally {
        try { $Context.Transaction.Dispose() } catch {}
        $Context.Transaction = $null
    }
}

function Rollback-PSNessusDbTransaction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Context
    )

    if ($null -eq $Context) {
        return
    }

    if ($Context.PSObject.Properties.Name -notcontains 'Transaction' -or -not $Context.Transaction) {
        return
    }

    try {
        $Context.Transaction.Rollback()
    }
    finally {
        try { $Context.Transaction.Dispose() } catch {}
        $Context.Transaction = $null
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
        [AllowNull()]
        [object[]]$Values
    )

    switch ($Context.Provider) {
        'Access' {
            return Invoke-AccessInsert -Table $Table -Columns $Columns -Values $Values -Connection $Context.Connection -Transaction $Context.Transaction
        }
        'SQLite' {
            return Invoke-SqliteInsert -Table $Table -Columns $Columns -Values $Values -Connection $Context.Connection -Transaction $Context.Transaction
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
            $data = Invoke-AccessQuery -Sql $Sql -Connection $Context.Connection
        }
        'SQLite' {
            $data = Invoke-SqliteQuery -Sql $Sql -Connection $Context.Connection
        }
        default {
            throw "Unsupported provider '$($Context.Provider)'."
        }
    }

    if ($data -is [object[]] -and $data.Count -eq 1 -and $data[0] -is [System.Data.DataTable]) {
        $data = $data[0]
    }

    if ($data -isnot [System.Data.DataTable]) {
        $actualType = if ($null -eq $data) { '<null>' } else { $data.GetType().FullName }
        $message = "Query result type mismatch for provider '$($Context.Provider)'. Expected System.Data.DataTable, got '$actualType'. SQL: $Sql"
        Write-Error $message
        throw $message
    }

    Write-Output -NoEnumerate $data
    return
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
        [AllowNull()]
        [object[]]$Values
    )

    switch ($Context.Provider) {
        'Access' {
            Ensure-AccessColumns -Table $Table -Columns $Columns -Values $Values -Connection $Context.Connection -Transaction $Context.Transaction
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
        [AllowNull()]
        [AllowEmptyString()]
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
