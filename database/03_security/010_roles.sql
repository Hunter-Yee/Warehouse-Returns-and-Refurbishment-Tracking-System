-- 010_roles.sql: Database roles and test login accounts
-- MySQL 8.0+ Role-Based Access Control (RBAC)
-- 1. Create database roles matching business roles (prefixed with wr_ to avoid server collisions)
CREATE ROLE IF NOT EXISTS 'wr_role_receiving';
CREATE ROLE IF NOT EXISTS 'wr_role_inspector';
CREATE ROLE IF NOT EXISTS 'wr_role_technician';
CREATE ROLE IF NOT EXISTS 'wr_role_manager';
CREATE ROLE IF NOT EXISTS 'wr_role_admin';

-- 2. Create local test accounts matching seeded AppUser.LoginIdentifier
-- Passwords are set by build/build_database.sh from build/config.env rather than committed here.
CREATE USER IF NOT EXISTS 'wr_receiving01'@'localhost';
CREATE USER IF NOT EXISTS 'wr_inspector01'@'localhost';
CREATE USER IF NOT EXISTS 'wr_technician01'@'localhost';
CREATE USER IF NOT EXISTS 'wr_technician02'@'localhost';
CREATE USER IF NOT EXISTS 'wr_manager01'@'localhost';
CREATE USER IF NOT EXISTS 'wr_admin01'@'localhost';

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
