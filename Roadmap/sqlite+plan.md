## Goal: Implement SQLite support in AccessProvider.ps1 using pssqlite.psm1

### Step-By-Step Plan
1. **Adopt pssqlite as a PSNessusDB nested module**
   - Migrate `pssqlite.psm1` (and related assets) into `PSNessusDB/` alongside `PS-Log.psm1` following Public/Private/Lib structure.
   - Create `PSNessusDB/PS-Sqlite/` with `PS-Sqlite.psm1`, `Public/`, `Private/`, and `Lib/` folders; relocate assemblies such as `System.Data.SQLite.dll` under `Lib/`.
   - Update the module manifest (`PSNessusDB.psd1`) to list the new nested module.
   - Ensure the module initializes the PATH or load context for `e_sqlite3.dll` from the Lib folder.
2. **Expose SQLite helpers within PSNessusDB**
   - Create thin wrapper exports (e.g., `Open-PSNessusSqliteConnection`, `Invoke-PSNessusSqliteQuery`) that mirror existing pssqlite functionality but align with module naming conventions.
   - Provide internal helper functions (Private) for command creation, parameter binding, and result conversion.
3. **Extend AccessProvider.ps1**
   - Add SQLite-specific helper functions (e.g., `New-SqliteConnection`, `Invoke-SqliteNonQuery`, `Invoke-SqliteQuery`, `Ensure-SqliteColumns`) that delegate to the new module.
   - Update provider switch statements in `New-PSNessusDbContext`, `Get-PSNessusDbData`, `Add-PSNessusDbRecord`, `Ensure-PSNessusDbColumns`, `Close-PSNessusDbContext`, and `ConvertTo-PSNessusDbValue` to support SQLite.
   - Handle schema bootstrap for SQLite when `-NewDB` is specified using `schema_sqlite.sql`.
4. **Coordinate schema/init changes**
   - Ensure schema generation scripts produce SQLite-compatible DDL (already in `schema_sqlite.sql`).
   - Add tooling (similar to Access schema export) for verifying SQLite schema creation.
5. **Refactor and test**
   - Update documentation (AGENTS.MD) and workflows to cover SQLite usage.
   - Add scripts/tests to exercise SQLite path: initialize DB, run importer, verify tables.

### Current State
- AccessProvider.ps1 has scaffolding for a 'SQLite' provider but throws NotImplementedException across connection, insert, query, and column management helpers.
- pssqlite.psm1 encapsulates connection handling, query execution, and parameter binding for System.Data.SQLite.
- Native schema DDL for SQLite lives in schema_sqlite.sql (for future support), while Access schema is now exported via schema_access_accessdb.sql.

### High-Level Work Plan
1. **Introduce SQLite Connection Layer via PS-Sqlite**
   - Update AccessProvider to import `PS-Sqlite.psm1` (nested module) and leverage its public helpers for opening connections and running commands instead of raw pssqlite references.
   - Ensure provider setup triggers PRAGMA settings (foreign keys) immediately after establishing a connection.
2. **Map Existing Surface to SQLite**
   - Update Get-PSNessusDbData, Add-PSNessusDbRecord, Ensure-PSNessusDbColumns, Close-PSNessusDbContext, New-PSNessusDbContext to branch on provider 'SQLite' and call new PS-Sqlite wrappers.
   - Provide ConvertTo-PSNessusDbValue logic for SQLite using parameterized queries to avoid manual escaping.
   - Ensure plugin cache logic works for SQLite (SELECT ID, PluginHash) using PS-Sqlite query helpers.
3. **Schema Creation & Migration**
   - When -NewDB is requested for SQLite, create a fresh `.db` file using `schema_sqlite.sql` executed through PS-Sqlite.
   - Decide on handling of AUTOINCREMENT / FOREIGN KEY pragmas; ensure schema matches Access analogues where practical.
4. **Parameterization & Transactions**
   - Align insert/update operations to use parameterized commands; avoid Access-style string concatenation.
   - Evaluate transaction batching for importer performance parity.
5. **Testing Strategy**
   - Create test harness scripts to initialize SQLite DB from schema, run Import-PSNessusDB, verify table counts.
   - Add scripted validation in `.testoutputs/` (e.g., `.testoutputs/sqlite-import.log`).
6. **Documentation & CLI Support**
   - Update AGENTS.MD to describe SQLite path, prerequisites (System.Data.SQLite, native DLL). Add guidance on using `-Provider SQLite` and `-NewDB` to bootstrap.
   - Provide fallback messaging when PS-Sqlite module not available.
7. **Prompt Suggestions for Future Iterations**
   - "Implement New-SqliteConnection helper inside AccessProvider.ps1 mirroring New-AccessConnection but leveraging PS-Sqlite module."
   - "Add SQLite branch to Get-PSNessusDbData and Add-PSNessusDbRecord using Invoke-PSNessusSqliteQuery / Invoke-PSNessusSqliteNonQuery."
   - "Create schema_sqlite.sql DDL executor that initializes SQLite DB when -NewDB flag is provided."
   - "Add integration test script under .testoutputs verifying both Access and SQLite providers load identical data from sample .nessus file."

### Recommended Next Steps
- Draft SQLite helper functions in AccessProvider.ps1 (New-SqliteConnection, Invoke-SqliteQueryWrapper, Invoke-SqliteNonQueryWrapper, Ensure-SqliteColumns).
- Wire provider switch cases to new helpers.
- Implement database initialization for SQLite from schema SQL when New-PSNessusDbContext sees -NewDB or missing file.
- Update documentation and plans to highlight requirements and testing.

### Testing with Newest_Export.nessus
1. Initialize an empty SQLite database using `schema_sqlite.sql` (`.testoutputs/sqlite-test.db`).
2. Run Import-PSNessusDB with `-Provider SQLite -DatabasePath .testoutputs/sqlite-test.db -FullName Newest_Export.nessus`.
3. Capture logs under `.testoutputs/` (e.g., `.testoutputs/sqlite-import.log`).
4. Compare record counts against Access baseline to ensure parity.


