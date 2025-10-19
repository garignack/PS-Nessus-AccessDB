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
- [ ] Validate the export routine mirrors the evolving SQLite database and preserves NATemplate relationships, macros, and lookup data.

#### Testing & Validation
- [ ] Build automated smoke tests to import sample `.nessus` files into SQLite and capture counts/logs under `.testoutputs/`.
- [ ] Cross-check record counts between SQLite imports and Access exports for parity (hosts, plugins, report items).
- [ ] Exercise Report Matrix exports against both providers and compare worksheet parity.

#### Documentation & Rollout
- [x] Update `AGENTS.MD`, `README.md`, and workflow scripts with SQLite-first guidance and Access export instructions.
- [ ] Publish migration notes for existing Access-only workflows, including fallback options.
- [ ] Gather stakeholder feedback on Access deliverables before deprecating direct Access imports.
