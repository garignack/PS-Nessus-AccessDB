# AGENTS.MD

## Mission
- Import Nessus .nessus exports into Access using the modernized PSNessusDB module.
- Generate Excel report matrices from loc_Reports_Matrix definitions using `Export-PSNessusReportMatrix`.

## Key Assets
- `PSNessusDB/PSNessusDB.psd1`
- `PSNessusDB/PSNessusDB.psm1`
- `PSNessusDB/Public/Import-PSNessusDB.ps1`
- `PSNessusDB/Public/Export-PSNessusReportMatrix.ps1`
- `PSNessusDB/Private/Database/AccessProvider.ps1`
- `PSNessusDB/Private/FileCutterUtilities.ps1`
- `PSNessusDB/PS-Log/*`
- `.testoutputs/` (ignored scratch space for local test artifacts)

## Standard Workflow
1. `Copy-Item NATemplate-Enumerated.accdb NATemplate-Enumerated-Test.accdb`
2. When Microsoft.ACE.OLEDB.12.0 is only available via 32-bit Office, run PowerShell from `SysWOW64`:
   ```powershell
   $repoRoot = Resolve-Path .
   & "$env:WINDIR\SysWOW64\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command "
       Set-Location '$repoRoot';
       Import-Module .\PSNessusDB\PSNessusDB.psd1 -Force;
       Import-PSNessusDB -FullName .\Newest_Export.nessus -DatabasePath .\NATemplate-Enumerated-Test.accdb -Verbose
   "
   ```
3. Inspect `NATemplate-Enumerated-Test.log` and the Access tables (Files, Hosts, Plugins, etc.) for verification.

## Report Matrix Workflow
1. A sample report JSON definition file lives at `SampleReports/AllReports.json`.
2. Store working JSON/Excel outputs under `.testoutputs/` when experimenting locally to keep the repo clean.
3. Execute the export under 32-bit PowerShell when Access requires it:
   ```powershell
   $repoRoot = Resolve-Path .
   & "$env:WINDIR\SysWOW64\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command "
       Set-Location '$repoRoot';
       Import-Module .\PSNessusDB\PSNessusDB.psd1 -Force;
       Export-PSNessusReportMatrix -JsonPath .\SampleReports\AllReports.json -DatabasePath .\refactor_enum4.accdb -OutputPath .\.testoutputs\AllReports.xlsx -Verbose -Force
   "
   ```
4. Each report with results produces a worksheet; skipped entries emit verbose status. Review Excel output and compare against known baselines as needed.

## Operating Notes
- Logging is handled by the PS-Log nested module; ensure `PS-Log.psm1` stays beside the manifest.
- SQLite provider paths exist but throw `NotImplementedException` until backed by the `pssqlite` module.
- Legacy scripts have been removed; use sources under `PSNessusDB` exclusively.
- Use `.testoutputs/` for temporary exports during development; purge or archive when no longer needed.

## Best Practices
- Align all PowerShell updates with the [PowerShell Practice and Style](https://github.com/PoshCode/PowerShellPracticeAndStyle) guide.
- Favor approved verb-noun naming, singular nouns, and consistent parameter casing when introducing new functions or parameters.
- Include comment-based help with synopsis, description, and parameter sections; prefer `Write-Verbose`/`Write-Debug` for diagnostics over `Write-Host`.
- Treat advanced functions as the default; validate parameters, and return objects instead of formatted strings.
- [FUTURE] Run `Invoke-ScriptAnalyzer` (PowerShell Script Analyzer) on changed scripts and resolve violations before shipping. (Not Installed)
