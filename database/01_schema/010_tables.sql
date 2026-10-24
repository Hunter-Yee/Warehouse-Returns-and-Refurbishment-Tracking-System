-- Warehouse Returns and Refurbishment Tracking System
-- FRD 2.1 / ERD 2.1 / TDD 1.0: 15-table baseline
-- MySQL 8.0.16+ (CHECK constraints enforced); use MySQL 8.0.36+ if available.
-- Run on a NEW/EMPTY database. No DROP statements are included.
-- Business rules spanning tables (roles, transitions, active codes, latest inspections,
-- concurrent serials, one active repair, atomic movement/audit) REQUIRE procedures/triggers.

CREATE DATABASE IF NOT EXISTS warehouse_returns_demo;
USE warehouse_returns_demo;

CREATE TABLE AppUser (
 UserID INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 LoginIdentifier VARCHAR(100) NOT NULL,
 DisplayName VARCHAR(150) NOT NULL,
 IsActive TINYINT(1) NOT NULL DEFAULT 1,
 CONSTRAINT uq_appuser_login UNIQUE (LoginIdentifier),
 CONSTRAINT ck_appuser_active CHECK (IsActive IN (0,1))
);

CREATE TABLE Role (
 RoleID INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 RoleCode VARCHAR(32) NOT NULL,
 Description VARCHAR(150) NOT NULL,
 IsActive TINYINT(1) NOT NULL DEFAULT 1,
 CONSTRAINT uq_role_code UNIQUE (RoleCode),
 CONSTRAINT ck_role_active CHECK (IsActive IN (0,1))
);

CREATE TABLE ReferenceValue (
 ReferenceValueID INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 Domain VARCHAR(32) NOT NULL,
 Code VARCHAR(32) NOT NULL,
 Description VARCHAR(150) NOT NULL,
 IsActive TINYINT(1) NOT NULL DEFAULT 1,
 CONSTRAINT uq_reference_domain_code UNIQUE (Domain, Code),
 CONSTRAINT ck_reference_active CHECK (IsActive IN (0,1))
);

CREATE TABLE Vendor (
 VendorID INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 VendorName VARCHAR(150) NOT NULL,
 ContactName VARCHAR(150) NULL,
 ContactEmail VARCHAR(255) NULL,
 Phone VARCHAR(40) NULL,
 IsActive TINYINT(1) NOT NULL DEFAULT 1,
 CONSTRAINT ck_vendor_active CHECK (IsActive IN (0,1))
);

CREATE TABLE Location (
 LocationID INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 LocationCode VARCHAR(40) NOT NULL,
 LocationName VARCHAR(150) NOT NULL,
 LocationTypeID INT UNSIGNED NOT NULL,
 IsActive TINYINT(1) NOT NULL DEFAULT 1,
 CONSTRAINT uq_location_code UNIQUE (LocationCode),
 CONSTRAINT ck_location_active CHECK (IsActive IN (0,1)),
 CONSTRAINT fk_location_type FOREIGN KEY (LocationTypeID) REFERENCES ReferenceValue(ReferenceValueID) ON DELETE RESTRICT
);

CREATE TABLE Product (
 ProductID INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 SKU VARCHAR(64) NOT NULL,
 Description VARCHAR(255) NOT NULL,
 VendorID INT UNSIGNED NOT NULL,
 SerialRequired TINYINT(1) NOT NULL DEFAULT 0,
 IsActive TINYINT(1) NOT NULL DEFAULT 1,
 CONSTRAINT uq_product_sku UNIQUE (SKU),
 CONSTRAINT ck_product_serial CHECK (SerialRequired IN (0,1)),
 CONSTRAINT ck_product_active CHECK (IsActive IN (0,1)),
 CONSTRAINT fk_product_vendor FOREIGN KEY (VendorID) REFERENCES Vendor(VendorID) ON DELETE RESTRICT
);

CREATE TABLE ReturnHeader (
 ReturnID INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 ExternalReference VARCHAR(100) NOT NULL,
 ReceivedAt DATETIME(6) NOT NULL,
 ReceivingUserID INT UNSIGNED NOT NULL,
 CONSTRAINT uq_return_external UNIQUE (ExternalReference),
 CONSTRAINT fk_return_receiver FOREIGN KEY (ReceivingUserID) REFERENCES AppUser(UserID) ON DELETE RESTRICT,
 INDEX ix_return_received (ReceivedAt, ReturnID)
);

CREATE TABLE UserRole (
 UserID INT UNSIGNED NOT NULL,
 RoleID INT UNSIGNED NOT NULL,
 PRIMARY KEY (UserID, RoleID),
 CONSTRAINT fk_userrole_user FOREIGN KEY (UserID) REFERENCES AppUser(UserID) ON DELETE RESTRICT,
 CONSTRAINT fk_userrole_role FOREIGN KEY (RoleID) REFERENCES Role(RoleID) ON DELETE RESTRICT,
 INDEX ix_userrole_role (RoleID)
);

CREATE TABLE ReturnItem (
 ReturnID INT UNSIGNED NOT NULL,
 LineNumber SMALLINT UNSIGNED NOT NULL,
 ProductID INT UNSIGNED NOT NULL,
 SerialNumber VARCHAR(100) NULL,
 ReturnReasonID INT UNSIGNED NOT NULL,
 ItemStatusID INT UNSIGNED NOT NULL,
 CurrentLocationID INT UNSIGNED NOT NULL,
 ApprovedOutcomeID INT UNSIGNED NULL,
 ApprovedByUserID INT UNSIGNED NULL,
 ApprovedAt DATETIME(6) NULL,
 CompletionAt DATETIME(6) NULL,
 RestockEstimatedValue DECIMAL(12,2) NULL,
 LiquidationProceeds DECIMAL(12,2) NULL,
 DisposalCost DECIMAL(12,2) NULL,
 PRIMARY KEY (ReturnID, LineNumber),
 CONSTRAINT ck_item_line CHECK (LineNumber > 0),
 CONSTRAINT ck_item_restock CHECK (RestockEstimatedValue IS NULL OR RestockEstimatedValue >= 0),
 CONSTRAINT ck_item_liquidation CHECK (LiquidationProceeds IS NULL OR LiquidationProceeds >= 0),
 CONSTRAINT ck_item_disposal CHECK (DisposalCost IS NULL OR DisposalCost >= 0),
 CONSTRAINT fk_item_return FOREIGN KEY (ReturnID) REFERENCES ReturnHeader(ReturnID) ON DELETE RESTRICT,
 CONSTRAINT fk_item_product FOREIGN KEY (ProductID) REFERENCES Product(ProductID) ON DELETE RESTRICT,
 CONSTRAINT fk_item_reason FOREIGN KEY (ReturnReasonID) REFERENCES ReferenceValue(ReferenceValueID) ON DELETE RESTRICT,
 CONSTRAINT fk_item_status FOREIGN KEY (ItemStatusID) REFERENCES ReferenceValue(ReferenceValueID) ON DELETE RESTRICT,
 CONSTRAINT fk_item_location FOREIGN KEY (CurrentLocationID) REFERENCES Location(LocationID) ON DELETE RESTRICT,
 CONSTRAINT fk_item_outcome FOREIGN KEY (ApprovedOutcomeID) REFERENCES ReferenceValue(ReferenceValueID) ON DELETE RESTRICT,
 CONSTRAINT fk_item_approver FOREIGN KEY (ApprovedByUserID) REFERENCES AppUser(UserID) ON DELETE RESTRICT,
 INDEX ix_item_product_serial_open (ProductID, SerialNumber, CompletionAt),
 INDEX ix_item_status_location (ItemStatusID, CurrentLocationID),
 INDEX ix_item_completion (CompletionAt)
);

CREATE TABLE SalesSummary (
 ProductID INT UNSIGNED NOT NULL,
 CalendarMonth DATE NOT NULL,
 UnitsSold INT UNSIGNED NOT NULL,
 SourceReference VARCHAR(150) NOT NULL,
 EnteredByUserID INT UNSIGNED NOT NULL,
 UpdatedAt DATETIME(6) NOT NULL,
 PRIMARY KEY (ProductID, CalendarMonth),
 CONSTRAINT ck_sales_month_first CHECK (DAYOFMONTH(CalendarMonth) = 1),
 CONSTRAINT fk_sales_product FOREIGN KEY (ProductID) REFERENCES Product(ProductID) ON DELETE RESTRICT,
 CONSTRAINT fk_sales_user FOREIGN KEY (EnteredByUserID) REFERENCES AppUser(UserID) ON DELETE RESTRICT
);

CREATE TABLE WorkOrder (
 ReturnID INT UNSIGNED NOT NULL,
 LineNumber SMALLINT UNSIGNED NOT NULL,
 WorkOrderNumber INT UNSIGNED NOT NULL,
 AssignedTechnicianUserID INT UNSIGNED NOT NULL,
 WorkOrderStatusID INT UNSIGNED NOT NULL,
 CreatedAt DATETIME(6) NOT NULL,
 StartedAt DATETIME(6) NULL,
 CompletedAt DATETIME(6) NULL,
 WorkDetails TEXT NULL,
 TotalLaborCost DECIMAL(12,2) NOT NULL DEFAULT 0,
 TotalPartsCost DECIMAL(12,2) NOT NULL DEFAULT 0,
 PRIMARY KEY (ReturnID, LineNumber, WorkOrderNumber),
 CONSTRAINT ck_workorder_number CHECK (WorkOrderNumber > 0),
 CONSTRAINT ck_workorder_labor CHECK (TotalLaborCost >= 0),
 CONSTRAINT ck_workorder_parts CHECK (TotalPartsCost >= 0),
 CONSTRAINT fk_workorder_item FOREIGN KEY (ReturnID, LineNumber) REFERENCES ReturnItem(ReturnID, LineNumber) ON DELETE RESTRICT,
 CONSTRAINT fk_workorder_technician FOREIGN KEY (AssignedTechnicianUserID) REFERENCES AppUser(UserID) ON DELETE RESTRICT,
 CONSTRAINT fk_workorder_status FOREIGN KEY (WorkOrderStatusID) REFERENCES ReferenceValue(ReferenceValueID) ON DELETE RESTRICT,
 INDEX ix_workorder_item_status (ReturnID, LineNumber, WorkOrderStatusID),
 INDEX ix_workorder_technician_status (AssignedTechnicianUserID, WorkOrderStatusID)
);

CREATE TABLE Inspection (
 InspectionID INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 ReturnID INT UNSIGNED NOT NULL,
 LineNumber SMALLINT UNSIGNED NOT NULL,
 InspectorUserID INT UNSIGNED NOT NULL,
 InspectedAt DATETIME(6) NOT NULL,
 InspectionTypeID INT UNSIGNED NOT NULL,
 ConditionGradeID INT UNSIGNED NOT NULL,
 InspectionResultID INT UNSIGNED NOT NULL,
 Notes TEXT NULL,
 WorkOrderNumber INT UNSIGNED NULL,
 CONSTRAINT fk_inspection_item FOREIGN KEY (ReturnID, LineNumber) REFERENCES ReturnItem(ReturnID, LineNumber) ON DELETE RESTRICT,
 CONSTRAINT fk_inspection_workorder FOREIGN KEY (ReturnID, LineNumber, WorkOrderNumber) REFERENCES WorkOrder(ReturnID, LineNumber, WorkOrderNumber) ON DELETE RESTRICT,
 CONSTRAINT fk_inspection_user FOREIGN KEY (InspectorUserID) REFERENCES AppUser(UserID) ON DELETE RESTRICT,
 CONSTRAINT fk_inspection_type FOREIGN KEY (InspectionTypeID) REFERENCES ReferenceValue(ReferenceValueID) ON DELETE RESTRICT,
 CONSTRAINT fk_inspection_grade FOREIGN KEY (ConditionGradeID) REFERENCES ReferenceValue(ReferenceValueID) ON DELETE RESTRICT,
 CONSTRAINT fk_inspection_result FOREIGN KEY (InspectionResultID) REFERENCES ReferenceValue(ReferenceValueID) ON DELETE RESTRICT,
 INDEX ix_inspection_item_time (ReturnID, LineNumber, InspectedAt, InspectionID),
 INDEX ix_inspection_workorder (ReturnID, LineNumber, WorkOrderNumber)
);

CREATE TABLE InventoryMovement (
 MovementID BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 ReturnID INT UNSIGNED NOT NULL,
 LineNumber SMALLINT UNSIGNED NOT NULL,
 SourceLocationID INT UNSIGNED NOT NULL,
 DestinationLocationID INT UNSIGNED NOT NULL,
 MovedAt DATETIME(6) NOT NULL,
 MovedByUserID INT UNSIGNED NOT NULL,
 MovementTypeID INT UNSIGNED NOT NULL,
 Notes TEXT NULL,
 CONSTRAINT ck_movement_distinct CHECK (SourceLocationID <> DestinationLocationID),
 CONSTRAINT fk_movement_item FOREIGN KEY (ReturnID, LineNumber) REFERENCES ReturnItem(ReturnID, LineNumber) ON DELETE RESTRICT,
 CONSTRAINT fk_movement_source FOREIGN KEY (SourceLocationID) REFERENCES Location(LocationID) ON DELETE RESTRICT,
 CONSTRAINT fk_movement_destination FOREIGN KEY (DestinationLocationID) REFERENCES Location(LocationID) ON DELETE RESTRICT,
 CONSTRAINT fk_movement_user FOREIGN KEY (MovedByUserID) REFERENCES AppUser(UserID) ON DELETE RESTRICT,
 CONSTRAINT fk_movement_type FOREIGN KEY (MovementTypeID) REFERENCES ReferenceValue(ReferenceValueID) ON DELETE RESTRICT,
 INDEX ix_movement_item_time (ReturnID, LineNumber, MovedAt, MovementID),
 INDEX ix_movement_source (SourceLocationID),
 INDEX ix_movement_destination (DestinationLocationID)
);

CREATE TABLE VendorClaim (
 ClaimID INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 ReturnID INT UNSIGNED NOT NULL,
 LineNumber SMALLINT UNSIGNED NOT NULL,
 VendorID INT UNSIGNED NOT NULL,
 RequestedAmount DECIMAL(12,2) NOT NULL,
 ClaimStatusID INT UNSIGNED NOT NULL,
 SubmittedAt DATETIME(6) NOT NULL,
 SettlementAmount DECIMAL(12,2) NULL,
 SettledAt DATETIME(6) NULL,
 RecordedByUserID INT UNSIGNED NOT NULL,
 ClaimReference VARCHAR(150) NULL,
 CONSTRAINT uq_claim_one_per_item UNIQUE (ReturnID, LineNumber),
 CONSTRAINT ck_claim_requested CHECK (RequestedAmount > 0),
 CONSTRAINT ck_claim_settlement CHECK (SettlementAmount IS NULL OR SettlementAmount > 0),
 CONSTRAINT fk_claim_item FOREIGN KEY (ReturnID, LineNumber) REFERENCES ReturnItem(ReturnID, LineNumber) ON DELETE RESTRICT,
 CONSTRAINT fk_claim_vendor FOREIGN KEY (VendorID) REFERENCES Vendor(VendorID) ON DELETE RESTRICT,
 CONSTRAINT fk_claim_status FOREIGN KEY (ClaimStatusID) REFERENCES ReferenceValue(ReferenceValueID) ON DELETE RESTRICT,
 CONSTRAINT fk_claim_user FOREIGN KEY (RecordedByUserID) REFERENCES AppUser(UserID) ON DELETE RESTRICT
);

CREATE TABLE AuditLog (
 AuditID BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 UserID INT UNSIGNED NOT NULL,
 RecordedAt DATETIME(6) NOT NULL,
 Action VARCHAR(32) NOT NULL,
 EntityName VARCHAR(64) NOT NULL,
 RecordKey JSON NOT NULL,
 OldValues JSON NULL,
 NewValues JSON NULL,
 TransactionID VARCHAR(64) NOT NULL,
 CONSTRAINT fk_audit_user FOREIGN KEY (UserID) REFERENCES AppUser(UserID) ON DELETE RESTRICT,
 INDEX ix_audit_entity_time (EntityName, RecordedAt),
 INDEX ix_audit_transaction (TransactionID)
);

-- Check that exactly 15 base tables were created.
SELECT COUNT(*) AS table_count FROM information_schema.tables
WHERE table_schema = DATABASE() AND table_type = 'BASE TABLE';
SELECT table_name FROM information_schema.tables
WHERE table_schema = DATABASE() AND table_type = 'BASE TABLE' ORDER BY table_name;
