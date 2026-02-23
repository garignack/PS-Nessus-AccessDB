#######################################################################################################################
# File:             Public/Export-PSNessusTagMatrix.ps1
# Description:      Creates an Excel matrix where findings rows are HostTags.TagName and cells contain HostTags.TagValue.
# Context:          Similar worksheet layout to Export-PSNessusReportMatrix, but does not require JSON report definitions.
#######################################################################################################################

function Export-PSNessusTagMatrix {
<#
.SYNOPSIS
    Builds an Excel host tag matrix directly from HostTags.

.DESCRIPTION
    Queries HostTags and Hosts from the Nessus database and produces a worksheet where each row is a distinct
    HostTags.TagName and each host column contains the matching HostTags.TagValue for that tag.

.PARAMETER DatabasePath
    Path to the database that stores Nessus import results.

.PARAMETER OutputPath
    Destination path for the generated workbook. Defaults to <DatabaseBase>-Tags.xlsx.

.PARAMETER Provider
    Database provider to use.

.PARAMETER Tags
    Optional list of TagName values to include. When omitted, all tags are included.

.PARAMETER UseFQDN
    When set, host columns display host-fqdn with host-ip in parentheses.

.PARAMETER Visible
    Leave Excel visible with the workbook open after generation.

.PARAMETER Force
    Overwrite an existing workbook at OutputPath.

.OUTPUTS
    PSCustomObject
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ })]
        [string]$DatabasePath,

        [Parameter()]
        [string]$OutputPath,

        [Parameter()]
        [ValidateSet('Access', 'SQLite')]
        [string]$Provider = 'Access',

        [Parameter()]
        [string[]]$Tags,

        [Parameter()]
        [switch]$UseFQDN,

        [Parameter()]
        [switch]$Visible,

        [Parameter()]
        [switch]$Force
    )

    $resolvedDatabasePath = (Resolve-Path -Path $DatabasePath).ProviderPath

    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($resolvedDatabasePath)
        $OutputPath = Join-Path -Path (Get-Location).ProviderPath -ChildPath ("{0}-Tags.xlsx" -f $baseName)
    }

    if (-not [System.IO.Path]::IsPathRooted($OutputPath)) {
        $OutputPath = Join-Path -Path (Get-Location).ProviderPath -ChildPath $OutputPath
    }

    if ([string]::IsNullOrEmpty([System.IO.Path]::GetExtension($OutputPath))) {
        $OutputPath = '{0}.xlsx' -f $OutputPath
    }

    $resolvedOutputPath = [System.IO.Path]::GetFullPath($OutputPath)
    $outputDirectory = [System.IO.Path]::GetDirectoryName($resolvedOutputPath)

    if (-not (Test-Path -Path $outputDirectory)) {
        $null = New-Item -ItemType Directory -Path $outputDirectory -Force
    }

    if ((Test-Path -Path $resolvedOutputPath) -and -not $Force) {
        throw "Output file '$resolvedOutputPath' already exists. Use -Force to overwrite it."
    }

    $tagFilter = @($Tags | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() } | Select-Object -Unique)
    $whereClause = New-PSNessusTagMatrixWhereClause -Provider $Provider -Tags $tagFilter

    $context = $null
    $excel = $null
    $workbook = $null
    $worksheet = $null

    try {
        $context = New-PSNessusDbContext -Path $resolvedDatabasePath -Provider $Provider

        $hosts = Get-PSNessusTagMatrixHosts -Context $context -WhereClause $whereClause -UseFQDN:$UseFQDN
        if ($hosts.Count -eq 0) {
            throw 'No hosts matched the selected tags/filter.'
        }

        $columnData = Get-PSNessusTagMatrixColumns -Context $context -WhereClause $whereClause
        if ($columnData.Rows.Count -eq 0) {
            throw 'No HostTags rows matched the selected tags/filter.'
        }

        $matchTable = Get-PSNessusTagMatrixMatches -Context $context -WhereClause $whereClause
        if ($matchTable.Rows.Count -eq 0) {
            throw 'No host/tag combinations were found.'
        }

        $outputLookup = Get-PSNessusTagMatrixOutputs -Context $context -WhereClause $whereClause

        $metadataColumns = @('TagName')
        $metadataMap = @{}
        foreach ($row in $columnData) {
            if ($null -eq $row) {
                continue
            }
            $hash = ConvertTo-ReportString -Value $row['pluginHash']
            if (-not $hash) {
                continue
            }

            if (-not $metadataMap.ContainsKey($hash)) {
                $metadataMap[$hash] = @(ConvertTo-NormalizedMultilineString -Value (ConvertTo-ReportString -Value $row['TagName']))
            }
        }

        if ($metadataMap.Count -eq 0) {
            throw 'No distinct tag names were produced for the matrix.'
        }

        $hostCounts = @{}
        foreach ($matchRow in $matchTable) {
            if ($null -eq $matchRow) {
                continue
            }
            $matchHash = ConvertTo-ReportString -Value $matchRow['pluginHash']
            if (-not $matchHash) {
                continue
            }

            if ($hostCounts.ContainsKey($matchHash)) {
                $hostCounts[$matchHash]++
            }
            else {
                $hostCounts[$matchHash] = 1
            }
        }

        $sortedHashes = $metadataMap.Keys |
            Sort-Object -Property @{ Expression = { if ($hostCounts.ContainsKey($_)) { $hostCounts[$_] } else { 0 } }; Descending = $true }, @{ Expression = { $_ }; Descending = $false }

        $findingsMap = [ordered]@{}
        $rowNumber = 0
        foreach ($hash in $sortedHashes) {
            $rowNumber++
            $findingsMap[$hash] = [pscustomobject]@{
                RowNumber = $rowNumber
                Values    = $metadataMap[$hash]
            }
        }

        $hostMap = @{}
        for ($index = 0; $index -lt $hosts.Count; $index++) {
            $hostMap[[string]$hosts[$index].Id] = $index + 1
        }

        try {
            $excel = New-Object -ComObject Excel.Application
        }
        catch {
            throw "Excel automation is required to export tag matrices. $_"
        }

        $originalSheetsSetting = $excel.SheetsInNewWorkbook
        $excel.SheetsInNewWorkbook = 1
        try {
            $workbook = $excel.Workbooks.Add()
        }
        finally {
            $excel.SheetsInNewWorkbook = $originalSheetsSetting
        }

        $excel.Visible = [bool]$Visible
        $worksheet = $workbook.Worksheets.Item(1)
        $worksheetName = Get-SafeWorksheetName -DesiredName 'Host Tags' -ExistingNames @()
        $worksheet.Name = $worksheetName

        $definition = [pscustomobject]@{
            Title      = 'Host Tag Matrix'
            Name       = $worksheetName
            ShowOutput = $true
        }

        Set-WorksheetContent -Worksheet $worksheet `
            -Definition $definition `
            -MetadataColumns $metadataColumns `
            -FindingsMap $findingsMap `
            -Hosts $hosts `
            -HostMap $hostMap `
            -MatchTable $matchTable `
            -OutputLookup $outputLookup

        if ((Test-Path -Path $resolvedOutputPath) -and $Force) {
            Remove-Item -Path $resolvedOutputPath -Force
        }

        $null = $workbook.SaveAs($resolvedOutputPath, 51)

        if (-not $Visible) {
            $null = $workbook.Close($true)
            $null = $excel.Quit()
        }

        return [pscustomobject]@{
            Name          = 'Host Tag Matrix'
            WorksheetName = $worksheetName
            Hosts         = $hosts.Count
            Findings      = $findingsMap.Count
            Status        = 'Completed'
            Reason        = $null
            IncludedTags  = $tagFilter
            OutputPath    = $resolvedOutputPath
            Provider      = $Provider
        }
    }
    catch {
        $message = "Export-PSNessusTagMatrix failed. OutputPath='$resolvedOutputPath', Provider='$Provider'."
        Write-Error $message
        Write-Verbose $_.Exception.ToString()
        if ($_.ScriptStackTrace) {
            Write-Verbose $_.ScriptStackTrace
        }
        throw "$message $($_.Exception.Message)"
    }
    finally {
        if ($worksheet) {
            try { Remove-ExcelComObject -Reference $worksheet } catch {}
        }
        if ($workbook) {
            try { Remove-ExcelComObject -Reference $workbook } catch {}
        }
        if ($excel) {
            try { Remove-ExcelComObject -Reference $excel } catch {}
        }
        if ($context) {
            try { Close-PSNessusDbContext -Context $context } catch {}
        }
    }
}

function ConvertTo-PSNessusTagMatrixDataTable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Data,

        [Parameter(Mandatory)]
        [string]$ContextLabel
    )

    if ($Data -is [object[]] -and $Data.Count -eq 1 -and $Data[0] -is [System.Data.DataTable]) {
        $Data = $Data[0]
    }

    if ($Data -isnot [System.Data.DataTable]) {
        $actualType = if ($null -eq $Data) { '<null>' } else { $Data.GetType().FullName }
        throw "$ContextLabel expected System.Data.DataTable but received '$actualType'."
    }

    Write-Output -NoEnumerate $Data
    return
}

function New-PSNessusTagMatrixWhereClause {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Access', 'SQLite')]
        [string]$Provider,

        [Parameter()]
        [string[]]$Tags
    )

    $clauses = @(
        'HostTags.TagName IS NOT NULL',
        "HostTags.TagName <> ''"
    )

    if ($Tags -and $Tags.Count -gt 0) {
        $literals = @()
        foreach ($tag in $Tags) {
            $safeTag = ConvertTo-PSNessusDbValue -Value $tag -Provider $Provider
            if ($Provider -eq 'Access') {
                $literals += ('"{0}"' -f $safeTag)
            }
            else {
                $literals += ("'{0}'" -f $safeTag)
            }
        }

        if ($literals.Count -gt 0) {
            $clauses += ('HostTags.TagName IN ({0})' -f ($literals -join ', '))
        }
    }

    return ($clauses -join ' AND ')
}

function Get-PSNessusTagMatrixHosts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Context,

        [Parameter(Mandatory)]
        [string]$WhereClause,

        [Parameter()]
        [switch]$UseFQDN
    )

    $isAccess = ($Context.Provider -eq 'Access')

    if ($UseFQDN) {
        if ($isAccess) {
            $nameExpression = 'Hosts.[host-fqdn] & " (" & Hosts.[host-ip] & ")" AS Name'
        }
        else {
            $nameExpression = 'Hosts."host-fqdn" || " (" || Hosts."host-ip" || ")" AS Name'
        }
    }
    else {
        if ($isAccess) {
            $nameExpression = 'Hosts.name AS Name'
        }
        else {
            $nameExpression = 'Hosts."name" AS Name'
        }
    }

    $sql = @"
SELECT DISTINCT Hosts.ID, $nameExpression
FROM Hosts
INNER JOIN HostTags ON HostTags.HostID = Hosts.ID
WHERE ($WhereClause);
"@

    $data = Get-PSNessusDbData -Context $Context -Sql $sql
    $data = ConvertTo-PSNessusTagMatrixDataTable -Data $data -ContextLabel 'Get-PSNessusTagMatrixHosts'

    $hosts = @()
    foreach ($row in $data) {
        if ($null -eq $row) {
            continue
        }

        $id = $row[0]
        $name = $row[1]

        if ($id -is [System.DBNull] -or $null -eq $id) {
            continue
        }

        $hostName = ConvertTo-ReportString -Value $name -PreserveWhitespace
        if (-not $hostName) {
            continue
        }

        $sortKey = if ($UseFQDN) {
            $hostName.ToLowerInvariant()
        }
        else {
            Get-HostSortKey -Value $hostName
        }

        $displayName = if ($UseFQDN) {
            $hostName
        }
        else {
            Get-HostDisplayName -Value $hostName
        }

        $hosts += [pscustomobject]@{
            Id      = [int]$id
            SortKey = $sortKey
            Display = $displayName
        }
    }

    return $hosts | Sort-Object -Property SortKey, Display
}

function Get-PSNessusTagMatrixColumns {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Context,

        [Parameter(Mandatory)]
        [string]$WhereClause
    )

    $sql = @"
SELECT DISTINCT HostTags.TagName AS pluginHash, HostTags.TagName AS [TagName]
FROM HostTags
INNER JOIN Hosts ON Hosts.ID = HostTags.HostID
WHERE ($WhereClause);
"@

    $data = Get-PSNessusDbData -Context $Context -Sql $sql
    $data = ConvertTo-PSNessusTagMatrixDataTable -Data $data -ContextLabel 'Get-PSNessusTagMatrixColumns'
    Write-Output -NoEnumerate $data
    return
}

function Get-PSNessusTagMatrixMatches {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Context,

        [Parameter(Mandatory)]
        [string]$WhereClause
    )

    $sql = @"
SELECT DISTINCT HostTags.TagName AS pluginHash, Hosts.ID
FROM HostTags
INNER JOIN Hosts ON Hosts.ID = HostTags.HostID
WHERE ($WhereClause);
"@

    $data = Get-PSNessusDbData -Context $Context -Sql $sql
    $data = ConvertTo-PSNessusTagMatrixDataTable -Data $data -ContextLabel 'Get-PSNessusTagMatrixMatches'
    Write-Output -NoEnumerate $data
    return
}

function Get-PSNessusTagMatrixOutputs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Context,

        [Parameter(Mandatory)]
        [string]$WhereClause
    )

    $sql = @"
SELECT HostTags.TagName AS pluginHash, Hosts.ID, HostTags.TagValue AS plugin_output
FROM HostTags
INNER JOIN Hosts ON Hosts.ID = HostTags.HostID
WHERE ($WhereClause);
"@

    $data = Get-PSNessusDbData -Context $Context -Sql $sql
    $data = ConvertTo-PSNessusTagMatrixDataTable -Data $data -ContextLabel 'Get-PSNessusTagMatrixOutputs'

    $lookup = @{}
    foreach ($row in $data) {
        if ($null -eq $row) {
            continue
        }
        $hash = ConvertTo-ReportString -Value $row['pluginHash']
        $id = $row['ID']
        if (-not $hash -or $id -is [System.DBNull]) {
            continue
        }

        $key = '{0}|{1}' -f $hash, [int]$id
        if ($lookup.ContainsKey($key)) {
            continue
        }

        $rawOutput = $row['plugin_output']
        $preserve = $false
        if ($rawOutput -is [string] -and $rawOutput -match "`n") {
            $preserve = $true
        }

        if ($preserve) {
            $value = ConvertTo-ReportString -Value $rawOutput -PreserveWhitespace
        }
        else {
            $value = ConvertTo-ReportString -Value $rawOutput
        }

        if ([string]::IsNullOrWhiteSpace($value)) {
            $value = 'N/A'
        }

        $lookup[$key] = ConvertTo-NormalizedMultilineString -Value $value
    }

    return $lookup
}
