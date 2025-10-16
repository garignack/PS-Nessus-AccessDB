$script:PSNessusSqliteInitialized = $false
$script:PSNessusSqliteDefaultConnection = $null

function Initialize-PSNessusSqliteEnvironment {
    if ($script:PSNessusSqliteInitialized) {
        return
    }

    $libPath = Join-Path $script:PSNessusSqliteModuleRoot 'Lib'

    if ($env:PATH -notlike "*$libPath*") {
        $env:PATH = "$libPath;$($env:PATH)"
    }

    Get-ChildItem -Path $libPath -Filter '*.dll' -File -ErrorAction SilentlyContinue |
        ForEach-Object { Unblock-File -Path $_.FullName -ErrorAction SilentlyContinue }

    $assemblyPath = Join-Path $libPath 'System.Data.SQLite.dll'
    if (-not (Test-Path -Path $assemblyPath)) {
        throw "Required assembly not found: $assemblyPath"
    }

    $alreadyLoaded = [AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object { $_.Location -eq $assemblyPath }

    if (-not $alreadyLoaded) {
        try {
            Add-Type -Path $assemblyPath | Out-Null
        }
        catch {
            throw "Failed to load System.Data.SQLite assembly from '$assemblyPath'. $_"
        }
    }

    $script:PSNessusSqliteInitialized = $true
}

function Resolve-PSNessusSqliteConnection {
    param(
        [Parameter(Mandatory)][object]$InputObject
    )

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [System.Data.SQLite.SQLiteConnection]) {
        return $InputObject
    }

    $prop = $InputObject.PSObject.Properties['Connection']
    if ($prop -and $prop.Value -is [System.Data.SQLite.SQLiteConnection]) {
        return $prop.Value
    }

    return $null
}

function Get-InternalPSNessusSqliteConnection {
    param(
        [object]$Connection
    )

    $cn = $null
    if ($PSBoundParameters.ContainsKey('Connection')) {
        $cn = Resolve-PSNessusSqliteConnection -InputObject $Connection
    }
    else {
        $cn = $script:PSNessusSqliteDefaultConnection
    }

    if (-not $cn) {
        throw 'No active SQLite connection. Call Open-PSNessusSqliteConnection first or pass -Connection.'
    }

    if ($cn.State -ne [System.Data.ConnectionState]::Open) {
        throw 'SQLite connection is not open.'
    }

    return $cn
}

function Add-PSNessusSqliteParameters {
    param(
        [Parameter(Mandatory)][System.Data.SQLite.SQLiteCommand]$Command,
        [hashtable]$Parameters
    )

    if (-not $Parameters) {
        return
    }

    foreach ($key in $Parameters.Keys) {
        $name = [string]$key
        if ($name -notmatch '^[@:$.]') {
            $name = '@' + $name
        }

        $parameter = $Command.CreateParameter()
        $parameter.ParameterName = $name
        $value = $Parameters[$key]
        if ($null -eq $value) {
            $value = [DBNull]::Value
        }
        $parameter.Value = $value
        [void]$Command.Parameters.Add($parameter)
    }
}
