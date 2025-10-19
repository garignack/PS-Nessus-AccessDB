#######################################################################################################################
# File:             Private/Get-NessusReportHosts.ps1
# Description:      Streaming helpers built on System.Xml.XmlReader that enumerate ReportHost nodes without loading
#                   entire Nessus exports into memory.
# Context:          Used by Import-PSNessusDB (and future tooling) to replace FileCutter-based slicing with an
#                   encoding-aware, namespace-friendly reader.
#######################################################################################################################

function Get-NessusReportMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $resolvedPath = (Resolve-Path -Path $Path).ProviderPath
    $settings = [System.Xml.XmlReaderSettings]::new()
    $settings.IgnoreWhitespace = $true
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Ignore
    $settings.XmlResolver = $null

    $reader = [System.Xml.XmlReader]::Create($resolvedPath, $settings)
    try {
        $reportName = $null
        $policyName = $null
        $isV2 = $false

        while ($reader.Read()) {
            if ($reader.NodeType -ne [System.Xml.XmlNodeType]::Element) {
                continue
            }

            if (-not $isV2 -and $reader.Depth -eq 0 -and $reader.Name -eq 'NessusClientData_v2') {
                $isV2 = $true
            }

            if ($reader.Name -eq 'Report') {
                $reportName = $reader.GetAttribute('name')
                if ($reportName) { break }
            }
            elseif ($reader.Name -eq 'policyName') {
                $policyName = $reader.ReadElementContentAsString()
                if ($policyName) { break }
            }
        }
    }
    finally {
        $reader.Close()
    }

    return [pscustomobject]@{
        ReportName = $reportName
        PolicyName = $policyName
        IsV2       = $isV2
    }
}

function Get-NessusReportHosts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [switch]$CountOnly
    )

    $resolvedPath = (Resolve-Path -Path $Path).ProviderPath
    $settings = [System.Xml.XmlReaderSettings]::new()
    $settings.IgnoreWhitespace = $true
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Ignore
    $settings.XmlResolver = $null

    $reader = [System.Xml.XmlReader]::Create($resolvedPath, $settings)
    $count = 0

    try {
        while ($reader.Read()) {
            if ($reader.NodeType -ne [System.Xml.XmlNodeType]::Element -or $reader.Name -ne 'ReportHost') {
                continue
            }

            $count++
            if ($CountOnly) {
                continue
            }

            $subReader = $reader.ReadSubtree()
            try {
                $xmlDocument = New-Object System.Xml.XmlDocument
                $xmlDocument.PreserveWhitespace = $false
                $xmlDocument.Load($subReader)
            }
            finally {
                $subReader.Close()
            }

            $hostName = $xmlDocument.DocumentElement.GetAttribute('name')

            [pscustomobject]@{
                Index = $count
                Name  = $hostName
                Xml   = $xmlDocument
            }
        }
    }
    finally {
        $reader.Close()
    }

    if ($CountOnly) {
        return $count
    }
}
