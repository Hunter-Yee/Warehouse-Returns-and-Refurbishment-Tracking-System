-- First movement triggers. Install AFTER procedures; test with a dedicated Receiving MySQL login.
-- Warning: the trigger processes one row; multi-step atomicity still requires the caller's transaction.
-- Application roles have no direct INSERT on InventoryMovement; sp_move_item is the only path.
DELIMITER $$
DROP TRIGGER IF EXISTS trg_movement_before_insert$$
CREATE DEFINER='wr_owner'@'localhost' TRIGGER trg_movement_before_insert BEFORE INSERT ON InventoryMovement
FOR EACH ROW
BEGIN
 DECLARE v_location INT UNSIGNED DEFAULT NULL;
 DECLARE v_completed DATETIME(6) DEFAULT NULL;
 DECLARE v_type VARCHAR(32) DEFAULT NULL;
 DECLARE v_destination_type VARCHAR(32) DEFAULT NULL;
 DECLARE v_status VARCHAR(32) DEFAULT NULL;
 DECLARE v_actor_login VARCHAR(100);
 DECLARE v_actor_role_count INT DEFAULT 0;
 SET v_actor_login=SUBSTRING_INDEX(USER(),'@',1);
 SELECT COUNT(*) INTO v_actor_role_count FROM AppUser u
 JOIN UserRole ur ON ur.UserID=u.UserID JOIN Role r ON r.RoleID=ur.RoleID
 WHERE u.UserID=NEW.MovedByUserID AND u.LoginIdentifier=v_actor_login
 AND u.IsActive=1 AND r.IsActive=1 AND r.RoleCode='Receiving';
 IF v_actor_role_count=0 THEN SIGNAL SQLSTATE '45003' SET MYSQL_ERRNO=50003, MESSAGE_TEXT='Active Receiving login required'; END IF;
 SELECT i.CurrentLocationID,i.CompletionAt,s.Code INTO v_location,v_completed,v_status
 FROM ReturnItem i JOIN ReferenceValue s ON s.ReferenceValueID=i.ItemStatusID
 WHERE i.ReturnID=NEW.ReturnID AND i.LineNumber=NEW.LineNumber FOR UPDATE;
 IF v_location IS NULL OR v_completed IS NOT NULL OR v_location<>NEW.SourceLocationID THEN
  SIGNAL SQLSTATE '45009' SET MYSQL_ERRNO=50009, MESSAGE_TEXT='Closed item, missing item, or stale source location'; END IF;
 SELECT mt.Code INTO v_type FROM ReferenceValue mt
 WHERE mt.ReferenceValueID=NEW.MovementTypeID AND mt.Domain='MovementType' AND mt.IsActive=1;
 SELECT lt.Code INTO v_destination_type FROM Location l JOIN ReferenceValue lt
 ON lt.ReferenceValueID=l.LocationTypeID AND lt.Domain='LocationType' AND lt.IsActive=1
 WHERE l.LocationID=NEW.DestinationLocationID AND l.IsActive=1;
 IF v_type IS NULL OR v_destination_type IS NULL THEN
  SIGNAL SQLSTATE '45001' SET MYSQL_ERRNO=50001, MESSAGE_TEXT='Inactive/incorrect movement type or destination'; END IF;
 IF (v_type='Restock' AND (v_status<>'ApprovedForRestock' OR v_destination_type<>'SaleableStock'))
 OR (v_type='Liquidate' AND (v_status<>'ApprovedForLiquidation' OR v_destination_type<>'LiquidationExit'))
 OR (v_type='Dispose' AND (v_status<>'ApprovedForDisposal' OR v_destination_type<>'DisposalExit'))
 OR (v_type='Relocate' AND v_destination_type IN ('SaleableStock','LiquidationExit','DisposalExit')) THEN
  SIGNAL SQLSTATE '45009' SET MYSQL_ERRNO=50009, MESSAGE_TEXT='Movement type, approved status, and destination mismatch'; END IF;
 -- Only recognized movement codes are seeded, so v_type cannot be an unexpected code.
END$$
DROP TRIGGER IF EXISTS trg_movement_after_insert$$
CREATE DEFINER='wr_owner'@'localhost' TRIGGER trg_movement_after_insert AFTER INSERT ON InventoryMovement
FOR EACH ROW
BEGIN
 DECLARE v_type VARCHAR(32);
 DECLARE v_target_status INT UNSIGNED DEFAULT NULL;
 SELECT Code INTO v_type FROM ReferenceValue
 WHERE ReferenceValueID=NEW.MovementTypeID AND Domain='MovementType';
 IF v_type='Relocate' THEN
  UPDATE ReturnItem SET CurrentLocationID=NEW.DestinationLocationID
  WHERE ReturnID=NEW.ReturnID AND LineNumber=NEW.LineNumber;
 ELSE
  SELECT ReferenceValueID INTO v_target_status FROM ReferenceValue
  WHERE Domain='ItemStatus' AND Code=CASE v_type WHEN 'Restock' THEN 'Restocked'
  WHEN 'Liquidate' THEN 'Liquidated' WHEN 'Dispose' THEN 'Disposed' END;
  IF v_target_status IS NULL THEN SIGNAL SQLSTATE '45500' SET MYSQL_ERRNO=50500, MESSAGE_TEXT='Missing terminal status'; END IF;
  UPDATE ReturnItem SET CurrentLocationID=NEW.DestinationLocationID,
  ItemStatusID=v_target_status,CompletionAt=NEW.MovedAt
  WHERE ReturnID=NEW.ReturnID AND LineNumber=NEW.LineNumber;
 END IF;
 INSERT INTO AuditLog(UserID,RecordedAt,Action,EntityName,RecordKey,OldValues,NewValues,TransactionID)
 VALUES (NEW.MovedByUserID,UTC_TIMESTAMP(6),'ITEM_MOVED','ReturnItem',
 JSON_OBJECT('ReturnID',NEW.ReturnID,'LineNumber',NEW.LineNumber),
 JSON_OBJECT('LocationID',NEW.SourceLocationID),
 JSON_OBJECT('LocationID',NEW.DestinationLocationID,'MovementType',v_type),fn_audit_transaction_id());
END$$

DROP TRIGGER IF EXISTS trg_auditlog_before_update$$
CREATE DEFINER='wr_owner'@'localhost' TRIGGER trg_auditlog_before_update BEFORE UPDATE ON AuditLog
FOR EACH ROW
BEGIN
 SIGNAL SQLSTATE '45500' SET MYSQL_ERRNO=50500, MESSAGE_TEXT='AuditLog is append-only: updates are not permitted';
END$$

DROP TRIGGER IF EXISTS trg_auditlog_before_delete$$
CREATE DEFINER='wr_owner'@'localhost' TRIGGER trg_auditlog_before_delete BEFORE DELETE ON AuditLog
FOR EACH ROW
BEGIN
 SIGNAL SQLSTATE '45500' SET MYSQL_ERRNO=50500, MESSAGE_TEXT='AuditLog is append-only: deletions are not permitted';
END$$
-- ---------------------------------------------------------------------------
-- FRD 5.1 / BR-10 reference administration guards (AC-10, AC-11).
-- Referenced rows cannot be recoded or moved to another domain; values needed by open work
-- or enabled transitions cannot be deactivated. Labels/descriptions stay editable. Deletes of
-- referenced rows are already blocked by ON DELETE RESTRICT foreign keys.

DROP TRIGGER IF EXISTS trg_referencevalue_guard_bu$$
CREATE DEFINER='wr_owner'@'localhost' TRIGGER trg_referencevalue_guard_bu BEFORE UPDATE ON ReferenceValue
FOR EACH ROW
BEGIN
 DECLARE v_open_use INT DEFAULT 0;
 IF NOT (BINARY NEW.Domain = BINARY OLD.Domain AND BINARY NEW.Code = BINARY OLD.Code) THEN
  -- Workflow codes (statuses, grades, types, dispositions...) are read by name in procedures
  -- and triggers: they change only through a design update. Only an unused ReturnReason may be recoded.
  IF OLD.Domain <> 'ReturnReason' OR NEW.Domain <> 'ReturnReason'
     OR EXISTS (SELECT 1 FROM ReturnItem WHERE ReturnReasonID = OLD.ReferenceValueID) THEN
   SIGNAL SQLSTATE '45009' SET MYSQL_ERRNO=50009, MESSAGE_TEXT='Referenced or workflow reference values cannot be recoded or moved to another domain';
  END IF;
 END IF;
 IF OLD.IsActive = 1 AND NEW.IsActive = 0 THEN
  IF OLD.Domain <> 'ReturnReason' THEN
   SIGNAL SQLSTATE '45009' SET MYSQL_ERRNO=50009, MESSAGE_TEXT='Workflow reference values are needed by enabled transitions and cannot be deactivated';
  END IF;
  SELECT COUNT(*) INTO v_open_use FROM ReturnItem
  WHERE ReturnReasonID = OLD.ReferenceValueID AND CompletionAt IS NULL;
  IF v_open_use > 0 THEN
   SIGNAL SQLSTATE '45009' SET MYSQL_ERRNO=50009, MESSAGE_TEXT='Return reason is used by open items and cannot be deactivated';
  END IF;
 END IF;
END$$

DROP TRIGGER IF EXISTS trg_location_guard_bu$$
CREATE DEFINER='wr_owner'@'localhost' TRIGGER trg_location_guard_bu BEFORE UPDATE ON Location
FOR EACH ROW
BEGIN
 IF NOT (BINARY NEW.LocationCode = BINARY OLD.LocationCode AND NEW.LocationTypeID = OLD.LocationTypeID)
    AND (EXISTS (SELECT 1 FROM ReturnItem WHERE CurrentLocationID = OLD.LocationID)
         OR EXISTS (SELECT 1 FROM InventoryMovement WHERE SourceLocationID = OLD.LocationID OR DestinationLocationID = OLD.LocationID)) THEN
  SIGNAL SQLSTATE '45009' SET MYSQL_ERRNO=50009, MESSAGE_TEXT='A referenced location cannot be recoded or change type';
 END IF;
 IF OLD.IsActive = 1 AND NEW.IsActive = 0
    AND EXISTS (SELECT 1 FROM ReturnItem WHERE CurrentLocationID = OLD.LocationID AND CompletionAt IS NULL) THEN
  SIGNAL SQLSTATE '45009' SET MYSQL_ERRNO=50009, MESSAGE_TEXT='Location holds open items and cannot be deactivated';
 END IF;
END$$

DROP TRIGGER IF EXISTS trg_appuser_guard_bu$$
CREATE DEFINER='wr_owner'@'localhost' TRIGGER trg_appuser_guard_bu BEFORE UPDATE ON AppUser
FOR EACH ROW
BEGIN
 -- The login is the link between a MySQL account and every recorded action.
 IF BINARY NEW.LoginIdentifier <> BINARY OLD.LoginIdentifier
    AND EXISTS (SELECT 1 FROM AuditLog WHERE UserID = OLD.UserID) THEN
  SIGNAL SQLSTATE '45009' SET MYSQL_ERRNO=50009, MESSAGE_TEXT='The login of a user with recorded activity cannot be changed';
 END IF;
 IF OLD.IsActive = 1 AND NEW.IsActive = 0
    AND EXISTS (SELECT 1 FROM WorkOrder w JOIN ReferenceValue s ON s.ReferenceValueID = w.WorkOrderStatusID
                WHERE w.AssignedTechnicianUserID = OLD.UserID AND s.Code IN ('Open','InProgress')) THEN
  SIGNAL SQLSTATE '45009' SET MYSQL_ERRNO=50009, MESSAGE_TEXT='User has active work orders and cannot be deactivated';
 END IF;
END$$

DROP TRIGGER IF EXISTS trg_role_guard_bu$$
CREATE DEFINER='wr_owner'@'localhost' TRIGGER trg_role_guard_bu BEFORE UPDATE ON Role
FOR EACH ROW
BEGIN
 -- Procedures check role codes by name; role permissions change only through a design update.
 IF BINARY NEW.RoleCode <> BINARY OLD.RoleCode THEN
  SIGNAL SQLSTATE '45009' SET MYSQL_ERRNO=50009, MESSAGE_TEXT='Role codes cannot be changed';
 END IF;
END$$
DELIMITER ;
