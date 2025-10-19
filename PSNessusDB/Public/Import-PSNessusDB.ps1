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
        [switch]$NoLog,

        [Parameter(Mandatory = $false, HelpMessage = 'Create a new database if one does not exist (SQLite only).')]
        [switch]$NewDb
    )

    begin {
        # Resolve upfront parameters and establish logging/database context before streaming hosts.
        $moduleRoot = $PSScriptRoot

        if ($NewDb -and $Provider -eq 'Access') {
            throw "-NewDb is only supported when -Provider SQLite."
        }

        if (-not $NewDb -and -not (Test-Path -LiteralPath $DatabasePath)) {
            throw "DatabasePath '$DatabasePath' does not exist. Provide an existing database or specify -NewDb."
        }

        if (Test-Path -LiteralPath $DatabasePath) {
            $resolvedDatabasePath = (Resolve-Path -Path $DatabasePath).ProviderPath
        }
        else {
            $resolvedDatabasePath = [System.IO.Path]::GetFullPath($DatabasePath)
        }

        $outputDirectory = [System.IO.Path]::GetDirectoryName($resolvedDatabasePath)
        if ($outputDirectory -and -not (Test-Path -LiteralPath $outputDirectory)) {
            New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
        }

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
            $script:ImportLog.Debug("Resolved database path: $resolvedDatabasePath | Provider: $Provider | Logging level: $loggingLevel")
        }
        catch {
            Write-Host 'Error Creating PS-Log Object'
            Write-Error $_.Exception.ToString()
            throw
        }

        try {
            $script:DbContext = New-PSNessusDbContext -Path $resolvedDatabasePath -Provider $Provider -NewDb:$NewDb
            $script:ImportLog.Debug("Database context created. NewDb: $NewDb | Connection: $($script:DbContext.Connection.GetType().FullName)")
        }
        catch {
            $script:ImportLog.Fatal("Cannot connect to database $resolvedDatabasePath", $_)
            $script:ImportLog.Debug($_.Exception.ToString())
            throw "Fatal Error, Exiting"
        }

        # Commit each host in its own transaction to tighten failure isolation.
        [int]$transactionBatchSize = 1
        $script:TotalStopwatch = [Diagnostics.Stopwatch]::new()
        $script:HostStopwatch = [Diagnostics.Stopwatch]::new()
    }

    process {
        $script:TotalStopwatch.Reset()
        $script:TotalStopwatch.Start()

        $resolvedFullName = (Resolve-Path -Path $FullName).ProviderPath
        $script:ImportLog.Debug("Starting import for file: $resolvedFullName")
        $script:ImportLog.Info('-----------------------------')
        $script:ImportLog.Info("Processing File: {0}" -f [System.IO.Path]::GetFileName($resolvedFullName))
        $script:ImportLog.Info('-----------------------------')

        $headerMetadata = Get-NessusReportMetadata -Path $resolvedFullName
        if (-not $headerMetadata.IsV2) {
            $script:ImportLog.Error('File is not a NessusClientData_v2 export.')
            throw 'Invalid Nessus export format.'
        }

        $script:ImportLog.Debug('Counting <ReportHost> entries')
        $totalHosts = Get-NessusReportHosts -Path $resolvedFullName -CountOnly
        $script:ImportLog.Verbose("Found $totalHosts ReportHost entries")

        if ($totalHosts -eq 0) {
            $script:ImportLog.Warn('No hosts found in file.')
            return
        }

        $script:ImportLog.Verbose('Parsing report name')
        $reportName = ''

        if ($headerMetadata.ReportName) {
            $reportName = $headerMetadata.ReportName
        }
        elseif ($headerMetadata.PolicyName) {
            $reportName = $headerMetadata.PolicyName
        }

        if ($reportName) {
            $reportName = $reportName.Trim()
        }
        else {
            $reportName = 'Unknown'
        }

        $script:ImportLog.Info("Report Name: $reportName")

        $timings = @()
        [int]$hostsProcessed = 0

        $initialPercent = if ($totalHosts -gt 0) { ($hostsProcessed / [double]$totalHosts) * 100 } else { 100 }
        Write-Progress -Activity "Processing $reportName" -Status "Hosts: $hostsProcessed / $totalHosts" -PercentComplete $initialPercent
        [int]$hostsInBatch = 0
        $transactionActive = $false

        try {
            Start-PSNessusDbTransaction -Context $script:DbContext | Out-Null
            $transactionActive = $true

            $fileColumns = @('reportName', 'FileLoc', 'FileName', 'ImportDate')
            $fileValues = @($reportName, $resolvedFullName, (Split-Path -Path $resolvedFullName -Leaf), (Get-Date))
            $fileId = Add-PSNessusDbRecord -Context $script:DbContext -Table 'Files' -Columns $fileColumns -Values $fileValues
            $script:ImportLog.Debug("Created Files row ID $fileId for report '$reportName'.")

            foreach ($hostEntry in Get-NessusReportHosts -Path $resolvedFullName) {
                $script:HostStopwatch.Reset()
                $script:HostStopwatch.Start()

                try {
                    $xmlHost = $hostEntry.Xml
                }
                catch {
                    $script:ImportLog.Error("Error processing ReportHost entry at index $($hostEntry.Index)", $_)
                    $script:ImportLog.Debug($_.Exception.ToString())
                    continue
                }

                $script:ImportLog.Verbose("Host retrieval: $($script:HostStopwatch.ElapsedMilliseconds)ms")
                $script:ImportLog.Info("Processing[$($hostEntry.Index)] : $($xmlHost.ReportHost.name)")

                Add-PSNessusHostRecord -XmlHost $xmlHost -DbContext $script:DbContext -FileId $fileId -Logger $script:ImportLog

                $hostsProcessed++
                $hostsInBatch++
                $script:HostStopwatch.Stop()
                $timings += $script:HostStopwatch.Elapsed
                $script:ImportLog.Verbose("Host Time: $($script:HostStopwatch.ElapsedMilliseconds)ms")

                $percentComplete = if ($totalHosts -gt 0) { ($hostsProcessed / [double]$totalHosts) * 100 } else { 100 }
                Write-Progress -Activity "Processing $reportName" -Status "Hosts: $hostsProcessed / $totalHosts" -PercentComplete $percentComplete

                if ($transactionBatchSize -gt 0 -and $hostsInBatch -ge $transactionBatchSize) {
                    Complete-PSNessusDbTransaction -Context $script:DbContext
                    $transactionActive = $false
                    $hostsInBatch = 0

                    if ($hostsProcessed -lt $totalHosts) {
                        Start-PSNessusDbTransaction -Context $script:DbContext | Out-Null
                        $transactionActive = $true
                        $script:ImportLog.Debug("Committed host batch at host index $($hostEntry.Index). Restarting transaction for remaining hosts.")
                    }
                }
            }

            if ($transactionActive) {
                Complete-PSNessusDbTransaction -Context $script:DbContext
                $transactionActive = $false
                $script:ImportLog.Debug('Final host transaction committed.')
            }
        }
        catch {
            if ($transactionActive) {
                Rollback-PSNessusDbTransaction -Context $script:DbContext
                $transactionActive = $false
                $script:ImportLog.Debug('Rolled back active transaction due to exception.')
            }
            throw
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
        $script:ImportLog.Debug("Hosts processed: $hostsProcessed | Timings recorded: $($timings.Count)")
        $script:ImportLog.Info("Host Avg: $average ms")
        $script:ImportLog.Info("Host Min: $minimum ms")
        $script:ImportLog.Info("Host Max: $maximum ms")
        $script:ImportLog.Info("Parsing Total: $($script:TotalStopwatch.Elapsed)")
        $script:ImportLog.Info('-----------------------------')

        Write-Progress -Activity "Processing $reportName" -Status "Hosts: $hostsProcessed / $totalHosts" -Completed
    }

    end {
        if ($script:DbContext) {
            Close-PSNessusDbContext -Context $script:DbContext
        }
    }
}
