# PSNessusDB Error Handling and Logging Hardening Roadmap

## Scope
- Source review basis: `AGENTS.MD` plus all scripts imported by `PSNessusDB/PSNessusDB.psm1` (`Private/**/*.ps1`, `Public/*.ps1`).
- Goal: improve importer/report/export resilience and diagnostics without changing intended data model behavior.

## Priority Order
1. **P0**: Host-write resilience for malformed/blank host tags (current top concern).
2. **P1**: Access data-return shape consistency (`Get-PSNessusDbData`) to avoid downstream `.Rows` failures.
3. **P2**: Structured logging for currently silent catches and fragile cleanup paths.
4. **P3**: Report matrix SQL safety/validation guardrails for JSON definition fields.

## P0: Host-Write Resilience (Blank Tag Failure)

### Problem Statement
- A malformed host tag (including blank tag names/values in edge cases) can cause `Add-PSNessusHostRecord` to throw during DB writes, which currently aborts file processing via the outer transaction/error path in `Import-PSNessusDB`.
- This is highest operational risk because one bad host can stop ingestion of otherwise valid hosts in the same file.

### Target Outcomes
- Import continues when a host has invalid tag content.
- Invalid tag rows are skipped with explicit warning/error logs that identify:
  - file path
  - report host index/name
  - tag name/value summary
  - provider and table
- Transaction remains consistent (no partial writes for the failed host record).

### Implementation Tasks
- [ ] Add explicit host-tag sanitization/validation helper in `Add-PSNessusHostRecord` before `HostTags` insert:
  - Skip empty/whitespace `TagName`.
  - Normalize null values to empty string (or `$null` by policy) explicitly.
  - Emit `Invoke-Logger -Warn` with host + tag context when skipping.
- [ ] Wrap host-level write path in `Import-PSNessusDB` around `Add-PSNessusHostRecord`:
  - Catch per-host exceptions.
  - Log full exception and continue to next host.
  - Track `HostsSucceeded` / `HostsFailed` counters in summary output.
- [ ] Ensure per-host transactional behavior is explicit for failure isolation:
  - Confirm rollback occurs for failed host.
  - Confirm next host starts cleanly.
- [ ] Add verbose summary section at end of import with failure counts and first N failed host names.

### Validation Tasks
- [ ] Create a reproducible malformed-host fixture under `.testoutputs/` (or transform sample input during test run) containing blank/invalid tags.
- [ ] Verify importer completes file with partial host success instead of full abort.
- [ ] Verify logs clearly show skipped tag(s) and failed host details.
- [ ] Verify row counts and relational integrity in SQLite and Access targets after run.

## P1: Access Data Return Consistency

### Problem Statement
- `Get-PSNessusDbData` Access branch currently wraps query output in a way that risks returning an array shape instead of the expected `DataTable`, breaking `.Rows` access patterns.

### Tasks
- [ ] Normalize return contract from `Get-PSNessusDbData` for both providers to always return `System.Data.DataTable`.
- [ ] Add defensive type check where used in critical paths (`Add-PSNessusHostRecord`, report matrix query helpers).
- [ ] Log provider + SQL context on type mismatch before throw.

## P2: Logging and Exception Context Hardening

### Problem Statement
- Several catches swallow errors or emit minimal context, reducing diagnosability.

### Tasks
- [ ] Replace silent cache-load catches in `New-PSNessusDbContext` with warning/debug logs (include provider, path, exception message).
- [ ] Standardize user-facing logger initialization failures to `Write-Error`/`Write-Warning` (avoid `Write-Host` for operational errors).
- [ ] Add structured context to export failures in:
  - `Export-PSNessusReportMatrix`
  - `Export-PSNessusAccessDatabase`
  - `Invoke-PSNessusSqliteToAccessExport`
- [ ] Ensure cleanup/close failures are logged at debug/warn level without masking primary exceptions.

## P3: Report Matrix SQL Guardrails

### Problem Statement
- Dynamic SQL interpolation from JSON definitions (`WhereClause`, `PluginHash`, `Columns`) is fragile and can fail hard on invalid content.

### Tasks
- [ ] Add preflight validation for required SQL fragments and reject dangerous/unsupported patterns with actionable error messages.
- [ ] Constrain column identifiers to an allowlist pattern where feasible.
- [ ] Improve log output to show report definition name/index that failed preflight.

## Execution Plan
1. Implement and test **P0** end-to-end first.
2. Land **P1** in same or immediately following change set (high regression risk if left open).
3. Address **P2** logging consistency.
4. Finish with **P3** validation guardrails.

## Definition of Done
- Import no longer aborts entire file due to blank/malformed host tags.
- Host-level failures are visible and measurable in logs and summary metrics.
- Access and SQLite imports complete with parity checks documented in `.testoutputs/`.
- No silent catch remains in critical import/export paths without at least warning/debug telemetry.
