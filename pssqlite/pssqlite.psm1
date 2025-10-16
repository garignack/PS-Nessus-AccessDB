$ErrorActionPreference = 'Stop'

$moduleRoot = $PSScriptRoot

# Ensure native e_sqlite3.dll is resolvable from module folder
if ($env:PATH -notlike "*$moduleRoot*") {
    $env:PATH = "$moduleRoot;$env:PATH"
}

# Unblock potentially downloaded assemblies in module (ignore if not blocked)
Get-ChildItem -Path $moduleRoot -File -Recurse -Include *.dll -ErrorAction SilentlyContinue |
    ForEach-Object { Unblock-File -Path $_.FullName -ErrorAction SilentlyContinue }

function Load-Assembly {
    param(
        [Parameter(Mandatory)][string]$RelativePath
    )
    $path = Join-Path $moduleRoot $RelativePath
    if (-not (Test-Path $path)) {
        throw "Required assembly not found: $path"
    }
    $alreadyLoaded = [AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.Location -eq $path }
    if (-not $alreadyLoaded) {
        try { Add-Type -Path $path | Out-Null }
        catch {
            throw "Failed to load assembly at '$path'. Ensure architecture matches (x64 vs x86) and native 'e_sqlite3.dll' is available on PATH. Error: $($_.Exception.Message)"
        }
    }
}

# Load System.Data.SQLite from module folder
Load-Assembly -RelativePath 'System.Data.SQLite.dll'

$script:DefaultConnection = $null

function Resolve-ConnectionObject {
    param(
        [Parameter(Mandatory)]$InputObject
    )
    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [System.Data.SQLite.SQLiteConnection]) { return $InputObject }
    $prop = $InputObject.PSObject.Properties['Connection']
    if ($prop -and $prop.Value -is [System.Data.SQLite.SQLiteConnection]) { return $prop.Value }
    return $null
}

function Get-ActiveSqliteConnection {
    [CmdletBinding()]
    param(
        [Alias('Database')]
        [object]$Connection
    )
    $cn = $null
    if ($PSBoundParameters.ContainsKey('Connection')) {
        $cn = Resolve-ConnectionObject -InputObject $Connection
    } else {
        $cn = $script:DefaultConnection
        if (-not $cn -and $global:SqliteConnection) {
            $cn = Resolve-ConnectionObject -InputObject $global:SqliteConnection
        }
    }
    if (-not $cn) { throw 'No active SQLite connection. Use Open-SqliteConnection first or pass -Connection.' }
    if ($cn.State -ne 'Open') { throw 'SQLite connection is not open.' }
    return $cn
}

function Open-SqliteConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Database
    )
    $csb = [System.Data.SQLite.SQLiteConnectionStringBuilder]::new()
    $csb.DataSource = $Database
    $csb.Version = 3
    $csb['Foreign Keys'] = $true
    $connString = $csb.ToString()

    $cn = [System.Data.SQLite.SQLiteConnection]::new($connString)
    try { $cn.Open() }
    catch { throw "Failed to open SQLite connection to '$Database'. Error: $($_.Exception.Message)" }
    $script:DefaultConnection = $cn

    # Return a wrapper object that exposes convenience methods
    $ctx = [pscustomobject]@{
        Connection = $cn
        Database   = $Database
    }
    Add-Member -InputObject $ctx -MemberType ScriptMethod -Name SqliteScalar -Value {
        param([string]$Query, [hashtable]$Parameters, [int]$TimeoutSec = 30)
        $cmd = $this.Connection.CreateCommand()
        try {
            $cmd.CommandText = $Query
            $cmd.CommandTimeout = $TimeoutSec
            Add-ParamsInternal -Command $cmd -Parameters $Parameters
            $cmd.ExecuteScalar()
        }
        finally { $cmd.Dispose() }
    } | Out-Null
    Add-Member -InputObject $ctx -MemberType ScriptMethod -Name SqliteNonQuery -Value {
        param([string]$Query, [hashtable]$Parameters, [int]$TimeoutSec = 30)
        $cmd = $this.Connection.CreateCommand()
        try {
            $cmd.CommandText = $Query
            $cmd.CommandTimeout = $TimeoutSec
            Add-ParamsInternal -Command $cmd -Parameters $Parameters
            $cmd.ExecuteNonQuery()
        }
        finally { $cmd.Dispose() }
    } | Out-Null
    Add-Member -InputObject $ctx -MemberType ScriptMethod -Name SqliteQuery -Value {
        param([string]$Query, [hashtable]$Parameters, [int]$TimeoutSec = 30)
        $cmd = $this.Connection.CreateCommand()
        try {
            $cmd.CommandText = $Query
            $cmd.CommandTimeout = $TimeoutSec
            Add-ParamsInternal -Command $cmd -Parameters $Parameters
            $reader = $cmd.ExecuteReader()
            try {
                $cols = for ($i = 0; $i -lt $reader.FieldCount; $i++) { $reader.GetName($i) }
                while ($reader.Read()) {
                    $row = [ordered]@{}
                    for ($i = 0; $i -lt $cols.Count; $i++) { $row[$cols[$i]] = $reader.GetValue($i) }
                    [pscustomobject]$row
                }
            }
            finally { $reader.Dispose() }
        }
        finally { $cmd.Dispose() }
    } | Out-Null
    Add-Member -InputObject $ctx -MemberType ScriptMethod -Name Close -Value {
        try { $this.Connection.Close() } catch {}
        try { $this.Connection.Dispose() } catch {}
        if ($script:DefaultConnection -eq $this.Connection) { $script:DefaultConnection = $null }
        $true
    } | Out-Null

    return $ctx
}

function Add-ParamsInternal {
    param(
        [Parameter(Mandatory)]$Command,
        [hashtable]$Parameters
    )
    if (-not $Parameters) { return }
    foreach ($k in $Parameters.Keys) {
        $name = [string]$k
        if ($name -notmatch '^[@:$.]') { $name = '@' + $name }
        $p = $Command.CreateParameter()
        $p.ParameterName = $name
        $val = $Parameters[$k]
        if ($null -eq $val) { $val = [DBNull]::Value }
        $p.Value = $val
        [void]$Command.Parameters.Add($p)
    }
}

function Invoke-SqliteScalar {
    [CmdletBinding()]
    param(
        [Alias('Database')]
        [object]$Connection,
        [Parameter(Mandatory)][string]$Query,
        [hashtable]$Parameters,
        [int]$TimeoutSec = 30
    )
    $cn = if ($PSBoundParameters.ContainsKey('Connection')) { Get-ActiveSqliteConnection -Connection $Connection } else { Get-ActiveSqliteConnection }
    $cmd = $cn.CreateCommand()
    try {
        $cmd.CommandText = $Query
        $cmd.CommandTimeout = $TimeoutSec
        Add-ParamsInternal -Command $cmd -Parameters $Parameters
        return $cmd.ExecuteScalar()
    }
    finally { $cmd.Dispose() }
}

function Invoke-SqliteNonQuery {
    [CmdletBinding()]
    param(
        [Alias('Database')]
        [object]$Connection,
        [Parameter(Mandatory)][string]$Query,
        [hashtable]$Parameters,
        [int]$TimeoutSec = 30
    )
    $cn = if ($PSBoundParameters.ContainsKey('Connection')) { Get-ActiveSqliteConnection -Connection $Connection } else { Get-ActiveSqliteConnection }
    $cmd = $cn.CreateCommand()
    try {
        $cmd.CommandText = $Query
        $cmd.CommandTimeout = $TimeoutSec
        Add-ParamsInternal -Command $cmd -Parameters $Parameters
        return $cmd.ExecuteNonQuery()
    }
    finally { $cmd.Dispose() }
}

function Invoke-SqliteQuery {
    [CmdletBinding()]
    param(
        [Alias('Database')]
        [object]$Connection,
        [Parameter(Mandatory)][string]$Query,
        [hashtable]$Parameters,
        [int]$TimeoutSec = 30
    )
    $cn = if ($PSBoundParameters.ContainsKey('Connection')) { Get-ActiveSqliteConnection -Connection $Connection } else { Get-ActiveSqliteConnection }
    $cmd = $cn.CreateCommand()
    try {
        $cmd.CommandText = $Query
        $cmd.CommandTimeout = $TimeoutSec
        Add-ParamsInternal -Command $cmd -Parameters $Parameters
        $reader = $cmd.ExecuteReader()
        try {
            $cols = for ($i = 0; $i -lt $reader.FieldCount; $i++) { $reader.GetName($i) }
            while ($reader.Read()) {
                $row = [ordered]@{}
                for ($i = 0; $i -lt $cols.Count; $i++) {
                    $row[$cols[$i]] = $reader.GetValue($i)
                }
                [pscustomobject]$row
            }
        }
        finally { $reader.Dispose() }
    }
    finally { $cmd.Dispose() }
}

function Close-SqliteConnection {
    [CmdletBinding()]
    param(
        [Alias('Database')]
        [object]$Connection
    )
    if ($PSBoundParameters.ContainsKey('Connection')) {
        $cn = Resolve-ConnectionObject -InputObject $Connection
        try { $cn.Close() } catch {}
        try { $cn.Dispose() } catch {}
        if ($script:DefaultConnection -eq $cn) { $script:DefaultConnection = $null }
        Write-Host 'SQLite connection closed.' -ForegroundColor Yellow
        return
    }
    if ($script:DefaultConnection) {
        try { $script:DefaultConnection.Close() } catch {}
        try { $script:DefaultConnection.Dispose() } catch {}
        $script:DefaultConnection = $null
        Write-Host 'SQLite connection closed.' -ForegroundColor Yellow
    } else {
        Write-Host 'No SQLite connection to close.' -ForegroundColor DarkYellow
    }
}

Export-ModuleMember -Function Open-SqliteConnection, Get-ActiveSqliteConnection, Invoke-SqliteScalar, Invoke-SqliteNonQuery, Invoke-SqliteQuery, Close-SqliteConnection
