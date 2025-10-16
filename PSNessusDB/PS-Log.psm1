$moduleRoot = Split-Path -Path $PSCommandPath -Parent
$componentRoot = Join-Path -Path $moduleRoot -ChildPath 'PS-Log'
$privateRoot = Join-Path -Path $componentRoot -ChildPath 'Private'
$publicRoot = Join-Path -Path $componentRoot -ChildPath 'Public'

#######################################################################################################################
# File:             PS-Log.psm1
# Description:      Internal logging module bootstrapper that loads shared logging utilities (Private) and exported
#                   logging functions (Public) used across the PSNessus solution.
# Context:          Ensure Private scripts define the underlying logging mechanics while Public scripts expose the API.
#                   When evolving logging behavior, adjust Private implementations first so consumers stay untouched.
#######################################################################################################################

$initializePath = Join-Path -Path $privateRoot -ChildPath 'Initialize-LogEnvironment.ps1'
if (Test-Path -Path $initializePath) {
    . $initializePath
}

Get-ChildItem -Path $privateRoot -Filter '*.ps1' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -ne $initializePath } |
    Sort-Object -Property FullName |
    ForEach-Object { . $_.FullName }

$publicFunctions = Get-ChildItem -Path $publicRoot -Filter '*.ps1' -ErrorAction SilentlyContinue |
    Sort-Object -Property FullName

foreach ($function in $publicFunctions) {
    . $function.FullName
}

Export-ModuleMember -Function ($publicFunctions | Select-Object -ExpandProperty BaseName)
