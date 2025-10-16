#######################################################################################################################
# File:             PS-Log/Private/Initialize-LogEnvironment.ps1
# Description:      Establishes logging constants, severity levels, and default global state for PS-Log consumers.
# Context:          This script runs before other logging helpers; update severity definitions or defaults here so all
#                   downstream functions inherit the correct configuration.
#######################################################################################################################

if (-not (Get-Variable -Name 'MSGTYPE_ALL' -Scope Script -ErrorAction SilentlyContinue)) {
    Set-Variable -Name MSGTYPE_ALL -Scope Script -Option ReadOnly -Value 0
    Set-Variable -Name MSGTYPE_TRACE -Scope Script -Option ReadOnly -Value 1
    Set-Variable -Name MSGTYPE_DEBUG -Scope Script -Option ReadOnly -Value 2
    Set-Variable -Name MSGTYPE_VERBOSE -Scope Script -Option ReadOnly -Value 3
    Set-Variable -Name MSGTYPE_INFO -Scope Script -Option ReadOnly -Value 4
    Set-Variable -Name MSGTYPE_WARN -Scope Script -Option ReadOnly -Value 5
    Set-Variable -Name MSGTYPE_ERROR -Scope Script -Option ReadOnly -Value 6
    Set-Variable -Name MSGTYPE_FATAL -Scope Script -Option ReadOnly -Value 7
    Set-Variable -Name MSGTYPE_OFF -Scope Script -Option ReadOnly -Value 8
}

if (-not (Get-Variable -Name 'SEVERITY_DESC' -Scope Script -ErrorAction SilentlyContinue)) {
    Set-Variable -Name SEVERITY_DESC -Scope Script -Option Constant -Value @(
        'All', 'Trace', 'Debug', 'Verbose', 'Info', 'Warn', 'Error', 'Fatal'
    )
}

if (-not (Get-Variable -Name 'GLOBAL:LogLevel' -ErrorAction SilentlyContinue)) {
    [int]$GLOBAL:LogLevel = $script:MSGTYPE_INFO
}

if (-not (Get-Variable -Name 'script:LogFileName' -ErrorAction SilentlyContinue)) {
    $script:LogFileName = [System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath) + '.log'
}

if (-not (Get-Variable -Name 'script:ScriptName' -ErrorAction SilentlyContinue)) {
    $script:ScriptName = [System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
}

if (-not (Get-Variable -Name 'script:NumOfArchives' -ErrorAction SilentlyContinue)) {
    [int]$script:NumOfArchives = 10
}
