-- 020_grants.sql: Permissions and Grants per Role
-- Enforces least-privilege access per FRD 2.1 / TDD Section 5.
-- 1. Common read privileges for operational reference tables
GRANT SELECT ON ReferenceValue TO 'wr_role_receiving', 'wr_role_inspector', 'wr_role_technician', 'wr_role_manager';
GRANT SELECT ON Location TO 'wr_role_receiving', 'wr_role_inspector', 'wr_role_technician', 'wr_role_manager';
GRANT SELECT ON Product TO 'wr_role_receiving', 'wr_role_inspector', 'wr_role_technician', 'wr_role_manager';
GRANT SELECT ON Vendor TO 'wr_role_receiving', 'wr_role_inspector', 'wr_role_technician', 'wr_role_manager';
GRANT SELECT ON AppUser TO 'wr_role_receiving', 'wr_role_inspector', 'wr_role_technician', 'wr_role_manager';
GRANT SELECT ON UserRole TO 'wr_role_receiving', 'wr_role_inspector', 'wr_role_technician', 'wr_role_manager';
GRANT SELECT ON Role TO 'wr_role_receiving', 'wr_role_inspector', 'wr_role_technician', 'wr_role_manager';

-- 2. Non-financial operational view
GRANT SELECT ON vw_open_items TO 'wr_role_receiving', 'wr_role_inspector', 'wr_role_technician', 'wr_role_manager';

-- 3. Receiving Role Privileges
GRANT SELECT, INSERT ON ReturnHeader TO 'wr_role_receiving';
GRANT SELECT, INSERT ON ReturnItem TO 'wr_role_receiving';
GRANT INSERT ON InventoryMovement TO 'wr_role_receiving';
GRANT EXECUTE ON PROCEDURE sp_register_return TO 'wr_role_receiving';
GRANT EXECUTE ON PROCEDURE sp_register_single_return TO 'wr_role_receiving';
GRANT EXECUTE ON PROCEDURE sp_move_item TO 'wr_role_receiving';

-- 4. Inspector Role Privileges
GRANT SELECT ON ReturnHeader TO 'wr_role_inspector';
GRANT SELECT ON ReturnItem TO 'wr_role_inspector';
GRANT SELECT ON Inspection TO 'wr_role_inspector';
GRANT EXECUTE ON PROCEDURE sp_record_initial_inspection TO 'wr_role_inspector';
GRANT EXECUTE ON PROCEDURE sp_record_postrepair_inspection TO 'wr_role_inspector';
GRANT EXECUTE ON PROCEDURE sp_record_final_inspection TO 'wr_role_inspector';

-- 5. Technician Role Privileges
GRANT SELECT ON WorkOrder TO 'wr_role_technician';
GRANT SELECT ON ReturnItem TO 'wr_role_technician';
GRANT EXECUTE ON PROCEDURE sp_start_repair TO 'wr_role_technician';
GRANT EXECUTE ON PROCEDURE sp_complete_repair TO 'wr_role_technician';

-- 6. Manager Role Privileges (Full operational + financial access)
GRANT SELECT ON ReturnHeader TO 'wr_role_manager';
GRANT SELECT ON ReturnItem TO 'wr_role_manager';
GRANT SELECT ON Inspection TO 'wr_role_manager';
GRANT SELECT ON WorkOrder TO 'wr_role_manager';
GRANT SELECT ON InventoryMovement TO 'wr_role_manager';
GRANT SELECT ON VendorClaim TO 'wr_role_manager';
GRANT SELECT, INSERT, UPDATE ON SalesSummary TO 'wr_role_manager';
GRANT SELECT ON AuditLog TO 'wr_role_manager';
GRANT SELECT ON vw_item_recovery TO 'wr_role_manager';
GRANT EXECUTE ON PROCEDURE sp_approve_disposition TO 'wr_role_manager';
GRANT EXECUTE ON PROCEDURE sp_assign_repair TO 'wr_role_manager';
GRANT EXECUTE ON PROCEDURE sp_enter_monthly_sales TO 'wr_role_manager';
GRANT EXECUTE ON PROCEDURE sp_submit_claim TO 'wr_role_manager';
GRANT EXECUTE ON PROCEDURE sp_approve_claim TO 'wr_role_manager';
GRANT EXECUTE ON PROCEDURE sp_settle_claim TO 'wr_role_manager';

-- 7. Administrator Role Privileges (User, role, and configuration management)
GRANT SELECT, INSERT, UPDATE ON AppUser TO 'wr_role_admin';
GRANT SELECT, INSERT, UPDATE ON Role TO 'wr_role_admin';
GRANT SELECT, INSERT, UPDATE, DELETE ON UserRole TO 'wr_role_admin';
GRANT SELECT, INSERT, UPDATE ON Location TO 'wr_role_admin';
GRANT SELECT, INSERT, UPDATE ON ReferenceValue TO 'wr_role_admin';
GRANT SELECT, INSERT, UPDATE ON Product TO 'wr_role_admin';
GRANT SELECT, INSERT, UPDATE ON Vendor TO 'wr_role_admin';
GRANT SELECT ON AuditLog TO 'wr_role_admin';

FLUSH PRIVILEGES;
