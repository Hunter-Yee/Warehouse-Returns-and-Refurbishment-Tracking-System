# Audit Trail Design: Temporal History Tables

This implements the final-project audit requirement: for the core business entity (a returned **unit**, `ReturnItem`), record who changed what and when, and provide a query a GUI screen can page through. Following the class design direction, the audit is a **history (temporal) table per core table** plus a **denormalized grid view**, not a single generic log.

## Objects

| Object | File | Purpose |
| --- | --- | --- |
| 14 `<Table>History` tables | `database/01_schema/020_history_tables.sql` | One per core table (all except `AuditLog`). Each mirrors its table's columns and keeps every version of every row. |
| 70 triggers | `database/02_programmability/050_history_triggers.sql` | Capture triggers (`AFTER INSERT/UPDATE/DELETE`) on each core table, and guard triggers (`BEFORE UPDATE/DELETE`) on each history table. |
| `fn_audit_login`, `fn_audit_user_id`, `fn_audit_transaction_id` | `database/02_programmability/020_functions.sql` | Who made the change, and which transaction it belonged to. |
| `vw_item_audit_trail` | `database/02_programmability/060_audit_trail.sql` | Grid view for the audit screen: one row per changed attribute, for a unit and everything recorded against it. |
| `vw_master_data_change_history` | same | The same grid for users, roles, role assignments, reference values, locations, products, vendors and monthly sales. |
| `sp_get_item_audit_trail` | same | Paged search used by the audit screen. |
| Generator | `tools/generate_history_sql.py` | Produces both history files from the live schema. Re-run it after changing a core table's columns. |
| Tests | `tests/audit_trail_tests.sh` | 54 checks run as the real role logins; saved output in `tests/results/`. |

## History table shape

Every history table has the base table's columns plus:

| Column | Meaning |
| --- | --- |
| `HistoryID` | Surrogate key for the version. |
| `ValidFrom` / `ValidTo` | Period during which this version was the current row (`ValidFrom` inclusive, `ValidTo` exclusive). The current version has `ValidTo = 9999-12-31 23:59:59.999999`. |
| `Operation` | `I` insert, `U` update, `D` delete. A `D` row holds the deleted values with `ValidFrom = ValidTo`. |
| `ChangedByLogin` | MySQL login of the session (`wr_manager01`, `root`, ...). `USER()` is the connecting client even inside `DEFINER` procedures. |
| `ChangedByUserID` | The `AppUser` for that login; `NULL` for setup accounts. |
| `TransactionID` | Shared by every row one database transaction wrote (see below). |

Indexes: `(primary key, ValidTo)` to find the open version and read one record's history; `(ValidFrom)` as the watermark for intraday incremental warehouse loads; `(TransactionID)`; and `(ReturnID, LineNumber, ValidFrom)` on history tables whose key does not start with the item key.

## How changes are captured

- **Insert:** write a version with `ValidFrom = now`, open-ended.
- **Update:** if any column changed, close the open version (`ValidTo = now`) and write the new one. An update that changes nothing writes nothing.
- **Delete:** close the open version and write a `D` version.

The triggers run inside the caller's transaction, so a rollback, a failed procedure, or a killed connection removes the history rows together with the business change. Because the triggers are on the tables, every write path is captured: procedures, the movement trigger's item update, administrator edits, and setup scripts.

**Append-only:** guard triggers reject any `DELETE` on a history table and any `UPDATE` other than closing the open version once. This applies to every account, including `root`. No application role is granted access to the history tables; they are read through the views and the procedure.

## Transaction IDs

`fn_audit_transaction_id()` returns `<connection id>-<transaction event id>` from `performance_schema.events_transactions_current`, which identifies the session's current transaction in real time. All history rows and all `AuditLog` rows written by one procedure call therefore share one ID. The procedures and the movement trigger now use it instead of a new `UUID()` per row, which fixes the midterm finding that `TransactionID` never grouped a transaction's rows. It also lets the grid show the business action (`DISPOSITION_APPROVED`, `ITEM_MOVED`, ...) that caused each data change.

The ID is unique for the life of the server process; pair it with the timestamps across restarts. (The `information_schema.INNODB_TRX` alternative was rejected because it is cached for about 0.1 s and returned the same ID for separate transactions in testing.)

## The grid view

`vw_item_audit_trail` combines `ReturnItemHistory`, `WorkOrderHistory`, `InspectionHistory`, `InventoryMovementHistory` and `VendorClaimHistory`. Each version becomes a JSON snapshot of display values (codes, names, amounts), is compared with the previous version of the same record using `LAG()`, and is unpivoted with `JSON_TABLE`:

| Column | Example |
| --- | --- |
| `EventAt` | `2026-11-27 18:18:48.43` |
| `ReturnID`, `LineNumber`, `ExternalReference` | `6`, `1`, `AUD-20261127181848` |
| `Entity`, `EntityKey` | `ReturnItem`, `Unit 6-1` · `VendorClaim`, `Claim 1` |
| `EventType` | `Created` / `Changed` / `Deleted` |
| `AttributeName`, `OldValue`, `NewValue` | `ItemStatus`, `ApprovedForRestock`, `Restocked` |
| `IsFinancial` | 1 for amounts (restock value, proceeds, costs, claim amounts) |
| `ChangedBy`, `ChangedByLogin` | `Morgan Lee`, `wr_receiving01` |
| `BusinessAction`, `TransactionID` | `ITEM_MOVED`, `183-5` |

Rows appear only for attributes that changed (all populated attributes for `Created`/`Deleted`).

## Audit screen query

```sql
CALL sp_get_item_audit_trail('RET-2026-1001', NULL, 1, 25);  -- reference, line (NULL = all), page, page size
```

- Result set 1: `TotalRows`, `Page`, `PageSize`, `TotalPages`, `IncludesFinancial`, for the grid's pager.
- Result set 2: that page of rows, oldest first. Each page is a separate `LIMIT`/`OFFSET` query, so the grid never loads the full history.
- Managers and Administrators may search (TDD §5: audit review). Amounts are returned only to Managers; Administrators get the redacted trail, which is the "redacted administrative view" the TDD promised. Operational roles use the non-financial operational views instead.
- Errors: unknown reference, page < 1, page size outside 1–200, inactive login.

Grants: `EXECUTE` on the procedure for Manager and Administrator; `SELECT` on `vw_item_audit_trail` for Manager only; `SELECT` on `vw_master_data_change_history` for Manager and Administrator.

## Measured results (MySQL 8.4.11)

From `tests/results/` and a scaled run with `database/06_performance/`:

- 54 of 54 audit checks pass on a fresh build, covering the workflow as each role, history capture, transaction grouping, the grid, paging and redaction, permission denials, append-only guards, rollback, and audited admin changes.
- One unit's trail with 100,006 units loaded: **0.17 ms**. MySQL pushes the `ReturnID` filter through the view's `UNION ALL`, CTEs and window function, so only that return's history is read.
- Write cost: loading 100,000 units took 9.1 s with the history triggers versus 5.3 s without, since each row now also writes a version.

## Midterm findings addressed

| Finding | Now |
| --- | --- |
| Audit log can be edited | History tables are append-only for every account (the `AuditLog` guards remain). |
| Administration bypasses audit | Every admin table has a history table; changes appear in `vw_master_data_change_history` with old/new values and the administrator's name. |
| Movement audit rows under-record status and completion | `ReturnItemHistory` records the full row, so the final move shows `ItemStatus` → `Restocked` and `CompletionAt` explicitly. |
| `TransactionID` never groups a transaction | One ID per database transaction, shared by history and `AuditLog`. |
| TDD's redacted administrator view did not exist | `sp_get_item_audit_trail` redacts amounts for non-Managers. |
| Evidence stops at loading | `tests/audit_trail_tests.sh` runs the workflow and saves its output. |

## Maintenance

After adding or changing columns on a core table, rebuild a scratch schema and regenerate:

```bash
MYSQL_PWD=... python3 tools/generate_history_sql.py --host 127.0.0.1 --port 3306 --user root --schema <scratch_db>
```

If the new column matters to the audit screen, also add it to that entity's `JSON_OBJECT` snapshot in `060_audit_trail.sql`.
