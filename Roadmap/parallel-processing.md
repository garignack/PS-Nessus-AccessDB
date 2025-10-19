# Parallel import design and evaluation

Purpose

This document evaluates the feasibility of a two-phase, parallel import workflow for PSNessusDB where the importer:

1. Streams a large `.nessus` file to collect and upsert unique plugin metadata first (single-writer phase).
2. Processes hosts (`ReportHost` segments) in parallel to populate host-level tables (multi-worker phase).

It's intended for review by multiple coders and to serve as the canonical design before any production code changes.

Summary / Verdict

Feasible and recommended. A streaming plugin-first pass (XmlReader or FileCutterUtilities) plus a runspace-based worker pool that uses per-worker SQLite connections in WAL mode is the recommended approach. This balances simplicity, performance, and data integrity without loading the entire XML DOM into memory.

Design constraints & assumptions

- Input files can exceed 500 MB — DOM parsing is not acceptable.
- PowerShell host is Windows PowerShell 5.1 by default; runspaces are available and preferable for performance.
- SQLite (PS-Sqlite) is the primary DB and will be tuned for concurrency (WAL, busy_timeout, per-connection PRAGMAs).
- Access export remains downstream and is out of scope for this document.

High-level workflow

1. DB preparation
   - Create/open SQLite DB, set PRAGMA journal_mode = WAL, synchronous = NORMAL, foreign_keys = ON, temp_store = MEMORY, busy_timeout = 10000.
   - Optionally drop non-essential indices for faster bulk loads; recreate after phase 3.

2. Plugin-first streaming pass (single-threaded)
   - Stream the .nessus file with a forward-only reader to locate every `ReportItem` and extract `pluginID` (and optional metadata: pluginName, pluginFamily, synopsis).
   - Store pluginIDs in a memory HashSet<int> and metadata in a small map. This set is small relative to full DOM and fits in memory in normal cases.
   - Insert/upsert plugin rows into `PluginInfo` with batch transactions.

3. Host slicing
   - Use `FileCutterUtilities` (existing) or XmlReader to locate byte offsets or create small temp slices for each `ReportHost`.
   - Produce a worklist: each item is a host identifier and slice descriptor (offset/length or temp file path).

4. Parallel host processing
   - Create a RunspacePool (or ThreadJobs fallback) with N workers (configurable: default 4).
   - Each worker opens its own SQLite connection configured with the PRAGMAs above.
   - Worker reads its slice, parses host and `ReportItem` nodes, and inserts data into Hosts, HostEnumeratedPorts, HostTags, ReportItem tables in a per-host transaction.
   - Prepared statements and parameterized inserts are used for speed.
   - On transient DB contention (SQLITE_BUSY), implement retries with exponential backoff.

5. Verification
   - Produce a JSON summary containing SQLite pre/post counts, inserted/skipped/failed rows per table, and a small sampled checksum for key columns.
   - Optionally run an integrity pass comparing expected counts from the parsed stream vs stored rows.

How to collect unique pluginIDs (detailed)

Recommended: .NET XmlReader streaming pass

- Use [System.Xml.XmlReader] with IgnoreWhitespace = $true.
- Advance until you encounter a `ReportItem` element. Extract `pluginID` from attribute or child element.
- Maintain a `System.Collections.Generic.HashSet[int]` to de-duplicate.
- Capture first-seen plugin metadata (name/family) in a hashtable keyed by pluginID.

Why XmlReader

- Robust, encoding-aware, small memory footprint, standard .NET API available in PowerShell.
- Avoids brittle string scanning and handles namespaces/encoding safely.

Alternative: FileCutterUtilities byte-scan

- Faster for strictly well-formed, uniform files.
- More brittle than XmlReader; recommended only if you need extra speed and can validate results.

Design for parallel host processing

Concurrency model options

A. Per-worker SQLite connections (recommended)
- Each worker opens an independent connection.
- Connection PRAGMAs: WAL, synchronous=NORMAL, busy_timeout=10000.
- Write operations use per-host transactions.
- Handle SQLITE_BUSY with retries and exponential backoff.

B. Single-writer queue (optional fallback)
- Workers parse and produce row batches (in memory or temp files) and send them to a single writer thread/process.
- Writer serializes DB writes, removing writer contention at the cost of a centralized bottleneck.

Why prefer per-worker connections

- Simpler to implement, easier to scale with CPU cores.
- WAL allows readers parallel to a writer; only writers serialize. With small per-host transactions and modest worker counts, throughput is good.

Worker behavior (recommended)

- Open SQLite connection, set PRAGMAs.
- Prepare INSERT statements for each table (Hosts, HostEnumeratedPorts, HostTags, ReportItem).
- Start transaction for host.
- Insert host metadata and associated rows.
- Commit transaction.
- On SQLITE_BUSY/LOCK error: retry up to 3 times with backoff (e.g., 200ms, 600ms, 1800ms). If still failing, save slice to `.testoutputs/failures/` and continue.

SQLite tuning recommendations

- Journal mode: WAL
- synchronous: NORMAL
- busy_timeout: 10000 (10s)
- temp_store: MEMORY
- Use prepared statements for repeated inserts
- For very large imports, drop non-critical indexes before load and recreate them after

Handling plugin metadata discovered later

- Aim to capture all pluginIDs in the plugin-first pass. If host parsing finds unknown pluginIDs then:
  - Option A: Buffer discovered pluginIDs and perform a single-threaded upsert after host parsing completes (simpler).
  - Option B: Have workers perform an INSERT OR IGNORE into PluginInfo before inserting ReportItem rows (requires occasional writer contention but is safe).

Failure modes and retry strategy (detailed)

- Transient SQLITE_BUSY: retry with exponential backoff (3 attempts). Log retries.
- Parsing error in a host slice: dump failing slice to `.testoutputs/failures/` and continue.
- Schema mismatch: treat as fatal by default; provide `-SkipMissingColumns` to proceed with logging.
- Capture failing SQL and parameter values to `.testoutputs/failures/<table>-<timestamp>.log`.

Runspace vs Job choices

- Runspaces (RunspacePool): high performance, low serialization overhead; recommended.
- Start-Job / Start-ThreadJob: higher overhead and object serialization; acceptable as a fallback.
- Provide a configuration flag to select worker mode; default to runspaces when available.

API surface suggestions

- `Import-PSNessusDB -FullName <file> -DatabasePath <path> -Provider SQLite -NewDb -Parallel -Workers 4 -BatchSize 500 -DryRun -Verbose`
- `Export-PSNessusSqliteToAccess` unchanged; export remains single-threaded.

Verification and testing

- Smoke tests: parse `.testoutputs/Newest_Export.nessus` in DryRun to collect pluginIDs and host counts; verify summary JSON.
- Integration tests: run full import with Workers=2 and compare row counts against single-threaded import.
- Failure injection tests: simulate SQLITE_BUSY by holding an exclusive transaction in another connection for a while and confirm retries and requeues.

Metrics to capture & report

- Total processed hosts, succeeded, failed
- Total ReportItems inserted, skipped, failed
- Plugin count in DB vs plugin IDs discovered
- Average time per host and per worker
- Number and types of SQLITE_BUSY events and retries

Implementation checklist (suggested incremental approach)

1. Implement `Collect-PluginIDs` utility (streaming XmlReader) and a DryRun mode that writes plugin list to `.testoutputs/`.
2. Implement host slicing helper that returns host offsets or temp files (use existing FileCutterUtilities).
3. Implement a runspace-based `WorkerPool` helper in `Private/` with a simple interface to process slices.
4. Implement `Process-HostSlice` worker function that opens its own SQLite connection and inserts per-host rows.
5. Add retry, failure dumping, and JSON summary generation.
6. Add integration smoke tests under `tools/` and update `sqlite-migration.md` with tuned default params.

Open questions for reviewers

- Maximum expected unique pluginIDs for our largest customers? (If > ~1M, consider disk-backed set)
- Tolerance for eventual consistency in plugin metadata vs strict parity (affects whether workers must upsert plugins).
- Preferred default worker count for CI vs local runs.

Appendix: sample XmlReader snippet (PowerShell)

```powershell
$settings = New-Object System.Xml.XmlReaderSettings
$settings.IgnoreWhitespace = $true
$reader = [System.Xml.XmlReader]::Create($nessusPath, $settings)
$pluginSet = New-Object 'System.Collections.Generic.HashSet[int]'
while ($reader.Read()) {
  if ($reader.NodeType -eq [System.Xml.XmlNodeType]::Element -and $reader.Name -eq 'ReportItem') {
    $attr = $reader.GetAttribute('pluginID')
    if ($attr) { $pid = [int]$attr }
    else {
      $sub = $reader.ReadSubtree()
      while ($sub.Read()) {
        if ($sub.NodeType -eq [System.Xml.XmlNodeType]::Element -and $sub.Name -eq 'pluginID') {
          $pid = [int]$sub.ReadElementContentAsString()
          break
        }
      }
      $sub.Close()
    }
    if ($pid -and -not $pluginSet.Contains($pid)) { $pluginSet.Add($pid) | Out-Null }
  }
}
$reader.Close()
```

Review checklist

- [ ] Confirm streaming approach and XmlReader sample is acceptable.
- [ ] Agree on per-worker connection + WAL strategy.
- [ ] Confirm retry/backoff policy and failure dump behavior.
- [ ] Decide whether workers should upsert missing plugins or if that should be a later reconciliation step.

Delivery & next steps

If the design is approved I can implement a minimal prototype consisting of:
- `Private/Collect-PluginIDs.ps1` (streaming collector)
- `Private/RunspacePoolHelper.ps1` (runspace worker pool)
- `Private/Process-HostSlice.ps1` (worker)
- `tools/import-parallel-smoke.ps1` (dry-run harness)

Once the prototype passes smoke tests I will iterate on tuning and add integration tests.

-----

Please add reviewer comments inline in this file. If you want, I can also open a PR branch and create those prototype files for hands-on review.

Work completed (this proposal)

- Evaluated and documented a two-phase import workflow (plugin-first, then parallel hosts) that avoids DOM parsing for large files.
- Specified streaming discovery of unique `pluginID` values using `System.Xml.XmlReader` and an in-memory `HashSet<int>` to deduplicate.
- Designed a runspace-based parallel host processing model with per-worker SQLite connections and recommended PRAGMA tuning (WAL, busy_timeout, etc.).
- Drafted failure/retry strategies (exponential backoff, per-table/host transactions, failure dump files) and verification/reporting requirements (JSON summary, sampled checksums).
- Considered a split-plugin DB approach (separate `plugins.sqlite` attached read-only) and documented its benefits and tradeoffs.

Benefits of this approach

- Performance: parallel host parsing and inserts utilize multiple CPU cores and reduce wall time for large imports while keeping memory usage low.
- Reduced writer contention: prepopulating plugin metadata or using an attached read-only plugin DB removes plugin writes from the hot path and reduces SQLITE_BUSY events.
- Deterministic plugin metadata: a canonical `plugins.sqlite` enables consistent plugin metadata across imports and easier auditing/versioning.
- Reliability: per-host transactions and bounded retries isolate failures to individual hosts; failing slices are captured for replay without aborting the whole import.
- Testability: DryRun and plugin-collector utilities make it easy to write smoke tests and compare parallel vs single-threaded results.
- Incremental rollout: the design allows toggling `-Parallel` and `-Workers` so teams can roll out gradually and tune parameters per environment.

Suggested next steps for implementation

1. Approve the design and pick default runtime parameters for CI (e.g., Workers=2 for CI, default Workers=4 for local runs).
2. Implement the minimal prototype listed above and run smoke tests using `.testoutputs/Newest_Export.nessus`.
3. Iterate based on observed SQLITE_BUSY rates and tune worker counts, batch sizes, and whether to use a local cache of plugin metadata per worker.
4. If the split-plugin DB pattern is chosen, implement `tools/prepare-plugins-db.ps1` and a documented release/update process for the canonical plugin DB.

Please review and comment on the proposed defaults (Workers, BatchSize, busy_timeout) and whether the team prefers runspaces or thread-jobs as the initial worker implementation.
