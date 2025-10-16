#######################################################################################################################
# File:             PS-Log/Public/New-LogFile.ps1
# Description:      Creates PS-Log objects with helper methods (Trace/Debug/Info/etc.) bound to Write-Log.
# Context:          Primary entrypoint for consumers; if severity handling or object shape changes, update this script
#                   alongside Write-Log.ps1 and Invoke-Logger.ps1 to stay aligned.
#######################################################################################################################

function New-LogFile {
    [CmdletBinding()]
    param(
        [Alias('Name')]
        [string]$ScriptName = $script:ScriptName,

        [Alias('Path', 'LogFileName')]
        [string]$LogName = $script:LogFileName,

        [Alias('LogLevel')]
        [int]$LogConfigLevel = $GLOBAL:LogLevel
    )

    try {
        New-Object -TypeName PSObject |
            Add-Member -MemberType NoteProperty -Name LogFileName -Value $LogName -PassThru |
            Add-Member -MemberType NoteProperty -Name ScriptBaseName -Value $ScriptName -PassThru |
            Add-Member -MemberType NoteProperty -Name LogLevel -Value $LogConfigLevel -PassThru |
            Add-Member -MemberType ScriptMethod -Name Trace -Value {
                param(
                    [Parameter()]
                    [object]$Message,
                    [System.Management.Automation.ErrorRecord]$ErrorRecord
                )

                $messageText = [string]$Message
                Write-Log -ScriptName $this.ScriptBaseName -LogName $this.LogFileName -LogLevel $this.LogLevel -Severity $script:MSGTYPE_TRACE -Message $messageText -ErrorRecord $ErrorRecord
            } -PassThru |
            Add-Member -MemberType ScriptMethod -Name Debug -Value {
                param(
                    [Parameter()]
                    [object]$Message,
                    [System.Management.Automation.ErrorRecord]$ErrorRecord
                )

                $messageText = [string]$Message
                Write-Log -ScriptName $this.ScriptBaseName -LogName $this.LogFileName -LogLevel $this.LogLevel -Severity $script:MSGTYPE_DEBUG -Message $messageText -ErrorRecord $ErrorRecord
            } -PassThru |
            Add-Member -MemberType ScriptMethod -Name Verbose -Value {
                param(
                    [Parameter()]
                    [object]$Message,
                    [System.Management.Automation.ErrorRecord]$ErrorRecord
                )

                $messageText = [string]$Message
                Write-Log -ScriptName $this.ScriptBaseName -LogName $this.LogFileName -LogLevel $this.LogLevel -Severity $script:MSGTYPE_VERBOSE -Message $messageText -ErrorRecord $ErrorRecord
            } -PassThru |
            Add-Member -MemberType ScriptMethod -Name Info -Value {
                param(
                    [Parameter()]
                    [object]$Message,
                    [System.Management.Automation.ErrorRecord]$ErrorRecord
                )

                $messageText = [string]$Message
                Write-Log -ScriptName $this.ScriptBaseName -LogName $this.LogFileName -LogLevel $this.LogLevel -Severity $script:MSGTYPE_INFO -Message $messageText -ErrorRecord $ErrorRecord
            } -PassThru |
            Add-Member -MemberType ScriptMethod -Name Warn -Value {
                param(
                    [Parameter()]
                    [object]$Message,
                    [System.Management.Automation.ErrorRecord]$ErrorRecord
                )

                $messageText = [string]$Message
                Write-Log -ScriptName $this.ScriptBaseName -LogName $this.LogFileName -LogLevel $this.LogLevel -Severity $script:MSGTYPE_WARN -Message $messageText -ErrorRecord $ErrorRecord
            } -PassThru |
            Add-Member -MemberType ScriptMethod -Name Error -Value {
                param(
                    [Parameter()]
                    [object]$Message,
                    [System.Management.Automation.ErrorRecord]$ErrorRecord
                )

                $messageText = [string]$Message
                Write-Log -ScriptName $this.ScriptBaseName -LogName $this.LogFileName -LogLevel $this.LogLevel -Severity $script:MSGTYPE_ERROR -Message $messageText -ErrorRecord $ErrorRecord
            } -PassThru |
            Add-Member -MemberType ScriptMethod -Name Fatal -Value {
                param(
                    [Parameter()]
                    [object]$Message,
                    [System.Management.Automation.ErrorRecord]$ErrorRecord
                )

                $messageText = [string]$Message
                Write-Log -ScriptName $this.ScriptBaseName -LogName $this.LogFileName -LogLevel $this.LogLevel -Severity $script:MSGTYPE_FATAL -Message $messageText -ErrorRecord $ErrorRecord
            } -PassThru
    }
    catch {
        $errorMessage = $_.Exception.Message
        Write-Host "[New-LogFile]: $errorMessage" -ForegroundColor Red

        $inner = $_.Exception.InnerException
        while ($inner) {
            Write-Host "[New-LogFile]: $($inner.Message)" -ForegroundColor Red
            $inner = $inner.InnerException
        }
    }
}
