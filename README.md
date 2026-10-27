# CS437 Project

## Warehouse Returns and Refurbishment Tracking System

Rajdeep Villuri and Hunter Yee

Current design: **FRD 2.1, ERD 2.1 and Technical Design 1.0**, synchronized October 24, 2026. The model has **15 tables**. WorkOrder uses the composite key `(ReturnID, LineNumber, WorkOrderNumber)`; the number is local to each returned item.

## Current documents

- [Functional requirements](docs/warehouse_returns_frd_simplified_v2_1.md)
- [Technical design and normalization](docs/warehouse_returns_technical_design.md)
- [Editable draw.io ER diagram](docs/warehouse_returns_erd_v2_1.drawio) - two tabs in one file
- [Warehouse workflow SVG](docs/warehouse_returns_erd_v2_1_workflow.svg)
- [Users and reference data SVG](docs/warehouse_returns_erd_v2_1_support.svg)
- [ER diagram explanation and attribute dictionary](docs/warehouse_returns_erd_v2_1.md)
- [Midterm readiness checklist](planning/warehouse_returns_midterm_readiness_checklist.md)
- [Build Script Demo Video](CS437Demo.mp4) or https://youtu.be/ivnjOL8iWFI

Present tab 01 (Warehouse workflow) first; tab 02 contains users, roles, audit, reference values and attribute examples. Both tabs belong to the same system. `NULL` means a field may be empty until applicable; it is not an unfinished placeholder.

## Earlier requirements and feedback

The original [FRD](docs/archive/FRD.md), [PDF](docs/archive/warehouse_returns_functional_requirements.pdf) and [professor feedback](docs/FRD_Feedback.md) are retained for history. Earlier FRD versions are in `docs/archive/`; professor feedback remains in `docs/`. Use the current documents linked above for ongoing design and implementation.

# Building and Running the Database Build

## Prerequisites
- **Operating Systems & Shell**: Windows with Git Bash, or macOS/Linux with Terminal (Bash 3.2+).
- **Git**: Installed and accessible via `PATH` (`git --version`).
- **MySQL Server**: MySQL 8.0.16+ (tested on MySQL 8.0 / MySQL 8.4; MySQL 8.0.16+ enforces `CHECK` constraints).
- **MySQL Client**: Command-line client `mysql` in `PATH` (`mysql --version`). On Windows, the build script also automatically searches standard installation directories such as `C:\Program Files\MySQL\MySQL Server 8.0\bin` if not already on `PATH`.
- **Core Utilities**: `bash`, `mktemp`.

## Repository Information
- **GitHub Repository**: `Hunter-Yee/Warehouse-Returns-and-Refurbishment-Tracking-System`
- **Retrieval Mechanism**: The build script retrieves an isolated, exact copy using `git clone --quiet --no-checkout`, fetches the specific tag reference (`refs/tags/<TAG>`), checks it out detached into an isolated `.build-work/` directory, and verifies the resolved tag and commit SHA before proceeding.
- **Release Tag to Use**: `v1.0.0`

## Database Configuration
Configure the MySQL server connection prior to building. The script reads optional environment variables or local settings from `build/config.env` (copy from [`build/config.example.env`](build/config.example.env)):
- `DB_HOST`: Database server host (e.g., `127.0.0.1` or `localhost`).
- `DB_PORT`: Database port (default: `3306`).
- `DB_ADMIN_USER`: MySQL administrative account name with privileges to create databases, users, and grant roles (e.g., `root`).
- `DB_ADMIN_PASSWORD`: Administrator password.
- `TARGET_DB`: Name of the target schema to be created (must start with a letter, max 64 chars, containing letters, digits, and underscores, e.g., `warehouse_returns_test01`).

## Credentials and Security
- **No Committed Secrets**: `build/config.env` contains local administrative credentials and is strictly excluded via `.gitignore`.
- **Secure Password Handling**: The build script passes credentials to the MySQL client via the internal `MYSQL_PWD` environment variable rather than command-line flags, preventing exposure in process listings (`ps`).
- **Sample/Demonstration Accounts**: `database/03_security/010_roles.sql` defines 5 functional roles (`role_receiving`, `role_inspector`, `role_technician`, `role_manager`, `role_admin`) and creates 6 sample login accounts matching `AppUser.LoginIdentifier` on `localhost` (`receiving01`, `inspector01`, `technician01`, `technician02`, `manager01`, `admin01`) with assigned default roles for testing and evaluation.

## Build Command
Execute the build script from the repository root:

```bash
bash build/build_database.sh Hunter-Yee Warehouse-Returns-and-Refurbishment-Tracking-System v1.0.0 warehouse_returns_test01
```
or
```bash
& "C:\Program Files\Git\bin\bash.exe" build/build_database.sh Hunter-Yee Warehouse-Returns-and-Refurbishment-Tracking-System v1.0.0 warehouse_returns_demo01
```

### Argument Explanations
1. `OWNER`: GitHub username or organization (`Hunter-Yee`).
2. `REPO`: Repository name (`Warehouse-Returns-and-Refurbishment-Tracking-System`).
3. `TAG`: Exact Git release tag to build (`v1.0.0`).
4. `TARGET_DB`: Fresh target schema name (e.g., `warehouse_returns_test01`).

## Execution Order
The build executes SQL files strictly in the order listed in [`database/manifest.txt`](database/manifest.txt), guaranteeing all dependencies exist before dependents:
1. `00_create_database.sql`: Confirms database context.
2. `01_schema/010_tables.sql`: 15 base DDL tables with primary keys, composite keys, foreign keys, and `CHECK` constraints.
3. `02_programmability/010_views.sql`: Reusable operational and financial reporting views (`vw_open_items`, `vw_item_recovery`).
4. `02_programmability/020_functions.sql`: Helper stored functions.
5. `02_programmability/030_procedures.sql`: Workflow stored procedures (`sp_record_initial_inspection`, `sp_approve_disposition`, `sp_assign_repair`, etc.).
6. `02_programmability/040_triggers.sql`: Movement and audit automation triggers (`trg_movement_before_insert`, `trg_movement_after_insert`).
7. `03_security/010_roles.sql`: Role definitions and local test login accounts.
8. `03_security/020_grants.sql`: Principle-of-least-privilege RBAC object grants to roles.
9. `04_seed/010_reference_data.sql`: Core lookup codes (ItemStatus, Disposition, ConditionGrade, ClaimStatus, Locations).
10. `04_seed/020_sample_data.sql`: Realistic demonstration returns, products, vendors, and initial item states.
11. `05_validation/010_object_validation.sql`: Verifies counts of tables, views, constraints, indexes, procedures, and triggers.
12. `05_validation/020_data_validation.sql`: Verifies seed row counts and data integrity relationships.
13. `05_validation/030_smoke_tests.sql`: Runs non-destructive read-only smoke queries and sample FRD reporting queries (RQ-01–05).

## Database Recreation
- The build script implements **protected fresh builds**: it checks `information_schema.schemata` for the `TARGET_DB` name before creating it.
- If `TARGET_DB` already exists, the script deliberately **refuses to overwrite or delete it** and exits immediately with an error message.
- To rerun the build, **supply a new target database name** (e.g. `warehouse_returns_test02`). If an intentional replacement of an existing schema is required, drop it manually first in MySQL (`DROP DATABASE <TARGET_DB>;`) prior to rerunning the script.

## Initial / Sample Data
- Reference data seeds all 50 operational domain codes and warehouse locations.
- Sample data populates realistic items across key operational scenarios: intake receiving, pending inspections, direct restocking paths, repairs, supplier vendor claims, and disposals.
- Initial validation verifies baseline item relationships (e.g. orphaned return lines, missing serial numbers on serial-tracked products).

## Verification Steps
After completion, the build script verifies that all 15 base tables exist:
- **Object Verification**: Confirms exactly 15 base tables, 2 views, foreign keys, indexes, 10 stored procedures, and 2 movement triggers via queries on `information_schema`.
- **Seed Record Counts**: Validates expected row counts (Users: 6, Roles: 5, ReferenceValues: 50, Vendors: 3, Products: 5, Locations: 7, Headers: 5, Items: 7, SalesSummary: 5).
- **Smoke Tests**: Executes test queries verifying view calculations (e.g. `vw_item_recovery`), status aggregations, and business report queries (RQ-01 through RQ-05). All query results are captured in the build log for inspection.

## Safety and Failure Handling
The build process enforces strict guardrails to prevent corrupted or partial installations:
- **Missing Prerequisites or Environment Variables**: Stops execution before modifying the database.
- **Failed Clone, Nonexistent Tag, or Version Mismatch**: Halts execution immediately if GitHub retrieval or checkout fails.
- **Inaccessible MySQL Server**: Verifies database connectivity upfront before attempting any modifications.
- **No Automatic Deletion**: An existing database is never deleted automatically; the script halts before making changes.
- **Sequential Fail-Fast SQL Pipeline**: Failed SQL scripts immediately stop all subsequent dependent scripts.
- **Object & Validation Failures**: Discrepancies in expected objects (e.g. fewer than 15 base tables) or validation tests cause the build to fail.
- **Logging**: All execution output, query results, and errors are cleanly separated and recorded in `.build-work/<REPO>-<TAG>-<ID>/build.log` and `error.log`.

## Reproducibility
- Builds are locked to an immutable release tag (`v1.0.0`) and verify the exact git commit SHA upon checkout.
- Order is deterministically driven by the repository's `database/manifest.txt`.
- Each build executes in an isolated temporary working directory with dedicated timestamped `build.log` and `error.log` files, ensuring complete traceability.
