-- 020_grants.sql: Permissions and Grants per Role
-- Enforces least-privilege access per FRD 2.1 / TDD Section 5.
-- 1. Common read privileges for operational reference tables
GRANT SELECT ON ReferenceValue TO 'role_receiving', 'role_inspector', 'role_technician', 'role_manager';
GRANT SELECT ON Location TO 'role_receiving', 'role_inspector', 'role_technician', 'role_manager';
GRANT SELECT ON Product TO 'role_receiving', 'role_inspector', 'role_technician', 'role_manager';
GRANT SELECT ON Vendor TO 'role_receiving', 'role_inspector', 'role_technician', 'role_manager';
GRANT SELECT ON AppUser TO 'role_receiving', 'role_inspector', 'role_technician', 'role_manager';
GRANT SELECT ON UserRole TO 'role_receiving', 'role_inspector', 'role_technician', 'role_manager';
GRANT SELECT ON Role TO 'role_receiving', 'role_inspector', 'role_technician', 'role_manager';

-- 2. Non-financial operational view
GRANT SELECT ON vw_open_items TO 'role_receiving', 'role_inspector', 'role_technician', 'role_manager';

-- 3. Receiving Role Privileges
GRANT SELECT ON ReturnHeader TO 'role_receiving';
GRANT SELECT ON ReturnItem TO 'role_receiving';
GRANT INSERT ON InventoryMovement TO 'role_receiving';
GRANT EXECUTE ON PROCEDURE sp_move_item TO 'role_receiving';

-- 4. Inspector Role Privileges
GRANT SELECT ON ReturnHeader TO 'role_inspector';
GRANT SELECT ON ReturnItem TO 'role_inspector';
GRANT SELECT ON Inspection TO 'role_inspector';
GRANT EXECUTE ON PROCEDURE sp_record_initial_inspection TO 'role_inspector';
GRANT EXECUTE ON PROCEDURE sp_record_postrepair_inspection TO 'role_inspector';

-- 5. Technician Role Privileges
GRANT SELECT ON WorkOrder TO 'role_technician';
GRANT SELECT ON ReturnItem TO 'role_technician';
GRANT EXECUTE ON PROCEDURE sp_start_repair TO 'role_technician';
GRANT EXECUTE ON PROCEDURE sp_complete_repair TO 'role_technician';

-- 6. Manager Role Privileges (Full operational + financial access)
GRANT SELECT ON ReturnHeader TO 'role_manager';
GRANT SELECT ON ReturnItem TO 'role_manager';
GRANT SELECT ON Inspection TO 'role_manager';
GRANT SELECT ON WorkOrder TO 'role_manager';
GRANT SELECT ON InventoryMovement TO 'role_manager';
GRANT SELECT ON VendorClaim TO 'role_manager';
GRANT SELECT ON SalesSummary TO 'role_manager';
GRANT SELECT ON AuditLog TO 'role_manager';
GRANT SELECT ON vw_item_recovery TO 'role_manager';
GRANT EXECUTE ON PROCEDURE sp_approve_disposition TO 'role_manager';
GRANT EXECUTE ON PROCEDURE sp_assign_repair TO 'role_manager';
GRANT EXECUTE ON PROCEDURE sp_submit_claim TO 'role_manager';
GRANT EXECUTE ON PROCEDURE sp_approve_claim TO 'role_manager';
GRANT EXECUTE ON PROCEDURE sp_settle_claim TO 'role_manager';

-- 7. Administrator Role Privileges (User, role, and configuration management)
GRANT SELECT, INSERT, UPDATE ON AppUser TO 'role_admin';
GRANT SELECT, INSERT, UPDATE ON Role TO 'role_admin';
GRANT SELECT, INSERT, UPDATE, DELETE ON UserRole TO 'role_admin';
GRANT SELECT, INSERT, UPDATE ON Location TO 'role_admin';
GRANT SELECT, INSERT, UPDATE ON ReferenceValue TO 'role_admin';
GRANT SELECT, INSERT, UPDATE ON Product TO 'role_admin';
GRANT SELECT, INSERT, UPDATE ON Vendor TO 'role_admin';
GRANT SELECT ON AuditLog TO 'role_admin';

FLUSH PRIVILEGES;
