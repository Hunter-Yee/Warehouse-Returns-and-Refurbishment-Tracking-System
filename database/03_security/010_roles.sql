-- 010_roles.sql: Database roles and test login accounts
-- MySQL 8.0+ Role-Based Access Control (RBAC)
-- 1. Create database roles matching business roles (prefixed with wr_ to avoid server collisions)
CREATE ROLE IF NOT EXISTS 'wr_role_receiving';
CREATE ROLE IF NOT EXISTS 'wr_role_inspector';
CREATE ROLE IF NOT EXISTS 'wr_role_technician';
CREATE ROLE IF NOT EXISTS 'wr_role_manager';
CREATE ROLE IF NOT EXISTS 'wr_role_admin';

-- 2. Create local test accounts matching seeded AppUser.LoginIdentifier
-- No password is stored in source control. Accounts are created LOCKED so they cannot be used
-- until a password is set: build/build_database.sh sets DEMO_PASSWORD from build/config.env
-- and unlocks them, failing the build if it cannot. For a manual (Workbench) run, set each
-- password yourself:  ALTER USER 'wr_manager01'@'localhost' IDENTIFIED BY '...' ACCOUNT UNLOCK;
CREATE USER IF NOT EXISTS 'wr_receiving01'@'localhost' ACCOUNT LOCK;
CREATE USER IF NOT EXISTS 'wr_inspector01'@'localhost' ACCOUNT LOCK;
CREATE USER IF NOT EXISTS 'wr_technician01'@'localhost' ACCOUNT LOCK;
CREATE USER IF NOT EXISTS 'wr_technician02'@'localhost' ACCOUNT LOCK;
CREATE USER IF NOT EXISTS 'wr_manager01'@'localhost' ACCOUNT LOCK;
CREATE USER IF NOT EXISTS 'wr_admin01'@'localhost' ACCOUNT LOCK;

-- 3. Grant roles to corresponding user accounts
GRANT 'wr_role_receiving' TO 'wr_receiving01'@'localhost';
GRANT 'wr_role_inspector' TO 'wr_inspector01'@'localhost';
GRANT 'wr_role_technician' TO 'wr_technician01'@'localhost', 'wr_technician02'@'localhost';
GRANT 'wr_role_manager' TO 'wr_manager01'@'localhost';
GRANT 'wr_role_admin' TO 'wr_admin01'@'localhost';

-- 4. Set default roles active on connection
SET DEFAULT ROLE 'wr_role_receiving' TO 'wr_receiving01'@'localhost';
SET DEFAULT ROLE 'wr_role_inspector' TO 'wr_inspector01'@'localhost';
SET DEFAULT ROLE 'wr_role_technician' TO 'wr_technician01'@'localhost', 'wr_technician02'@'localhost';
SET DEFAULT ROLE 'wr_role_manager' TO 'wr_manager01'@'localhost';
SET DEFAULT ROLE 'wr_role_admin' TO 'wr_admin01'@'localhost';
