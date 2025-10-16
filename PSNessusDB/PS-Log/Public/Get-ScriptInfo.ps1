#######################################################################################################################
# File:             PS-Log/Public/Get-ScriptInfo.ps1
# Description:      Retrieves script base information (name, path) and seeds PS-Log state for callers.
# Context:          Keeps legacy workflows working; when changing default log naming conventions, update this function
#                   in tandem with Initialize-LogEnvironment.
#######################################################################################################################

function Get-ScriptInfo {
    [CmdletBinding()]
    param()

    try {
        $scriptPath = $MyInvocation.ScriptName
        Write-Debug "script path: $scriptPath"
        $scriptName = [System.IO.Path]::GetFileNameWithoutExtension($scriptPath)
        $scriptDir = [System.IO.Path]::GetDirectoryName($scriptPath)

        if ([string]::IsNullOrWhiteSpace($scriptDir)) {
            $currentPath = Resolve-Path -Path '.'
            $scriptDir = $currentPath.Path
        }

        return [pscustomobject]@{
            Name = $scriptName
            Path = $scriptDir
        }
    }
    catch {
        $errorMessage = $_.Exception.Message
        Write-Host "[Get-ScriptInfo]: $errorMessage" -ForegroundColor Red

        $inner = $_.Exception.InnerException
        while ($inner) {
            Write-Host "[Get-ScriptInfo]: $($inner.Message)" -ForegroundColor Red
            $inner = $inner.InnerException
        }
    }
    finally {
        if ($scriptName) {
            $script:ScriptName = $scriptName
        }
        if ($scriptDir -and $scriptName) {
            $script:LogFileName = Join-Path -Path $scriptDir -ChildPath ($scriptName + '.log')
        }
    }
}
