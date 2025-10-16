#######################################################################################################################
# File:             PS-Log/Private/Write-Log.ps1
# Description:      Core logging routine that formats messages, writes to disk, and mirrors output to the console based
#                   on severity.
# Context:          Invoked via New-LogFile script methods; adjust formatting or severity routing here to affect every
#                   consumer. Remember Host/Tabs info is derived from Invoke-Logger overrides.
#######################################################################################################################

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$ScriptName = $script:ScriptName,

        [Parameter()]
        [string]$LogName = $script:LogFileName,

        [Parameter(Mandatory)]
        [int]$LogLevel = $GLOBAL:LogLevel,

        [Parameter(Mandatory)]
        [ValidateSet(0, 1, 2, 3, 4, 5, 6, 7)]
        [int]$Severity,

        [Parameter()]
        [string]$Message,

        [Parameter()]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    try {
        if ($Severity -lt $LogLevel) {
            return
        }

        if ($null -eq $Message) {
            $Message = ''
        }

        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

        $callerName = $ScriptName
        if ([string]::IsNullOrWhiteSpace($callerName)) {
            $stack = Get-PSCallStack | Where-Object { $_.InvocationInfo -and $_.InvocationInfo.MyCommand }
            $callerName = ($stack | Where-Object {
                    $name = $_.InvocationInfo.MyCommand.Name
                    $name -and $name -notin @('Write-Log', 'Invoke-Logger')
                } | Select-Object -First 1).InvocationInfo.MyCommand.Name
        }
        if ([string]::IsNullOrWhiteSpace($callerName)) {
            $callerName = 'CLI'
        }

        if ($ErrorRecord) {
            $segments = @()

            $exceptionMessage = $ErrorRecord.Exception.Message
            if (-not [string]::IsNullOrWhiteSpace($exceptionMessage)) {
                $segments += ("Exception={0}" -f $exceptionMessage.Trim())
            }

            $invocation = $ErrorRecord.InvocationInfo
            if ($invocation) {
                $scriptPath = $invocation.ScriptName
                if ([string]::IsNullOrWhiteSpace($scriptPath) -and $invocation.MyCommand) {
                    $scriptPath = $invocation.MyCommand.Path
                }

                if (-not [string]::IsNullOrWhiteSpace($scriptPath)) {
                    $segments += ("Script={0}" -f $scriptPath)
                }

                if ($invocation.ScriptLineNumber) {
                    $segments += ("Line={0}" -f $invocation.ScriptLineNumber)
                }

                if ($invocation.OffsetInLine) {
                    $segments += ("Column={0}" -f $invocation.OffsetInLine)
                }

                $lineText = $invocation.Line
                if (-not [string]::IsNullOrWhiteSpace($lineText)) {
                    $segments += ("Code={0}" -f $lineText.Trim())
                }
            }

            if ($ErrorRecord.FullyQualifiedErrorId) {
                $segments += ("FQID={0}" -f $ErrorRecord.FullyQualifiedErrorId)
            }

            if ($ErrorRecord.CategoryInfo) {
                $segments += ("Category={0}" -f $ErrorRecord.CategoryInfo)
            }

            if ($ErrorRecord.ScriptStackTrace) {
                $segments += ("StackTrace={0}" -f (($ErrorRecord.ScriptStackTrace -replace '\r?\n', ' > ').Trim()))
            }

            $recordText = $ErrorRecord.ToString()
            if (-not [string]::IsNullOrWhiteSpace($recordText)) {
                $segments += ("ErrorRecord={0}" -f ($recordText -replace '\r?\n', ' ').Trim())
            }

            if ($segments.Count -gt 0) {
                $errorSummary = $segments -join ' | '
                if ([string]::IsNullOrWhiteSpace($Message)) {
                    $Message = $errorSummary
                }
                else {
                    $Message = "{0} | {1}" -f $Message, $errorSummary
                }
            }
        }

        $output = "{0}`t[{1}]: ({2})`t{3}" -f $timestamp, $script:SEVERITY_DESC[$Severity], $callerName, $Message

        Add-Content -Path $LogName -Value $output

        switch ($Severity) {
            { $_ -eq $script:MSGTYPE_TRACE } { Write-Host $output -ForegroundColor Green; break }
            { $_ -eq $script:MSGTYPE_DEBUG } { Write-Host $output -ForegroundColor Blue; break }
            { $_ -eq $script:MSGTYPE_VERBOSE } { Write-Host $output -ForegroundColor Magenta; break }
            { $_ -eq $script:MSGTYPE_INFO } { Write-Host $output -ForegroundColor White; break }
            { $_ -eq $script:MSGTYPE_WARN } { Write-Host $output -ForegroundColor Yellow; break }
            { $_ -eq $script:MSGTYPE_ERROR } { Write-Host $output -ForegroundColor Red; break }
            { $_ -eq $script:MSGTYPE_FATAL } { Write-Host $output -ForegroundColor Red; break }
        }
    }
    catch {
        $errorMessage = $_.Exception.Message
        Write-Host "[Write-Log]: $errorMessage" -ForegroundColor Red

        $inner = $_.Exception.InnerException
        while ($inner) {
            Write-Host "[Write-Log]: $($inner.Message)" -ForegroundColor Red
            $inner = $inner.InnerException
        }
    }
}
