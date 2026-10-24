-- Run on a fresh database after 010_reference_data.sql.
-- Sample baseline data only. These returns have not yet been inspected or processed.
-- Later, insert inspections, approvals, repairs, movements, claims and audit records
-- via the controlled procedures/triggers rather than bypassing business rules.
USE warehouse_returns_demo;
START TRANSACTION;

INSERT INTO AppUser (LoginIdentifier, DisplayName) VALUES
 ('receiving01', 'Morgan Lee'),
 ('inspector01', 'Avery Chen'),
 ('technician01', 'Taylor Reed'),
 ('technician02', 'Jordan Patel'),
 ('manager01', 'Casey Brown'),
 ('admin01', 'Riley Kim');

INSERT INTO UserRole (UserID, RoleID)
SELECT u.UserID, r.RoleID FROM AppUser AS u JOIN Role AS r
 ON (u.LoginIdentifier='receiving01' AND r.RoleCode='Receiving')
 OR (u.LoginIdentifier='inspector01' AND r.RoleCode='Inspector')
 OR (u.LoginIdentifier IN ('technician01','technician02') AND r.RoleCode='Technician')
 OR (u.LoginIdentifier='manager01' AND r.RoleCode='Manager')
 OR (u.LoginIdentifier='admin01' AND r.RoleCode='Administrator');

INSERT INTO Vendor (VendorName, ContactName, ContactEmail, Phone) VALUES
 ('Northstar Electronics', 'Sam Rivera', 'sam@example.test', '555-0101'),
 ('Evergreen Home Goods', 'Alex Morgan', 'alex@example.test', '555-0102'),
 ('Summit Office Supply', 'Devon Stone', 'devon@example.test', '555-0103');

INSERT INTO Product (SKU, Description, VendorID, SerialRequired) VALUES
 ('LAP-100', '14-inch laptop', (SELECT VendorID FROM Vendor WHERE VendorName='Northstar Electronics'), 1),
 ('MON-200', '24-inch monitor', (SELECT VendorID FROM Vendor WHERE VendorName='Northstar Electronics'), 1),
 ('TOA-300', 'Two-slice toaster', (SELECT VendorID FROM Vendor WHERE VendorName='Evergreen Home Goods'), 0),
 ('CHA-400', 'Ergonomic office chair', (SELECT VendorID FROM Vendor WHERE VendorName='Summit Office Supply'), 0),
 ('KBD-500', 'USB keyboard', (SELECT VendorID FROM Vendor WHERE VendorName='Summit Office Supply'), 0);

INSERT INTO Location (LocationCode, LocationName, LocationTypeID) VALUES
 ('INT-01','Intake station', (SELECT ReferenceValueID FROM ReferenceValue WHERE Domain='LocationType' AND Code='Intake')),
 ('INSP-01','Inspection bench', (SELECT ReferenceValueID FROM ReferenceValue WHERE Domain='LocationType' AND Code='Inspection')),
 ('REP-01','Repair bench', (SELECT ReferenceValueID FROM ReferenceValue WHERE Domain='LocationType' AND Code='Repair')),
 ('STO-01','Return storage', (SELECT ReferenceValueID FROM ReferenceValue WHERE Domain='LocationType' AND Code='Storage')),
 ('SALE-01','Saleable stock', (SELECT ReferenceValueID FROM ReferenceValue WHERE Domain='LocationType' AND Code='SaleableStock')),
 ('LIQ-01','Liquidation dispatch', (SELECT ReferenceValueID FROM ReferenceValue WHERE Domain='LocationType' AND Code='LiquidationExit')),
 ('DIS-01','Disposal dispatch', (SELECT ReferenceValueID FROM ReferenceValue WHERE Domain='LocationType' AND Code='DisposalExit'));

INSERT INTO ReturnHeader (ExternalReference, ReceivedAt, ReceivingUserID) VALUES
 ('RET-2026-1001','2026-10-10 09:00:00', (SELECT UserID FROM AppUser WHERE LoginIdentifier='receiving01')),
 ('RET-2026-1002','2026-10-14 10:00:00', (SELECT UserID FROM AppUser WHERE LoginIdentifier='receiving01')),
 ('RET-2026-1003','2026-10-18 11:00:00', (SELECT UserID FROM AppUser WHERE LoginIdentifier='receiving01')),
 ('RET-2026-1004','2026-10-21 09:30:00', (SELECT UserID FROM AppUser WHERE LoginIdentifier='receiving01')),
 ('RET-2026-1005','2026-10-23 14:00:00', (SELECT UserID FROM AppUser WHERE LoginIdentifier='receiving01'));

-- Each item is a separate physical unit and initially awaits inspection.
INSERT INTO ReturnItem
 (ReturnID,LineNumber,ProductID,SerialNumber,ReturnReasonID,ItemStatusID,CurrentLocationID)
VALUES
 ((SELECT ReturnID FROM ReturnHeader WHERE ExternalReference='RET-2026-1001'),1,
  (SELECT ProductID FROM Product WHERE SKU='LAP-100'),'LAP-DEMO-001',
  (SELECT ReferenceValueID FROM ReferenceValue WHERE Domain='ReturnReason' AND Code='Defective'),
  (SELECT ReferenceValueID FROM ReferenceValue WHERE Domain='ItemStatus' AND Code='AwaitingInspection'),
  (SELECT LocationID FROM Location WHERE LocationCode='INT-01')),
 ((SELECT ReturnID FROM ReturnHeader WHERE ExternalReference='RET-2026-1001'),2,
  (SELECT ProductID FROM Product WHERE SKU='KBD-500'),NULL,
  (SELECT ReferenceValueID FROM ReferenceValue WHERE Domain='ReturnReason' AND Code='Unwanted'),
  (SELECT ReferenceValueID FROM ReferenceValue WHERE Domain='ItemStatus' AND Code='AwaitingInspection'),
  (SELECT LocationID FROM Location WHERE LocationCode='INT-01')),
 ((SELECT ReturnID FROM ReturnHeader WHERE ExternalReference='RET-2026-1002'),1,
  (SELECT ProductID FROM Product WHERE SKU='MON-200'),'MON-DEMO-001',
  (SELECT ReferenceValueID FROM ReferenceValue WHERE Domain='ReturnReason' AND Code='Damaged'),
  (SELECT ReferenceValueID FROM ReferenceValue WHERE Domain='ItemStatus' AND Code='AwaitingInspection'),
  (SELECT LocationID FROM Location WHERE LocationCode='INT-01')),
 ((SELECT ReturnID FROM ReturnHeader WHERE ExternalReference='RET-2026-1002'),2,
  (SELECT ProductID FROM Product WHERE SKU='CHA-400'),NULL,
  (SELECT ReferenceValueID FROM ReferenceValue WHERE Domain='ReturnReason' AND Code='Damaged'),
  (SELECT ReferenceValueID FROM ReferenceValue WHERE Domain='ItemStatus' AND Code='AwaitingInspection'),
  (SELECT LocationID FROM Location WHERE LocationCode='INT-01')),
 ((SELECT ReturnID FROM ReturnHeader WHERE ExternalReference='RET-2026-1003'),1,
  (SELECT ProductID FROM Product WHERE SKU='TOA-300'),NULL,
  (SELECT ReferenceValueID FROM ReferenceValue WHERE Domain='ReturnReason' AND Code='Defective'),
  (SELECT ReferenceValueID FROM ReferenceValue WHERE Domain='ItemStatus' AND Code='AwaitingInspection'),
  (SELECT LocationID FROM Location WHERE LocationCode='INT-01')),
 ((SELECT ReturnID FROM ReturnHeader WHERE ExternalReference='RET-2026-1004'),1,
  (SELECT ProductID FROM Product WHERE SKU='LAP-100'),'LAP-DEMO-002',
  (SELECT ReferenceValueID FROM ReferenceValue WHERE Domain='ReturnReason' AND Code='WrongItem'),
  (SELECT ReferenceValueID FROM ReferenceValue WHERE Domain='ItemStatus' AND Code='AwaitingInspection'),
  (SELECT LocationID FROM Location WHERE LocationCode='INT-01')),
 ((SELECT ReturnID FROM ReturnHeader WHERE ExternalReference='RET-2026-1005'),1,
  (SELECT ProductID FROM Product WHERE SKU='KBD-500'),NULL,
  (SELECT ReferenceValueID FROM ReferenceValue WHERE Domain='ReturnReason' AND Code='Unwanted'),
  (SELECT ReferenceValueID FROM ReferenceValue WHERE Domain='ItemStatus' AND Code='AwaitingInspection'),
  (SELECT LocationID FROM Location WHERE LocationCode='INT-01'));

INSERT INTO SalesSummary (ProductID,CalendarMonth,UnitsSold,SourceReference,EnteredByUserID,UpdatedAt)
SELECT ProductID, '2026-10-01',
 CASE SKU WHEN 'LAP-100' THEN 200 WHEN 'MON-200' THEN 120 WHEN 'TOA-300' THEN 85
 WHEN 'CHA-400' THEN 60 ELSE 300 END,
 'MANUAL-OCT-2026',
 (SELECT UserID FROM AppUser WHERE LoginIdentifier='manager01'),
 '2026-10-24 12:00:00'
FROM Product;
COMMIT;

SELECT 'AppUser' AS table_name, COUNT(*) AS row_count FROM AppUser
UNION ALL SELECT 'Role',COUNT(*) FROM Role
UNION ALL SELECT 'ReferenceValue',COUNT(*) FROM ReferenceValue
UNION ALL SELECT 'Vendor',COUNT(*) FROM Vendor
UNION ALL SELECT 'Product',COUNT(*) FROM Product
UNION ALL SELECT 'Location',COUNT(*) FROM Location
UNION ALL SELECT 'ReturnHeader',COUNT(*) FROM ReturnHeader
UNION ALL SELECT 'ReturnItem',COUNT(*) FROM ReturnItem
UNION ALL SELECT 'SalesSummary',COUNT(*) FROM SalesSummary;
