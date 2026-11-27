-- Warehouse Returns: audit trail grid views and query procedure (MySQL 8.0.22+).
-- Built on the temporal history tables (01_schema/020_history_tables.sql), not on AuditLog.
-- Run after 050_history_triggers.sql.
--
-- Design: each history version is turned into a JSON snapshot of its display values
-- (codes, names, amounts), compared with the previous version of the same record via LAG(),
-- and unpivoted with JSON_TABLE so the grid has ONE ROW PER CHANGED ATTRIBUTE:
--   Created  (Operation I): every attribute that has a value   (OldValue NULL)
--   Changed  (Operation U): only attributes whose value changed
--   Deleted  (Operation D): every attribute that had a value   (NewValue NULL)
-- BusinessAction links the version to the AuditLog action(s) of the same transaction
-- (e.g. DISPOSITION_APPROVED), using the shared fn_audit_transaction_id() value.

-- ---------------------------------------------------------------------------
-- Core entity: one returned unit (ReturnItem) and everything recorded against it.
CREATE OR REPLACE VIEW vw_item_audit_trail AS
WITH versions AS (
 SELECT h.ReturnID, h.LineNumber, 'ReturnItem' AS Entity,
        CONCAT('Unit ', h.ReturnID, '-', h.LineNumber) AS EntityKey,
        h.HistoryID, h.ValidFrom, h.Operation, h.ChangedByLogin, h.ChangedByUserID, h.TransactionID,
        JSON_OBJECT('Product', p.SKU, 'SerialNumber', h.SerialNumber, 'ReturnReason', rr.Code,
                    'ItemStatus', st.Code, 'Location', loc.LocationCode,
                    'ApprovedOutcome', oc.Code, 'ApprovedBy', ap.DisplayName, 'CompletionAt', h.CompletionAt,
                    'RestockEstimatedValue', h.RestockEstimatedValue,
                    'LiquidationProceeds', h.LiquidationProceeds, 'DisposalCost', h.DisposalCost) AS Snapshot
 FROM ReturnItemHistory h
 LEFT JOIN Product p ON p.ProductID = h.ProductID
 LEFT JOIN ReferenceValue rr ON rr.ReferenceValueID = h.ReturnReasonID
 LEFT JOIN ReferenceValue st ON st.ReferenceValueID = h.ItemStatusID
 LEFT JOIN Location loc ON loc.LocationID = h.CurrentLocationID
 LEFT JOIN ReferenceValue oc ON oc.ReferenceValueID = h.ApprovedOutcomeID
 LEFT JOIN AppUser ap ON ap.UserID = h.ApprovedByUserID
 UNION ALL
 SELECT h.ReturnID, h.LineNumber, 'WorkOrder', CONCAT('Work order ', h.WorkOrderNumber),
        h.HistoryID, h.ValidFrom, h.Operation, h.ChangedByLogin, h.ChangedByUserID, h.TransactionID,
        JSON_OBJECT('WorkOrderStatus', ws.Code, 'AssignedTechnician', tech.DisplayName,
                    'StartedAt', h.StartedAt, 'CompletedAt', h.CompletedAt, 'WorkDetails', h.WorkDetails,
                    'TotalLaborCost', h.TotalLaborCost, 'TotalPartsCost', h.TotalPartsCost)
 FROM WorkOrderHistory h
 LEFT JOIN ReferenceValue ws ON ws.ReferenceValueID = h.WorkOrderStatusID
 LEFT JOIN AppUser tech ON tech.UserID = h.AssignedTechnicianUserID
 UNION ALL
 SELECT h.ReturnID, h.LineNumber, 'Inspection', CONCAT('Inspection ', h.InspectionID),
        h.HistoryID, h.ValidFrom, h.Operation, h.ChangedByLogin, h.ChangedByUserID, h.TransactionID,
        JSON_OBJECT('InspectionType', it.Code, 'InspectionResult', ir.Code, 'ConditionGrade', cg.Code,
                    'Inspector', insp.DisplayName, 'InspectedAt', h.InspectedAt,
                    'WorkOrderNumber', h.WorkOrderNumber, 'Notes', h.Notes)
 FROM InspectionHistory h
 LEFT JOIN ReferenceValue it ON it.ReferenceValueID = h.InspectionTypeID
 LEFT JOIN ReferenceValue ir ON ir.ReferenceValueID = h.InspectionResultID
 LEFT JOIN ReferenceValue cg ON cg.ReferenceValueID = h.ConditionGradeID
 LEFT JOIN AppUser insp ON insp.UserID = h.InspectorUserID
 UNION ALL
 SELECT h.ReturnID, h.LineNumber, 'InventoryMovement', CONCAT('Movement ', h.MovementID),
        h.HistoryID, h.ValidFrom, h.Operation, h.ChangedByLogin, h.ChangedByUserID, h.TransactionID,
        JSON_OBJECT('MovementType', mt.Code, 'FromLocation', src.LocationCode, 'ToLocation', dst.LocationCode,
                    'MovedBy', mover.DisplayName, 'MovedAt', h.MovedAt, 'Notes', h.Notes)
 FROM InventoryMovementHistory h
 LEFT JOIN ReferenceValue mt ON mt.ReferenceValueID = h.MovementTypeID
 LEFT JOIN Location src ON src.LocationID = h.SourceLocationID
 LEFT JOIN Location dst ON dst.LocationID = h.DestinationLocationID
 LEFT JOIN AppUser mover ON mover.UserID = h.MovedByUserID
 UNION ALL
 SELECT h.ReturnID, h.LineNumber, 'VendorClaim', CONCAT('Claim ', h.ClaimID),
        h.HistoryID, h.ValidFrom, h.Operation, h.ChangedByLogin, h.ChangedByUserID, h.TransactionID,
        JSON_OBJECT('Vendor', v.VendorName, 'ClaimStatus', cs.Code, 'RequestedAmount', h.RequestedAmount,
                    'SettlementAmount', h.SettlementAmount, 'SettledAt', h.SettledAt,
                    'ClaimReference', h.ClaimReference)
 FROM VendorClaimHistory h
 LEFT JOIN Vendor v ON v.VendorID = h.VendorID
 LEFT JOIN ReferenceValue cs ON cs.ReferenceValueID = h.ClaimStatusID
), compared AS (
 SELECT v.*,
        LAG(v.Snapshot) OVER (PARTITION BY v.ReturnID, v.LineNumber, v.Entity, v.EntityKey
                              ORDER BY v.ValidFrom, v.HistoryID) AS PrevSnapshot
 FROM versions v
), cells AS (
 SELECT c.ReturnID, c.LineNumber, c.Entity, c.EntityKey, c.HistoryID, c.ValidFrom, c.Operation,
        c.ChangedByLogin, c.ChangedByUserID, c.TransactionID, k.AttributeSeq, k.AttributeName,
        CASE c.Operation WHEN 'I' THEN NULL WHEN 'D' THEN JSON_EXTRACT(c.Snapshot, CONCAT('$.', k.AttributeName))
             ELSE JSON_EXTRACT(c.PrevSnapshot, CONCAT('$.', k.AttributeName)) END AS OldJson,
        CASE c.Operation WHEN 'D' THEN NULL
             ELSE JSON_EXTRACT(c.Snapshot, CONCAT('$.', k.AttributeName)) END AS NewJson
 FROM compared c
 JOIN JSON_TABLE(JSON_KEYS(c.Snapshot), '$[*]'
        COLUMNS (AttributeSeq FOR ORDINALITY, AttributeName VARCHAR(64) PATH '$')) k
)
SELECT x.ReturnID, x.LineNumber, rh.ExternalReference,
       x.ValidFrom AS EventAt, x.Entity, x.EntityKey,
       CASE x.Operation WHEN 'I' THEN 'Created' WHEN 'U' THEN 'Changed' ELSE 'Deleted' END AS EventType,
       x.AttributeName,
       IF(JSON_TYPE(x.OldJson) = 'NULL', NULL, JSON_UNQUOTE(x.OldJson)) AS OldValue,
       IF(JSON_TYPE(x.NewJson) = 'NULL', NULL, JSON_UNQUOTE(x.NewJson)) AS NewValue,
       x.AttributeName IN ('RestockEstimatedValue', 'LiquidationProceeds', 'DisposalCost',
                           'TotalLaborCost', 'TotalPartsCost', 'RequestedAmount', 'SettlementAmount') AS IsFinancial,
       COALESCE(u.DisplayName, x.ChangedByLogin) AS ChangedBy,
       x.ChangedByLogin,
       (SELECT GROUP_CONCAT(DISTINCT a.Action ORDER BY a.Action)
        FROM AuditLog a WHERE a.TransactionID = x.TransactionID) AS BusinessAction,
       x.TransactionID, x.HistoryID, x.AttributeSeq
FROM cells x
JOIN ReturnHeader rh ON rh.ReturnID = x.ReturnID
LEFT JOIN AppUser u ON u.UserID = x.ChangedByUserID
WHERE NOT (IF(JSON_TYPE(x.OldJson) = 'NULL', NULL, x.OldJson) <=> IF(JSON_TYPE(x.NewJson) = 'NULL', NULL, x.NewJson));

-- ---------------------------------------------------------------------------
-- Master/administrative data: users, roles, role assignments, reference values,
-- locations, products, vendors, and monthly sales. Same one-row-per-changed-attribute
-- shape, keyed by entity instead of by unit. Closes the gap where administration
-- changes wrote no audit at all.
CREATE OR REPLACE VIEW vw_master_data_change_history AS
WITH versions AS (
 SELECT 'AppUser' AS Entity, CAST(h.UserID AS CHAR) AS EntityKey, h.HistoryID, h.ValidFrom, h.Operation,
        h.ChangedByLogin, h.ChangedByUserID, h.TransactionID,
        JSON_OBJECT('LoginIdentifier', h.LoginIdentifier, 'DisplayName', h.DisplayName, 'IsActive', h.IsActive) AS Snapshot
 FROM AppUserHistory h
 UNION ALL
 SELECT 'Role', CAST(h.RoleID AS CHAR), h.HistoryID, h.ValidFrom, h.Operation, h.ChangedByLogin, h.ChangedByUserID, h.TransactionID,
        JSON_OBJECT('RoleCode', h.RoleCode, 'Description', h.Description, 'IsActive', h.IsActive)
 FROM RoleHistory h
 UNION ALL
 SELECT 'UserRole', CONCAT(h.UserID, '/', h.RoleID), h.HistoryID, h.ValidFrom, h.Operation, h.ChangedByLogin, h.ChangedByUserID, h.TransactionID,
        JSON_OBJECT('User', u.LoginIdentifier, 'Role', r.RoleCode)
 FROM UserRoleHistory h
 LEFT JOIN AppUser u ON u.UserID = h.UserID
 LEFT JOIN Role r ON r.RoleID = h.RoleID
 UNION ALL
 SELECT 'ReferenceValue', CAST(h.ReferenceValueID AS CHAR), h.HistoryID, h.ValidFrom, h.Operation, h.ChangedByLogin, h.ChangedByUserID, h.TransactionID,
        JSON_OBJECT('Domain', h.Domain, 'Code', h.Code, 'Description', h.Description, 'IsActive', h.IsActive)
 FROM ReferenceValueHistory h
 UNION ALL
 SELECT 'Location', CAST(h.LocationID AS CHAR), h.HistoryID, h.ValidFrom, h.Operation, h.ChangedByLogin, h.ChangedByUserID, h.TransactionID,
        JSON_OBJECT('LocationCode', h.LocationCode, 'LocationName', h.LocationName, 'LocationType', lt.Code, 'IsActive', h.IsActive)
 FROM LocationHistory h
 LEFT JOIN ReferenceValue lt ON lt.ReferenceValueID = h.LocationTypeID
 UNION ALL
 SELECT 'Product', CAST(h.ProductID AS CHAR), h.HistoryID, h.ValidFrom, h.Operation, h.ChangedByLogin, h.ChangedByUserID, h.TransactionID,
        JSON_OBJECT('SKU', h.SKU, 'Description', h.Description, 'Vendor', v.VendorName,
                    'SerialRequired', h.SerialRequired, 'IsActive', h.IsActive)
 FROM ProductHistory h
 LEFT JOIN Vendor v ON v.VendorID = h.VendorID
 UNION ALL
 SELECT 'Vendor', CAST(h.VendorID AS CHAR), h.HistoryID, h.ValidFrom, h.Operation, h.ChangedByLogin, h.ChangedByUserID, h.TransactionID,
        JSON_OBJECT('VendorName', h.VendorName, 'ContactName', h.ContactName, 'ContactEmail', h.ContactEmail,
                    'Phone', h.Phone, 'IsActive', h.IsActive)
 FROM VendorHistory h
 UNION ALL
 SELECT 'SalesSummary', CONCAT(p.SKU, ' ', DATE_FORMAT(h.CalendarMonth, '%Y-%m')), h.HistoryID, h.ValidFrom, h.Operation,
        h.ChangedByLogin, h.ChangedByUserID, h.TransactionID,
        JSON_OBJECT('UnitsSold', h.UnitsSold, 'SourceReference', h.SourceReference)
 FROM SalesSummaryHistory h
 LEFT JOIN Product p ON p.ProductID = h.ProductID
), compared AS (
 SELECT v.*, LAG(v.Snapshot) OVER (PARTITION BY v.Entity, v.EntityKey ORDER BY v.ValidFrom, v.HistoryID) AS PrevSnapshot
 FROM versions v
), cells AS (
 SELECT c.Entity, c.EntityKey, c.HistoryID, c.ValidFrom, c.Operation, c.ChangedByLogin, c.ChangedByUserID,
        c.TransactionID, k.AttributeSeq, k.AttributeName,
        CASE c.Operation WHEN 'I' THEN NULL WHEN 'D' THEN JSON_EXTRACT(c.Snapshot, CONCAT('$.', k.AttributeName))
             ELSE JSON_EXTRACT(c.PrevSnapshot, CONCAT('$.', k.AttributeName)) END AS OldJson,
        CASE c.Operation WHEN 'D' THEN NULL
             ELSE JSON_EXTRACT(c.Snapshot, CONCAT('$.', k.AttributeName)) END AS NewJson
 FROM compared c
 JOIN JSON_TABLE(JSON_KEYS(c.Snapshot), '$[*]'
        COLUMNS (AttributeSeq FOR ORDINALITY, AttributeName VARCHAR(64) PATH '$')) k
)
SELECT x.ValidFrom AS EventAt, x.Entity, x.EntityKey,
       CASE x.Operation WHEN 'I' THEN 'Created' WHEN 'U' THEN 'Changed' ELSE 'Deleted' END AS EventType,
       x.AttributeName,
       IF(JSON_TYPE(x.OldJson) = 'NULL', NULL, JSON_UNQUOTE(x.OldJson)) AS OldValue,
       IF(JSON_TYPE(x.NewJson) = 'NULL', NULL, JSON_UNQUOTE(x.NewJson)) AS NewValue,
       COALESCE(u.DisplayName, x.ChangedByLogin) AS ChangedBy, x.ChangedByLogin,
       x.TransactionID, x.HistoryID, x.AttributeSeq
FROM cells x
LEFT JOIN AppUser u ON u.UserID = x.ChangedByUserID
WHERE NOT (IF(JSON_TYPE(x.OldJson) = 'NULL', NULL, x.OldJson) <=> IF(JSON_TYPE(x.NewJson) = 'NULL', NULL, x.NewJson));

-- ---------------------------------------------------------------------------
-- Audit trail query for the GUI screen: search by return reference (and optionally line),
-- one page at a time. Result set 1 = paging summary; result set 2 = the page of grid rows,
-- oldest first. Any active staff role may search; amounts are included only for Managers
-- (Administrators and other roles get the redacted trail).
DELIMITER $$
DROP PROCEDURE IF EXISTS sp_get_item_audit_trail$$
CREATE PROCEDURE sp_get_item_audit_trail(
 IN p_external_ref VARCHAR(100),
 IN p_line_number SMALLINT UNSIGNED,
 IN p_page INT UNSIGNED,
 IN p_page_size INT UNSIGNED
)
SQL SECURITY DEFINER
READS SQL DATA
BEGIN
 DECLARE v_actor INT UNSIGNED DEFAULT NULL;
 DECLARE v_is_manager TINYINT(1) DEFAULT 0;
 DECLARE v_return_id INT UNSIGNED DEFAULT NULL;
 DECLARE v_total INT UNSIGNED DEFAULT 0;
 DECLARE v_offset INT UNSIGNED DEFAULT 0;

 SELECT u.UserID, MAX(r.RoleCode = 'Manager') INTO v_actor, v_is_manager
 FROM AppUser u
 JOIN UserRole ur ON ur.UserID = u.UserID
 JOIN Role r ON r.RoleID = ur.RoleID AND r.IsActive = 1
 WHERE u.LoginIdentifier = fn_audit_login() AND u.IsActive = 1
 GROUP BY u.UserID;
 IF v_actor IS NULL THEN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Active staff login with an active role required';
 END IF;

 IF p_page IS NULL OR p_page < 1 THEN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Page must be 1 or greater';
 END IF;
 IF p_page_size IS NULL OR p_page_size < 1 OR p_page_size > 200 THEN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Page size must be between 1 and 200';
 END IF;

 SELECT ReturnID INTO v_return_id FROM ReturnHeader WHERE ExternalReference = TRIM(p_external_ref);
 IF v_return_id IS NULL THEN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Return reference not found';
 END IF;

 SELECT COUNT(*) INTO v_total FROM vw_item_audit_trail t
 WHERE t.ReturnID = v_return_id
   AND (p_line_number IS NULL OR t.LineNumber = p_line_number)
   AND (v_is_manager = 1 OR t.IsFinancial = 0);
 SET v_offset = (p_page - 1) * p_page_size;

 SELECT v_return_id AS ReturnID, TRIM(p_external_ref) AS ExternalReference, p_line_number AS LineNumber,
        v_total AS TotalRows, p_page AS Page, p_page_size AS PageSize,
        GREATEST(CEIL(v_total / p_page_size), 1) AS TotalPages, v_is_manager AS IncludesFinancial;

 SELECT t.EventAt, t.LineNumber, t.Entity, t.EntityKey, t.EventType, t.AttributeName,
        t.OldValue, t.NewValue, t.ChangedBy, t.BusinessAction, t.TransactionID
 FROM vw_item_audit_trail t
 WHERE t.ReturnID = v_return_id
   AND (p_line_number IS NULL OR t.LineNumber = p_line_number)
   AND (v_is_manager = 1 OR t.IsFinancial = 0)
 ORDER BY t.EventAt, t.HistoryID, t.AttributeSeq
 LIMIT v_offset, p_page_size;
END$$
DELIMITER ;

SELECT TABLE_NAME AS AuditView FROM information_schema.VIEWS
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME IN ('vw_item_audit_trail', 'vw_master_data_change_history');
