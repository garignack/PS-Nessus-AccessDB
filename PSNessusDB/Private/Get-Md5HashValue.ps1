#######################################################################################################################
# File:             Private/Get-Md5HashValue.ps1
# Description:      Generates MD5 hashes for plugin uniqueness checks, matching historical behavior in legacy scripts.
# Context:          Centralizing hashing logic keeps plugin de-duplication consistent. If hash strategy changes, update
#                   this helper and legacy add-NessusHost.ps1 simultaneously.
#######################################################################################################################

function Get-Md5HashValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InputString
    )

    $algorithm = [System.Security.Cryptography.HashAlgorithm]::Create('MD5')
    $builder = New-Object System.Text.StringBuilder
    $encoder = [System.Text.Encoding]::UTF8

    foreach ($byte in $algorithm.ComputeHash($encoder.GetBytes($InputString))) {
        [void]$builder.Append($byte.ToString('x2'))
    }

    return $builder.ToString()
}
