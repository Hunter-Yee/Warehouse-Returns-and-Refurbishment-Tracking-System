-- Dedicated owner (DEFINER) for every view, function, procedure and trigger (TDD section 5:
-- "a dedicated least-privileged owner, not a student staff account or unrestricted root").
-- Run BEFORE the other programmability files; they all declare DEFINER = 'wr_owner'@'localhost'.
--
-- The account is LOCKED: nobody can log in as it. MySQL still runs definer-rights code with
-- its privileges, which are limited to data access in THIS schema plus the one Performance
-- Schema table fn_audit_transaction_id() reads. It cannot create, drop or grant anything.
-- The build (setup) account needs SET_ANY_DEFINER (8.2+) or SET_USER_ID (8.0) to create
-- objects for another definer; root has it.
CREATE USER IF NOT EXISTS 'wr_owner'@'localhost' ACCOUNT LOCK;
ALTER USER 'wr_owner'@'localhost' ACCOUNT LOCK;

-- GRANT needs the schema name as a literal, so build it from DATABASE().
SET @wr_owner_grant = CONCAT('GRANT SELECT, INSERT, UPDATE, EXECUTE, TRIGGER ON `', DATABASE(), '`.* TO ''wr_owner''@''localhost''');
PREPARE wr_owner_stmt FROM @wr_owner_grant;
EXECUTE wr_owner_stmt;
DEALLOCATE PREPARE wr_owner_stmt;
GRANT SELECT ON performance_schema.events_transactions_current TO 'wr_owner'@'localhost';

SHOW GRANTS FOR 'wr_owner'@'localhost';
