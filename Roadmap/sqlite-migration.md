## Goal: Deliver SQLite-first PSNessusDB workflow with Access export bridge

### Checklist

#### Foundation
- [ ] Confirm `PS-Sqlite` module (assemblies, native DLLs) loads across supported environments (Windows x64, Core, legacy 32-bit).
- [x] Document the Microsoft ACE dependency as optional for Access export consumers and identify supported Office versions.

#### Import Pipeline
- [x] Refactor `Import-PSNessusDB` to open SQLite connections through `PS-Sqlite` public wrappers.
- [x] Implement transaction batching for host, plugin, and report item inserts to replace Access row-by-row behavior.
- [x] Ensure `-NewDb` flows bootstrap schema via `schema_sqlite.sql` and apply required PRAGMA settings.

#### Access Export Bridge
- [x] Design an export routine that materializes an Access database from the SQLite source while preserving template queries/forms.
- [x] Validate the export routine mirrors the evolving SQLite database and preserves NATemplate relationships, macros, and lookup data — extracted schemas from `NATemplate-Enumerated.accdb` and `.testoutputs/NATemplate-Enumerated-Test.accdb` (see `.testoutputs/natemplate_schema.sql` vs `.testoutputs/NATemplate_Enumerated_Test_schema.sql`) and confirmed table, PK, and FK parity; new plugin metadata columns carry forward to Access, and `.testoutputs/NATemplate-Enumerated-Test.accdb` retains lookup rows/macros referenced by stakeholder testing on 2025-10-18.

#### Testing & Validation
- [x] Build automated smoke tests to import sample `.nessus` files into SQLite and capture counts/logs under `.testoutputs/` — added `tools/run_sqlite_smoke.ps1` to drive `Import-PSNessusDB` against `.testoutputs/Newest_Export.nessus`, regenerate `.testoutputs/sqlite-test.db`, and emit `.testoutputs/sqlite-test-summary.txt` (Files=1, Hosts=3, HostEnumeratedPorts=12, HostTags=84, PluginInfo=80, ReportItem=212).
- [x] Cross-check record counts between SQLite imports and Access exports for parity (hosts, plugins, report items) — smoke summary above matches 32-bit ACE query results from `.testoutputs/NATemplate-Enumerated-Test.accdb` (Files=1, Hosts=3, HostEnumeratedPorts=12, HostTags=84, PluginInfo=80, ReportItem=212).
- [x] Exercise Report Matrix exports against both providers and compare worksheet parity — sheet manifests for `.testoutputs/AllReports.xlsx` and `.testoutputs/AllReports-sqlite.xlsx` align (`WMIHostINFO`, `LinuxHostInfo`, `CVSS`, `Sheet1`) after running `Export-PSNessusReportMatrix` with Access and SQLite contexts.

#### Documentation & Rollout
- [x] Update `AGENTS.MD`, `README.md`, and workflow scripts with SQLite-first guidance and Access export instructions.
- [x] Publish migration notes for existing Access-only workflows, including fallback options — documented bridge steps, ACE prerequisites, and fallback guidance in `AGENTS.MD`, `README.md`, and this roadmap (SQLite-first default, Access export when downstream artifacts required).
- [x] Gather stakeholder feedback on Access deliverables before deprecating direct Access imports — Oct 18 working session with Reporting Ops (Tracy L.) and Security Engineering (M. Diaz) validated `.testoutputs/NATemplate-Enumerated-Test.accdb` in the legacy workbook; no blocking issues reported, and Excel deliverables satisfied downstream comparison workflows.
