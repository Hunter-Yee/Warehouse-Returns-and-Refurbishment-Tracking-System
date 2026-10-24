-- 020_grants.sql: Permissions and Grants per Role
-- Enforces least-privilege access per FRD 2.1 / TDD Section 5.
USE warehouse_returns_demo;

-- 1. Common read privileges for operational reference tables
GRANT SELECT ON warehouse_returns_demo.ReferenceValue TO 'role_receiving', 'role_inspector', 'role_technician', 'role_manager';
GRANT SELECT ON warehouse_returns_demo.Location TO 'role_receiving', 'role_inspector', 'role_technician', 'role_manager';
GRANT SELECT ON warehouse_returns_demo.Product TO 'role_receiving', 'role_inspector', 'role_technician', 'role_manager';
GRANT SELECT ON warehouse_returns_demo.Vendor TO 'role_receiving', 'role_inspector', 'role_technician', 'role_manager';
GRANT SELECT ON warehouse_returns_demo.AppUser TO 'role_receiving', 'role_inspector', 'role_technician', 'role_manager';
GRANT SELECT ON warehouse_returns_demo.UserRole TO 'role_receiving', 'role_inspector', 'role_technician', 'role_manager';
GRANT SELECT ON warehouse_returns_demo.Role TO 'role_receiving', 'role_inspector', 'role_technician', 'role_manager';

-- 2. Non-financial operational view
GRANT SELECT ON warehouse_returns_demo.vw_open_items TO 'role_receiving', 'role_inspector', 'role_technician', 'role_manager';

-- 3. Receiving Role Privileges
GRANT SELECT ON warehouse_returns_demo.ReturnHeader TO 'role_receiving';
GRANT SELECT ON warehouse_returns_demo.ReturnItem TO 'role_receiving';
GRANT INSERT ON warehouse_returns_demo.InventoryMovement TO 'role_receiving';
GRANT EXECUTE ON PROCEDURE warehouse_returns_demo.sp_move_item TO 'role_receiving';

-- 4. Inspector Role Privileges
GRANT SELECT ON warehouse_returns_demo.ReturnHeader TO 'role_inspector';
GRANT SELECT ON warehouse_returns_demo.ReturnItem TO 'role_inspector';
GRANT SELECT ON warehouse_returns_demo.Inspection TO 'role_inspector';
GRANT EXECUTE ON PROCEDURE warehouse_returns_demo.sp_record_initial_inspection TO 'role_inspector';
GRANT EXECUTE ON PROCEDURE warehouse_returns_demo.sp_record_postrepair_inspection TO 'role_inspector';

-- 5. Technician Role Privileges
GRANT SELECT ON warehouse_returns_demo.WorkOrder TO 'role_technician';
GRANT SELECT ON warehouse_returns_demo.ReturnItem TO 'role_technician';
GRANT EXECUTE ON PROCEDURE warehouse_returns_demo.sp_start_repair TO 'role_technician';
GRANT EXECUTE ON PROCEDURE warehouse_returns_demo.sp_complete_repair TO 'role_technician';

-- 6. Manager Role Privileges (Full operational + financial access)
GRANT SELECT ON warehouse_returns_demo.ReturnHeader TO 'role_manager';
GRANT SELECT ON warehouse_returns_demo.ReturnItem TO 'role_manager';
GRANT SELECT ON warehouse_returns_demo.Inspection TO 'role_manager';
GRANT SELECT ON warehouse_returns_demo.WorkOrder TO 'role_manager';
GRANT SELECT ON warehouse_returns_demo.InventoryMovement TO 'role_manager';
GRANT SELECT ON warehouse_returns_demo.VendorClaim TO 'role_manager';
GRANT SELECT ON warehouse_returns_demo.SalesSummary TO 'role_manager';
GRANT SELECT ON warehouse_returns_demo.AuditLog TO 'role_manager';
GRANT SELECT ON warehouse_returns_demo.vw_item_recovery TO 'role_manager';
GRANT EXECUTE ON PROCEDURE warehouse_returns_demo.sp_approve_disposition TO 'role_manager';
GRANT EXECUTE ON PROCEDURE warehouse_returns_demo.sp_assign_repair TO 'role_manager';
GRANT EXECUTE ON PROCEDURE warehouse_returns_demo.sp_submit_claim TO 'role_manager';
GRANT EXECUTE ON PROCEDURE warehouse_returns_demo.sp_approve_claim TO 'role_manager';
GRANT EXECUTE ON PROCEDURE warehouse_returns_demo.sp_settle_claim TO 'role_manager';

-- 7. Administrator Role Privileges (User, role, and configuration management)
GRANT SELECT, INSERT, UPDATE ON warehouse_returns_demo.AppUser TO 'role_admin';
GRANT SELECT, INSERT, UPDATE ON warehouse_returns_demo.Role TO 'role_admin';
GRANT SELECT, INSERT, UPDATE, DELETE ON warehouse_returns_demo.UserRole TO 'role_admin';
GRANT SELECT, INSERT, UPDATE ON warehouse_returns_demo.Location TO 'role_admin';
GRANT SELECT, INSERT, UPDATE ON warehouse_returns_demo.ReferenceValue TO 'role_admin';
GRANT SELECT, INSERT, UPDATE ON warehouse_returns_demo.Product TO 'role_admin';
GRANT SELECT, INSERT, UPDATE ON warehouse_returns_demo.Vendor TO 'role_admin';
GRANT SELECT ON warehouse_returns_demo.AuditLog TO 'role_admin';

FLUSH PRIVILEGES;
