#######################################################################################################################
# File:             Public/Export-PSNessusReportMatrix.ps1
# Description:      Creates Excel matrix workbooks based on loc_Reports_Matrix-style definitions stored in JSON and a
#                   Nessus database (Access or SQLite) populated by the importer.
# Context:          Replaces the legacy xlMatrixBuilder VBA routine with a PowerShell implementation that operates
#                   against the modernized module surface while keeping worksheet layout parity for downstream tooling.
#######################################################################################################################

function Export-PSNessusReportMatrix {
<#
.SYNOPSIS
    Builds Excel worksheets for loc_Reports_Matrix definitions supplied via JSON.

.DESCRIPTION
    Reads one or more report definitions from a JSON file, queries the associated Nessus database (Access or SQLite) to resolve
    metadata, host columns, and plugin findings, and materializes the results into an Excel workbook. A worksheet is
    created for each report definition, mirroring the behavior of the legacy xlMatrixBuilder VBA implementation.

.PARAMETER JsonPath
    Path to the JSON file containing an array of loc_Reports_Matrix row definitions.

.PARAMETER DatabasePath
    Path to the database that stores the Nessus import results.

.PARAMETER OutputPath
    Destination path for the generated workbook. Defaults to <JsonPathBase>.xlsx in the JSON directory.

.PARAMETER Provider
    Database provider to use.

.PARAMETER Visible
    When present, leaves the Excel application visible with the workbook open after creation. Without this switch the
    workbook is saved and Excel is closed automatically.

.PARAMETER Force
    Allows overwriting an existing workbook at OutputPath.

.EXAMPLE
    Export-PSNessusReportMatrix -JsonPath .\Reports.json -DatabasePath .\PSNessusDB.accdb -OutputPath .\Reports.xlsx

.OUTPUTS
    PSCustomObject
        Emits a summary object for each processed report detailing the worksheet name, host count, and finding count.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, HelpMessage = 'Path to JSON file containing loc_Reports_Matrix definitions.')]
        [ValidateScript({ Test-Path $_ })]
        [string]$JsonPath,

        [Parameter(Mandatory, HelpMessage = 'Database that contains the Nessus import results (Access or SQLite).')]
        [ValidateScript({ Test-Path $_ })]
        [string]$DatabasePath,

        [Parameter(HelpMessage = 'Full path for the generated Excel workbook.')]
        [string]$OutputPath,

        [Parameter()]
        [ValidateSet('Access', 'SQLite')]
        [string]$Provider = 'Access',

        [Parameter(HelpMessage = 'Leave Excel visible after the workbook is generated.')]
        [switch]$Visible,

        [Parameter(HelpMessage = 'Overwrite an existing workbook at the output path.')]
        [switch]$Force
    )

    $resolvedJsonPath = (Resolve-Path -Path $JsonPath).ProviderPath
    $resolvedDatabasePath = (Resolve-Path -Path $DatabasePath).ProviderPath

    $jsonContent = Get-Content -Path $resolvedJsonPath -Raw

    try {
        $reportDefinitions = $jsonContent | ConvertFrom-Json
    }
    catch {
        throw "Unable to parse JSON from '$resolvedJsonPath'. $_"
    }

    if ($null -eq $reportDefinitions) {
        throw "No report definitions were found in '$resolvedJsonPath'."
    }

    $reportDefinitions = @($reportDefinitions) | Where-Object { $_ }
    if ($reportDefinitions.Count -eq 0) {
        throw "No report definitions were found in '$resolvedJsonPath'."
    }

    $reportCount = $reportDefinitions.Count
    $overallActivity = 'Building report matrices'
    [int]$overallProgressId = Get-Random -Minimum 1 -Maximum ([int]::MaxValue)
    $updateOverallProgress = {
        param(
            [string]$Status,
            [int]$CompletedCount
        )

        $percent = 0
        if ($reportCount -gt 0) {
            $ratio = [double]$CompletedCount / [double]$reportCount
            if ($ratio -lt 0) { $ratio = 0 }
            if ($ratio -gt 1) { $ratio = 1 }
            $percent = [int][math]::Round($ratio * 100, 0)
        }

        Write-Progress -Id $overallProgressId -Activity $overallActivity -Status $Status -PercentComplete $percent
    }

    & $updateOverallProgress 'Initializing report build...' 0

    if ($PSBoundParameters.ContainsKey('OutputPath')) {
        if ([System.IO.Path]::IsPathRooted($OutputPath)) {
            $resolvedOutputPath = $OutputPath
        }
        else {
            $resolvedOutputPath = Join-Path -Path (Get-Location).ProviderPath -ChildPath $OutputPath
        }
    }
    else {
        $outputFileName = '{0}.xlsx' -f [System.IO.Path]::GetFileNameWithoutExtension($resolvedJsonPath)
        $resolvedOutputPath = Join-Path -Path ([System.IO.Path]::GetDirectoryName($resolvedJsonPath)) -ChildPath $outputFileName
    }

    if ([string]::IsNullOrEmpty([System.IO.Path]::GetExtension($resolvedOutputPath))) {
        $resolvedOutputPath = '{0}.xlsx' -f $resolvedOutputPath
    }

    $resolvedOutputPath = [System.IO.Path]::GetFullPath($resolvedOutputPath)
    $outputDirectory = [System.IO.Path]::GetDirectoryName($resolvedOutputPath)

    if (-not (Test-Path -Path $outputDirectory)) {
        $null = New-Item -ItemType Directory -Path $outputDirectory -Force
    }

    if ((Test-Path -Path $resolvedOutputPath) -and -not $Force) {
        throw "Output file '$resolvedOutputPath' already exists. Use -Force to overwrite it."
    }

    $context = $null
    $excel = $null
    $workbook = $null
    $worksheet = $null
    $results = New-Object System.Collections.ArrayList
    $worksheetNames = New-Object System.Collections.ArrayList

    try {
        $context = New-PSNessusDbContext -Path $resolvedDatabasePath -Provider $Provider
    }
    catch {
        throw "Unable to open database '$resolvedDatabasePath'. $_"
    }

    try {
        try {
            $excel = New-Object -ComObject Excel.Application
        }
        catch {
            throw "Excel automation is required to export report matrices. $_"
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
        $processedSheets = 0
        [int]$reportIndex = 0

        foreach ($definition in $reportDefinitions) {
            $reportIndex++
            $resolvedDefinition = Resolve-ReportDefinition -Definition $definition -Index ($processedSheets + 1)
            $statusMessage = "Processing {0} ({1}/{2})" -f $resolvedDefinition.Name, $reportIndex, $reportCount
            & $updateOverallProgress $statusMessage ($reportIndex - 1)
            Write-Verbose ("Processing report '{0}'" -f $resolvedDefinition.Name)

            $hosts = Get-ReportMatrixHosts -Definition $resolvedDefinition -Context $context
            if ($hosts.Count -eq 0) {
                $null = $results.Add([pscustomobject]@{
                        Name          = $resolvedDefinition.Name
                        WorksheetName = $null
                        Hosts         = 0
                        Findings      = 0
                        Status        = 'Skipped'
                        Reason        = 'No hosts matched the whereClause.'
                    })
                Write-Verbose ("Skipping '{0}' because no hosts were returned." -f $resolvedDefinition.Name)
                & $updateOverallProgress ("Skipped {0} ({1}/{2})" -f $resolvedDefinition.Name, $reportIndex, $reportCount) $reportIndex
                continue
            }

            $columnData = Get-ReportMatrixColumns -Definition $resolvedDefinition -Context $context
            if ($columnData.Rows.Count -eq 0) {
                $null = $results.Add([pscustomobject]@{
                        Name          = $resolvedDefinition.Name
                        WorksheetName = $null
                        Hosts         = $hosts.Count
                        Findings      = 0
                        Status        = 'Skipped'
                        Reason        = 'No plugin rows matched the whereClause.'
                    })
                Write-Verbose ("Skipping '{0}' because no plugin rows were returned." -f $resolvedDefinition.Name)
                & $updateOverallProgress ("Skipped {0} ({1}/{2})" -f $resolvedDefinition.Name, $reportIndex, $reportCount) $reportIndex
                continue
            }

            $matchTable = Get-ReportMatrixMatches -Definition $resolvedDefinition -Context $context
            if ($matchTable.Rows.Count -eq 0) {
                $null = $results.Add([pscustomobject]@{
                        Name          = $resolvedDefinition.Name
                        WorksheetName = $null
                        Hosts         = $hosts.Count
                        Findings      = 0
                        Status        = 'Skipped'
                        Reason        = 'No host/plugin combinations were found.'
                    })
                Write-Verbose ("Skipping '{0}' because no host/plugin combinations were returned." -f $resolvedDefinition.Name)
                & $updateOverallProgress ("Skipped {0} ({1}/{2})" -f $resolvedDefinition.Name, $reportIndex, $reportCount) $reportIndex
                continue
            }
            Write-Verbose ("Match table type: {0}" -f $matchTable.GetType().FullName)

            $outputLookup = $null
            if ($resolvedDefinition.ShowOutput) {
                $outputLookup = Get-ReportMatrixOutputs -Definition $resolvedDefinition -Context $context
            }

            $metadataColumns = @()
            foreach ($column in $columnData.Columns) {
                if ($column.ColumnName -ne 'pluginHash') {
                    $metadataColumns += $column.ColumnName
                }
            }

            $metadataColumnCount = $metadataColumns.Count
            if ($metadataColumnCount -eq 0) {
                $null = $results.Add([pscustomobject]@{
                        Name          = $resolvedDefinition.Name
                        WorksheetName = $null
                        Hosts         = $hosts.Count
                        Findings      = 0
                        Status        = 'Skipped'
                        Reason        = 'No metadata columns were defined for the report.'
                    })
                Write-Verbose ("Skipping '{0}' because no metadata columns were defined." -f $resolvedDefinition.Name)
                & $updateOverallProgress ("Skipped {0} ({1}/{2})" -f $resolvedDefinition.Name, $reportIndex, $reportCount) $reportIndex
                continue
            }

            $metadataMap = @{}
            foreach ($row in $columnData.Rows) {
                $hash = ConvertTo-ReportString -Value $row['pluginHash']
                if (-not $hash) {
                    continue
                }

                if (-not $metadataMap.ContainsKey($hash)) {
                    $values = @()
                    foreach ($columnName in $metadataColumns) {
                        $rawValue = $row[$columnName]
                        $preserveWhitespace = $false
                        if ($rawValue -is [string] -and $rawValue -match "`n") {
                            $preserveWhitespace = $true
                        }

                        if ($preserveWhitespace) {
                            $cellValue = ConvertTo-ReportString -Value $rawValue -PreserveWhitespace
                        }
                        else {
                            $cellValue = ConvertTo-ReportString -Value $rawValue
                        }

                        if ($cellValue.Length -gt 255) {
                            if ($preserveWhitespace) {
                                $cellValue = Resolve-FullColumnValue -Definition $resolvedDefinition -ColumnName $columnName -PluginHash $hash -Context $context -PreserveWhitespace
                            }
                            else {
                                $cellValue = Resolve-FullColumnValue -Definition $resolvedDefinition -ColumnName $columnName -PluginHash $hash -Context $context
                            }
                        }

                        $values += (ConvertTo-NormalizedMultilineString -Value $cellValue)
                    }

                    $metadataMap[$hash] = $values
                }
            }

            if ($metadataMap.Count -eq 0) {
                $null = $results.Add([pscustomobject]@{
                        Name          = $resolvedDefinition.Name
                        WorksheetName = $null
                        Hosts         = $hosts.Count
                        Findings      = 0
                        Status        = 'Skipped'
                        Reason        = 'No distinct plugin hashes were produced for the report.'
                    })
                Write-Verbose ("Skipping '{0}' because no plugin hashes were produced." -f $resolvedDefinition.Name)
                & $updateOverallProgress ("Skipped {0} ({1}/{2})" -f $resolvedDefinition.Name, $reportIndex, $reportCount) $reportIndex
                continue
            }

            $hostCounts = @{}
            foreach ($matchRow in $matchTable.Rows) {
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
                Sort-Object -Property @{
                        Expression = {
                            if ($hostCounts.ContainsKey($_)) {
                                $hostCounts[$_]
                            }
                            else {
                                0
                            }
                        }
                        Descending = $true
                    }, @{
                        Expression = { $_ }
                        Descending = $false
                    }

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

            $worksheet = $workbook.Worksheets.Add()

            try {
                $worksheetName = Get-SafeWorksheetName -DesiredName $resolvedDefinition.Name -ExistingNames $worksheetNames
                $null = $worksheetNames.Add($worksheetName)
                $worksheet.Name = $worksheetName

                do {
                    [int]$reportProgressId = Get-Random -Minimum 1 -Maximum ([int]::MaxValue)
                } while ($reportProgressId -eq $overallProgressId)

                Set-WorksheetContent -Worksheet $worksheet `
                    -Definition $resolvedDefinition `
                    -MetadataColumns $metadataColumns `
                    -FindingsMap $findingsMap `
                    -Hosts $hosts `
                    -HostMap $hostMap `
                    -MatchTable $matchTable `
                    -OutputLookup $outputLookup `
                    -ProgressId $reportProgressId `
                    -ProgressParentId $overallProgressId `
                    -ProgressActivity ("Report: {0}" -f $resolvedDefinition.Name)

                $null = $results.Add([pscustomobject]@{
                        Name          = $resolvedDefinition.Name
                        WorksheetName = $worksheetName
                        Hosts         = $hosts.Count
                        Findings      = $findingsMap.Count
                        Status        = 'Completed'
                        Reason        = $null
                    })

                & $updateOverallProgress ("Completed {0} ({1}/{2})" -f $resolvedDefinition.Name, $reportIndex, $reportCount) $reportIndex
                $processedSheets++
            }
            finally {
                if ($worksheet) {
                    Remove-ExcelComObject -Reference $worksheet
                    $worksheet = $null
                }
            }
        }

        & $updateOverallProgress 'Saving workbook...' $reportCount

        if ($processedSheets -eq 0) {
            throw 'No worksheets were created because every definition was skipped.'
        }

        if ((Test-Path -Path $resolvedOutputPath) -and $Force) {
            Remove-Item -Path $resolvedOutputPath -Force
        }

        $null = $workbook.SaveAs($resolvedOutputPath, 51)

        if (-not $Visible) {
            $null = $workbook.Close($true)
            $null = $excel.Quit()
        }
    }
    finally {
        if ($worksheet) {
            Remove-ExcelComObject -Reference $worksheet
        }

        if ($workbook) {
            Remove-ExcelComObject -Reference $workbook
        }

        if ($excel) {
            Remove-ExcelComObject -Reference $excel
        }

        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()

        if ($context) {
            Close-PSNessusDbContext -Context $context
        }

        if ($overallProgressId) {
            Write-Progress -Id $overallProgressId -Activity $overallActivity -Completed
        }
    }

    return $results.ToArray()
}

function Resolve-ReportDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Definition,

        [Parameter(Mandatory)]
        [int]$Index
    )

    $required = 'Title', 'Name', 'pluginHash', 'Columns', 'whereClause'
    foreach ($field in $required) {
        $value = $Definition.$field
        if ([string]::IsNullOrWhiteSpace([string]$value)) {
            throw "Report definition #$Index is missing required field '$field'."
        }
    }

    $useFqdn = $false
    if ($null -ne $Definition.UseFQDN) {
        $useFqdn = [bool]$Definition.UseFQDN
    }
    elseif ($null -ne $Definition.FQDN) {
        $useFqdn = [bool]$Definition.FQDN
    }

    $title = [string]$Definition.Title
    $name = [string]$Definition.Name
    $pluginHash = [string]$Definition.pluginHash
    $columns = [string]$Definition.Columns
    $whereClause = [string]$Definition.whereClause

    return [pscustomobject]@{
        Title      = $title.Trim()
        Name       = $name.Trim()
        PluginHash = $pluginHash.Trim()
        Columns    = $columns.Trim()
        WhereClause = $whereClause.Trim()
        ShowOutput = [bool]$Definition.showOutput
        UseFQDN    = $useFqdn
    }
}

function Get-ReportMatrixHosts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Definition,

        [Parameter(Mandatory)]
        [psobject]$Context
    )

    $provider = $Context.Provider
    $isAccess = ($provider -eq 'Access')

    if ($Definition.UseFQDN) {
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
INNER JOIN ReportItem ON Hosts.ID = ReportItem.HostID
INNER JOIN PluginInfo ON PluginInfo.ID = ReportItem.PID
WHERE ($($Definition.WhereClause));
"@

    $data = Get-PSNessusDbData -Context $Context -Sql $sql

    $hosts = @()
    foreach ($row in $data.Rows) {
        $id = $row['ID']
        $name = $row['Name']

        if ($id -is [System.DBNull] -or $null -eq $id) {
            continue
        }

        $hostName = ConvertTo-ReportString -Value $name -PreserveWhitespace
        if (-not $hostName) {
            continue
        }

        $sortKey = if ($Definition.UseFQDN) {
            $hostName.ToLowerInvariant()
        }
        else {
            Get-HostSortKey -Value $hostName
        }

        $displayName = if ($Definition.UseFQDN) {
            $hostName
        }
        else {
            Get-HostDisplayName -Value $hostName
        }

        $hosts += [pscustomobject]@{
            Id       = [int]$id
            SortKey  = $sortKey
            Display  = $displayName
        }
    }

    return $hosts | Sort-Object -Property SortKey, Display
}

function Get-ReportMatrixColumns {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Definition,

        [Parameter(Mandatory)]
        [psobject]$Context
    )

    $sql = @"
SELECT DISTINCT $($Definition.PluginHash) AS pluginHash, $($Definition.Columns)
FROM PluginInfo
INNER JOIN ReportItem ON PluginInfo.ID = ReportItem.PID
INNER JOIN Hosts ON Hosts.ID = ReportItem.HostID
WHERE ($($Definition.WhereClause));
"@

    return Get-PSNessusDbData -Context $Context -Sql $sql
}

function Get-ReportMatrixMatches {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Definition,

        [Parameter(Mandatory)]
        [psobject]$Context
    )

    $sql = @"
SELECT DISTINCT $($Definition.PluginHash) AS pluginHash, Hosts.ID
FROM PluginInfo
INNER JOIN ReportItem ON PluginInfo.ID = ReportItem.PID
INNER JOIN Hosts ON Hosts.ID = ReportItem.HostID
WHERE ($($Definition.WhereClause));
"@

    return Get-PSNessusDbData -Context $Context -Sql $sql
}

function Get-ReportMatrixOutputs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Definition,

        [Parameter(Mandatory)]
        [psobject]$Context
    )

    $sql = @"
SELECT $($Definition.PluginHash) AS pluginHash, Hosts.ID, ReportItem.plugin_output
FROM PluginInfo
INNER JOIN ReportItem ON PluginInfo.ID = ReportItem.PID
INNER JOIN Hosts ON Hosts.ID = ReportItem.HostID
WHERE ($($Definition.WhereClause));
"@

    $data = Get-PSNessusDbData -Context $Context -Sql $sql
    $lookup = @{}

    foreach ($row in $data.Rows) {
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

function Resolve-FullColumnValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Definition,

        [Parameter(Mandatory)]
        [string]$ColumnName,

        [Parameter(Mandatory)]
        [string]$PluginHash,

        [Parameter(Mandatory)]
        [psobject]$Context,

        [switch]$PreserveWhitespace
    )

    $provider = $Context.Provider
    $escapedHash = ConvertTo-PSNessusDbValue -Value $PluginHash -Provider $provider

    if ($provider -eq 'Access') {
        $sql = @"
SELECT TOP 1 $ColumnName
FROM PluginInfo
INNER JOIN ReportItem ON PluginInfo.ID = ReportItem.PID
INNER JOIN Hosts ON Hosts.ID = ReportItem.HostID
WHERE (($($Definition.PluginHash)) = ("$escapedHash"));
"@
    }
    else {
        $sql = @"
SELECT $ColumnName
FROM PluginInfo
INNER JOIN ReportItem ON PluginInfo.ID = ReportItem.PID
INNER JOIN Hosts ON Hosts.ID = ReportItem.HostID
WHERE (($($Definition.PluginHash)) = ('$escapedHash'))
LIMIT 1;
"@
    }

    $data = Get-PSNessusDbData -Context $Context -Sql $sql
    if ($data.Rows.Count -eq 0) {
        return ''
    }

    $rawValue = $data.Rows[0][$ColumnName]
    if ($PreserveWhitespace) {
        $value = ConvertTo-ReportString -Value $rawValue -PreserveWhitespace
    }
    else {
        $value = ConvertTo-ReportString -Value $rawValue
    }
    return ConvertTo-NormalizedMultilineString -Value $value
}

function Set-WorksheetContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Worksheet,

        [Parameter(Mandatory)]
        [pscustomobject]$Definition,

        [Parameter(Mandatory)]
        [string[]]$MetadataColumns,

        [Parameter(Mandatory)]
        [hashtable]$FindingsMap,

        [Parameter(Mandatory)]
        [array]$Hosts,

        [Parameter(Mandatory)]
        [hashtable]$HostMap,

        [Parameter(Mandatory)]
        [object]$MatchTable,

        [Parameter()]
        [hashtable]$OutputLookup,

        [Parameter()]
        [int]$ProgressId,

        [Parameter()]
        [int]$ProgressParentId,

        [Parameter()]
        [string]$ProgressActivity
    )

    $progressParams = $null
    $progressEnabled = ($PSBoundParameters.ContainsKey('ProgressId') -and $ProgressId -gt 0 -and -not [string]::IsNullOrWhiteSpace($ProgressActivity))
    if ($progressEnabled) {
        $progressParams = @{
            Id       = $ProgressId
            Activity = $ProgressActivity
        }

        if ($ProgressParentId -gt 0) {
            $progressParams.ParentId = $ProgressParentId
        }

        Write-Progress @progressParams -Status 'Preparing worksheet layout' -PercentComplete 0
    }

    $xlCenter = -4108
    $xlBottom = -4107
    $xlTop = -4160
    $xlCellTypeConstants = 2

    $introOffset = 3
    $metadataCount = $MetadataColumns.Count
    $countColumnIndex = $metadataCount + 1
    $firstHostColumnIndex = $countColumnIndex + 1
    $firstHostColumnName = Get-ExcelColumnName -ColumnIndex $firstHostColumnIndex
    $findingCount = [int]$FindingsMap.Count
    $hostCount = [int]$Hosts.Count

    try {
        $Worksheet.Activate()
        $Worksheet.Cells.Item(1, 1).Value2 = $Definition.Title

        if ($metadataCount -gt 0) {
            for ($index = 0; $index -lt $metadataCount; $index++) {
                $columnName = $MetadataColumns[$index]
                $Worksheet.Cells.Item($introOffset - 1, $index + 1).Value2 = $columnName
            }
        }

        for ($index = 0; $index -lt $hostCount; $index++) {
            $columnIndex = $firstHostColumnIndex + $index
            $columnLetter = Get-ExcelColumnName -ColumnIndex $columnIndex
            $Worksheet.Cells.Item(1, $columnIndex).Value2 = $Hosts[$index].Display
            $Worksheet.Cells.Item(2, $columnIndex).Formula = [string]::Format(
                "=counta({0}{1}:{0}1048576)",
                $columnLetter,
                $introOffset
            )
        }

        $headerRow = $Worksheet.Rows.Item('1:1')
        $headerRow.Orientation = 90
        $headerRow.HorizontalAlignment = $xlCenter
        $headerRow.VerticalAlignment = $xlBottom

        try {
            $headerRow.SpecialCells($xlCellTypeConstants).EntireColumn.AutoFit() | Out-Null
        }
        catch {
            # SpecialCells throws when no constants exist; ignore.
        }

        if ($findingCount -gt 0) {
            # Placeholder to keep structure; formulas will be written per-row for clarity.
        }

        if ($findingCount -gt 0) {
            foreach ($entry in $FindingsMap.GetEnumerator()) {
                $rowNumber = [int]$entry.Value.RowNumber
                $rowIndex = $rowNumber - 1
                $values = $entry.Value.Values

                $excelRowIndex = $rowNumber + ($introOffset - 1)

                for ($valueIndex = 0; $valueIndex -lt $metadataCount; $valueIndex++) {
                    $targetColumn = $valueIndex + 1
                    $cellValue = ''
                    if ($values -and $valueIndex -lt $values.Count -and $null -ne $values[$valueIndex]) {
                        $cellValue = [string]$values[$valueIndex]
                    }

                    $cell = $Worksheet.Cells.Item($excelRowIndex, $targetColumn)
                    $cell.Value2 = $cellValue
                    $cell.VerticalAlignment = $xlTop
                }
                $formulaValue = if ($Definition.ShowOutput) {
                    [string]::Format("=counta({0}{1}:XFD{1})", $firstHostColumnName, $excelRowIndex)
                }
                else {
                    [string]::Format("=countif({0}{1}:XFD{1},""x"")", $firstHostColumnName, $excelRowIndex)
                }
                $Worksheet.Cells.Item($excelRowIndex, $countColumnIndex).Formula = $formulaValue
            }
        }

        Write-Verbose ("Set-WorksheetContent: Match table type {0}" -f ($MatchTable.GetType().FullName))
        if ($MatchTable -isnot [System.Data.DataTable]) {
            throw "MatchTable must be a System.Data.DataTable."
        }

        $totalMatchRows = if ($MatchTable) { [int]$MatchTable.Rows.Count } else { 0 }
        $rowsProcessed = 0
        $updateInterval = if ($totalMatchRows -gt 0) { [math]::Max([int][math]::Floor($totalMatchRows / 100), 1) } else { 1 }
        $maxMatrixCells = 20000000
        $useHostMatrix = ($findingCount -gt 0 -and $hostCount -gt 0 -and ([int64]$findingCount * [int64]$hostCount) -le $maxMatrixCells)
        $hostColumnArrays = $null
        if ($useHostMatrix) {
            $hostColumnArrays = @{}
            for ($col = 1; $col -le $hostCount; $col++) {
                $hostColumnArrays[$col] = [object[]]::new($findingCount)
            }
        }

        if ($progressEnabled) {
            $status = if ($totalMatchRows -gt 0) {
                "Populating findings (0/$totalMatchRows)"
            }
            else {
                'No match rows to populate'
            }
            Write-Progress @progressParams -Status $status -PercentComplete 0
        }

        foreach ($row in $MatchTable.Rows) {
            $hash = ConvertTo-ReportString -Value $row['pluginHash']
            $hostId = $row['ID']

            if (-not $hash -or $hostId -is [System.DBNull]) {
                continue
            }

            if (-not $FindingsMap.Contains($hash)) {
                continue
            }

            $hostKey = [string][int]$hostId
            if (-not $HostMap.ContainsKey($hostKey)) {
                continue
            }

            $rowNumber = [int]$FindingsMap[$hash].RowNumber
            $rowIndex = $rowNumber - 1
            $excelRowIndex = $rowNumber + ($introOffset - 1)
            $columnOrdinal = [int]$HostMap[$hostKey]
            $columnIndex = $columnOrdinal - 1

            $value = 'x'
            if ($Definition.ShowOutput) {
                $lookupKey = '{0}|{1}' -f $hash, [int]$hostId
                if ($OutputLookup -and $OutputLookup.ContainsKey($lookupKey)) {
                    $value = $OutputLookup[$lookupKey]
                }
                else {
                    $value = 'N/A'
                }
            }

            if ($null -eq $value) {
                $value = ''
            }
            else {
                $value = [string]$value
            }

            if ($useHostMatrix) {
                $hostColumnArrays[$columnOrdinal][$rowIndex] = $value
            }
            else {
                $dataColumnIndex = $columnOrdinal + $countColumnIndex
                $Worksheet.Cells.Item($excelRowIndex, $dataColumnIndex).Value2 = $value
            }

            $rowsProcessed++
            if ($progressEnabled -and $totalMatchRows -gt 0) {
                if ($rowsProcessed -eq 1 -or $rowsProcessed -eq $totalMatchRows -or ($rowsProcessed % $updateInterval -eq 0)) {
                    $percentComplete = [int][math]::Round(($rowsProcessed / $totalMatchRows) * 100, 0)
                    $status = "Populating findings ({0}/{1})" -f $rowsProcessed, $totalMatchRows
                    Write-Progress @progressParams -Status $status -PercentComplete $percentComplete
                }
            }
        }

        if ($useHostMatrix -and $hostColumnArrays) {
            foreach ($columnOrdinal in $hostColumnArrays.Keys) {
                $columnIndex = $firstHostColumnIndex + ($columnOrdinal - 1)
                $columnRange = $Worksheet.Cells.Item($introOffset, $columnIndex).Resize($findingCount, 1)
                $columnData = $hostColumnArrays[$columnOrdinal]
                if ($findingCount -eq 1) {
                    $columnRange.Value2 = $columnData[0]
                }
                else {
                    $application = $Worksheet.Parent.Application
                    $columnRange.Value = $application.WorksheetFunction.Transpose($columnData)
                }
            }
        }

        if ($progressEnabled -and $totalMatchRows -eq 0) {
            Write-Progress @progressParams -Status 'Worksheet populated (no findings rows)' -PercentComplete 100
        }
        elseif ($progressEnabled -and $totalMatchRows -gt 0 -and $rowsProcessed -lt $totalMatchRows) {
            $percentComplete = [int][math]::Round(($rowsProcessed / $totalMatchRows) * 100, 0)
            Write-Progress @progressParams -Status ("Populating findings ({0}/{1})" -f $rowsProcessed, $totalMatchRows) -PercentComplete $percentComplete
        }

        if ($findingCount -gt 0) {
            $findingsRowRange = $Worksheet.Rows.Item(("{0}:{1}" -f $introOffset, ($introOffset + $findingCount - 1)))
            $findingsRowRange.RowHeight = 16
        }

        $null = $Worksheet.Rows.Item('2:2').AutoFilter()

        $window = $Worksheet.Parent.Application.ActiveWindow
        $window.SplitRow = $introOffset - 1
        if ($window.SplitRow -lt 0) { $window.SplitRow = 0 }
        $window.SplitColumn = [math]::Max($firstHostColumnIndex - 1, 0)
        $window.FreezePanes = $true

        $titleRange = $Worksheet.Range('A1')
        $titleRange.HorizontalAlignment = -4131
        $titleRange.VerticalAlignment = $xlCenter
        $titleRange.Font.Size = 24
        $titleRange.Font.Bold = $true
    }
    finally {
        if ($progressEnabled) {
            Write-Progress @progressParams -Status 'Worksheet population complete' -PercentComplete 100
            Write-Progress @progressParams -Completed
        }
    }
}

function Get-SafeWorksheetName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DesiredName,

        [System.Collections.IEnumerable]$ExistingNames
    )

    $cleanName = ($DesiredName -replace '[:\\/?*\[\]]', '_').Trim()
    if ([string]::IsNullOrWhiteSpace($cleanName)) {
        $cleanName = 'Report'
    }

    if ($cleanName.Length -gt 31) {
        $cleanName = $cleanName.Substring(0, 31)
    }

    $existing = @()
    if ($ExistingNames) {
        $existing = @($ExistingNames)
    }

    $candidate = $cleanName
    $suffix = 1

    while ($existing -contains $candidate) {
        $suffixString = "_$suffix"
        $baseLength = [math]::Min(31 - $suffixString.Length, $cleanName.Length)
        if ($baseLength -le 0) {
            $baseLength = [math]::Min(27, $cleanName.Length)
            $suffixString = "_{0}" -f $suffix
        }
        $candidate = $cleanName.Substring(0, $baseLength) + $suffixString
        $suffix++
    }

    return $candidate
}

function ConvertTo-ReportString {
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Value,

        [switch]$PreserveWhitespace
    )

    if ($null -eq $Value) {
        return ''
    }

    if ($Value -is [System.DBNull]) {
        return ''
    }

    $stringValue = [string]$Value

    if ($PreserveWhitespace) {
        return $stringValue
    }

    return $stringValue.Trim()
}

function Remove-ExcelComObject {
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Reference
    )

    if ($null -eq $Reference) {
        return
    }

    if ([System.Runtime.InteropServices.Marshal]::IsComObject($Reference)) {
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($Reference) | Out-Null
    }
}

function ConvertTo-NormalizedMultilineString {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Value
    )

    if ([string]::IsNullOrEmpty($Value)) {
        return ''
    }

    return $Value
}

function Get-HostSortKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    $segments = $Value.Split('.')
    if ($segments.Length -ne 4) {
        return $Value.ToLowerInvariant()
    }

    $numbers = @()
    foreach ($segment in $segments) {
        $parsed = 0
        if (-not [int]::TryParse($segment, [ref]$parsed)) {
            return $Value.ToLowerInvariant()
        }

        if ($parsed -lt 0) {
            return $Value.ToLowerInvariant()
        }

        $numbers += ('{0:D3}' -f $parsed)
    }

    return ($numbers -join '.')
}

function Get-HostDisplayName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    return $Value.Trim()
}

function Get-ExcelColumnName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$ColumnIndex
    )

    if ($ColumnIndex -le 0) {
        throw "ColumnIndex must be greater than zero. Received: $ColumnIndex"
    }

    $index = [int]$ColumnIndex
    $columnName = ''
    while ($index -gt 0) {
        $index--
        $remainder = [int]($index % 26)
        $columnName = [char](65 + $remainder) + $columnName
        $index = [int][math]::Floor($index / 26)
    }

    return $columnName
}
