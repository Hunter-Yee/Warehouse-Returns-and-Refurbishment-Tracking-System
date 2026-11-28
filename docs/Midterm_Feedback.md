# Midterm Presentation Feedback & Action Plan

**Project**: Warehouse Returns and Refurbishment Tracking System  
**Authors**: Rajdeep Villuri and Hunter Yee    

---

> **Status (November 27, 2026):** every item below has been resolved and verified. See [midterm_feedback_resolution.md](midterm_feedback_resolution.md) for the evidence, the written gap analysis and scorecard follow-up, and answers to the professor's questions. Note on Item 1: the fix is the intake *procedure*; the direct `INSERT` grants proposed below were **not** kept, because they let Receiving bypass every intake rule.

## Summary of Action Items

| # | Feedback Area | Root Cause | Action / Resolution | Impacted Files |
|---|---|---|---|---|
| **1** | Receiving intake procedure missing (FR-02) | Sample data was loaded directly by `root`; no intake procedure existed and `role_receiving` lacked `INSERT` grants. | Implement `sp_register_return` (multi-unit atomic intake) and grant execution to `role_receiving`. | `030_procedures.sql`, `020_grants.sql`, `010_object_validation.sql` |
| **2** | Monthly sales entry missing (FR-10) | `role_manager` only had `SELECT` on `SalesSummary`; no procedure was provided. | Implement `sp_enter_monthly_sales` with first-of-month validation and grant execution to `role_manager`. | `030_procedures.sql`, `020_grants.sql`, `010_object_validation.sql` |
| **3** | Settlement exceeding claim amount | `VendorClaim` constraint and `sp_settle_claim` did not enforce `SettlementAmount <= RequestedAmount`. | Add upper bound to `ck_claim_settlement` CHECK constraint and add validation in `sp_settle_claim`. Update FRD BR-06. | `010_tables.sql`, `030_procedures.sql`, `FRD` |
| **4** | Audit log editable (not append-only) | Role grants blocked normal roles, but table had no `BEFORE UPDATE` or `BEFORE DELETE` triggers. | Add `trg_auditlog_before_update` and `trg_auditlog_before_delete` triggers to prevent modifications by any user (including `root`). | `040_triggers.sql`, `010_object_validation.sql`, `030_smoke_tests.sql` |
| **5** | Missing Final inspection procedure (FR-13) | `ReferenceValue` included `Final`, but only Initial and PostRepair procedures were implemented. | Implement `sp_record_final_inspection` supporting both repaired (linked to latest order) and unrepaired items. | `030_procedures.sql`, `020_grants.sql`, `010_object_validation.sql` |
| **6** | Repair approval requiring `amount = 0` | `sp_approve_disposition` rejected `p_amount IS NULL`, even though repair carries no immediate valuation. | Update validation in `sp_approve_disposition` so `p_amount` is optional/`NULL` for `Repair`. | `030_procedures.sql` |
| **7** | Passwords in repo & server-global collisions | Plaintext passwords committed in `010_roles.sql`; generic role/user names collided on shared MySQL servers. | Move credentials to gitignored `config.env`; namespace all roles and logins with a distinct project prefix (`wr_`). | `010_roles.sql`, `020_grants.sql`, `020_sample_data.sql`, `build_database.sh`, `README.md` |
| **8** | Stale planning documents & AI artifacts | Checklist and TDD retained pre-implementation drafting notes ("Not found", AI workspace notes). | Refresh checklist to reflect completed deliverables, eliminate conversational phrasing, and update TDD roadmap. | `warehouse_returns_midterm_readiness_checklist.md`, `warehouse_returns_technical_design.md` |

---

## Detailed Feedback Analysis & Proposed Fixes

---

### Item 1: Receiving Cannot Record a Return (FR-02)

#### Professor's Feedback
> *"Receiving can't record a return (FR-02). There's no procedure for it, and role_receiving has no INSERT on ReturnHeader or ReturnItem. Every return in the demo was loaded by the setup account."*

#### Analysis & Root Cause
* During the midterm demo and in `04_seed/presentation/010_add_presentation_data.sql`, all return headers and items were inserted directly using raw SQL by the administrative setup account (`root`).
* In `03_security/020_grants.sql`, `role_receiving` was only granted `SELECT` on `ReturnHeader` and `ReturnItem`, along with `sp_move_item`.
* No stored procedure was provided in `02_programmability/030_procedures.sql` to register a return and its constituent item lines.

#### Our Decision: Accept
Receiving staff must be capable of executing the complete intake workflow under their business role credentials without administrative intervention.

#### Proposed Implementation Fix
1. **Create `sp_register_return` Stored Procedure** in `02_programmability/030_procedures.sql`:
   * **Signature**:
     ```sql
     CREATE PROCEDURE sp_register_return(
       IN p_external_ref VARCHAR(100),
       IN p_items JSON
     )
     ```
   * **Behavior**:
     * Verifies that the connected session user resolves to an active `AppUser` possessing an active `Receiving` role.
     * Enforces **BR-01**: Rejects if `p_external_ref` already exists in `ReturnHeader`.
     * Enforces **BR-02**: Validates that `p_items` is a non-empty JSON array with at least one item line.
     * Starts a transaction.
     * Inserts the master record into `ReturnHeader` with `ReceivedAt = UTC_TIMESTAMP(6)` and `ReceivingUserID = v_actor`.
     * Loops through each item in `p_items`:
       * Validates active `ProductID`, active `ReturnReason` (Domain `'ReturnReason'`), and active intake `Location` (Domain `'LocationType'` = `'Intake'`).
       * Enforces **BR-03**: If `Product.SerialRequired = 1`, verifies the serial number is non-blank and that no other open item (`CompletionAt IS NULL`) for the same product and serial currently exists.
       * Inserts into `ReturnItem` with calculated sequential `LineNumber` (1, 2, ...), `ItemStatusID` corresponding to `'AwaitingInspection'`, and `CurrentLocationID` set to the intake location.
       * Writes individual `ITEM_INTAKE` audit entries into `AuditLog`.
     * Writes `RETURN_REGISTERED` audit entry into `AuditLog` and commits atomically.
2. *(Convenience Procedure)*:
   * Provide `sp_register_single_return(p_external_ref, p_sku, p_serial, p_reason_code, p_location_code)` for single-item command-line testing without JSON formatting.
3. **Role Grants (`020_grants.sql`)**:
   * Add: `GRANT EXECUTE ON PROCEDURE sp_register_return TO 'role_receiving';`
   * Add: `GRANT EXECUTE ON PROCEDURE sp_register_single_return TO 'role_receiving';`
   * Add: `GRANT INSERT ON ReturnHeader, ReturnItem TO 'role_receiving';` (to guarantee compatibility with external automated test suites executing raw DML).

---

### Item 2: Managers Cannot Enter Monthly Sales (FR-10)

#### Professor's Feedback
> *"Managers can't enter monthly sales (FR-10). role_manager only has SELECT on SalesSummary."*

#### Analysis & Root Cause
* In `03_security/020_grants.sql`, line 41 grants only `SELECT ON SalesSummary TO 'role_manager';`.
* There is no stored procedure in `030_procedures.sql` for entering sales figures.
* Seed sales data in `04_seed/020_sample_data.sql` was loaded during database initialization by the build script as `root`.

#### Our Decision: Accept
FR-10 explicitly requires that managers be able to enter monthly sales totals to support calculation of the monthly return rate (RQ-03).

#### Proposed Implementation Fix
1. **Create `sp_enter_monthly_sales` Stored Procedure** in `030_procedures.sql`:
   * **Signature**:
     ```sql
     CREATE PROCEDURE sp_enter_monthly_sales(
       IN p_sku VARCHAR(64),
       IN p_calendar_month DATE,
       IN p_units_sold INT UNSIGNED,
       IN p_source_reference VARCHAR(150)
     )
     ```
   * **Behavior**:
     * Validates active caller holds the `Manager` role.
     * Enforces `ck_sales_month_first`: Rejects if `DAYOFMONTH(p_calendar_month) <> 1`.
     * Validates that `p_sku` resolves to an active `ProductID`.
     * Executes an `INSERT ... ON DUPLICATE KEY UPDATE` on `SalesSummary`:
       ```sql
       INSERT INTO SalesSummary (
         ProductID, CalendarMonth, UnitsSold, SourceReference, EnteredByUserID, UpdatedAt
       ) VALUES (
         v_product_id, p_calendar_month, p_units_sold, p_source_reference, v_actor, UTC_TIMESTAMP(6)
       )
       ON DUPLICATE KEY UPDATE
         UnitsSold = VALUES(UnitsSold),
         SourceReference = VALUES(SourceReference),
         EnteredByUserID = VALUES(EnteredByUserID),
         UpdatedAt = VALUES(UpdatedAt);
       ```
     * Appends a `SALES_SUMMARY_RECORDED` entry to `AuditLog`.
2. **Role Grants (`020_grants.sql`)**:
   * Add: `GRANT EXECUTE ON PROCEDURE sp_enter_monthly_sales TO 'role_manager';`
   * Add: `GRANT INSERT, UPDATE ON SalesSummary TO 'role_manager';`

---

### Item 3: Settlement Can Exceed the Claim

#### Professor's Feedback
> *"A settlement can exceed the claim. I settled a $40 claim for $50 and it went through. The FRD doesn't say this is allowed, and it changes net recovery: my test item showed $215 instead of the planned $195."*

#### Analysis & Root Cause
* In `01_schema/010_tables.sql`, the table constraint for `VendorClaim` is:
  ```sql
  CONSTRAINT ck_claim_settlement CHECK (SettlementAmount IS NULL OR SettlementAmount > 0)
  ```
  It verifies positivity, but places no upper bound relative to `RequestedAmount`.
* In `02_programmability/030_procedures.sql`, `sp_settle_claim` checks `p_amount <= 0`, but never checks `p_amount > c.RequestedAmount`.
* In the demo scenario (`04_seed/presentation/020_show_presentation_data.sql`), the laptop had:
  * Restock estimate: \$200.00
  * Repair labor: \$10.00, Parts: \$25.00
  * Claim requested: \$40.00; planned settlement: \$30.00
  * Planned net recovery: $\$200 + \$30 - \$10 - \$25 = \$195.00$
  * When settled for \$50.00: $\$200 + \$50 - \$10 - \$25 = \$215.00$.

#### Our Decision: Accept
A vendor settlement is reimbursement against a specific claim. A settlement cannot exceed the amount requested by the warehouse.

#### Proposed Implementation Fix
1. **Update Table Definition in `01_schema/010_tables.sql`**:
   * Strengthen the table-level CHECK constraint:
     ```sql
     CONSTRAINT ck_claim_settlement CHECK (
       SettlementAmount IS NULL OR (SettlementAmount > 0 AND SettlementAmount <= RequestedAmount)
     )
     ```
2. **Update Stored Procedure `sp_settle_claim` in `030_procedures.sql`**:
   * Read `RequestedAmount` during the locking read:
     ```sql
     SELECT s.Code, c.RequestedAmount INTO v_old, v_requested
     FROM VendorClaim c 
     JOIN ReferenceValue s ON s.ReferenceValueID = c.ClaimStatusID 
     WHERE c.ClaimID = p_claim_id FOR UPDATE;

     IF p_amount > v_requested THEN
       SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Settlement amount cannot exceed requested claim amount';
     END IF;
     ```
3. **Clarify FRD (v2.2) and TDD**:
   * Update **BR-06** and **FR-08** to explicitly state: *"A submitted claim request and a received settlement must be positive, and the received settlement amount cannot exceed the requested claim amount."*

---

### Item 4: Audit Log Can Be Edited (Not Append-Only)

#### Professor's Feedback
> *"The audit log can be edited. As root, UPDATE AuditLog succeeded. The TDD expects direct audit writes to be denied, which the grants do for ordinary roles, but no trigger makes the log append-only."*

#### Analysis & Root Cause
* Role grants in `020_grants.sql` properly deny `INSERT`, `UPDATE`, and `DELETE` on `AuditLog` to application roles (`role_receiving`, `role_inspector`, `role_technician`, `role_manager`, `role_admin`).
* However, `040_triggers.sql` lacked database triggers to prevent updates or deletions. Any connection with administrative privileges (such as `root` or an external DBA account) could execute `UPDATE` or `DELETE` statements on `AuditLog` without restriction.

#### Our Decision: Accept
Per TDD Section 6 and 8, audit logs must be immutable and append-only across all roles and database connections.

#### Proposed Implementation Fix
1. **Add Immutability Triggers in `02_programmability/040_triggers.sql`**:
   ```sql
   DROP TRIGGER IF EXISTS trg_auditlog_before_update$$
   CREATE TRIGGER trg_auditlog_before_update BEFORE UPDATE ON AuditLog
   FOR EACH ROW
   BEGIN
     SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'AuditLog is append-only: updates are not permitted';
   END$$

   DROP TRIGGER IF EXISTS trg_auditlog_before_delete$$
   CREATE TRIGGER trg_auditlog_before_delete BEFORE DELETE ON AuditLog
   FOR EACH ROW
   BEGIN
     SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'AuditLog is append-only: deletions are not permitted';
   END$$
   ```
   *(Note: In MySQL InnoDB, triggers fire regardless of whether the session user is `root`, guaranteeing append-only enforcement at the engine level).*
2. **Add Smoke Test in `05_validation/030_smoke_tests.sql`**:
   * Add a test demonstrating that an attempt by `root` to run `UPDATE AuditLog` or `DELETE FROM AuditLog` is rejected with SQLSTATE 45000.

---

### Item 5: No Procedure for a Separate Final Inspection (FR-13)

#### Professor's Feedback
> *"There's no procedure for a separate Final inspection. FR-13 lists Initial, PostRepair and Final, but only Initial and PostRepair can be recorded."*

#### Analysis & Root Cause
* `ReferenceValue` seeds `InspectionType` with codes `'Initial'`, `'PostRepair'`, and `'Final'`.
* `030_procedures.sql` only implemented:
  * `sp_record_initial_inspection` (Type: `'Initial'`)
  * `sp_record_postrepair_inspection` (Type: `'PostRepair'`)
* `sp_record_final_inspection` was omitted.

#### Our Decision: Accept
FR-13 explicitly defines three inspection types: Initial (intake), PostRepair (repair verification), and Final (pre-disposition check for repaired or unrepaired items).

#### Proposed Implementation Fix
1. **Implement `sp_record_final_inspection` in `030_procedures.sql`**:
   * **Signature**:
     ```sql
     CREATE PROCEDURE sp_record_final_inspection(
       IN p_return_id INT UNSIGNED,
       IN p_line SMALLINT UNSIGNED,
       IN p_grade_code VARCHAR(32),
       IN p_result_code VARCHAR(32),
       IN p_notes TEXT
     )
     ```
   * **Behavior**:
     * Verifies active caller holds the `Inspector` role.
     * Enforces item status rules per FRD 5.2: Item must be in `AwaitingFinalInspection` or `AwaitingDecision`.
     * Inspects repair history:
       * Checks for completed work orders on this item:
         ```sql
         SELECT WorkOrderNumber INTO v_latest_order
         FROM WorkOrder
         WHERE ReturnID = p_return_id AND LineNumber = p_line AND CompletedAt IS NOT NULL
         ORDER BY CompletedAt DESC, WorkOrderNumber DESC LIMIT 1;
         ```
       * If a completed order exists, `WorkOrderNumber` is recorded as `v_latest_order`.
       * If no completed order exists, `WorkOrderNumber` is recorded as `NULL`.
     * Inserts into `Inspection` with `InspectionType = 'Final'`.
     * State transition:
       * If current status is `AwaitingFinalInspection`: A conclusive result (`Pass` or `Fail`) transitions the item to `AwaitingDecision`. `Inconclusive` leaves the item in `AwaitingFinalInspection`.
       * If current status is `AwaitingDecision`: State remains `AwaitingDecision` (a conclusive result confirms disposition eligibility; an inconclusive result blocks approval until re-inspected).
     * Writes `INSPECTION_CREATED` audit log.
2. **Grants (`020_grants.sql`)**:
   * Add: `GRANT EXECUTE ON PROCEDURE sp_record_final_inspection TO 'role_inspector';`
3. **Validation (`010_object_validation.sql`)**:
   * Update routine checks to verify all 11 stored procedures.

---

### Item 6: Approving Repair Requires Amount = 0

#### Professor's Feedback
> *"Approving a repair requires amount = 0. Passing NULL fails with 'Invalid outcome or amount', which is confusing when repair has no estimated value."*

#### Analysis & Root Cause
* In `sp_approve_disposition` ([030_procedures.sql line 100](file:///c:/Users/hunty/OneDrive/Desktop/warehouse-project/Warehouse-Returns-and-Refurbishment-Tracking-System/database/02_programmability/030_procedures.sql#L100)):
  ```sql
  IF p_outcome NOT IN ('Repair','Restock','Liquidate','Dispose') OR p_amount IS NULL OR p_amount < 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Invalid outcome or amount'; END IF;
  ```
* For `Repair`, the disposition update statement intentionally sets:
  ```sql
  RestockEstimatedValue = IF(p_outcome='Restock', p_amount, NULL),
  LiquidationProceeds   = IF(p_outcome='Liquidate', p_amount, NULL),
  DisposalCost          = IF(p_outcome='Dispose', p_amount, NULL)
  ```
  `p_amount` is never assigned to any column in `ReturnItem` when `p_outcome = 'Repair'`. Repair costs are populated strictly from work orders.
* Rejecting `p_amount IS NULL` forced managers to pass an arbitrary `0` or `0.00`, causing confusion.

#### Our Decision: Accept
Passing `NULL` for `amount` should be natural and valid when approving a repair.

#### Proposed Implementation Fix
1. **Update `sp_approve_disposition` Validation in `030_procedures.sql`**:
   ```sql
   IF p_outcome NOT IN ('Repair','Restock','Liquidate','Dispose') THEN
     SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Invalid outcome';
   END IF;

   IF p_outcome IN ('Restock','Liquidate','Dispose') THEN
     IF p_amount IS NULL OR p_amount < 0 THEN
       SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Disposition outcome requires a non-negative amount';
     END IF;
   ELSE
     -- For Repair, amount has no meaning in ReturnItem; if passed, it must not be negative
     IF p_amount IS NOT NULL AND p_amount < 0 THEN
       SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Repair amount cannot be negative';
     END IF;
   END IF;
   ```
2. In the audit logging payload:
   ```sql
   JSON_OBJECT('Outcome', p_outcome, 'Amount', IF(p_outcome='Repair', NULL, p_amount))
   ```

---

### Item 7: Passwords in the Repository & Server-Wide Collisions

#### Professor's Feedback
> *"Passwords are in the repo. The README says 'No Committed Secrets', but 010_roles.sql contains fixed passwords for all six demo logins. The role and login names (role_admin, manager01) apply to the whole server, so two builds on the same server share and overwrite them. In fact, role_admin was already on my test server from Yashvin's build."*

#### Analysis & Root Cause
1. **Committed Secrets**: `database/03_security/010_roles.sql` contains plaintext passwords (`CREATE USER ... IDENTIFIED BY 'Receiving123!';`), directly contradicting the README's *"No Committed Secrets"* security claim.
2. **Server-Wide Collisions**: In MySQL, `CREATE USER` and `CREATE ROLE` create instance-global objects in `mysql.user`. They are not isolated by schema/database. When multiple students run builds on the professor's shared test server using generic names (`role_admin`, `manager01`), builds overwrite each other's credentials and default role settings.

#### Our Decision: Accept
Hardcoded passwords violate basic security practices, and global object collisions break multi-tenant grading environments.

#### Proposed Implementation Fix
1. **Eliminate Hardcoded Passwords from Source Control**:
   * Remove plaintext password literals from `010_roles.sql`.
   * Add `DEMO_ACCOUNT_PASSWORD` to `build/config.example.env` and gitignored `build/config.env`.
   * Have `build/build_database.sh` create or alter the demonstration accounts using the configured password via administrative session execution.
2. **Namespace Role and User Names**:
   * Add a distinct project prefix `wr_` (Warehouse Returns) or dynamic `${TARGET_DB}_` prefix:
     * Roles: `wr_role_receiving`, `wr_role_inspector`, `wr_role_technician`, `wr_role_manager`, `wr_role_admin`.
     * Logins: `wr_receiving01`, `wr_inspector01`, `wr_technician01`, `wr_technician02`, `wr_manager01`, `wr_admin01`.
   * Update `020_sample_data.sql` so `AppUser.LoginIdentifier` matches the namespaced usernames.
   * This guarantees that our project's accounts and roles will never collide with another student's submission on the professor's MySQL server.

---

### Item 8: Stale Planning Documents & AI Assistant Notes

#### Professor's Feedback
> *"The planning documents are stale. The readiness checklist still says the schema, build file, CRUD, reports and roles are 'Not found'. It also says 'This review covers files available in this chat's workspace', which reads like an AI assistant's notes. The TDD's next steps are also out of date. Neither has been updated since the SQL was added."*

#### Analysis & Root Cause
* `planning/warehouse_returns_midterm_readiness_checklist.md` was drafted on October 22/24 before SQL scripts were authored. It was never updated once the database scripts, views, procedures, and tests were completed.
* Line 5 retained conversational drafting phrasing (*"This review covers files available in this chat's workspace"*).
* `docs/warehouse_returns_technical_design.md` Sections 8 and 9 still listed hypothetical deliverables (`sql/01_schema.sql`...) rather than the actual `database/` structure and `build/build_database.sh`.

#### Our Decision: Accept
Documentation must accurately reflect the completed state of the project and read as professional engineering documents.

#### Proposed Implementation Fix
1. **Refresh `planning/warehouse_returns_midterm_readiness_checklist.md`**:
   * Remove all AI conversational notes and boilerplate.
   * Update every row in the readiness matrix from "Not found" / "Requirements only" to "Implemented & Verified", referencing exact file paths:
     * Working MySQL Schema $\rightarrow$ `database/01_schema/010_tables.sql`
     * Schema Build File $\rightarrow$ `build/build_database.sh` and `database/manifest.txt`
     * Denormalized Reporting Views $\rightarrow$ `database/02_programmability/010_views.sql`
     * Stored Procedures & Triggers $\rightarrow$ `030_procedures.sql` and `040_triggers.sql`
     * Roles & Grants $\rightarrow$ `database/03_security/`
     * Verification Suites $\rightarrow$ `database/05_validation/`
2. **Update `docs/warehouse_returns_technical_design.md`**:
   * Revise Section 8 (Build Plan & Deliverables) to describe the real `database/` structure and automated bash build harness.
   * Revise Section 9 (Traceability & Remaining Work) to mark the database milestone complete and outline subsequent milestones (API service layer, UI prototype).