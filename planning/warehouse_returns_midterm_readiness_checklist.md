# Warehouse Returns: Midterm Readiness Check

**Project**: Warehouse Returns and Refurbishment Tracking System
**Authors**: Rajdeep Villuri and Hunter Yee
**Status as of**: November 27, 2026, after the midterm feedback fixes
**Baseline**: FRD 2.1, ERD 2.1, TDD 1.0 (sections 5, 6 and 9 updated); 15 business tables + 14 history tables + 2 build-stamp tables

Every "Verified" row below has run output committed in the repository. "Implemented" means the code exists and builds but has no dedicated committed test. The previous version of this checklist claimed everything was verified before any run output existed; this version states only what the evidence shows.

## Deliverables and evidence

| Requirement | Status | Evidence |
| --- | --- | --- |
| FRD with requirements, use cases, business rules, acceptance criteria | Completed | [FRD 2.1](../docs/warehouse_returns_frd_simplified_v2_1.md): FR-01–FR-15, BR-01–BR-10, AC-01–AC-11 |
| ERD with meaningful entities, relationships, participation | Completed, **update pending** | [draw.io](../docs/warehouse_returns_erd_v2_1.drawio) and [dictionary](../docs/warehouse_returns_erd_v2_1.md). The diagram does not yet show the history tables, the SchemaBuild tables or the `AuditLog` generated columns. |
| Technical design and 3NF | Completed | [TDD](../docs/warehouse_returns_technical_design.md) sections 3–4 |
| Schema with keys, constraints, indexes | Verified | Fresh build through `build/build_database.sh` on MySQL 8.4.11: 18 scripts, 15 base + 14 history tables |
| Reproducible tagged build | Verified | Build script clones an exact tag, verifies the commit and records a `SchemaBuild` stamp. Acceptance check "In-database version stamp names the release, commit and every script" |
| Controlled operations (procedures) | Verified | 20 procedures (19 callable, 1 internal) and 3 functions; every workflow path exercised in [acceptance results](../tests/results/) |
| Reports RQ-01–RQ-05 | Verified | Views `vw_open_items`, `vw_item_recovery`, `vw_monthly_return_rate`, `vw_turnaround_by_outcome`, plus `sp_get_item_audit_trail`; AC-07, AC-08, AC-09 |
| Role definitions and entitlements | Verified | Grants follow the TDD §5 matrix; no role writes protected tables directly; AC-07, AC-10; routine owner `wr_owner` |
| Audit mechanism and append-only enforcement | Verified | History tables + `AuditLog`; [audit trail results](../tests/results/) (54/54) |
| Killed transaction and rollback | Verified | AC-05 in `tests/acceptance_tests.sh`: kill after 4 uncommitted row changes; all tables unchanged |
| Exception handling hierarchy | Implemented and verified | Error classes 45001/45003/45004/45009/45500 and warnings 01000 (TDD §6); class checks in the acceptance tests |
| Scaled performance | Verified | [database/06_performance](../database/06_performance/README.md): 100,006 units, before/after `EXPLAIN ANALYZE` |
| Progress report and presentation | Completed | Demo video: https://youtu.be/ivnjOL8iWFI; feedback in [Midterm_Feedback.md](../docs/Midterm_Feedback.md) and [resolution](../docs/midterm_feedback_resolution.md) |

## Not done yet (final project)

- App service and GUI: dashboard, drill-down grids, screens generated from metadata, paged grids, audit trail screen (the database side, `sp_get_item_audit_trail`, is ready)
- Data warehouse with column-based storage, intraday watermark loads, and a reporting database (the history tables' `ValidFrom` indexes are the intended watermarks)
- Testing Plan document; ERD covering the warehouse and reporting schemas
- Release tag `v1.1.0` for the current work
