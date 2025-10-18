#######################################################################################################################
# File:             PSNessusDB.psd1                                                                                   #
# Author:           Garignack                                                                                         #
# Publisher:                                                                                                          #
# Copyright:        c 2013 . All rights reserved.                                                                     #
# Link:            https://github.com/garignack/PS-Nessus-AccessDB                                                        #
#######################################################################################################################

@{

# Script module or binary module file associated with this manifest
ModuleToProcess = 'PSNessusDB.psm1'

# Version number of this module.
ModuleVersion = '0.0.2.0'

# ID used to uniquely identify this module
GUID = '{5c79f04c-70b7-456a-839d-90c7c5453307}'

# Author of this module
Author = 'Garignack'

# Company or vendor of this module
CompanyName = ''

# Copyright statement for this module
Copyright = 'c 2013 . All rights reserved.'

# Description of the functionality provided by this module
Description = 'Imports a Nessus_V2 file into a database using Access today with an extensible provider surface for SQLite.'

# Minimum version of the Windows PowerShell engine required by this module
PowerShellVersion = '2.0'

# Minimum version of the .NET Framework required by this module
DotNetFrameworkVersion = '2.0'

# Minimum version of the common language runtime (CLR) required by this module
CLRVersion = '2.0.50727'

# Processor architecture (None, X86, Amd64, IA64) required by this module
ProcessorArchitecture = 'None'

# Modules that must be imported into the global environment prior to importing
# this module
RequiredModules = @()

# Assemblies that must be loaded prior to importing this module
RequiredAssemblies = @()

# Script files (.ps1) that are run in the caller's environment prior to
# importing this module
ScriptsToProcess = @()

# Type files (.ps1xml) to be loaded when importing this module
TypesToProcess = @()

# Format files (.ps1xml) to be loaded when importing this module
FormatsToProcess = @()

# Modules to import as nested modules of the module specified in
# ModuleToProcess
NestedModules = @(
    '.\PS-Log.psm1'
    '.\PS-Sqlite.psm1'
)

# Functions to export from this module
FunctionsToExport = @('Import-PSNessusDB', 'Export-PSNessusReportMatrix', 'Export-PSNessusAccessDatabase')

# Cmdlets to export from this module
CmdletsToExport = @()

# Variables to export from this module
VariablesToExport = @()

# Aliases to export from this module
AliasesToExport = @()

# List of all modules packaged with this module
ModuleList = @()

# List of all files packaged with this module
FileList = @(
    '.\PSNessusDB.psm1'
    '.\PSNessusDB.psd1'
    '.\PS-Log.psm1'
    '.\PS-Sqlite.psm1'
    '.\Public\Import-PSNessusDB.ps1'
    '.\Public\Export-PSNessusReportMatrix.ps1'
    '.\Public\Export-PSNessusAccessDatabase.ps1'
    '.\Private\Add-PSNessusHostRecord.ps1'
    '.\Private\Database\AccessProvider.ps1'
    '.\Private\Export\Invoke-PSNessusSqliteToAccessExport.ps1'
    '.\Private\FileCutterUtilities.ps1'
    '.\Private\Get-Md5HashValue.ps1'
    '.\Private\Invoke-Logger.ps1'
    '.\PS-Log\Private\Initialize-LogEnvironment.ps1'
    '.\PS-Log\Private\Add-BackslashToPath.ps1'
    '.\PS-Log\Private\Write-Log.ps1'
    '.\PS-Log\Public\Get-ScriptInfo.ps1'
    '.\PS-Log\Public\Switch-LogFile.ps1'
    '.\PS-Log\Public\New-LogFile.ps1'
    '.\PS-Sqlite\Private\Initialize-PSNessusSqliteEnvironment.ps1'
    '.\PS-Sqlite\Public\PSNessusSqliteCommands.ps1'
    '.\PS-Sqlite\Lib\System.Data.SQLite.dll'
    '.\PS-Sqlite\Lib\e_sqlite3.dll'
)

# Private data to pass to the module specified in ModuleToProcess
PrivateData = ''

}

