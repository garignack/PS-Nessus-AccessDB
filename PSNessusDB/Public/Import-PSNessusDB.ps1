#######################################################################################################################
# File:             Public/Import-PSNessusDB.ps1
# Description:      Top-level cmdlet that orchestrates Nessus file ingestion into Access (and future providers) with
#                   logging, plugin de-duplication, and host parsing.
# Context:          This is the user-facing entry point; coordinate changes with Add-PSNessusHostRecord, AccessProvider,
#                   and PS-Log modules. Keep parameter behavior aligned with legacy scripts when introducing new options.
#######################################################################################################################

function Import-PSNessusDB {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, HelpMessage = 'The Directory of Nessus Files to Process', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('f', 'file')]
        [ValidateScript({ Test-Path $_ })]
        [string]$FullName,

        [Parameter(Mandatory, HelpMessage = 'Database to import results to')]
        [Alias('d', 'AccessDB')]
        [ValidateScript({ Test-Path $_ })]
        [string]$DatabasePath,

        [Parameter(HelpMessage = 'The Log File to write logging information to. Defaults to database name .log')]
        [Alias('l')]
        [string]$LogFileName,

        [Parameter()]
        [ValidateSet('Access', 'SQLite')]
        [string]$Provider = 'Access',

        [Parameter(Mandatory = $false, HelpMessage = 'Enable All Logging')]
        [switch]$Trace,

        [Parameter(Mandatory = $false, HelpMessage = 'Disable All Logging')]
        [switch]$NoLog
    )

    begin {
        $moduleRoot = $PSScriptRoot
        $resolvedDatabasePath = (Resolve-Path -Path $DatabasePath).ProviderPath
        $outputDirectory = [System.IO.Path]::GetDirectoryName($resolvedDatabasePath)

        if (-not $LogFileName) {
            $LogFileName = Join-Path $outputDirectory ("{0}.log" -f [System.IO.Path]::GetFileNameWithoutExtension($resolvedDatabasePath))
        }

        try {
            Switch-LogFile -Name $LogFileName
        }
        catch {
            $LogFileName = Join-Path ([System.IO.Path]::GetTempPath()) ("{0}.log" -f [System.IO.Path]::GetFileNameWithoutExtension($resolvedDatabasePath))
            Write-Warning "Error creating log file, results will be logged to: $LogFileName"
        }

        [int]$loggingLevel = $GLOBAL:LogLevel
        if ($NoLog) { $loggingLevel = 8 }
        if ($PSCmdlet.MyInvocation.BoundParameters.ContainsKey('Verbose')) { $loggingLevel = 3 }
        if ($PSCmdlet.MyInvocation.BoundParameters.ContainsKey('Debug')) { $loggingLevel = 2 }
        if ($Trace) { $loggingLevel = 1 }

        try {
            $script:ImportLog = New-LogFile -Name 'Import-PSNessusDB' -Path $LogFileName -LogLevel $loggingLevel
            $script:ImportLog.Info("Log FileName: $LogFileName")
        }
        catch {
            Write-Host 'Error Creating PS-Log Object'
            Write-Error $_.Exception.ToString()
            throw
        }

        try {
            $script:DbContext = New-PSNessusDbContext -Path $resolvedDatabasePath -Provider $Provider
        }
        catch {
            $script:ImportLog.Fatal("Cannot connect to database $resolvedDatabasePath", $_)
            $script:ImportLog.Debug($_.Exception.ToString())
            throw "Fatal Error, Exiting"
        }

        try {
            Initialize-FileCutter
        }
        catch {
            $script:ImportLog.Debug($_.Exception.ToString())
            $script:ImportLog.Fatal('Cannot load [PSNessusDB.Cutter] library', $_)
            throw "Fatal Error, Exiting"
        }

        $script:TotalStopwatch = [Diagnostics.Stopwatch]::new()
        $script:HostStopwatch = [Diagnostics.Stopwatch]::new()
    }

    process {
        $script:TotalStopwatch.Reset()
        $script:TotalStopwatch.Start()

        $resolvedFullName = (Resolve-Path -Path $FullName).ProviderPath
        $script:ImportLog.Info('-----------------------------')
        $script:ImportLog.Info("Processing File: {0}" -f [System.IO.Path]::GetFileName($resolvedFullName))
        $script:ImportLog.Info('-----------------------------')

        $script:ImportLog.Verbose('Building Stream Reader')
        $streamReader = New-Object System.IO.StreamReader($resolvedFullName, $true)
        $fileLength = $streamReader.BaseStream.Length
        $script:ImportLog.Verbose("File size is: $fileLength")

        $script:ImportLog.Verbose('Checking if file is a Nessus_V2 export')
        [string]$fileHeader = $streamReader.ReadLine()
        $fileHeader += $streamReader.ReadLine()

        $script:ImportLog.Debug('---- Header ----')
        $script:ImportLog.Debug($fileHeader)

        if ($fileHeader.Contains('<NessusClientData_v2>') -ne $true) {
            $streamReader.Close()
            Remove-Variable -Name streamReader -ErrorAction SilentlyContinue
            $script:ImportLog.Error('File is not a Nessus_V2 export')
            throw 'Invalid Nessus export format.'
        }

        $streamReader.Close()

        $pattern = "<ReportHost "
        $script:ImportLog.Verbose("Locating ReportHost patterns: $pattern")
        $rawOffsets = [System.Collections.Generic.List[int]](Get-ByteMatchLocations -FilePath $resolvedFullName -Pattern $pattern)
        $pattern = "</ReportHost>"
        $rawHostsEnd = [System.Collections.Generic.List[int]](Get-ByteMatchLocations -FilePath $resolvedFullName -Pattern $pattern)

        $offsets = @($rawOffsets | Where-Object { $_ -ge 0 -and $_ -lt $fileLength })
        $hostsEnd = @($rawHostsEnd | Where-Object { $_ -ge 0 -and $_ -lt $fileLength })

        $script:ImportLog.Verbose("Found $($offsets.Count) ReportHost entries")

        if ($offsets.Count -eq 0) {
            $script:ImportLog.Warn('No hosts found in file.')
            return
        }

        $script:ImportLog.Verbose('Parsing report name')
        $reportName = ''

        if ($hostsEnd.Count -gt 0) {
            [byte[]]$reportBytes = Get-FileBytes -FilePath $resolvedFullName -Start 0 -End $offsets[0]
            $reportHeader = Convert-BytesToString -Bytes $reportBytes -Encoding 'UTF8'

            $reportMatch = [regex]::Match($reportHeader, '<Report\s+name="([^"]+)"', 'IgnoreCase')
            if ($reportMatch.Success) {
                $reportName = $reportMatch.Groups[1].Value
            }
            elseif (-not $reportName) {
                $policyMatch = [regex]::Match($reportHeader, '<policyName>([^<]+)</policyName>', 'IgnoreCase')
                if ($policyMatch.Success) {
                    $reportName = $policyMatch.Groups[1].Value
                }
            }
        }

        if ($reportName) {
            $reportName = $reportName.Trim()
        }
        else {
            $reportName = 'Unknown'
        }

        $script:ImportLog.Info("Report Name: $reportName")

        $fileColumns = @('reportName', 'FileLoc', 'FileName', 'ImportDate')
        $fileValues = @($reportName, $resolvedFullName, (Split-Path -Path $resolvedFullName -Leaf), (Get-Date))

        $fileId = Add-PSNessusDbRecord -Context $script:DbContext -Table 'Files' -Columns $fileColumns -Values $fileValues

        $timings = @()
        [int]$hostsProcessed = 0

        Write-Progress -Activity "Processing $reportName" -Status "Hosts: $hostsProcessed / $($offsets.Count)" -PercentComplete (($hostsProcessed / $offsets.Count) * 100)

        for ($index = 0; $index -le $offsets.Count - 1; $index++) {
            $script:HostStopwatch.Reset()
            $script:HostStopwatch.Start()

            try {
                $hostStart = $offsets[$index]
                $hostEndBoundary = -1
                if ($hostsEnd.Count -gt $index) {
                    $hostEndBoundary = $hostsEnd[$index] + 13
                }

                $hostString = Get-FileString -FilePath $resolvedFullName -Start $hostStart -End $hostEndBoundary -Encoding 'UTF8'

                $hostString = $hostString.Substring(0, ($hostString.IndexOf('</ReportHost>') + 13))
                $hostString = $hostString.Replace('><HostProperties>', ' xmlns:cm="http://www.nessus.org/cm"><HostProperties>')
                [xml]$xmlHost = $hostString
            }
            catch {
                $script:ImportLog.Error("Error processing ReportHost entry at offset $($offsets[$index])", $_)
                $script:ImportLog.Debug($_.Exception.ToString())
                continue
            }

            $script:ImportLog.Verbose("Host retrieval: $($script:HostStopwatch.ElapsedMilliseconds)ms")
            $script:ImportLog.Info("Processing[$($offsets[$index])] : $($xmlHost.ReportHost.name)")

            Add-PSNessusHostRecord -XmlHost $xmlHost -DbContext $script:DbContext -FileId $fileId -Logger $script:ImportLog

            $hostsProcessed++
            $script:HostStopwatch.Stop()
            $timings += $script:HostStopwatch.Elapsed
            $script:ImportLog.Verbose("Host Time: $($script:HostStopwatch.ElapsedMilliseconds)ms")

            Write-Progress -Activity "Processing $reportName" -Status "Hosts: $hostsProcessed / $($offsets.Count)" -PercentComplete (($hostsProcessed / $offsets.Count) * 100)
        }

        $script:TotalStopwatch.Stop()

        if ($timings.Count -gt 0) {
            $stats = $timings | Measure-Object -Average -Minimum -Maximum -Property Ticks
            $average = [System.TimeSpan]::FromTicks($stats.Average).TotalMilliseconds
            $minimum = [System.TimeSpan]::FromTicks($stats.Minimum).TotalMilliseconds
            $maximum = [System.TimeSpan]::FromTicks($stats.Maximum).TotalMilliseconds
        }
        else {
            $average = $minimum = $maximum = 0
        }

        $script:ImportLog.Info('-----------------------------')
        $script:ImportLog.Info("Completed: $reportName")
        $script:ImportLog.Info("Host Avg: $average ms")
        $script:ImportLog.Info("Host Min: $minimum ms")
        $script:ImportLog.Info("Host Max: $maximum ms")
        $script:ImportLog.Info("Parsing Total: $($script:TotalStopwatch.Elapsed)")
        $script:ImportLog.Info('-----------------------------')
    }

    end {
        if ($script:DbContext) {
            Close-PSNessusDbContext -Context $script:DbContext
        }
    }
}
