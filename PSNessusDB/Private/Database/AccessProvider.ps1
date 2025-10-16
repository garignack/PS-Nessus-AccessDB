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

function Ensure-HostEnumeratedPortsTable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Data.OleDb.OleDbConnection]$Connection
    )

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

function Ensure-HostTagsTable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Data.OleDb.OleDbConnection]$Connection
    )

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
        [string]$Provider = 'Access'
    )

    $resolvedPath = (Resolve-Path -Path $Path).ProviderPath

    switch ($Provider) {
        'Access' {
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
            throw [System.NotImplementedException]::new(
                "SQLite provider not yet implemented. Import the pssqlite module and extend the database adapter."
            )
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
            throw [System.NotImplementedException]::new("SQLite insert support not implemented yet.")
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
            throw [System.NotImplementedException]::new("SQLite query support not implemented yet.")
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
            throw [System.NotImplementedException]::new("SQLite column management not implemented yet.")
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
        [string]$Value
    )

    return ConvertTo-AccessSafeValue -Value $Value
}

# Backwards-compatible aliases for legacy function names.
Set-Alias -Name run-AccessNoQuery -Value Invoke-AccessNonQuery -Scope Local
Set-Alias -Name Get-AccessData -Value Invoke-AccessQuery -Scope Local
Set-Alias -Name add-AccessData -Value Invoke-AccessInsert -Scope Local
Set-Alias -Name fix-SQLColumns -Value Ensure-AccessColumns -Scope Local
Set-Alias -Name get-SQLEscaping -Value ConvertTo-AccessSafeValue -Scope Local
Set-Alias -Name update_or_create_by_id -Value Set-AccessRecord -Scope Local
