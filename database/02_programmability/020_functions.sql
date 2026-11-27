-- Warehouse Returns: audit helper functions (MySQL 8.0.16+).
-- Financial recovery is still calculated only in vw_item_recovery; no function duplicates it.
-- These functions answer "who" and "which transaction" for the history (temporal) tables
-- and AuditLog. Run before 030_procedures.sql and 050_history_triggers.sql.
DELIMITER $$

-- The MySQL login of the session that made the change ('wr_manager01', 'root', ...).
-- USER() is the connecting client even inside DEFINER procedures and triggers, which is
-- what the business procedures already use to resolve the acting staff member.
DROP FUNCTION IF EXISTS fn_audit_login$$
CREATE FUNCTION fn_audit_login() RETURNS VARCHAR(100)
NOT DETERMINISTIC NO SQL SQL SECURITY INVOKER
BEGIN
 RETURN SUBSTRING_INDEX(USER(), '@', 1);
END$$

-- The AppUser behind that login, or NULL for setup/administrative accounts (e.g. root).
DROP FUNCTION IF EXISTS fn_audit_user_id$$
CREATE FUNCTION fn_audit_user_id() RETURNS INT UNSIGNED
NOT DETERMINISTIC READS SQL DATA SQL SECURITY DEFINER
BEGIN
 RETURN (SELECT UserID FROM AppUser WHERE LoginIdentifier = fn_audit_login() LIMIT 1);
END$$

-- One ID per database transaction, shared by every history and AuditLog row the transaction
-- writes: '<connection id>-<transaction event id>' from Performance Schema, which identifies
-- the current transaction (each autocommit statement is its own transaction). It is unique
-- for the life of the server process; pair it with the row timestamps across restarts.
-- Falls back to a per-call UUID if transaction instrumentation is disabled.
DROP FUNCTION IF EXISTS fn_audit_transaction_id$$
CREATE FUNCTION fn_audit_transaction_id() RETURNS VARCHAR(64)
NOT DETERMINISTIC READS SQL DATA SQL SECURITY DEFINER
BEGIN
 DECLARE v_id VARCHAR(64) DEFAULT NULL;
 SELECT CONCAT(CONNECTION_ID(), '-', EVENT_ID) INTO v_id
 FROM performance_schema.events_transactions_current
 WHERE THREAD_ID = PS_CURRENT_THREAD_ID() AND STATE = 'ACTIVE'
 LIMIT 1;
 RETURN COALESCE(v_id, UUID());
END$$

DELIMITER ;

SELECT ROUTINE_NAME FROM information_schema.ROUTINES
WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_TYPE = 'FUNCTION' ORDER BY ROUTINE_NAME;
