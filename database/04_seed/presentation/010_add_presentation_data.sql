-- Optional presentation data: 6 additional returns / 12 individual units.
-- Includes 7 laptops supplied by the existing Northstar Electronics vendor.
-- Run AFTER the normal build and baseline seed, as the database setup account.
-- In Workbench, select the correct schema first; stop execution on SQL errors.
-- In mysql CLI, do not use --force. A failed run must be ROLLBACKed.
-- Do not add this optional file to the baseline manifest: baseline checks expect 7 items.
-- No USE/DROP DATABASE, credential changes, or updates to existing business rows.
-- Safe to repeat for these identifiers: existing headers/items are left unchanged.
-- All added units START AwaitingInspection at INT-01. Scenario labels describe
-- intended demonstrations; they do not claim repairs, claims or outcomes happened.

DROP TEMPORARY TABLE IF EXISTS tmp_wr_presentation_returns;
DROP TEMPORARY TABLE IF EXISTS tmp_wr_presentation_units;
DROP TEMPORARY TABLE IF EXISTS tmp_wr_presentation_checks;

CREATE TEMPORARY TABLE tmp_wr_presentation_returns (
 ExternalReference VARCHAR(100) PRIMARY KEY,
 DaysAgo INT UNSIGNED NOT NULL
) ENGINE=InnoDB;

CREATE TEMPORARY TABLE tmp_wr_presentation_units (
 ExternalReference VARCHAR(100) NOT NULL,
 LineNumber SMALLINT UNSIGNED NOT NULL,
 SKU VARCHAR(64) NOT NULL,
 SerialNumber VARCHAR(100) NULL,
 ReasonCode VARCHAR(32) NOT NULL,
 PRIMARY KEY (ExternalReference, LineNumber)
) ENGINE=InnoDB;

CREATE TEMPORARY TABLE tmp_wr_presentation_checks (
 AssertionName VARCHAR(100) PRIMARY KEY,
 Passed TINYINT NOT NULL,
 CHECK (Passed = 1)
) ENGINE=InnoDB;

INSERT INTO tmp_wr_presentation_returns VALUES
 ('PRES-LAP-REPAIR', 2),
 ('PRES-LAP-RESTOCK', 1),
 ('PRES-LAP-LIQUIDATE', 3),
 ('PRES-LAP-DISPOSE', 4),
 ('PRES-LAP-OPEN', 10),
 ('PRES-LAP-CLAIM', 2);

INSERT INTO tmp_wr_presentation_units VALUES
 -- Laptop battery repair example, plus a keyboard from the same return.
 ('PRES-LAP-REPAIR', 1, 'LAP-100', 'LAP-PRES-001', 'Defective'),
 ('PRES-LAP-REPAIR', 2, 'KBD-500', NULL, 'Unwanted'),
 -- Unwanted laptop suitable for a passing-inspection/direct-restock demo.
 ('PRES-LAP-RESTOCK', 1, 'LAP-100', 'LAP-PRES-002', 'Unwanted'),
 ('PRES-LAP-RESTOCK', 2, 'MON-200', 'MON-PRES-001', 'WrongItem'),
 -- Damaged laptop: inspect before choosing liquidation.
 ('PRES-LAP-LIQUIDATE', 1, 'LAP-100', 'LAP-PRES-003', 'Damaged'),
 ('PRES-LAP-LIQUIDATE', 2, 'TOA-300', NULL, 'Damaged'),
 -- Defective laptop: inspect before choosing disposal.
 ('PRES-LAP-DISPOSE', 1, 'LAP-100', 'LAP-PRES-004', 'Defective'),
 ('PRES-LAP-DISPOSE', 2, 'KBD-500', NULL, 'Defective'),
 -- Ten-day-old open return provides an overdue-work example.
 ('PRES-LAP-OPEN', 1, 'LAP-100', 'LAP-PRES-005', 'WrongItem'),
 ('PRES-LAP-OPEN', 2, 'LAP-100', 'LAP-PRES-006', 'Defective'),
 -- Separate laptop for a vendor-claim demonstration.
 ('PRES-LAP-CLAIM', 1, 'LAP-100', 'LAP-PRES-007', 'Defective'),
 ('PRES-LAP-CLAIM', 2, 'MON-200', 'MON-PRES-002', 'Damaged');

START TRANSACTION;

-- Preconditions: these are assertions, not just informational SELECTs.
INSERT INTO tmp_wr_presentation_checks
SELECT 'Required active products', COUNT(*) = 4
FROM Product WHERE SKU IN ('LAP-100','KBD-500','MON-200','TOA-300') AND IsActive=1;
INSERT INTO tmp_wr_presentation_checks
SELECT 'Active receiving01 business identity', COUNT(*) = 1
FROM AppUser u JOIN UserRole ur ON ur.UserID=u.UserID
JOIN Role r ON r.RoleID=ur.RoleID
WHERE u.LoginIdentifier='receiving01' AND u.IsActive=1
 AND r.RoleCode='Receiving' AND r.IsActive=1;
INSERT INTO tmp_wr_presentation_checks
SELECT 'Intake location', COUNT(*) = 1 FROM Location
WHERE LocationCode='INT-01' AND IsActive=1;
INSERT INTO tmp_wr_presentation_checks
SELECT 'AwaitingInspection status', COUNT(*) = 1 FROM ReferenceValue
WHERE Domain='ItemStatus' AND Code='AwaitingInspection' AND IsActive=1;
INSERT INTO tmp_wr_presentation_checks
SELECT 'Return reason codes', COUNT(*) = 4 FROM ReferenceValue
WHERE Domain='ReturnReason' AND Code IN ('Defective','Damaged','Unwanted','WrongItem') AND IsActive=1;
-- Reject identifier collisions with unrelated records or conflicting serials.
INSERT INTO tmp_wr_presentation_checks
SELECT 'Existing item identifiers match fixture', COUNT(*) = 0
FROM tmp_wr_presentation_units f
JOIN ReturnHeader h ON h.ExternalReference=f.ExternalReference
JOIN ReturnItem i ON i.ReturnID=h.ReturnID AND i.LineNumber=f.LineNumber
JOIN Product p ON p.ProductID=i.ProductID
WHERE p.SKU<>f.SKU OR NOT (i.SerialNumber <=> f.SerialNumber);
INSERT INTO tmp_wr_presentation_checks
SELECT 'No conflicting open presentation serials', COUNT(*) = 0
FROM tmp_wr_presentation_units f
JOIN Product p ON p.SKU=f.SKU
JOIN ReturnItem i ON i.ProductID=p.ProductID AND i.SerialNumber=f.SerialNumber
JOIN ReturnHeader h ON h.ReturnID=i.ReturnID
WHERE f.SerialNumber IS NOT NULL AND i.CompletionAt IS NULL
 AND (h.ExternalReference<>f.ExternalReference OR i.LineNumber<>f.LineNumber);

INSERT INTO ReturnHeader (ExternalReference,ReceivedAt,ReceivingUserID)
SELECT f.ExternalReference,
       TIMESTAMPADD(DAY, -CAST(f.DaysAgo AS SIGNED), UTC_TIMESTAMP(6)),
       u.UserID
FROM tmp_wr_presentation_returns f
JOIN AppUser u ON u.LoginIdentifier='receiving01'
LEFT JOIN ReturnHeader existing ON existing.ExternalReference=f.ExternalReference
WHERE existing.ReturnID IS NULL
ORDER BY f.ExternalReference;

INSERT INTO ReturnItem
 (ReturnID,LineNumber,ProductID,SerialNumber,ReturnReasonID,ItemStatusID,CurrentLocationID)
SELECT h.ReturnID,f.LineNumber,p.ProductID,f.SerialNumber,
       reason.ReferenceValueID,status.ReferenceValueID,l.LocationID
FROM tmp_wr_presentation_units f
JOIN ReturnHeader h ON h.ExternalReference=f.ExternalReference
JOIN Product p ON p.SKU=f.SKU
JOIN ReferenceValue reason ON reason.Domain='ReturnReason' AND reason.Code=f.ReasonCode
JOIN ReferenceValue status ON status.Domain='ItemStatus' AND status.Code='AwaitingInspection'
JOIN Location l ON l.LocationCode='INT-01'
LEFT JOIN ReturnItem existing ON existing.ReturnID=h.ReturnID AND existing.LineNumber=f.LineNumber
WHERE existing.ReturnID IS NULL
ORDER BY h.ReturnID,f.LineNumber;

INSERT INTO tmp_wr_presentation_checks
SELECT 'All 12 fixture items exist', COUNT(*) = 12
FROM tmp_wr_presentation_units f
JOIN ReturnHeader h ON h.ExternalReference=f.ExternalReference
JOIN ReturnItem i ON i.ReturnID=h.ReturnID AND i.LineNumber=f.LineNumber;

COMMIT;

SELECT h.ExternalReference,i.ReturnID,i.LineNumber,p.SKU,i.SerialNumber,
       reason.Code AS ReturnReason,s.Code AS ItemStatus,l.LocationCode
FROM tmp_wr_presentation_units f
JOIN ReturnHeader h ON h.ExternalReference=f.ExternalReference
JOIN ReturnItem i ON i.ReturnID=h.ReturnID AND i.LineNumber=f.LineNumber
JOIN Product p ON p.ProductID=i.ProductID
JOIN ReferenceValue reason ON reason.ReferenceValueID=i.ReturnReasonID
JOIN ReferenceValue s ON s.ReferenceValueID=i.ItemStatusID
JOIN Location l ON l.LocationID=i.CurrentLocationID
ORDER BY h.ExternalReference,i.LineNumber;

DROP TEMPORARY TABLE tmp_wr_presentation_checks;
DROP TEMPORARY TABLE tmp_wr_presentation_units;
DROP TEMPORARY TABLE tmp_wr_presentation_returns;

-- Fresh baseline + this file: 11 headers, 19 units, 9 of them LAP-100.
-- Existing inspected/repaired/completed rows are not reset on a repeat run.
-- Intake is setup SQL because the current project has no guarded intake routine.
-- Use the existing business procedures for subsequent inspection/repair/claim/movement.
