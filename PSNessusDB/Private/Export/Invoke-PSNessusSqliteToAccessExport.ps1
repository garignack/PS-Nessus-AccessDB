#######################################################################################################################
# File:             Private/Export/Invoke-PSNessusSqliteToAccessExport.ps1
# Description:      Copies Nessus import data from a SQLite database into an Access template while preserving
#                   relationships and producing ID maps for downstream lookups.
# Context:          Called by Export-PSNessusAccessDatabase. Expects the caller to provide initialized contexts created
#                   via New-PSNessusDbContext so connection helpers and plugin caches remain consistent.
#######################################################################################################################

function Invoke-PSNessusSqliteToAccessExport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$SourceContext,

        [Parameter(Mandatory)]
        [psobject]$TargetContext,

        [psobject]$Logger
    )

    if ($SourceContext.Provider -ne 'SQLite') {
        throw 'SourceContext must reference a SQLite provider.'
    }

    if ($TargetContext.Provider -ne 'Access') {
        throw 'TargetContext must reference an Access provider.'
    }

    $summary = [ordered]@{
        Files                = 0
        Hosts                = 0
        HostEnumeratedPorts  = 0
        HostTags             = 0
        PluginInfo           = 0
        ReportItem           = 0
    }

    $idMaps = @{
        Files   = @{}
        Hosts   = @{}
        Plugins = @{}
    }

    $transactionActive = $false
    try {
        Start-PSNessusDbTransaction -Context $TargetContext | Out-Null
        $transactionActive = $true

        $tablesToClear = @('ReportItem', 'HostEnumeratedPorts', 'HostTags', 'Hosts', 'PluginInfo', 'Files')
        foreach ($tableName in $tablesToClear) {
            Invoke-AccessNonQuery -Sql "DELETE FROM [$tableName];" -Connection $TargetContext.Connection -Transaction $TargetContext.Transaction
        }

        # Files
        $filesTable = Invoke-SqliteQuery -Sql 'SELECT * FROM Files ORDER BY ID;' -Connection $SourceContext.Connection
        $fileColumns = @($filesTable.Columns | Where-Object { $_.ColumnName -ne 'ID' } | ForEach-Object { $_.ColumnName })
        $filesColumnsEnsured = $false
        foreach ($row in $filesTable.Rows) {
            $values = @()
            foreach ($column in $fileColumns) {
                $value = $row[$column]
                if ($value -is [System.DBNull]) {
                    $values += ,$null
                    continue
                }

                if ($column -eq 'ImportDate') {
                    [datetime]$parsedImportDate = [datetime]::MinValue
                    if ([datetime]::TryParse([string]$value, [ref]$parsedImportDate)) {
                        $values += $parsedImportDate
                    }
                    else {
                        $values += [string]$value
                    }
                }
                else {
                    $values += [string]$value
                }
            }

            if (-not $filesColumnsEnsured) {
                Ensure-PSNessusDbColumns -Context $TargetContext -Table 'Files' -Columns $fileColumns -Values $values
                $filesColumnsEnsured = $true
            }

            $newId = Add-PSNessusDbRecord -Context $TargetContext -Table 'Files' -Columns $fileColumns -Values $values
            $idMaps.Files[[int]$row['ID']] = $newId
            $summary.Files++
        }

        # Hosts
        $hostsTable = Invoke-SqliteQuery -Sql 'SELECT * FROM Hosts ORDER BY ID;' -Connection $SourceContext.Connection
        $hostColumns = @($hostsTable.Columns | Where-Object { $_.ColumnName -ne 'ID' } | ForEach-Object { $_.ColumnName })
        $hostsColumnsEnsured = $false
        foreach ($row in $hostsTable.Rows) {
            $values = @()
            foreach ($column in $hostColumns) {
                $value = $row[$column]
                if ($value -is [System.DBNull]) {
                    $values += ,$null
                    continue
                }

                switch ($column) {
                    'FileID' {
                        $sourceFileId = [int]$value
                        if (-not $idMaps.Files.ContainsKey($sourceFileId)) {
                            throw "Missing file mapping for ID $sourceFileId while exporting Hosts."
                        }
                        $values += $idMaps.Files[$sourceFileId]
                    }
                    default {
                        $values += [string]$value
                    }
                }
            }

            if (-not $hostsColumnsEnsured) {
                Ensure-PSNessusDbColumns -Context $TargetContext -Table 'Hosts' -Columns $hostColumns -Values $values
                $hostsColumnsEnsured = $true
            }

            $newHostId = Add-PSNessusDbRecord -Context $TargetContext -Table 'Hosts' -Columns $hostColumns -Values $values
            $idMaps.Hosts[[int]$row['ID']] = $newHostId
            $summary.Hosts++
        }

        # PluginInfo
        $pluginTable = Invoke-SqliteQuery -Sql 'SELECT * FROM PluginInfo ORDER BY ID;' -Connection $SourceContext.Connection
        $pluginColumns = @($pluginTable.Columns | Where-Object { $_.ColumnName -ne 'ID' } | ForEach-Object { $_.ColumnName })
        $pluginColumnsEnsured = $false
        foreach ($row in $pluginTable.Rows) {
            $values = @()
            foreach ($column in $pluginColumns) {
                $value = $row[$column]
                if ($value -is [System.DBNull]) {
                    $values += ,$null
                    continue
                }

                switch ($column) {
                    'pluginID' { $values += [long]$value }
                    default    { $values += [string]$value }
                }
            }

            if (-not $pluginColumnsEnsured) {
                Ensure-PSNessusDbColumns -Context $TargetContext -Table 'PluginInfo' -Columns $pluginColumns -Values $values
                $pluginColumnsEnsured = $true
            }

            $newPluginId = Add-PSNessusDbRecord -Context $TargetContext -Table 'PluginInfo' -Columns $pluginColumns -Values $values
            $idMaps.Plugins[[int]$row['ID']] = $newPluginId

            $pluginHash = $row['pluginHash']
            if ($pluginHash -and $pluginHash -isnot [System.DBNull]) {
                $TargetContext.PluginCache[[string]$pluginHash] = $newPluginId
            }

            $summary.PluginInfo++
        }

        # Host Enumerated Ports
        Ensure-HostEnumeratedPortsTable -Connection $TargetContext.Connection
        $portsTable = Invoke-SqliteQuery -Sql 'SELECT * FROM HostEnumeratedPorts ORDER BY ID;' -Connection $SourceContext.Connection
        $portColumns = @($portsTable.Columns | Where-Object { $_.ColumnName -ne 'ID' } | ForEach-Object { $_.ColumnName })
        foreach ($row in $portsTable.Rows) {
            $values = @()
            foreach ($column in $portColumns) {
                $value = $row[$column]
                if ($value -is [System.DBNull]) {
                    $values += ,$null
                    continue
                }

                switch ($column) {
                    'HostID' {
                        $sourceHostId = [int]$value
                        if (-not $idMaps.Hosts.ContainsKey($sourceHostId)) {
                            throw "Missing host mapping for ID $sourceHostId while exporting HostEnumeratedPorts."
                        }
                        $values += $idMaps.Hosts[$sourceHostId]
                    }
                    'Port'    { $values += [int]$value }
                    default   { $values += [string]$value }
                }
            }

            Add-PSNessusDbRecord -Context $TargetContext -Table 'HostEnumeratedPorts' -Columns $portColumns -Values $values | Out-Null
            $summary.HostEnumeratedPorts++
        }

        # Host Tags
        Ensure-HostTagsTable -Connection $TargetContext.Connection
        $tagsTable = Invoke-SqliteQuery -Sql 'SELECT * FROM HostTags ORDER BY ID;' -Connection $SourceContext.Connection
        $tagColumns = @($tagsTable.Columns | Where-Object { $_.ColumnName -ne 'ID' } | ForEach-Object { $_.ColumnName })
        foreach ($row in $tagsTable.Rows) {
            $values = @()
            foreach ($column in $tagColumns) {
                $value = $row[$column]
                if ($value -is [System.DBNull]) {
                    $values += ,$null
                    continue
                }

                switch ($column) {
                    'HostID' {
                        $sourceHostId = [int]$value
                        if (-not $idMaps.Hosts.ContainsKey($sourceHostId)) {
                            throw "Missing host mapping for ID $sourceHostId while exporting HostTags."
                        }
                        $values += $idMaps.Hosts[$sourceHostId]
                    }
                    default {
                        $values += [string]$value
                    }
                }
            }

            Add-PSNessusDbRecord -Context $TargetContext -Table 'HostTags' -Columns $tagColumns -Values $values | Out-Null
            $summary.HostTags++
        }

        # Report Items
        $reportTable = Invoke-SqliteQuery -Sql 'SELECT * FROM ReportItem ORDER BY ID;' -Connection $SourceContext.Connection
        $reportColumns = @($reportTable.Columns | Where-Object { $_.ColumnName -ne 'ID' } | ForEach-Object { $_.ColumnName })
        $reportColumnsEnsured = $false
        foreach ($row in $reportTable.Rows) {
            $values = @()
            foreach ($column in $reportColumns) {
                $value = $row[$column]
                if ($value -is [System.DBNull]) {
                    $values += ,$null
                    continue
                }

                switch ($column) {
                    'PID' {
                        $sourcePluginId = [int]$value
                        if (-not $idMaps.Plugins.ContainsKey($sourcePluginId)) {
                            throw "Missing plugin mapping for ID $sourcePluginId while exporting ReportItem."
                        }
                        $values += $idMaps.Plugins[$sourcePluginId]
                    }
                    'HostID' {
                        $sourceHostId = [int]$value
                        if (-not $idMaps.Hosts.ContainsKey($sourceHostId)) {
                            throw "Missing host mapping for ID $sourceHostId while exporting ReportItem."
                        }
                        $values += $idMaps.Hosts[$sourceHostId]
                    }
                    'port'     { $values += [int]$value }
                    'severity' { $values += [int]$value }
                    default    { $values += [string]$value }
                }
            }

            if (-not $reportColumnsEnsured) {
                Ensure-PSNessusDbColumns -Context $TargetContext -Table 'ReportItem' -Columns $reportColumns -Values $values
                $reportColumnsEnsured = $true
            }

            Add-PSNessusDbRecord -Context $TargetContext -Table 'ReportItem' -Columns $reportColumns -Values $values | Out-Null
            $summary.ReportItem++
        }

        if ($transactionActive) {
            Complete-PSNessusDbTransaction -Context $TargetContext
            $transactionActive = $false
        }

        $message = "Access export complete: Files={0}, Hosts={1}, Plugins={2}, ReportItems={3}, HostTags={4}, HostPorts={5}" -f `
            $summary.Files, $summary.Hosts, $summary.PluginInfo, $summary.ReportItem, $summary.HostTags, $summary.HostEnumeratedPorts

        if ($Logger) {
            Invoke-Logger -Logger $Logger -Method 'Info' -Message $message -Source 'SQLiteToAccessExport'
        }
        else {
            Write-Verbose $message
        }

        return [pscustomobject]$summary
    }
    catch {
        $errorMessage = "SQLite-to-Access export failed after partial progress: Files={0}, Hosts={1}, PluginInfo={2}, ReportItem={3}, HostTags={4}, HostEnumeratedPorts={5}. Source='{6}', Target='{7}'." -f `
            $summary.Files, $summary.Hosts, $summary.PluginInfo, $summary.ReportItem, $summary.HostTags, $summary.HostEnumeratedPorts, $SourceContext.Path, $TargetContext.Path

        if ($Logger) {
            Invoke-Logger -Logger $Logger -Method 'Error' -Message $errorMessage -Source 'SQLiteToAccessExport' -ErrorRecord $_
            Invoke-Logger -Logger $Logger -Method 'Debug' -Message $_.Exception.ToString() -Source 'SQLiteToAccessExport'
        }
        else {
            Write-Error $errorMessage
            Write-Verbose $_.Exception.ToString()
            if ($_.ScriptStackTrace) {
                Write-Verbose $_.ScriptStackTrace
            }
        }

        if ($transactionActive) {
            Rollback-PSNessusDbTransaction -Context $TargetContext
            $transactionActive = $false
        }
        throw
    }
}
