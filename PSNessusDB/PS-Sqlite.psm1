$script:PSNessusSqliteModuleRoot = Split-Path -Path $PSCommandPath -Parent
$script:PSNessusSqliteModuleRoot = Join-Path $script:PSNessusSqliteModuleRoot 'PS-Sqlite'

$publicPath = Join-Path $script:PSNessusSqliteModuleRoot 'Public'
$privatePath = Join-Path $script:PSNessusSqliteModuleRoot 'Private'

# Load private helpers first
Get-ChildItem -Path $privatePath -Filter '*.ps1' -ErrorAction SilentlyContinue |
    Sort-Object -Property FullName |
    ForEach-Object { . $_.FullName }

# Initialize environment once private functions are available
Initialize-PSNessusSqliteEnvironment

# Load public commands
$publicFunctions = Get-ChildItem -Path $publicPath -Filter '*.ps1' -ErrorAction SilentlyContinue |
    Sort-Object -Property FullName

foreach ($function in $publicFunctions) {
    . $function.FullName
}

Export-ModuleMember -Function @('Open-PSNessusSqliteConnection','Get-PSNessusSqliteConnection','Invoke-PSNessusSqliteScalar','Invoke-PSNessusSqliteNonQuery','Invoke-PSNessusSqliteQuery','Close-PSNessusSqliteConnection')

