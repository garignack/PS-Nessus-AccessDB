#######################################################################################################################
# File:             Private/Invoke-Logger.ps1
# Description:      Thin wrapper that safely proxies logging calls into PS-Log objects while allowing temporary source
#                   overrides for more readable log output.
# Context:          Imported by host processing and other components. When adding structured logging needs, enhance this
#                   helper so call sites remain minimal.
#######################################################################################################################

function Invoke-Logger {
    [CmdletBinding()]
    param(
        [Parameter()]
        [psobject]$Logger,

        [Parameter(Mandatory)]
        [ValidateSet('Trace', 'Debug', 'Verbose', 'Info', 'Warn', 'Error', 'Fatal')]
        [string]$Method,

        [Parameter(Mandatory)]
        [string]$Message,

        [string]$Source,

        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    if (-not $Logger) {
        return
    }

    $methods = $Logger.PSObject.Methods.Name
    if ($methods -contains $Method) {
        $originalSource = $null
        $hasSourceProperty = $Logger.PSObject.Properties.Name -contains 'ScriptBaseName'
        if ($Source -and $hasSourceProperty) {
            $originalSource = $Logger.ScriptBaseName
            $Logger.ScriptBaseName = $Source
        }

        try {
            if ($PSBoundParameters.ContainsKey('ErrorRecord') -and $ErrorRecord) {
                $null = $Logger.$Method.Invoke($Message, $ErrorRecord)
            }
            else {
                $null = $Logger.$Method.Invoke($Message)
            }
        }
        finally {
            if ($Source -and $hasSourceProperty) {
                $Logger.ScriptBaseName = $originalSource
            }
        }
    }
}
