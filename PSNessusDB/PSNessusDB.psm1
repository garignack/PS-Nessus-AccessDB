$moduleRoot = Split-Path -Path $PSCommandPath -Parent
$publicPath = Join-Path $moduleRoot 'Public'
$privatePath = Join-Path $moduleRoot 'Private'

#######################################################################################################################
# File:             PSNessusDB.psm1
# Description:      Dynamic module bootstrapper that loads all private helpers and public cmdlets before exporting them.
# Context:          Keep Private/ and Public/ folders in sync with manifest exports; PS-Log dependencies are loaded via
#                   nested modules. When adding new scripts, drop them in the appropriate folder and they will be
#                   discovered automatically during Import-Module.
#######################################################################################################################

Get-ChildItem -Path $privatePath -Filter '*.ps1' -Recurse -ErrorAction SilentlyContinue |
    Sort-Object -Property FullName |
    ForEach-Object { . $_.FullName }

$publicFunctions = Get-ChildItem -Path $publicPath -Filter '*.ps1' -ErrorAction SilentlyContinue |
    Sort-Object -Property FullName

foreach ($function in $publicFunctions) {
    . $function.FullName
}

Export-ModuleMember -Function ($publicFunctions | Select-Object -ExpandProperty BaseName)
