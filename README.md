# PSNessusDB

PSNessusDB is a PowerShell module for importing Tenable Nessus `.nessus` exports into a portable SQLite database, running report automation, and optionally materialising Microsoft Access deliverables for Office-centric stakeholders.

## Requirements
- Windows PowerShell 5.1 or PowerShell 7.x
- .NET Framework 4.7.2 or later (PowerShell 5.1)
- Optional: Microsoft Access Database Engine (ACE) if you need to open or automate the Access exports

## Installation
1. Clone or download this repository.
2. Add the repository root to `$Env:PSModulePath` or import the module by path:
   ```powershell
   Import-Module .\PSNessusDB\PSNessusDB.psd1 -Force
   ```

## SQLite-First Workflow
### Import Nessus Data
```powershell
Import-PSNessusDB `
    -FullName .\Exports\WeeklyScan.nessus `
    -DatabasePath .\.testoutputs\nessus.sqlite `
    -Provider SQLite `
    -NewDb `
    -Verbose
```
- Creates (or reuses) a SQLite database and logs under `.testoutputs\nessus.log`.
- All plugin metadata is de-duplicated automatically using the `PluginInfo` table.

#### Import Multiple Nessus Files
```powershell
Get-ChildItem .\.testoutputs\GoogleTop1000 -Filter '*.nessus' |
    Sort-Object FullName |
    Import-PSNessusDB -DatabasePath .\.testoutputs\google-top1000.sqlite `
                     -Provider SQLite -NewDb -Verbose
```
- Streams every `.nessus` file in the directory through `Import-PSNessusDB`.
- Use `-NewDb` to bootstrap a fresh SQLite database on the first run; omit it to append into an existing database.
- All imports share the same log file (based on the database name) so you can review a consolidated trace.

### Export Report Matrices
```powershell
Export-PSNessusReportMatrix `
    -JsonPath .\SampleReports\AllReports.json `
    -DatabasePath .\.testoutputs\nessus.sqlite `
    -Provider SQLite `
    -OutputPath .\.testoutputs\AllReports.xlsx `
    -Verbose -Force
```
- Each populated definition becomes a worksheet; skipped definitions emit verbose messages.

### Export Tag Matrix (No JSON)
```powershell
Export-PSNessusTagMatrix `
    -DatabasePath .\.testoutputs\nessus.sqlite `
    -Provider SQLite `
    -OutputPath .\.testoutputs\TagMatrix.xlsx `
    -Force -Verbose
```
- Rows are built from `HostTags.TagName`.
- Host cells are filled with `HostTags.TagValue`.
- Omitting `-Tags` includes all tags.

```powershell
Export-PSNessusTagMatrix `
    -DatabasePath .\.testoutputs\nessus.sqlite `
    -Provider SQLite `
    -Tags @('Credentialed_Scan', 'HOST_END_TIMESTAMP') `
    -OutputPath .\.testoutputs\TagMatrix-Filtered.xlsx `
    -Force -Verbose
```

### Bridge to Access (Optional)
```powershell
Export-PSNessusAccessDatabase `
    -SqlitePath .\.testoutputs\nessus.sqlite `
    -AccessTemplatePath .\NATemplate-Enumerated.accdb `
    -OutputPath .\.testoutputs\nessus-access.accdb `
    -Force -Verbose
```
- Copies the template, replays data from SQLite, and keeps template forms, queries, and macros intact.
- Requires the Microsoft ACE OLE DB provider (32-bit environments must run 32-bit PowerShell).

## Data Flow
1. **Import-PSNessusDB** parses each `ReportHost` block with streaming file cutters, batches inserts inside provider-aware transactions, and hydrates the normalized schema (`Files`, `Hosts`, `HostEnumeratedPorts`, `HostTags`, `PluginInfo`, `ReportItem`).
2. **SQLite** is the system of record. Schema bootstrap comes from `schema_sqlite.sql` and PRAGMAs (`WAL`, `foreign_keys`) are applied on first run.
3. **Export-PSNessusAccessDatabase** mirrors the SQLite contents into an Access copy, remapping IDs so relationships, lookups, and macros defined in the template continue to function.
4. **Export-PSNessusReportMatrix** runs cross-table queries (SQLite or Access) defined via JSON, turning findings into analyst-friendly Excel matrices.
5. **Export-PSNessusTagMatrix** builds a host-tag matrix directly from `HostTags` without requiring a report definition JSON.

## Project Conventions
- All transient outputs, logs, and test artefacts belong under `.testoutputs\`.
- Provider helpers live in `Private\Database\AccessProvider.ps1` and expose provider-neutral functions (`Add-PSNessusDbRecord`, `Get-PSNessusDbData`, transactions, etc.).
- PS-Sqlite is vendored (`PSNessusDB\PS-Sqlite\`) and loaded on demand to avoid separate installation steps.
- Use `Invoke-PSNessusSqlite*` and `Invoke-Access*` wrappers instead of ad-hoc SQL; they handle parameterisation, transactions, and provider quirks.

## Logging & Diagnostics
- Logging is powered by PS-Log (`Switch-LogFile`, `New-LogFile`, `Invoke-Logger`). Default logs mirror the database name with a `.log` extension.
- Verbose output surfaces counts and timing data; enable `-Trace` on `Import-PSNessusDB` for per-host detail.
- Transaction batches (default 50 hosts) keep imports performant across both providers.

## Optional Tooling
- `tools\extract_access_schema.ps1` can regenerate Access DDL snapshots.
- Future enhancements: integrate `Invoke-ScriptAnalyzer`, automated regression imports, and host delta comparisons.
