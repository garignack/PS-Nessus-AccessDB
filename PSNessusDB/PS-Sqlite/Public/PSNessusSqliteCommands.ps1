function Open-PSNessusSqliteConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Database,
        [switch]$AsDefault
    )

    Initialize-PSNessusSqliteEnvironment

    $builder = [System.Data.SQLite.SQLiteConnectionStringBuilder]::new()
    if (Test-Path -LiteralPath $Database) {
        $builder.DataSource = (Resolve-Path -Path $Database).ProviderPath
    }
    else {
        $builder.DataSource = [System.IO.Path]::GetFullPath($Database)
    }
    $builder.Version = 3
    $builder['Foreign Keys'] = $true

    $connection = [System.Data.SQLite.SQLiteConnection]::new($builder.ToString())
    try {
        $connection.Open()
        $pragma = $connection.CreateCommand()
        try {
            $pragma.CommandText = 'PRAGMA foreign_keys = ON;'
            $pragma.ExecuteNonQuery() | Out-Null
        }
        finally {
            $pragma.Dispose()
        }
    }
    catch {
        $connection.Dispose()
        throw "Failed to open SQLite database '$Database'. $_"
    }

    if ($AsDefault -or -not $script:PSNessusSqliteDefaultConnection) {
        $script:PSNessusSqliteDefaultConnection = $connection
    }

    return $connection
}

function Get-PSNessusSqliteConnection {
    [CmdletBinding()]
    param(
        [object]$Connection
    )

    return Get-InternalPSNessusSqliteConnection -Connection:$Connection
}

function Invoke-PSNessusSqliteScalar {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Query,
        [hashtable]$Parameters,
        [object]$Connection,
        [int]$TimeoutSec = 30
    )

    $cn = Get-InternalPSNessusSqliteConnection -Connection:$Connection
    $cmd = $cn.CreateCommand()
    try {
        $cmd.CommandText = $Query
        $cmd.CommandTimeout = $TimeoutSec
        Add-PSNessusSqliteParameters -Command $cmd -Parameters $Parameters
        return $cmd.ExecuteScalar()
    }
    finally {
        $cmd.Dispose()
    }
}

function Invoke-PSNessusSqliteNonQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Query,
        [hashtable]$Parameters,
        [object]$Connection,
        [int]$TimeoutSec = 30
    )

    $cn = Get-InternalPSNessusSqliteConnection -Connection:$Connection
    $cmd = $cn.CreateCommand()
    try {
        $cmd.CommandText = $Query
        $cmd.CommandTimeout = $TimeoutSec
        Add-PSNessusSqliteParameters -Command $cmd -Parameters $Parameters
        return $cmd.ExecuteNonQuery()
    }
    finally {
        $cmd.Dispose()
    }
}

function Invoke-PSNessusSqliteQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Query,
        [hashtable]$Parameters,
        [object]$Connection,
        [int]$TimeoutSec = 30
    )

    $cn = Get-InternalPSNessusSqliteConnection -Connection:$Connection
    $cmd = $cn.CreateCommand()
    $dataTable = New-Object System.Data.DataTable
    try {
        $cmd.CommandText = $Query
        $cmd.CommandTimeout = $TimeoutSec
        Add-PSNessusSqliteParameters -Command $cmd -Parameters $Parameters
        $adapter = [System.Data.SQLite.SQLiteDataAdapter]::new($cmd)
        [void]$adapter.Fill($dataTable)
        return ,$dataTable
    }
    finally {
        $cmd.Dispose()
    }
}

function Close-PSNessusSqliteConnection {
    [CmdletBinding()]
    param(
        [object]$Connection
    )

    $cn = if ($PSBoundParameters.ContainsKey('Connection')) {
        Resolve-PSNessusSqliteConnection -InputObject $Connection
    }
    else {
        $script:PSNessusSqliteDefaultConnection
    }

    if (-not $cn) {
        return
    }

    try { $cn.Close() } catch {}
    try { $cn.Dispose() } catch {}

    if ($script:PSNessusSqliteDefaultConnection -eq $cn) {
        $script:PSNessusSqliteDefaultConnection = $null
    }
}

