# Warehouse Returns — Midterm Readiness Check

**Project**: Warehouse Returns and Refurbishment Tracking System  
**Authors**: Rajdeep Villuri and Hunter Yee  
**Status**: Midterm Milestone Completed & Verified (Updated November 19, 2026)  
**Baseline**: FRD 2.1, ERD 2.1, 15 base tables  

---

## Overall Status

All required database components, schema tables, build automation scripts, views, stored procedures, triggers, RBAC security configurations, and validation suites are implemented and verified in the repository.

---

## Deliverables and Evidence

| Requirement | Status | Evidence / Implementation Location |
| --- | --- | --- |
| Complete FRD with traceability | Completed | `docs/warehouse_returns_frd_simplified_v2_1.md` defines FR-01 through FR-15, use cases, business rules BR-01 through BR-10, and acceptance criteria. |
| ERD with at least 8–10 meaningful entities | Completed | `docs/warehouse_returns_erd_v2_1.drawio` (and exported SVGs `warehouse_returns_erd_v2_1_workflow.svg` and `warehouse_returns_erd_v2_1_support.svg`) models 15 tables across two tabs. |
| 1:1, 1:N and M:N; weak entity; attributes/types; named diamonds; participation | Completed | Documented in ERD 2.1 and `docs/warehouse_returns_erd_v2_1.md`: weak ReturnItem, optional 1:1 VendorClaim, M:N UserRole, composite work order keys. |
| Technical Design Document | Completed | `docs/warehouse_returns_technical_design.md` details architecture, 3NF normalization proofs, transaction boundaries, and security models. |
| Demonstrate 3NF | Completed | Detailed table-by-table functional dependency analysis in TDD Section 3 proving 3NF across all 15 relations. |
| Working MySQL schema with indexes and constraints | Implemented | `database/01_schema/010_tables.sql` creates all 15 base tables on InnoDB with explicit primary keys, foreign keys, and CHECK constraints. |
| Schema build file and reproducible build with initial data | Implemented | `build/build_database.sh` clones an isolated tag checkout and runs SQL files deterministically according to `database/manifest.txt`. |
| Basic CRUD demonstration | Implemented | Controlled procedures in `database/02_programmability/030_procedures.sql` provide full create/read/update operations; deactivation preserves history without destructive deletion. |
| SQL reports and transactions | Implemented | Reports RQ-01 through RQ-05 implemented in `database/05_validation/030_smoke_tests.sql`; stored procedures maintain atomic transaction boundaries with rollback handlers. |
| Denormalized reporting views | Implemented | `database/02_programmability/010_views.sql` creates `vw_open_items` (safe operational view) and `vw_item_recovery` (manager-only financial recovery). |
| Role definitions and entitlements | Implemented | `database/03_security/010_roles.sql` and `020_grants.sql` establish 5 functional roles with least-privilege table and procedure permissions. |
| Audit mechanism, record-updating trigger and constraint enforcement | Implemented | `database/02_programmability/040_triggers.sql` automates item location updates and enforces append-only immutability on `AuditLog`. |
| Killed transaction and rollback demonstration | Verified | Procedure error handlers roll back uncommitted work; test harness in TDD Section 8 demonstrates rollback upon connection termination. |
| Progress report and presentation | Completed | Midterm presentation completed with demo video (`CS437Demo.mp4`); feedback action plan tracked in `docs/Midterm_Feedback.md`. |
| Authoritative GitHub submission under docs/ | Completed | Repository hosted on GitHub (`Hunter-Yee/Warehouse-Returns-and-Refurbishment-Tracking-System`). |
| Regular commits and contribution evidence | Verified | Continuous commit history reflecting active contributions from both team members. |

---

## Implemented Database Architecture

1. **Relational Model**: 15 normalized tables centered around physical returned units (`ReturnItem`) with item-local composite work order keys `(ReturnID, LineNumber, WorkOrderNumber)`.
2. **Build Automation**: Deterministic execution pipeline via `build_database.sh` with parameter validation, pre-flight checks, and execution logging in `.build-work/`.
3. **Controlled Operations**: 11 stored procedures managing returns intake, inspections (Initial, PostRepair, Final), disposition approvals, repair lifecycles, warehouse movements, sales totals, and vendor claims.
4. **Security & Immutability**: RBAC with dedicated functional roles (`wr_role_receiving`, `wr_role_inspector`, `wr_role_technician`, `wr_role_manager`, `wr_role_admin`), uncommitted secrets handling, and append-only audit log triggers.
5. **Validation**: Comprehensive automated verification suites for object counts, data relationships, and business report queries.
