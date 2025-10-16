#######################################################################################################################
# File:             Private/Add-PSNessusHostRecord.ps1
# Description:      Parses a Nessus ReportHost node into normalized database tables (Hosts, HostEnumeratedPorts,
#                   HostTags, PluginInfo, ReportItem) while coordinating logging and plugin de-duplication.
# Context:          Invoked by Import-PSNessusDB and legacy scripts; relies on AccessProvider helpers for DB IO and
#                   Invoke-Logger for telemetry. Update synchronization with legacy add-NessusHost.ps1 when model changes.
#######################################################################################################################

function Add-PSNessusHostRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [xml]$XmlHost,

        [Parameter(Mandatory)]
        [psobject]$DbContext,

        [Parameter(Mandatory)]
        [int]$FileId,

        [Parameter()]
        [psobject]$Logger
    )

    if (-not $Logger) {
        try {
            $Logger = Get-Variable -Name 'ImportLog' -Scope Script -ErrorAction Stop | Select-Object -ExpandProperty Value
        }
        catch {
            $Logger = $null
        }
    }

    if (-not ($DbContext.PSObject.Properties.Name -contains 'PluginCache')) {
        Add-Member -InputObject $DbContext -NotePropertyName PluginCache -NotePropertyValue @{} -Force
    }
    $pluginCache = $DbContext.PluginCache
    $logSource = 'Add-PSNessusHostRecord'

    $preserveTags = @('host-ip', 'host-fqdn', 'host_start', 'host_end')
    $hostColumns = @('FileID', 'Name')
    $hostValues = @($FileId, $XmlHost.ReportHost.name)
    $enumeratedPorts = @()
    $hostTags = @()

    Invoke-Logger -Logger $Logger -Method 'Info' -Message ("Importing host '{0}'" -f $XmlHost.ReportHost.name) -Source $logSource

    foreach ($tag in $XmlHost.ReportHost.HostProperties.tag) {
        switch -Wildcard ($tag.name) {
            'enumerated-ports-*' {
                if ($tag.name -match '^enumerated-ports-(\d+)-(.*)$') {
                    $enumeratedPorts += [pscustomobject]@{
                        Port     = [int]$Matches[1]
                        Protocol = $Matches[2]
                        State    = [string]$tag.'#text'
                    }
                    $hostTags += [pscustomobject]@{
                        Name  = $tag.name
                        Value = [string]$tag.'#text'
                    }
                }
            }
            default {
                $tagName = [string]$tag.name
                $tagValue = [string]$tag.'#text'
                if ([string]::IsNullOrWhiteSpace($tagName)) {
                    continue
                }
                if ($preserveTags -contains $tagName.ToLowerInvariant()) {
                    $hostColumns += $tagName
                    $hostValues += (ConvertTo-PSNessusDbValue -Value $tagValue)
                }
                else {
                    $hostTags += [pscustomobject]@{
                        Name  = $tagName
                        Value = $tagValue
                    }
                }
            }
        }
    }

    Ensure-PSNessusDbColumns -Context $DbContext -Table 'Hosts' -Columns $hostColumns -Values $hostValues
    $hostId = Add-PSNessusDbRecord -Context $DbContext -Table 'Hosts' -Columns $hostColumns -Values $hostValues

    Invoke-Logger -Logger $Logger -Method 'Debug' -Message ("Host '{0}' imported as ID {1}" -f $XmlHost.ReportHost.name, $hostId) -Source $logSource

    if ($enumeratedPorts.Count -gt 0) {
        Ensure-HostEnumeratedPortsTable -Connection $DbContext.Connection
        foreach ($entry in $enumeratedPorts) {
            $columns = @('HostID', 'Port', 'Protocol', 'State')
            $values  = @($hostId, $entry.Port, $entry.Protocol, $entry.State)
            Add-PSNessusDbRecord -Context $DbContext -Table 'HostEnumeratedPorts' -Columns $columns -Values $values | Out-Null
        }
    }

    if ($hostTags.Count -gt 0) {
        Ensure-HostTagsTable -Connection $DbContext.Connection
        foreach ($tag in $hostTags) {
            $columns = @('HostID', 'TagName', 'TagValue')
            $values  = @(
                $hostId,
                $tag.Name,
                (ConvertTo-PSNessusDbValue -Value $tag.Value)
            )
            Add-PSNessusDbRecord -Context $DbContext -Table 'HostTags' -Columns $columns -Values $values | Out-Null
        }
    }

    foreach ($reportItem in $XmlHost.ReportHost.ReportItem) {
        $pluginId = $null
        $reportColumns = @()
        $reportValues = @()
        $pluginColumns = @()
        $pluginValues = @()

        $hashSource = '{0}{1}{2}{3}{4}' -f $reportItem.PluginID,
            $reportItem.description,
            $reportItem.plugin_version,
            $reportItem.pluginName,
            $reportItem.Plugin_Publication_Date

        $pluginHash = Get-Md5HashValue -InputString $hashSource
        $pluginColumns += 'PluginHash'
        $pluginValues += $pluginHash

        $existingPlugin = Get-PSNessusDbData -Context $DbContext -Sql "SELECT ID, PluginHash FROM PluginInfo WHERE PluginHash = '$pluginHash';"
        $existingPluginId = $null
        if ($pluginCache.ContainsKey($pluginHash)) {
            $existingPluginId = [int]$pluginCache[$pluginHash]
        }
        elseif ($existingPlugin -and $existingPlugin.Rows.Count -gt 0) {
            $idCandidate = $existingPlugin.Rows[0].ID
            if ($idCandidate -and $idCandidate -isnot [System.DBNull]) {
                $existingPluginId = [int]$idCandidate
                $pluginCache[$pluginHash] = $existingPluginId
            }
        }

        if (-not $existingPluginId) {
            Invoke-Logger -Logger $Logger -Method 'Verbose' -Message ("Creating new plugin record for PluginID {0}" -f $reportItem.PluginID) -Source $logSource

            foreach ($attribute in $reportItem.Attributes) {
                switch -Wildcard ($attribute.name) {
                    'plugin*' {
                        $pluginColumns += $attribute.name
                        $pluginValues += (ConvertTo-PSNessusDbValue -Value ([string]$attribute.'#text'))
                    }
                    default {
                        $reportColumns += $attribute.name
                        $reportValues += (ConvertTo-PSNessusDbValue -Value ([string]$attribute.'#text'))
                    }
                }
            }

            foreach ($child in $reportItem.ChildNodes) {
                switch -Wildcard ($child.name) {
                    'plugin_output' {
                        $reportColumns += $child.name
                        $reportValues += (ConvertTo-PSNessusDbValue -Value ([string]$child.'#text'))
                    }
                    'cm:compliance-result' {
                        $reportColumns += $child.name
                        $reportValues += (ConvertTo-PSNessusDbValue -Value ([string]$child.'#text'))
                    }
                    'cm:compliance-actual-value' {
                        $reportColumns += $child.name
                        $reportValues += (ConvertTo-PSNessusDbValue -Value ([string]$child.'#text'))
                    }
                    default {
                        if ($pluginColumns -notcontains $child.name) {
                            $pluginColumns += $child.name
                            $pluginValues += (ConvertTo-PSNessusDbValue -Value ([string]$child.'#text'))
                        }
                        else {
                            for ($index = 0; $index -lt $pluginColumns.Count; $index++) {
                                if ($pluginColumns[$index] -eq $child.name) {
                                    $pluginValues[$index] += ';' + (ConvertTo-PSNessusDbValue -Value ([string]$child.'#text'))
                                }
                            }
                        }
                    }
                }
            }

            Ensure-PSNessusDbColumns -Context $DbContext -Table 'PluginInfo' -Columns $pluginColumns -Values $pluginValues
            $pluginId = Add-PSNessusDbRecord -Context $DbContext -Table 'PluginInfo' -Columns $pluginColumns -Values $pluginValues
            Invoke-Logger -Logger $Logger -Method 'Debug' -Message ("Plugin {0} persisted as ID {1}" -f $reportItem.PluginID, $pluginId) -Source $logSource
            $pluginCache[$pluginHash] = $pluginId
        }
        else {
            $pluginId = $existingPluginId
            Invoke-Logger -Logger $Logger -Method 'Verbose' -Message ("Reusing plugin ID {0} for PluginID {1}" -f $pluginId, $reportItem.PluginID) -Source $logSource

            foreach ($attribute in $reportItem.Attributes) {
                switch -Wildcard ($attribute.name) {
                    'plugin*' { }
                    default {
                        $reportColumns += $attribute.name
                        $reportValues += (ConvertTo-PSNessusDbValue -Value ([string]$attribute.'#text'))
                    }
                }
            }

            if ($reportItem.plugin_output) {
                $reportColumns += 'plugin_output'
                $reportValues += (ConvertTo-PSNessusDbValue -Value ([string]$reportItem.plugin_output))
            }

            if ($reportItem.'cm:compliance-result') {
                $reportColumns += 'cm:compliance-result'
                $reportValues += (ConvertTo-PSNessusDbValue -Value ([string]$reportItem.'cm:compliance-result'))
            }

            if ($reportItem.'cm:compliance-actual-value') {
                $reportColumns += 'cm:compliance-actual-value'
                $reportValues += (ConvertTo-PSNessusDbValue -Value ([string]$reportItem.'cm:compliance-actual-value'))
            }
        }

        if ($pluginId) {
            $reportColumns += 'HostID'
            $reportValues += $hostId

            $reportColumns += 'PID'
            $reportValues += $pluginId

            Add-PSNessusDbRecord -Context $DbContext -Table 'ReportItem' -Columns $reportColumns -Values $reportValues | Out-Null
            Invoke-Logger -Logger $Logger -Method 'Debug' -Message ("Report item for host ID {0} mapped to plugin ID {1}" -f $hostId, $pluginId) -Source $logSource
        }
        else {
            Write-Warning ("Could not find Plugin: {0}" -f ($reportItem.Attributes | Where-Object { $_.name -eq 'pluginID' } | Select-Object -ExpandProperty '#text'))
            Invoke-Logger -Logger $Logger -Method 'Warn' -Message ("Could not resolve plugin for PluginID {0}" -f ($reportItem.Attributes | Where-Object { $_.name -eq 'pluginID' } | Select-Object -ExpandProperty '#text')) -Source $logSource
        }
    }

    Invoke-Logger -Logger $Logger -Method 'Info' -Message ("Completed host '{0}'" -f $XmlHost.ReportHost.name) -Source $logSource
}
