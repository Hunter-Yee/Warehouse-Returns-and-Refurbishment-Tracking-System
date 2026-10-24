-- 010_roles.sql: Database roles and test login accounts
-- MySQL 8.0+ Role-Based Access Control (RBAC)
USE warehouse_returns_demo;

-- 1. Create database roles matching business roles
CREATE ROLE IF NOT EXISTS 'role_receiving';
CREATE ROLE IF NOT EXISTS 'role_inspector';
CREATE ROLE IF NOT EXISTS 'role_technician';
CREATE ROLE IF NOT EXISTS 'role_manager';
CREATE ROLE IF NOT EXISTS 'role_admin';

-- 2. Create local test accounts matching seeded AppUser.LoginIdentifier
-- Passwords are set for local demonstration/testing environments.
CREATE USER IF NOT EXISTS 'receiving01'@'localhost' IDENTIFIED BY 'Receiving123!';
CREATE USER IF NOT EXISTS 'inspector01'@'localhost' IDENTIFIED BY 'Inspector123!';
CREATE USER IF NOT EXISTS 'technician01'@'localhost' IDENTIFIED BY 'Technician123!';
CREATE USER IF NOT EXISTS 'technician02'@'localhost' IDENTIFIED BY 'Technician123!';
CREATE USER IF NOT EXISTS 'manager01'@'localhost' IDENTIFIED BY 'Manager123!';
CREATE USER IF NOT EXISTS 'admin01'@'localhost' IDENTIFIED BY 'Admin123!';

-- 3. Grant roles to corresponding user accounts
GRANT 'role_receiving' TO 'receiving01'@'localhost';
GRANT 'role_inspector' TO 'inspector01'@'localhost';
GRANT 'role_technician' TO 'technician01'@'localhost', 'technician02'@'localhost';
GRANT 'role_manager' TO 'manager01'@'localhost';
GRANT 'role_admin' TO 'admin01'@'localhost';

-- 4. Set default roles active on connection
SET DEFAULT ROLE 'role_receiving' TO 'receiving01'@'localhost';
SET DEFAULT ROLE 'role_inspector' TO 'inspector01'@'localhost';
SET DEFAULT ROLE 'role_technician' TO 'technician01'@'localhost', 'technician02'@'localhost';
SET DEFAULT ROLE 'role_manager' TO 'manager01'@'localhost';
SET DEFAULT ROLE 'role_admin' TO 'admin01'@'localhost';
