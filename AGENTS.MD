# AGENTS.MD

## Mission
- PSNessusDB is a Powershell toolkit for parsing and analyzing Tennable Nessus Scan results.  It was designed to aid information security professionals with processing and evaluting large, complex result sets with minimal installation requirements.
- Import Nessus .nessus exports into Access or SQLite using the modernized PSNessusDB module.
- Generate Excel report matrices from loc_Reports_Matrix definitions using `Export-PSNessusReportMatrix` (Access or SQLite).

## Primary Usage
1. Import one or many Nessus scan files into a portable database for consolidated querying, trend analysis, and deduplicated plugin metadata.
2. Export standardized or custom reports (notably the Report Matrix) to summarize and compare large host populations rapidly.
3. **[Future]** Re-ingest subsequent scans of the same assets to surface improvements or regressions automatically.

## Provider Strategy Notes
- Favor SQLite as the default ingestion target to avoid ACE prerequisites and retain cross-platform workflows, while keeping Access support for consumers that rely on downstream artifacts.
- Introducing an SQLite-to-Access export path preserves existing Access templates but requires validation to ensure predefined queries/forms and schema nuances survive the transfer.
- Any architectural shift should be staged alongside stakeholder feedback and parity testing between Access and SQLite outputs.

## Key Assets
- `PSNessusDB/PSNessusDB.psd1`
- `PSNessusDB/PSNessusDB.psm1`
- `PSNessusDB/Public/Import-PSNessusDB.ps1`
- `PSNessusDB/Public/Export-PSNessusReportMatrix.ps1`
- `PSNessusDB/Private/Database/AccessProvider.ps1`
- `PSNessusDB/Private/FileCutterUtilities.ps1`
- `PSNessusDB/PS-Log/*`
- `PSNessusDB/PS-Sqlite.psm1` with `Public/`, `Private/`, `Lib/` (System.Data.SQLite + e_sqlite3)
- Schemas: `schema_sqlite.sql` (SQLite), `schema_access_accessdb.sql` (Access reference)
- `.testoutputs/` for transient logs, databases, and exports (ignored by git)

## Standard Workflow
1. **Choose provider & target database**
   - Access: `Copy-Item NATemplate-Enumerated.accdb NATemplate-Enumerated-Test.accdb`
   - SQLite: allow importer to create a new DB with `-Provider SQLite -NewDb -DatabasePath .\.testoutputs\sqlite\import.db`
2. **Use 32-bit PowerShell for Access** (when Office ACE provider is 32-bit):
   ```powershell
   $repoRoot = Resolve-Path .
   & "$env:WINDIR\SysWOW64\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command "
       Set-Location '$repoRoot';
       Import-Module .\PSNessusDB\PSNessusDB.psd1 -Force;
       Import-PSNessusDB -FullName .\Newest_Export.nessus -DatabasePath .\NATemplate-Enumerated-Test.accdb -Verbose
   "
   ```
3. **SQLite import** (native PowerShell session):
   ```powershell
   Import-Module .\PSNessusDB\PSNessusDB.psd1 -Force
   Import-PSNessusDB -FullName .\.testoutputs\Newest_Export.nessus -DatabasePath .\.testoutputs\sqlite-test.db -Provider SQLite -NewDb -Verbose
   ```
4. Review `.testoutputs\sqlite-test.log` (or Access log) plus summary counts (`.testoutputs\sqlite-test-summary.txt` created via PS-Sqlite helpers) to confirm hosts, plugins, and report items were imported (baseline: Files=1, Hosts=3, PluginInfo=80, ReportItem=212).

## Report Matrix Workflow
1. Sample definition JSON: SampleReports/AllReports.json (replace \u0026 with & if tweaking).
2. Keep experimental outputs under .testoutputs/ (e.g., .testoutputs/AllReports.xlsx).
3. Access database (32-bit PowerShell when ACE is 32-bit):
   `powershell
    = Resolve-Path .
   & "C:\WINDOWS\\SysWOW64\\WindowsPowerShell\\v1.0\\powershell.exe" -NoProfile -Command "
       Set-Location '';
       Import-Module .\\PSNessusDB\\PSNessusDB.psd1 -Force;
       Export-PSNessusReportMatrix -JsonPath .\\SampleReports\\AllReports.json -DatabasePath .\\refactor_enum4.accdb -OutputPath .\\.testoutputs\\AllReports.xlsx -Verbose -Force
   "
   `
4. SQLite database (standard PowerShell session):
   `powershell
   Import-Module .\\PSNessusDB\\PSNessusDB.psd1 -Force
   Export-PSNessusReportMatrix -JsonPath .\\SampleReports\\AllReports.json -DatabasePath .\\.testoutputs\\sqlite-test.db -Provider SQLite -OutputPath .\\.testoutputs\\AllReports-sqlite.xlsx -Verbose -Force
   `
5. Each report with results produces a worksheet; skipped definitions emit verbose status. Review both Access and SQLite outputs for parity.

## Operating Notes
- PS-Log handles logging; keep module alongside manifest.
- PS-Sqlite nested module must remain with its `Lib` dependencies so SQLite connections work.
- Legacy scripts have been removed; use the module surface exclusively.
- `.testoutputs/` directory is ignored by git-stage/import logs there, then prune when finished.

## Best Practices & Testing
- Follow [PowerShell Practice and Style](https://github.com/PoshCode/PowerShellPracticeAndStyle): approved verbs, comment-based help, advanced functions.
- Prefer `Invoke-PSNessusSqlite*` helpers for SQLite and parameterized commands over string concatenation.
- Validate new database paths with `-NewDb`; the importer handles schema bootstrap via `schema_sqlite.sql`.
- Record comparison counts (e.g., Access vs SQLite) to ensure parity after imports.
- Run `Invoke-ScriptAnalyzer` when available; current environment lacks installation so mark tasks `[FUTURE]` and note when skipped.
- Use `.testoutputs/` artifacts (logs, summaries, Excel) as reproducible evidence for test runs.

