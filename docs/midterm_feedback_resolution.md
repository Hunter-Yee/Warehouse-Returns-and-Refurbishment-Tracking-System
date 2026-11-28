# Midterm Feedback: Resolution and Evidence

**Updated:** November 27, 2026 · **Verified on:** MySQL 8.4.11, fresh build through `build/build_database.sh`

This document records what was done about every point in the midterm feedback: the eight spoken findings, the written gap analysis, and the scorecard. Each item names its evidence, usually a check in one of the two test scripts, so a reviewer can rerun it. The original analysis is in [Midterm_Feedback.md](Midterm_Feedback.md).

| Evidence | Result |
| --- | --- |
| `tests/acceptance_tests.sh` (FRD AC-01 to AC-11 plus security checks) | **123 passed, 0 failed** · [results](../tests/results/) |
| `tests/audit_trail_tests.sh` (history tables, audit grid) | **54 passed, 0 failed** · [results](../tests/results/) |
| `database/06_performance/` (100,006 units, 451,654 audit rows) | RQ-02 audit lookup 181 ms → 0.014 ms · [results](../database/06_performance/README.md#results) |

## 1. Spoken findings

| # | Finding | Status | What changed | Evidence |
| --- | --- | --- | --- | --- |
| 1 | Receiving can't record a return (FR-02) | ✅ Fixed | `sp_register_return` and `sp_register_single_return`. Receiving holds **EXECUTE only**: the direct `INSERT` grants on `ReturnHeader`/`ReturnItem` were revoked, because they let a Receiving login insert an already-"Restocked" item worth $9,999 and bypass every intake rule. | AC-01 (all checks); "Receiving cannot bypass the procedure with a direct INSERT" |
| 2 | Managers can't enter monthly sales (FR-10) | ✅ Fixed | `sp_enter_monthly_sales`; the direct `INSERT/UPDATE` on `SalesSummary` was revoked. | AC-08 sales entry; "Monthly sales go through the procedure only" |
| 3 | Settlement can exceed the claim | ✅ Fixed | `CHECK (SettlementAmount <= RequestedAmount)` plus a procedure check (error 45001). Partial settlements succeed with a warning. | "Settlement above the claim is rejected (50 > 40)"; "partial-recovery warning" |
| 4 | Audit log can be edited | ✅ Fixed | `AuditLog` and all 14 history tables reject `UPDATE`/`DELETE` for every account, including root (error 45500). No role can write audit tables. | "Even the setup account cannot edit AuditLog"; audit tests section 6 |
| 5 | No separate Final inspection (FR-13) | ✅ Fixed | `sp_record_final_inspection`, allowed in AwaitingFinalInspection or AwaitingDecision as FRD 5.2 specifies. | AC-02/AC-04 Final Fail blocks, then Final Pass allows, restock |
| 6 | Repair approval required amount = 0 | ✅ Fixed | `NULL` is accepted for Repair. | "Manager approves Repair with no amount" |
| 7 | Passwords in the repo; server-wide name collisions | ✅ Fixed | No password in source: logins are created `ACCOUNT LOCK`ed and unlocked only by the build with `DEMO_PASSWORD`, and the build fails if that step fails. The example config has a placeholder, and the build rejects it. The build **refuses** to reuse `wr_*` accounts that already serve another schema unless `ALLOW_SHARED_ACCOUNTS=1`. | "Routine owner wr_owner cannot log in"; build refusal verified on a server with other builds |
| 8 | Stale planning documents | ✅ Fixed | Checklist rewritten with the real status and links to evidence; TDD section 9 replaced by a requirement → implementation → test matrix. | [checklist](../planning/warehouse_returns_midterm_readiness_checklist.md), [TDD §9](warehouse_returns_technical_design.md#9-traceability-and-remaining-work) |

## 2. Written gap analysis

| Gap | Status | What changed | Evidence |
| --- | --- | --- | --- |
| No intake path (FR-02/BR-03/UC-01); concurrent duplicate-serial rule only on paper | ✅ Fixed | Intake procedure; a `Product` row lock serializes intakes of the same product. | AC-01 "Exactly one of the two concurrent intakes succeeded" |
| Final inspections unreachable | ✅ Fixed | See finding 5. | AC-02, AC-04 |
| Seeded states with no exits (WorkOrder Cancelled, Claim Denied/Cancelled, approval withdrawal) | ✅ Fixed | `sp_withdraw_approval`, `sp_cancel_work_order`, `sp_deny_claim`, `sp_cancel_claim`, all following FRD 5.2. | AC-02 withdrawal/cancellation; AC-06 deny/cancel |
| Administration bypasses audit; FRD 5.1 guard enforced nowhere | ✅ Fixed | History tables audit every admin table. Guard triggers block recoding, domain changes, and deactivating values or locations needed by open work, and technicians with active orders. | AC-10, AC-11; audit tests section 8 |
| Grants contradict the TDD (direct movement INSERT; Admin edits products/vendors; Admin reads raw AuditLog) | ✅ Fixed | Grants rewritten from the TDD section 5 matrix: no direct protected writes; Product/Vendor maintenance moved to Manager; Admin uses the redacted audit views; non-Managers can't select money columns. | "Role logins have no direct write access to any protected table"; AC-07 |
| Routines execute as root | ✅ Fixed | All 107 views, routines and triggers are owned by a locked, least-privileged `wr_owner@localhost`. | "All views, routines and triggers are owned by wr_owner" |
| Audit rows under-record status and completion; `TransactionID` never groups | ✅ Fixed | History tables store the whole row per version; one transaction ID per database transaction, shared with `AuditLog`. | Audit tests sections 2–3 |
| Evidence stops at loading | ✅ Fixed | Two test suites with committed output, including the killed-transaction demo. | `tests/results/` |
| Workflow graph is code, distributed | ⚠️ Partly | Transitions are still checked in each procedure (one place per transition, documented in the FRD 5.2 table). Deactivating the codes they depend on is now blocked, so an admin edit can no longer cause an outage. A data-driven transition table is planned with the final project's metadata-driven screens. | AC-11 "Deactivating a workflow value needed by open work is rejected" |
| Toy scale, plan-only performance | ✅ Fixed | 100,006 units and 451,654 audit rows; `EXPLAIN ANALYZE` before and after, with a control. | `database/06_performance/README.md` |
| Lopsided git record | ⚠️ Noted | Commit identities corrected; both members' work is attributed. The balance of future work is the team's responsibility. | `git log` |

## 3. Scorecard

| Criterion | Midterm | What addresses it now |
| --- | --- | --- |
| Audit table process | 3/5 | Temporal history table per core table, append-only for all accounts, admin changes audited, full row versions, shared transaction IDs, paged audit grid. |
| Build script idempotency / logging | 4/5 | Test and benchmark output committed; in-database version stamp; build refuses unsafe account sharing; password step fails loudly. |
| Role-based entitlements | 3/5 | Grants match the TDD matrix; dedicated locked definer; locked-until-unlocked logins; column-level money restriction. |
| Scalable workflow management | 3/5 | All FRD exits implemented; reference guards; item row locks verified under concurrency. |
| Scaled performance testing | 1/5 | 100k-unit load, before/after `EXPLAIN ANALYZE`, write-cost and index-size measurements. |
| ER diagram | 5/5 | Attribute dictionary updated; the draw.io file still needs the history and SchemaBuild tables (pending). |
| Exception handling hierarchy | 3/5 | Five error classes plus warnings, with distinct SQLSTATE and error numbers; see the TDD error catalog. |
| Lineage FR → implementation → tests | 3/5 | Traceability matrix in TDD §9; every AC runs in `acceptance_tests.sh` with saved output. |
| Version tags feeding the build | 5/5 | Unchanged; the next release is `v1.1.0`. |
| Versioning of DB objects | 3/5 | `SchemaBuild` / `SchemaBuildScript` record the tag, commit, manifest checksum and each script's SHA-256 inside the database. |

## 4. Answers to the professor's questions

**1. "Show me how a Receiving user records a new return with two items. Which procedure or grant allows it?"**

```sql
-- connected as wr_receiving01
CALL sp_register_return('RET-2026-2001', '[
  {"sku":"LAP-100","serial":"LAP-7781","reason":"Defective","location":"INT-01"},
  {"sku":"KBD-500","serial":null,"reason":"Unwanted","location":"INT-01"}]');
```

The only grant involved is `EXECUTE ON PROCEDURE sp_register_return TO wr_role_receiving`. Receiving has no `INSERT` on any table. The procedure runs as `wr_owner`, re-checks that the caller is an active Receiving user, and in one transaction:
- validates each SKU, required serial, reason and location;
- locks the `Product` row so two simultaneous intakes of the same serial can't both succeed;
- writes the header, one line per unit, and the audit rows, all sharing one transaction ID.

Any invalid line rolls back the whole return. *(AC-01)*

**2. "A vendor settles a $40 claim for $50. Should that be allowed, and how does it affect net recovery?"**

No. FR-08 says the settlement must not exceed the requested amount. It is blocked twice: by `CHECK (SettlementAmount <= RequestedAmount)` and by `sp_settle_claim`, which returns error 45001 "Settlement cannot exceed requested claim amount". Net recovery adds only *received* settlements, so allowing it would overstate recovery. The presentation laptop would show 200 + 50 − 35 = **$215** instead of the planned 200 + 30 − 35 = **$195**. A settlement below the request succeeds with a "partial recovery" warning.

**3. "Your trigger and procedures look up the caller with USER(). Why not CURRENT_USER(), and why not pass the user ID in as a parameter?"**

- **`CURRENT_USER()`:** inside a `DEFINER` routine it returns the *definer*. Here that is `wr_owner@localhost` for every caller, which would attribute every action to the owner. During testing, MySQL's process list even showed a running `sp_move_item` session as `wr_owner`.
- **`USER()`:** returns the account the client authenticated as. We map it to an active `AppUser` with the required active role, so a MySQL grant alone isn't enough (tested: with the app role removed, the procedure refuses with 45003).
- **A user-ID parameter:** callers could pass anyone's ID and impersonate them.

The one caveat is that `USER()` can differ from the authenticated account if anonymous or proxy accounts exist. The server has none, and only role logins hold `EXECUTE`.

**4. "Walk us through trg_movement_before_insert. Why lock the item row with FOR UPDATE, and what does the stale source location check protect against?"**

The trigger:
1. Confirms the mover is an active Receiving user matching `MovedByUserID`.
2. Reads the item `FOR UPDATE`.
3. Rejects closed items and any movement whose source is not the item's *current* location.
4. Checks the movement type against the destination's location type and the approved status, so final moves happen only from the matching approval into the matching exit.

The row lock serializes concurrent changes to the same unit: a second mover or approver waits, then reads the committed state. The stale-source check prevents lost updates. If one clerk moves a unit INT-01 → INSP-01 while another, working from an outdated screen, tries INT-01 → STO-01, the second move is rejected instead of silently overwriting the first. The after-insert trigger then updates location, status, completion time and audit in the same transaction. *(AC-05 "A stale source location is rejected")*

**5. "Why is WorkOrder keyed on (ReturnID, LineNumber, WorkOrderNumber) instead of its own ID?"**

A work order belongs to exactly one unit, and its number is local to that unit (unit 6-1, order 2). The important consequence is that `Inspection` references `WorkOrder` with the same three-column foreign key, so **the database itself guarantees an inspection can only link to an order of the same unit** (FR-13's "wrong-item link"), with no trigger needed. A surrogate `WorkOrderID` would allow linking unit A's inspection to unit B's order unless extra code checked it. Numbers are allocated as `MAX + 1` while the item row is locked, so concurrent assignments can't collide. The cost is wider foreign keys, which is acceptable at this scale.

**6. "Run the killed-transaction demo from your TDD. What's left in the item, movement and audit tables?"**

Nothing changes. `acceptance_tests.sh` runs it with the real procedure:
1. Session 2 holds a lock that pauses session 1's `sp_move_item` after it has written the movement, the item update and the history rows (**4 uncommitted row changes**), but before its audit row and `COMMIT`.
2. Session 1 is killed.
3. The movement count, item location, history count and `ITEM_MOVED` audit count are all identical before and after.

While session 1 was open, other sessions could not see its changes. *(AC-05)*

**7. "Who can change AuditLog today? Show an UPDATE being rejected."**

No one through normal access. No role has `INSERT`, `UPDATE` or `DELETE` on it, and guard triggers reject `UPDATE`/`DELETE` for every account:

```
mysql> UPDATE AuditLog SET Action='X' LIMIT 1;   -- as root
ERROR 50500 (45500): AuditLog is append-only: updates are not permitted
```

The same applies to all 14 history tables. Only someone with DBA rights to drop the triggers or the table could get around this, which is a server-administration control, not an application one.

**8. "Your seed data never runs a procedure. Where are your test results, and which acceptance criteria have been run?"**

The seed is a static baseline, so the validation scripts can check exact counts. Workflow testing is done by `tests/acceptance_tests.sh`, which runs **all of AC-01 to AC-11** as the real role logins through the procedures. Its output is committed in `tests/results/`: 123 passed, 0 failed. The only direct setup-account writes are the AC-08 turnaround fixtures, which move receipt times into the past and are labelled `FIXTURE` in the output.

**9. "The readiness checklist still says the schema is 'Not found'. Which documents are current, and who wrote the checklist?"**

Current documents: FRD 2.1, ERD 2.1, the TDD (with the updated sections 5, 6 and 9), the audit trail design, this resolution document, and the refreshed checklist. All are linked from the README.

*On who wrote it, answer honestly in the presentation. The original checklist contained "This review covers files available in this chat's workspace", which indicates it was drafted with an AI assistant and not revised after the SQL was written. It has now been rewritten against the actual repository and test results.*
