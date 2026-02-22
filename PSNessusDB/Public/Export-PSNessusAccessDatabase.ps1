#######################################################################################################################
# File:             Public/Export-PSNessusAccessDatabase.ps1
# Description:      Copies Nessus data from a SQLite database into an Access template, producing a distributable
#                   Access database that preserves forms, queries, and relationships from the template.
# Context:          Requires an existing Access template (e.g., NATemplate-Enumerated.accdb). SQLite remains the source
#                   of truth; this command is intended for downstream consumers that need Office-native deliverables.
#######################################################################################################################

function Export-PSNessusAccessDatabase {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path -LiteralPath $_ })]
        [string]$SqlitePath,

        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path -LiteralPath $_ })]
        [string]$AccessTemplatePath,

        [Parameter(Mandatory)]
        [string]$OutputPath,

        [switch]$Force
    )

    $resolvedSqlitePath = (Resolve-Path -Path $SqlitePath).ProviderPath
    $resolvedTemplatePath = (Resolve-Path -Path $AccessTemplatePath).ProviderPath
    $resolvedOutputPath = [System.IO.Path]::GetFullPath($OutputPath)

    $outputDirectory = [System.IO.Path]::GetDirectoryName($resolvedOutputPath)
    if ($outputDirectory -and -not (Test-Path -LiteralPath $outputDirectory)) {
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    }

    if (Test-Path -LiteralPath $resolvedOutputPath) {
        if (-not $Force) {
            throw "OutputPath '$resolvedOutputPath' already exists. Specify -Force to overwrite."
        }
        if (-not $PSCmdlet.ShouldProcess($resolvedOutputPath, 'Remove existing Access database')) {
            return
        }
        Remove-Item -LiteralPath $resolvedOutputPath -Force
    }

    if (-not $PSCmdlet.ShouldProcess($resolvedOutputPath, 'Create Access export from SQLite database')) {
        return
    }

    Copy-Item -LiteralPath $resolvedTemplatePath -Destination $resolvedOutputPath -Force

    $sqliteContext = $null
    $accessContext = $null
    try {
        try {
            $sqliteContext = New-PSNessusDbContext -Path $resolvedSqlitePath -Provider 'SQLite'
            $accessContext = New-PSNessusDbContext -Path $resolvedOutputPath -Provider 'Access'
        }
        catch {
            $message = "Failed to initialize export contexts. SQLite='$resolvedSqlitePath', Access='$resolvedOutputPath'."
            Write-Error $message
            Write-Verbose $_.Exception.ToString()
            throw "$message $($_.Exception.Message)"
        }

        try {
            $summary = Invoke-PSNessusSqliteToAccessExport -SourceContext $sqliteContext -TargetContext $accessContext
        }
        catch {
            $message = "Access export failed. SQLite='$resolvedSqlitePath', Template='$resolvedTemplatePath', Output='$resolvedOutputPath'."
            Write-Error $message
            Write-Verbose $_.Exception.ToString()
            throw "$message $($_.Exception.Message)"
        }
        return $summary
    }
    finally {
        if ($accessContext) {
            try {
                Close-PSNessusDbContext -Context $accessContext
            }
            catch {
                Write-Warning ("Failed to close Access export context for '{0}': {1}" -f $resolvedOutputPath, $_.Exception.Message)
                Write-Verbose $_.Exception.ToString()
            }
        }
        if ($sqliteContext) {
            try {
                Close-PSNessusDbContext -Context $sqliteContext
            }
            catch {
                Write-Warning ("Failed to close SQLite export context for '{0}': {1}" -f $resolvedSqlitePath, $_.Exception.Message)
                Write-Verbose $_.Exception.ToString()
            }
        }
    }
}
