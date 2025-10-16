#######################################################################################################################
# File:             PS-Log/Public/Switch-LogFile.ps1
# Description:      Handles log rotation by archiving existing log files and creating fresh ones before logging resumes.
# Context:          Works with New-LogFile/Write-Log; when adjusting rotation strategy or archive naming, modify this
#                   script and ensure any tooling invoking PS-Log follows the same conventions.
#######################################################################################################################

function Switch-LogFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter()]
        [int]$Arch
    )

    try {
        $pathToFile = [System.IO.Path]::GetDirectoryName($Name)
        if (-not (Test-Path -Path $pathToFile)) {
            $null = New-Item -Path $pathToFile -ItemType Directory
        }

        $pathToFile = Resolve-Path -Path $pathToFile
        $pathToFile = Add-BackslashToPath -Path $pathToFile.Path
        $isValidPath = Test-Path -Path $pathToFile -IsValid

        if (-not $Arch) {
            $Arch = $script:NumOfArchives
        }

        if (-not $isValidPath) {
            return
        }

        $gciLogPath = "$pathToFile*"
        $nameOnly = Split-Path -Path $Name -Leaf
        $logName = $nameOnly.Substring(0, $nameOnly.Length - 4)

        $defaultLogExists = Test-Path -Path $gciLogPath -Include $nameOnly

        if ($defaultLogExists) {
        $dirContent = Get-ChildItem -Path $gciLogPath -Filter "$logName*.log" |
            Sort-Object -Property Name -Descending |
            Select-Object -ExpandProperty Name

        foreach ($fileName in $dirContent) {
            $match = [regex]::Match($fileName, '^(?<base>.+)\.(?<number>\d{3})\.log$')
            if ($match.Success) {
                $logNumber = [int]$match.Groups['number'].Value

                if ($logNumber -eq $Arch) {
                    $fileToDelete = Join-Path -Path $pathToFile -ChildPath $fileName
                    Remove-Item -LiteralPath $fileToDelete -Force
                }
                else {
                    $newNumber = '{0:D3}' -f ($logNumber + 1)
                    $newName = '{0}.{1}.log' -f $match.Groups['base'].Value, $newNumber
                    $fullPath = Join-Path -Path $pathToFile -ChildPath $fileName
                    Rename-Item -Path $fullPath -NewName $newName -Force
                }
            }
        }

            $fullPath = Join-Path -Path $pathToFile -ChildPath $nameOnly
            Rename-Item -Path $fullPath -NewName "$logName.001.log" -Force
            $null = New-Item -Path $fullPath -ItemType File -Force
        }
        else {
            $fullPath = Join-Path -Path $pathToFile -ChildPath $nameOnly
            $null = New-Item -Path $fullPath -ItemType File -Force
        }
    }
    catch {
        $errorMessage = $_.Exception.Message
        Write-Host "[Switch-LogFile]: $errorMessage" -ForegroundColor Red

        $inner = $_.Exception.InnerException
        while ($inner) {
            Write-Host "[Switch-LogFile]: $($inner.Message)" -ForegroundColor Red
            $inner = $inner.InnerException
        }
    }
}
