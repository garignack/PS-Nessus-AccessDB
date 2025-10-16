#######################################################################################################################
# File:             PS-Log/Private/Add-BackslashToPath.ps1
# Description:      Ensures log file paths end with a trailing backslash so file rotation logic can rely on consistent
#                   formatting.
# Context:          Internal PS-Log helper; keep adjustments here when supporting cross-platform path separators or new
#                   rotation strategies.
#######################################################################################################################

function Add-BackslashToPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -Path $Path -IsValid)) {
        throw "Invalid path '$Path'"
    }

    if ($Path -match '\\$') {
        return $Path
    }

    return "$Path\"
}
