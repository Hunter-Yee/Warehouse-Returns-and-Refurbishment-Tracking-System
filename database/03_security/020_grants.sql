-- 020_grants.sql: Permissions and grants per role.
-- Implements the TDD section 5 capability matrix:
--  * Business writes go only through procedures (EXECUTE). No role holds direct
--    INSERT/UPDATE/DELETE on protected workflow tables (ReturnHeader, ReturnItem, Inspection,
--    WorkOrder, InventoryMovement, VendorClaim, SalesSummary, AuditLog, history tables).
--  * Ordinary SELECT never exposes money: non-Manager roles get column-level SELECT on
--    ReturnItem without RestockEstimatedValue, LiquidationProceeds and DisposalCost.
--  * Products/vendors are Manager maintenance; accounts, roles, locations and reference values
--    are Administrator maintenance. Both are direct table edits guarded by the reference
--    triggers in 040_triggers.sql and recorded by the history tables.

-- 1. Common read privileges for operational reference tables
GRANT SELECT ON ReferenceValue TO 'wr_role_receiving', 'wr_role_inspector', 'wr_role_technician', 'wr_role_manager';
GRANT SELECT ON Location TO 'wr_role_receiving', 'wr_role_inspector', 'wr_role_technician', 'wr_role_manager';
GRANT SELECT ON Product TO 'wr_role_receiving', 'wr_role_inspector', 'wr_role_technician', 'wr_role_manager';
GRANT SELECT ON Vendor TO 'wr_role_receiving', 'wr_role_inspector', 'wr_role_technician', 'wr_role_manager';
GRANT SELECT ON AppUser TO 'wr_role_receiving', 'wr_role_inspector', 'wr_role_technician', 'wr_role_manager';
GRANT SELECT ON UserRole TO 'wr_role_receiving', 'wr_role_inspector', 'wr_role_technician', 'wr_role_manager';
GRANT SELECT ON Role TO 'wr_role_receiving', 'wr_role_inspector', 'wr_role_technician', 'wr_role_manager';

-- 2. Non-financial operational data for every operational role
GRANT SELECT ON vw_open_items TO 'wr_role_receiving', 'wr_role_inspector', 'wr_role_technician', 'wr_role_manager';
-- Operational reports RQ-03 / RQ-05 (no money)
GRANT SELECT ON vw_monthly_return_rate TO 'wr_role_receiving', 'wr_role_inspector', 'wr_role_technician', 'wr_role_manager';
GRANT SELECT ON vw_turnaround_by_outcome TO 'wr_role_receiving', 'wr_role_inspector', 'wr_role_technician', 'wr_role_manager';
GRANT SELECT ON ReturnHeader TO 'wr_role_receiving', 'wr_role_inspector', 'wr_role_technician', 'wr_role_manager';
GRANT SELECT (ReturnID, LineNumber, ProductID, SerialNumber, ReturnReasonID, ItemStatusID, CurrentLocationID,
              ApprovedOutcomeID, ApprovedByUserID, ApprovedAt, CompletionAt)
 ON ReturnItem TO 'wr_role_receiving', 'wr_role_inspector', 'wr_role_technician';

-- 3. Receiving: intake and permitted movement (procedures only)
GRANT EXECUTE ON PROCEDURE sp_register_return TO 'wr_role_receiving';
GRANT EXECUTE ON PROCEDURE sp_register_single_return TO 'wr_role_receiving';
GRANT EXECUTE ON PROCEDURE sp_move_item TO 'wr_role_receiving';

-- 4. Inspector: inspections
GRANT SELECT ON Inspection TO 'wr_role_inspector';
GRANT EXECUTE ON PROCEDURE sp_record_initial_inspection TO 'wr_role_inspector';
GRANT EXECUTE ON PROCEDURE sp_record_postrepair_inspection TO 'wr_role_inspector';
GRANT EXECUTE ON PROCEDURE sp_record_final_inspection TO 'wr_role_inspector';

-- 5. Technician: assigned repair work (labor/parts are theirs to record)
GRANT SELECT ON WorkOrder TO 'wr_role_technician';
GRANT EXECUTE ON PROCEDURE sp_start_repair TO 'wr_role_technician';
GRANT EXECUTE ON PROCEDURE sp_complete_repair TO 'wr_role_technician';

-- 6. Manager: approvals, assignments, claims, sales, products/vendors, financial reports
GRANT SELECT ON ReturnItem TO 'wr_role_manager';
GRANT SELECT ON Inspection TO 'wr_role_manager';
GRANT SELECT ON WorkOrder TO 'wr_role_manager';
GRANT SELECT ON InventoryMovement TO 'wr_role_manager';
GRANT SELECT ON VendorClaim TO 'wr_role_manager';
GRANT SELECT ON SalesSummary TO 'wr_role_manager';
GRANT SELECT ON AuditLog TO 'wr_role_manager';
GRANT SELECT ON vw_item_recovery TO 'wr_role_manager';
GRANT SELECT, INSERT, UPDATE ON Product TO 'wr_role_manager';
GRANT SELECT, INSERT, UPDATE ON Vendor TO 'wr_role_manager';
GRANT EXECUTE ON PROCEDURE sp_approve_disposition TO 'wr_role_manager';
GRANT EXECUTE ON PROCEDURE sp_withdraw_approval TO 'wr_role_manager';
GRANT EXECUTE ON PROCEDURE sp_assign_repair TO 'wr_role_manager';
GRANT EXECUTE ON PROCEDURE sp_cancel_work_order TO 'wr_role_manager';
GRANT EXECUTE ON PROCEDURE sp_enter_monthly_sales TO 'wr_role_manager';
GRANT EXECUTE ON PROCEDURE sp_submit_claim TO 'wr_role_manager';
GRANT EXECUTE ON PROCEDURE sp_approve_claim TO 'wr_role_manager';
GRANT EXECUTE ON PROCEDURE sp_deny_claim TO 'wr_role_manager';
GRANT EXECUTE ON PROCEDURE sp_cancel_claim TO 'wr_role_manager';
GRANT EXECUTE ON PROCEDURE sp_settle_claim TO 'wr_role_manager';

-- 7. Administrator: accounts, membership, roles, locations, reference values.
-- No business or financial access; audit review only through the redacted views/procedure.
GRANT SELECT, INSERT, UPDATE ON AppUser TO 'wr_role_admin';
GRANT SELECT, INSERT, UPDATE ON Role TO 'wr_role_admin';
GRANT SELECT, INSERT, DELETE ON UserRole TO 'wr_role_admin';
GRANT SELECT, INSERT, UPDATE ON Location TO 'wr_role_admin';
GRANT SELECT, INSERT, UPDATE ON ReferenceValue TO 'wr_role_admin';

-- 8. Audit review (TDD: Manager = business/financial view, Administrator = redacted view).
-- History tables are never granted directly; only the triggers write them.
GRANT EXECUTE ON PROCEDURE sp_get_item_audit_trail TO 'wr_role_manager', 'wr_role_admin';
GRANT SELECT ON vw_item_audit_trail TO 'wr_role_manager';
GRANT SELECT ON vw_master_data_change_history TO 'wr_role_manager', 'wr_role_admin';

-- 9. In-database version stamp (read-only)
GRANT SELECT ON SchemaBuild TO 'wr_role_manager', 'wr_role_admin';
GRANT SELECT ON SchemaBuildScript TO 'wr_role_manager', 'wr_role_admin';

FLUSH PRIVILEGES;
