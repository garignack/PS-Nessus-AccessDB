@{
    RootModule        = 'pssqlite.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'a7a7df2a-7c0d-4d68-9a46-2b4fd2698a7b'
    Author            = 'pssqlite maintainers'
    CompanyName       = ''
    Copyright        = ''
    Description       = 'Lightweight PowerShell helpers to work with SQLite via System.Data.SQLite.'
    PowerShellVersion = '5.1'
    RequiredAssemblies = @('System.Data.SQLite.dll')

    FunctionsToExport = @(
        'Open-SqliteConnection',
        'Get-ActiveSqliteConnection',
        'Invoke-SqliteScalar',
        'Invoke-SqliteNonQuery',
        'Invoke-SqliteQuery',
        'Close-SqliteConnection'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{}
}
