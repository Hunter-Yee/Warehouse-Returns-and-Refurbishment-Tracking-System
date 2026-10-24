-- Warehouse Returns: first controlled business procedures (MySQL 8.0.16+)
-- RUN AFTER schema, reference data and staff accounts; run before triggers.
-- IMPORTANT: USER() login must match an ACTIVE AppUser.LoginIdentifier.
-- Create separate limited local MySQL logins matching inspector01/manager01/receiving01.
-- Do not call as root for business-role testing. Direct table grants must be limited separately.
USE warehouse_returns_demo;
DELIMITER $$

DROP PROCEDURE IF EXISTS sp_record_initial_inspection$$
CREATE PROCEDURE sp_record_initial_inspection(
 IN p_return_id INT UNSIGNED,
 IN p_line_number SMALLINT UNSIGNED,
 IN p_grade_code VARCHAR(32),
 IN p_result_code VARCHAR(32),
 IN p_notes TEXT
)
SQL SECURITY DEFINER
BEGIN
 DECLARE v_actor INT UNSIGNED DEFAULT NULL;
 DECLARE v_status VARCHAR(32) DEFAULT NULL;
 DECLARE v_grade INT UNSIGNED DEFAULT NULL;
 DECLARE v_result INT UNSIGNED DEFAULT NULL;
 DECLARE v_type INT UNSIGNED DEFAULT NULL;
 DECLARE v_next_status INT UNSIGNED DEFAULT NULL;
 DECLARE v_inspection_id INT UNSIGNED DEFAULT NULL;
 DECLARE v_tx VARCHAR(64);
 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
 START TRANSACTION;
 SELECT u.UserID INTO v_actor FROM AppUser u
 JOIN UserRole ur ON ur.UserID=u.UserID
 JOIN Role r ON r.RoleID=ur.RoleID
 WHERE u.LoginIdentifier=SUBSTRING_INDEX(USER(),'@',1)
   AND u.IsActive=1 AND r.IsActive=1 AND r.RoleCode='Inspector'
 LIMIT 1;
 IF v_actor IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Active Inspector login required'; END IF;
 SELECT rv.Code INTO v_status FROM ReturnItem i
 JOIN ReferenceValue rv ON rv.ReferenceValueID=i.ItemStatusID AND rv.Domain='ItemStatus'
 WHERE i.ReturnID=p_return_id AND i.LineNumber=p_line_number FOR UPDATE;
 IF v_status IS NULL OR v_status <> 'AwaitingInspection' THEN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Item must be awaiting initial inspection';
 END IF;
 SELECT ReferenceValueID INTO v_grade FROM ReferenceValue
 WHERE Domain='ConditionGrade' AND Code=p_grade_code AND IsActive=1 LIMIT 1;
 SELECT ReferenceValueID INTO v_result FROM ReferenceValue
 WHERE Domain='InspectionResult' AND Code=p_result_code AND IsActive=1 LIMIT 1;
 SELECT ReferenceValueID INTO v_type FROM ReferenceValue
 WHERE Domain='InspectionType' AND Code='Initial' AND IsActive=1 LIMIT 1;
 IF v_grade IS NULL OR v_result IS NULL OR v_type IS NULL THEN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Invalid or inactive inspection reference value';
 END IF;
 INSERT INTO Inspection (ReturnID,LineNumber,InspectorUserID,InspectedAt,
 InspectionTypeID,ConditionGradeID,InspectionResultID,Notes,WorkOrderNumber)
 VALUES (p_return_id,p_line_number,v_actor,UTC_TIMESTAMP(6),v_type,v_grade,v_result,p_notes,NULL);
 SET v_inspection_id=LAST_INSERT_ID();
 SET v_tx=UUID();
 IF p_result_code IN ('Pass','Fail') THEN
  SELECT ReferenceValueID INTO v_next_status FROM ReferenceValue
  WHERE Domain='ItemStatus' AND Code='AwaitingDecision' AND IsActive=1 LIMIT 1;
  IF v_next_status IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Missing active AwaitingDecision status'; END IF;
  UPDATE ReturnItem SET ItemStatusID=v_next_status
  WHERE ReturnID=p_return_id AND LineNumber=p_line_number;
 END IF;
 INSERT INTO AuditLog(UserID,RecordedAt,Action,EntityName,RecordKey,OldValues,NewValues,TransactionID)
 VALUES (v_actor,UTC_TIMESTAMP(6),'INSPECTION_CREATED','Inspection',
 JSON_OBJECT('InspectionID',v_inspection_id),NULL,
 JSON_OBJECT('ReturnID',p_return_id,'LineNumber',p_line_number,'Grade',p_grade_code,
 'Result',p_result_code,'Type','Initial','NewItemStatus',IF(p_result_code='Inconclusive','AwaitingInspection','AwaitingDecision')),v_tx);
 COMMIT;
 SELECT v_inspection_id AS InspectionID;
END$$

DROP PROCEDURE IF EXISTS sp_approve_disposition$$
CREATE PROCEDURE sp_approve_disposition(
 IN p_return_id INT UNSIGNED, IN p_line_number SMALLINT UNSIGNED,
 IN p_outcome VARCHAR(32), IN p_amount DECIMAL(12,2)
)
SQL SECURITY DEFINER
BEGIN
 DECLARE v_actor INT UNSIGNED DEFAULT NULL;
 DECLARE v_status VARCHAR(32) DEFAULT NULL;
 DECLARE v_outcome_id INT UNSIGNED DEFAULT NULL;
 DECLARE v_new_status_id INT UNSIGNED DEFAULT NULL;
 DECLARE v_inspection_grade VARCHAR(32) DEFAULT NULL;
 DECLARE v_inspection_result VARCHAR(32) DEFAULT NULL;
 DECLARE v_inspection_type VARCHAR(32) DEFAULT NULL;
 DECLARE v_inspection_order INT UNSIGNED DEFAULT NULL;
 DECLARE v_latest_order INT UNSIGNED DEFAULT NULL;
 DECLARE v_tx VARCHAR(64);
 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
 START TRANSACTION;
 SELECT u.UserID INTO v_actor FROM AppUser u JOIN UserRole ur ON ur.UserID=u.UserID
 JOIN Role r ON r.RoleID=ur.RoleID
 WHERE u.LoginIdentifier=SUBSTRING_INDEX(USER(),'@',1) AND u.IsActive=1 AND r.IsActive=1
 AND r.RoleCode='Manager' LIMIT 1;
 IF v_actor IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Active Manager login required'; END IF;
 SELECT s.Code INTO v_status FROM ReturnItem i
 JOIN ReferenceValue s ON s.ReferenceValueID=i.ItemStatusID AND s.Domain='ItemStatus'
 WHERE i.ReturnID=p_return_id AND i.LineNumber=p_line_number FOR UPDATE;
 IF v_status IS NULL OR v_status <> 'AwaitingDecision' THEN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Item must await manager decision'; END IF;
 IF p_outcome NOT IN ('Repair','Restock','Liquidate','Dispose') OR p_amount IS NULL OR p_amount < 0 THEN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Invalid outcome or amount'; END IF;
 SELECT ReferenceValueID INTO v_outcome_id FROM ReferenceValue
 WHERE Domain='Disposition' AND Code=p_outcome AND IsActive=1 LIMIT 1;
 SELECT ReferenceValueID INTO v_new_status_id FROM ReferenceValue
 WHERE Domain='ItemStatus' AND Code=CASE p_outcome
 WHEN 'Repair' THEN 'ApprovedForRepair' WHEN 'Restock' THEN 'ApprovedForRestock'
 WHEN 'Liquidate' THEN 'ApprovedForLiquidation' WHEN 'Dispose' THEN 'ApprovedForDisposal' END
 AND IsActive=1 LIMIT 1;
 IF v_outcome_id IS NULL OR v_new_status_id IS NULL THEN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Missing active disposition/status'; END IF;
 -- Most recent inspection determines eligibility; tie-break on InspectionID.
 SELECT g.Code,res.Code,typ.Code,ins.WorkOrderNumber
 INTO v_inspection_grade,v_inspection_result,v_inspection_type,v_inspection_order
 FROM Inspection ins
 JOIN ReferenceValue g ON g.ReferenceValueID=ins.ConditionGradeID AND g.Domain='ConditionGrade'
 JOIN ReferenceValue res ON res.ReferenceValueID=ins.InspectionResultID AND res.Domain='InspectionResult'
 JOIN ReferenceValue typ ON typ.ReferenceValueID=ins.InspectionTypeID AND typ.Domain='InspectionType'
 WHERE ins.ReturnID=p_return_id AND ins.LineNumber=p_line_number
 ORDER BY ins.InspectedAt DESC,ins.InspectionID DESC LIMIT 1;
 IF v_inspection_result IS NULL OR v_inspection_result='Inconclusive' THEN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Conclusive inspection required'; END IF;
 IF p_outcome='Restock' AND (v_inspection_result<>'Pass' OR v_inspection_grade NOT IN ('A','B')) THEN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Restock requires latest Pass and grade A/B'; END IF;
 SELECT MAX(WorkOrderNumber) INTO v_latest_order FROM WorkOrder
 WHERE ReturnID=p_return_id AND LineNumber=p_line_number AND CompletedAt IS NOT NULL;
 IF p_outcome='Restock' AND v_latest_order IS NOT NULL
 AND (v_inspection_order IS NULL OR v_inspection_order<>v_latest_order
      OR v_inspection_type NOT IN ('PostRepair','Final')) THEN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Restock requires check of latest completed repair'; END IF;
 IF p_outcome='Repair' AND EXISTS (
   SELECT 1 FROM WorkOrder wo JOIN ReferenceValue ws ON ws.ReferenceValueID=wo.WorkOrderStatusID
   WHERE wo.ReturnID=p_return_id AND wo.LineNumber=p_line_number
     AND ws.Domain='WorkOrderStatus' AND ws.Code IN ('Open','InProgress')) THEN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Active repair order already exists'; END IF;
 UPDATE ReturnItem SET ItemStatusID=v_new_status_id,ApprovedOutcomeID=v_outcome_id,
 ApprovedByUserID=v_actor,ApprovedAt=UTC_TIMESTAMP(6),
 RestockEstimatedValue=IF(p_outcome='Restock',p_amount,NULL),
 LiquidationProceeds=IF(p_outcome='Liquidate',p_amount,NULL),
 DisposalCost=IF(p_outcome='Dispose',p_amount,NULL)
 WHERE ReturnID=p_return_id AND LineNumber=p_line_number;
 SET v_tx=UUID();
 INSERT INTO AuditLog(UserID,RecordedAt,Action,EntityName,RecordKey,OldValues,NewValues,TransactionID)
 VALUES (v_actor,UTC_TIMESTAMP(6),'DISPOSITION_APPROVED','ReturnItem',
 JSON_OBJECT('ReturnID',p_return_id,'LineNumber',p_line_number),
 JSON_OBJECT('ItemStatus','AwaitingDecision'),
 JSON_OBJECT('Outcome',p_outcome,'Amount',p_amount),v_tx);
 COMMIT;
END$$
DELIMITER ;

USE warehouse_returns_demo;
DELIMITER $$

DROP PROCEDURE IF EXISTS sp_assign_repair$$
CREATE PROCEDURE sp_assign_repair(IN p_return_id INT UNSIGNED, IN p_line SMALLINT UNSIGNED, IN p_technician_id INT UNSIGNED)
SQL SECURITY DEFINER
BEGIN
 DECLARE v_actor INT UNSIGNED DEFAULT NULL;
 DECLARE v_state VARCHAR(32) DEFAULT NULL;
 DECLARE v_open INT DEFAULT 0;
 DECLARE v_next INT UNSIGNED;
 DECLARE v_status_id INT UNSIGNED;
 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
 START TRANSACTION;
 SELECT u.UserID INTO v_actor FROM AppUser u JOIN UserRole ur ON ur.UserID=u.UserID JOIN Role r ON r.RoleID=ur.RoleID
 WHERE u.LoginIdentifier=SUBSTRING_INDEX(USER(),'@',1) AND u.IsActive=1 AND r.IsActive=1 AND r.RoleCode='Manager' LIMIT 1;
 IF v_actor IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Manager login required'; END IF;
 SELECT rv.Code INTO v_state FROM ReturnItem i JOIN ReferenceValue rv ON rv.ReferenceValueID=i.ItemStatusID
 WHERE i.ReturnID=p_return_id AND i.LineNumber=p_line FOR UPDATE;
 IF v_state IS NULL OR v_state <> 'ApprovedForRepair' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Item must be approved for repair'; END IF;
 IF NOT EXISTS (SELECT 1 FROM AppUser u JOIN UserRole ur ON ur.UserID=u.UserID JOIN Role r ON r.RoleID=ur.RoleID
 WHERE u.UserID=p_technician_id AND u.IsActive=1 AND r.RoleCode='Technician' AND r.IsActive=1)
 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Technician must be active and assigned Technician role'; END IF;
 SELECT COUNT(*) INTO v_open FROM WorkOrder w JOIN ReferenceValue s ON s.ReferenceValueID=w.WorkOrderStatusID
 WHERE w.ReturnID=p_return_id AND w.LineNumber=p_line AND s.Domain='WorkOrderStatus' AND s.Code IN ('Open','InProgress');
 IF v_open>0 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='An active work order already exists'; END IF;
 SELECT COALESCE(MAX(WorkOrderNumber),0)+1 INTO v_next FROM WorkOrder WHERE ReturnID=p_return_id AND LineNumber=p_line;
 SELECT ReferenceValueID INTO v_status_id FROM ReferenceValue WHERE Domain='WorkOrderStatus' AND Code='Open' AND IsActive=1;
 IF v_status_id IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Open status missing'; END IF;
 INSERT INTO WorkOrder(ReturnID,LineNumber,WorkOrderNumber,AssignedTechnicianUserID,WorkOrderStatusID,CreatedAt,TotalLaborCost,TotalPartsCost)
 VALUES(p_return_id,p_line,v_next,p_technician_id,v_status_id,UTC_TIMESTAMP(6),0,0);
 INSERT INTO AuditLog(UserID,RecordedAt,Action,EntityName,RecordKey,OldValues,NewValues,TransactionID)
 VALUES(v_actor,UTC_TIMESTAMP(6),'REPAIR_ASSIGNED','WorkOrder',JSON_OBJECT('ReturnID',p_return_id,'LineNumber',p_line,'WorkOrderNumber',v_next),NULL,
 JSON_OBJECT('TechnicianUserID',p_technician_id,'Status','Open'),UUID());
 COMMIT;
 SELECT v_next AS WorkOrderNumber;
END$$

DROP PROCEDURE IF EXISTS sp_start_repair$$
CREATE PROCEDURE sp_start_repair(IN p_return_id INT UNSIGNED, IN p_line SMALLINT UNSIGNED, IN p_order INT UNSIGNED)
SQL SECURITY DEFINER
BEGIN
 DECLARE v_actor INT UNSIGNED DEFAULT NULL; DECLARE v_state VARCHAR(32) DEFAULT NULL;
 DECLARE v_order_state VARCHAR(32) DEFAULT NULL; DECLARE v_owner INT UNSIGNED DEFAULT NULL;
 DECLARE v_wstatus INT UNSIGNED; DECLARE v_istatus INT UNSIGNED;
 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
 START TRANSACTION;
 SELECT u.UserID INTO v_actor FROM AppUser u JOIN UserRole ur ON ur.UserID=u.UserID JOIN Role r ON r.RoleID=ur.RoleID
 WHERE u.LoginIdentifier=SUBSTRING_INDEX(USER(),'@',1) AND u.IsActive=1 AND r.IsActive=1 AND r.RoleCode='Technician' LIMIT 1;
 IF v_actor IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Technician login required'; END IF;
 SELECT s.Code INTO v_state FROM ReturnItem i JOIN ReferenceValue s ON s.ReferenceValueID=i.ItemStatusID
 WHERE i.ReturnID=p_return_id AND i.LineNumber=p_line FOR UPDATE;
 SELECT w.AssignedTechnicianUserID, s.Code INTO v_owner,v_order_state FROM WorkOrder w
 JOIN ReferenceValue s ON s.ReferenceValueID=w.WorkOrderStatusID
 WHERE w.ReturnID=p_return_id AND w.LineNumber=p_line AND w.WorkOrderNumber=p_order FOR UPDATE;
 IF v_state IS NULL OR v_state <> 'ApprovedForRepair' OR v_owner IS NULL OR v_owner<>v_actor OR v_order_state<>'Open'
 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Order not open, assigned to actor, or item not repair-approved'; END IF;
 SELECT ReferenceValueID INTO v_wstatus FROM ReferenceValue WHERE Domain='WorkOrderStatus' AND Code='InProgress' AND IsActive=1;
 SELECT ReferenceValueID INTO v_istatus FROM ReferenceValue WHERE Domain='ItemStatus' AND Code='InRepair' AND IsActive=1;
 IF v_wstatus IS NULL OR v_istatus IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Required status missing'; END IF;
 UPDATE WorkOrder SET WorkOrderStatusID=v_wstatus,StartedAt=UTC_TIMESTAMP(6) WHERE ReturnID=p_return_id AND LineNumber=p_line AND WorkOrderNumber=p_order;
 UPDATE ReturnItem SET ItemStatusID=v_istatus WHERE ReturnID=p_return_id AND LineNumber=p_line;
 INSERT INTO AuditLog(UserID,RecordedAt,Action,EntityName,RecordKey,OldValues,NewValues,TransactionID)
 VALUES(v_actor,UTC_TIMESTAMP(6),'REPAIR_STARTED','WorkOrder',JSON_OBJECT('ReturnID',p_return_id,'LineNumber',p_line,'WorkOrderNumber',p_order),
 JSON_OBJECT('Status','Open'),JSON_OBJECT('Status','InProgress'),UUID());
 COMMIT;
END$$

DROP PROCEDURE IF EXISTS sp_complete_repair$$
CREATE PROCEDURE sp_complete_repair(IN p_return_id INT UNSIGNED, IN p_line SMALLINT UNSIGNED, IN p_order INT UNSIGNED,
 IN p_details TEXT, IN p_labor DECIMAL(12,2), IN p_parts DECIMAL(12,2))
SQL SECURITY DEFINER
BEGIN
 DECLARE v_actor INT UNSIGNED DEFAULT NULL; DECLARE v_state VARCHAR(32) DEFAULT NULL;
 DECLARE v_order_state VARCHAR(32) DEFAULT NULL; DECLARE v_owner INT UNSIGNED DEFAULT NULL;
 DECLARE v_wstatus INT UNSIGNED; DECLARE v_istatus INT UNSIGNED;
 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
 IF p_labor IS NULL OR p_parts IS NULL OR p_labor<0 OR p_parts<0 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Costs must be nonnegative'; END IF;
 START TRANSACTION;
 SELECT u.UserID INTO v_actor FROM AppUser u JOIN UserRole ur ON ur.UserID=u.UserID JOIN Role r ON r.RoleID=ur.RoleID
 WHERE u.LoginIdentifier=SUBSTRING_INDEX(USER(),'@',1) AND u.IsActive=1 AND r.IsActive=1 AND r.RoleCode='Technician' LIMIT 1;
 IF v_actor IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Technician login required'; END IF;
 SELECT s.Code INTO v_state FROM ReturnItem i JOIN ReferenceValue s ON s.ReferenceValueID=i.ItemStatusID
 WHERE i.ReturnID=p_return_id AND i.LineNumber=p_line FOR UPDATE;
 SELECT w.AssignedTechnicianUserID,s.Code INTO v_owner,v_order_state FROM WorkOrder w
 JOIN ReferenceValue s ON s.ReferenceValueID=w.WorkOrderStatusID
 WHERE w.ReturnID=p_return_id AND w.LineNumber=p_line AND w.WorkOrderNumber=p_order FOR UPDATE;
 IF v_state IS NULL OR v_state<>'InRepair' OR v_owner IS NULL OR v_owner<>v_actor OR v_order_state<>'InProgress'
 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Only assigned technician can complete an in-progress order'; END IF;
 SELECT ReferenceValueID INTO v_wstatus FROM ReferenceValue WHERE Domain='WorkOrderStatus' AND Code='Completed' AND IsActive=1;
 SELECT ReferenceValueID INTO v_istatus FROM ReferenceValue WHERE Domain='ItemStatus' AND Code='AwaitingFinalInspection' AND IsActive=1;
 IF v_wstatus IS NULL OR v_istatus IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Required status missing'; END IF;
 UPDATE WorkOrder SET WorkOrderStatusID=v_wstatus,CompletedAt=UTC_TIMESTAMP(6),WorkDetails=p_details,TotalLaborCost=p_labor,TotalPartsCost=p_parts
 WHERE ReturnID=p_return_id AND LineNumber=p_line AND WorkOrderNumber=p_order;
 UPDATE ReturnItem SET ItemStatusID=v_istatus WHERE ReturnID=p_return_id AND LineNumber=p_line;
 INSERT INTO AuditLog(UserID,RecordedAt,Action,EntityName,RecordKey,OldValues,NewValues,TransactionID)
 VALUES(v_actor,UTC_TIMESTAMP(6),'REPAIR_COMPLETED','WorkOrder',JSON_OBJECT('ReturnID',p_return_id,'LineNumber',p_line,'WorkOrderNumber',p_order),
 JSON_OBJECT('Status','InProgress'),JSON_OBJECT('Status','Completed','Labor',p_labor,'Parts',p_parts),UUID());
 COMMIT;
END$$

DROP PROCEDURE IF EXISTS sp_record_postrepair_inspection$$
CREATE PROCEDURE sp_record_postrepair_inspection(IN p_return_id INT UNSIGNED, IN p_line SMALLINT UNSIGNED,
 IN p_order INT UNSIGNED, IN p_grade VARCHAR(32), IN p_result VARCHAR(32), IN p_notes TEXT)
SQL SECURITY DEFINER
BEGIN
 DECLARE v_actor INT UNSIGNED DEFAULT NULL; DECLARE v_state VARCHAR(32) DEFAULT NULL;
 DECLARE v_order_completed DATETIME(6) DEFAULT NULL; DECLARE v_latest INT UNSIGNED DEFAULT NULL;
 DECLARE v_grade_id INT UNSIGNED DEFAULT NULL; DECLARE v_result_id INT UNSIGNED DEFAULT NULL;
 DECLARE v_type_id INT UNSIGNED DEFAULT NULL; DECLARE v_next INT UNSIGNED DEFAULT NULL;
 DECLARE v_inspection INT UNSIGNED;
 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
 START TRANSACTION;
 SELECT u.UserID INTO v_actor FROM AppUser u JOIN UserRole ur ON ur.UserID=u.UserID JOIN Role r ON r.RoleID=ur.RoleID
 WHERE u.LoginIdentifier=SUBSTRING_INDEX(USER(),'@',1) AND u.IsActive=1 AND r.IsActive=1 AND r.RoleCode='Inspector' LIMIT 1;
 IF v_actor IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Inspector login required'; END IF;
 SELECT s.Code INTO v_state FROM ReturnItem i JOIN ReferenceValue s ON s.ReferenceValueID=i.ItemStatusID
 WHERE i.ReturnID=p_return_id AND i.LineNumber=p_line FOR UPDATE;
 IF v_state IS NULL OR v_state<>'AwaitingFinalInspection' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Item not awaiting repair inspection'; END IF;
 SELECT CompletedAt INTO v_order_completed FROM WorkOrder WHERE ReturnID=p_return_id AND LineNumber=p_line AND WorkOrderNumber=p_order;
 SELECT WorkOrderNumber INTO v_latest FROM WorkOrder WHERE ReturnID=p_return_id AND LineNumber=p_line AND CompletedAt IS NOT NULL
 ORDER BY CompletedAt DESC, WorkOrderNumber DESC LIMIT 1;
 IF v_order_completed IS NULL OR v_latest IS NULL OR v_latest<>p_order THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Inspection must reference latest completed order'; END IF;
 SELECT ReferenceValueID INTO v_grade_id FROM ReferenceValue WHERE Domain='ConditionGrade' AND Code=p_grade AND IsActive=1;
 SELECT ReferenceValueID INTO v_result_id FROM ReferenceValue WHERE Domain='InspectionResult' AND Code=p_result AND IsActive=1;
 SELECT ReferenceValueID INTO v_type_id FROM ReferenceValue WHERE Domain='InspectionType' AND Code='PostRepair' AND IsActive=1;
 IF v_grade_id IS NULL OR v_result_id IS NULL OR v_type_id IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Invalid inspection grade/result/type'; END IF;
 INSERT INTO Inspection(ReturnID,LineNumber,InspectorUserID,InspectedAt,InspectionTypeID,ConditionGradeID,InspectionResultID,Notes,WorkOrderNumber)
 VALUES(p_return_id,p_line,v_actor,UTC_TIMESTAMP(6),v_type_id,v_grade_id,v_result_id,p_notes,p_order);
 SET v_inspection=LAST_INSERT_ID();
 IF p_result IN ('Pass','Fail') THEN
 SELECT ReferenceValueID INTO v_next FROM ReferenceValue WHERE Domain='ItemStatus' AND Code='AwaitingDecision' AND IsActive=1;
 IF v_next IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='AwaitingDecision status missing'; END IF;
 UPDATE ReturnItem SET ItemStatusID=v_next WHERE ReturnID=p_return_id AND LineNumber=p_line;
 END IF;
 INSERT INTO AuditLog(UserID,RecordedAt,Action,EntityName,RecordKey,OldValues,NewValues,TransactionID)
 VALUES(v_actor,UTC_TIMESTAMP(6),'INSPECTION_CREATED','Inspection',JSON_OBJECT('InspectionID',v_inspection),NULL,
 JSON_OBJECT('Type','PostRepair','WorkOrderNumber',p_order,'Result',p_result,'Grade',p_grade),UUID());
 COMMIT;
 SELECT v_inspection AS InspectionID;
END$$

DROP PROCEDURE IF EXISTS sp_move_item$$
CREATE PROCEDURE sp_move_item(IN p_return_id INT UNSIGNED, IN p_line SMALLINT UNSIGNED,
 IN p_source INT UNSIGNED, IN p_destination INT UNSIGNED, IN p_type VARCHAR(32), IN p_notes TEXT)
SQL SECURITY DEFINER
BEGIN
 DECLARE v_actor INT UNSIGNED DEFAULT NULL; DECLARE v_movement_id BIGINT UNSIGNED;
 DECLARE v_current INT UNSIGNED DEFAULT NULL; DECLARE v_move_type INT UNSIGNED DEFAULT NULL;
 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
 START TRANSACTION;
 SELECT u.UserID INTO v_actor FROM AppUser u JOIN UserRole ur ON ur.UserID=u.UserID JOIN Role r ON r.RoleID=ur.RoleID
 WHERE u.LoginIdentifier=SUBSTRING_INDEX(USER(),'@',1) AND u.IsActive=1 AND r.IsActive=1 AND r.RoleCode='Receiving' LIMIT 1;
 IF v_actor IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Receiving login required'; END IF;
 SELECT CurrentLocationID INTO v_current FROM ReturnItem WHERE ReturnID=p_return_id AND LineNumber=p_line FOR UPDATE;
 IF v_current IS NULL OR v_current<>p_source OR p_source=p_destination THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Invalid item/source/destination'; END IF;
 SELECT ReferenceValueID INTO v_move_type FROM ReferenceValue WHERE Domain='MovementType' AND Code=p_type AND IsActive=1;
 IF v_move_type IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Invalid movement type'; END IF;
 -- BEFORE/AFTER triggers perform final destination/status checks, location update, and movement audit.
 INSERT INTO InventoryMovement(ReturnID,LineNumber,SourceLocationID,DestinationLocationID,MovedAt,MovedByUserID,MovementTypeID,Notes)
 VALUES(p_return_id,p_line,p_source,p_destination,UTC_TIMESTAMP(6),v_actor,v_move_type,p_notes);
 SET v_movement_id=LAST_INSERT_ID();
 COMMIT;
 SELECT v_movement_id AS MovementID;
END$$

DROP PROCEDURE IF EXISTS sp_submit_claim$$
CREATE PROCEDURE sp_submit_claim(IN p_return_id INT UNSIGNED, IN p_line SMALLINT UNSIGNED,
 IN p_requested DECIMAL(12,2), IN p_reference VARCHAR(150))
SQL SECURITY DEFINER
BEGIN
 DECLARE v_actor INT UNSIGNED DEFAULT NULL; DECLARE v_completed DATETIME(6);
 DECLARE v_vendor INT UNSIGNED; DECLARE v_status INT UNSIGNED;
 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
 IF p_requested IS NULL OR p_requested<=0 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Claim amount must be positive'; END IF;
 START TRANSACTION;
 SELECT u.UserID INTO v_actor FROM AppUser u JOIN UserRole ur ON ur.UserID=u.UserID JOIN Role r ON r.RoleID=ur.RoleID
 WHERE u.LoginIdentifier=SUBSTRING_INDEX(USER(),'@',1) AND u.IsActive=1 AND r.IsActive=1 AND r.RoleCode='Manager' LIMIT 1;
 IF v_actor IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Manager login required'; END IF;
 SELECT i.CompletionAt,p.VendorID INTO v_completed,v_vendor FROM ReturnItem i JOIN Product p ON p.ProductID=i.ProductID
 WHERE i.ReturnID=p_return_id AND i.LineNumber=p_line FOR UPDATE;
 IF v_vendor IS NULL OR v_completed IS NOT NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Cannot claim missing or closed item'; END IF;
 SELECT ReferenceValueID INTO v_status FROM ReferenceValue WHERE Domain='ClaimStatus' AND Code='Submitted' AND IsActive=1;
 IF v_status IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Submitted status missing'; END IF;
 INSERT INTO VendorClaim(ReturnID,LineNumber,VendorID,RequestedAmount,ClaimStatusID,SubmittedAt,RecordedByUserID,ClaimReference)
 VALUES(p_return_id,p_line,v_vendor,p_requested,v_status,UTC_TIMESTAMP(6),v_actor,p_reference);
 INSERT INTO AuditLog(UserID,RecordedAt,Action,EntityName,RecordKey,OldValues,NewValues,TransactionID)
 VALUES(v_actor,UTC_TIMESTAMP(6),'CLAIM_SUBMITTED','VendorClaim',JSON_OBJECT('ClaimID',LAST_INSERT_ID()),NULL,
 JSON_OBJECT('ReturnID',p_return_id,'LineNumber',p_line,'RequestedAmount',p_requested),UUID());
 COMMIT;
END$$

DROP PROCEDURE IF EXISTS sp_approve_claim$$
CREATE PROCEDURE sp_approve_claim(IN p_claim_id INT UNSIGNED)
SQL SECURITY DEFINER
BEGIN
 DECLARE v_actor INT UNSIGNED DEFAULT NULL; DECLARE v_old VARCHAR(32) DEFAULT NULL; DECLARE v_new INT UNSIGNED;
 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
 START TRANSACTION;
 SELECT u.UserID INTO v_actor FROM AppUser u JOIN UserRole ur ON ur.UserID=u.UserID JOIN Role r ON r.RoleID=ur.RoleID
 WHERE u.LoginIdentifier=SUBSTRING_INDEX(USER(),'@',1) AND u.IsActive=1 AND r.IsActive=1 AND r.RoleCode='Manager' LIMIT 1;
 IF v_actor IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Manager login required'; END IF;
 SELECT s.Code INTO v_old FROM VendorClaim c JOIN ReferenceValue s ON s.ReferenceValueID=c.ClaimStatusID WHERE c.ClaimID=p_claim_id FOR UPDATE;
 IF v_old IS NULL OR v_old<>'Submitted' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Only submitted claims can be approved'; END IF;
 SELECT ReferenceValueID INTO v_new FROM ReferenceValue WHERE Domain='ClaimStatus' AND Code='Approved' AND IsActive=1;
 UPDATE VendorClaim SET ClaimStatusID=v_new WHERE ClaimID=p_claim_id;
 INSERT INTO AuditLog(UserID,RecordedAt,Action,EntityName,RecordKey,OldValues,NewValues,TransactionID)
 VALUES(v_actor,UTC_TIMESTAMP(6),'CLAIM_APPROVED','VendorClaim',JSON_OBJECT('ClaimID',p_claim_id),JSON_OBJECT('Status','Submitted'),JSON_OBJECT('Status','Approved'),UUID());
 COMMIT;
END$$

DROP PROCEDURE IF EXISTS sp_settle_claim$$
CREATE PROCEDURE sp_settle_claim(IN p_claim_id INT UNSIGNED, IN p_amount DECIMAL(12,2))
SQL SECURITY DEFINER
BEGIN
 DECLARE v_actor INT UNSIGNED DEFAULT NULL; DECLARE v_old VARCHAR(32) DEFAULT NULL; DECLARE v_new INT UNSIGNED;
 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
 IF p_amount IS NULL OR p_amount<=0 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Settlement must be positive'; END IF;
 START TRANSACTION;
 SELECT u.UserID INTO v_actor FROM AppUser u JOIN UserRole ur ON ur.UserID=u.UserID JOIN Role r ON r.RoleID=ur.RoleID
 WHERE u.LoginIdentifier=SUBSTRING_INDEX(USER(),'@',1) AND u.IsActive=1 AND r.IsActive=1 AND r.RoleCode='Manager' LIMIT 1;
 IF v_actor IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Manager login required'; END IF;
 SELECT s.Code INTO v_old FROM VendorClaim c JOIN ReferenceValue s ON s.ReferenceValueID=c.ClaimStatusID WHERE c.ClaimID=p_claim_id FOR UPDATE;
 IF v_old IS NULL OR v_old<>'Approved' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Only approved claims can settle'; END IF;
 SELECT ReferenceValueID INTO v_new FROM ReferenceValue WHERE Domain='ClaimStatus' AND Code='Settled' AND IsActive=1;
 UPDATE VendorClaim SET ClaimStatusID=v_new,SettlementAmount=p_amount,SettledAt=UTC_TIMESTAMP(6) WHERE ClaimID=p_claim_id;
 INSERT INTO AuditLog(UserID,RecordedAt,Action,EntityName,RecordKey,OldValues,NewValues,TransactionID)
 VALUES(v_actor,UTC_TIMESTAMP(6),'CLAIM_SETTLED','VendorClaim',JSON_OBJECT('ClaimID',p_claim_id),JSON_OBJECT('Status','Approved'),JSON_OBJECT('Status','Settled','Amount',p_amount),UUID());
 COMMIT;
END$$
DELIMITER ;
