-- First movement triggers. Install AFTER procedures; test with a dedicated Receiving MySQL login.
-- Warning: the trigger processes one row; multi-step atomicity still requires the caller's transaction.
-- Do not grant application users direct INSERT on InventoryMovement in the final release.
-- Replace direct insert demonstrations with a controlled movement procedure before final submission.
DELIMITER $$
DROP TRIGGER IF EXISTS trg_movement_before_insert$$
CREATE TRIGGER trg_movement_before_insert BEFORE INSERT ON InventoryMovement
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
 IF v_actor_role_count=0 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Active Receiving login required'; END IF;
 SELECT i.CurrentLocationID,i.CompletionAt,s.Code INTO v_location,v_completed,v_status
 FROM ReturnItem i JOIN ReferenceValue s ON s.ReferenceValueID=i.ItemStatusID
 WHERE i.ReturnID=NEW.ReturnID AND i.LineNumber=NEW.LineNumber FOR UPDATE;
 IF v_location IS NULL OR v_completed IS NOT NULL OR v_location<>NEW.SourceLocationID THEN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Closed item, missing item, or stale source location'; END IF;
 SELECT mt.Code INTO v_type FROM ReferenceValue mt
 WHERE mt.ReferenceValueID=NEW.MovementTypeID AND mt.Domain='MovementType' AND mt.IsActive=1;
 SELECT lt.Code INTO v_destination_type FROM Location l JOIN ReferenceValue lt
 ON lt.ReferenceValueID=l.LocationTypeID AND lt.Domain='LocationType' AND lt.IsActive=1
 WHERE l.LocationID=NEW.DestinationLocationID AND l.IsActive=1;
 IF v_type IS NULL OR v_destination_type IS NULL THEN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Inactive/incorrect movement type or destination'; END IF;
 IF (v_type='Restock' AND (v_status<>'ApprovedForRestock' OR v_destination_type<>'SaleableStock'))
 OR (v_type='Liquidate' AND (v_status<>'ApprovedForLiquidation' OR v_destination_type<>'LiquidationExit'))
 OR (v_type='Dispose' AND (v_status<>'ApprovedForDisposal' OR v_destination_type<>'DisposalExit'))
 OR (v_type='Relocate' AND v_destination_type IN ('SaleableStock','LiquidationExit','DisposalExit')) THEN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Movement type, approved status, and destination mismatch'; END IF;
 -- Only recognized movement codes are seeded, so v_type cannot be an unexpected code.
END$$
DROP TRIGGER IF EXISTS trg_movement_after_insert$$
CREATE TRIGGER trg_movement_after_insert AFTER INSERT ON InventoryMovement
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
  IF v_target_status IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Missing terminal status'; END IF;
  UPDATE ReturnItem SET CurrentLocationID=NEW.DestinationLocationID,
  ItemStatusID=v_target_status,CompletionAt=NEW.MovedAt
  WHERE ReturnID=NEW.ReturnID AND LineNumber=NEW.LineNumber;
 END IF;
 INSERT INTO AuditLog(UserID,RecordedAt,Action,EntityName,RecordKey,OldValues,NewValues,TransactionID)
 VALUES (NEW.MovedByUserID,UTC_TIMESTAMP(6),'ITEM_MOVED','ReturnItem',
 JSON_OBJECT('ReturnID',NEW.ReturnID,'LineNumber',NEW.LineNumber),
 JSON_OBJECT('LocationID',NEW.SourceLocationID),
 JSON_OBJECT('LocationID',NEW.DestinationLocationID,'MovementType',v_type),UUID());
END$$
DELIMITER ;
