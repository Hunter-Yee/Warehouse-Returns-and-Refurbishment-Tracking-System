-- Verify required objects are present. Query results are evidence; inspect expected counts.
USE warehouse_returns_demo;

-- 1. Base tables verification (expected: 15 tables)
SELECT COUNT(*) AS BaseTableCount FROM information_schema.TABLES
 WHERE TABLE_SCHEMA=DATABASE() AND TABLE_TYPE='BASE TABLE';
SELECT TABLE_NAME FROM information_schema.TABLES
 WHERE TABLE_SCHEMA=DATABASE() AND TABLE_TYPE='BASE TABLE' ORDER BY TABLE_NAME;

-- 2. Views verification (expected: 2 views after 010_views.sql)
SELECT COUNT(*) AS ViewCount FROM information_schema.VIEWS
 WHERE TABLE_SCHEMA=DATABASE();
SELECT TABLE_NAME AS ViewName FROM information_schema.VIEWS
 WHERE TABLE_SCHEMA=DATABASE() ORDER BY TABLE_NAME;

-- 3. Constraints and Indexes
SELECT TABLE_NAME,CONSTRAINT_NAME,CONSTRAINT_TYPE
 FROM information_schema.TABLE_CONSTRAINTS WHERE TABLE_SCHEMA=DATABASE()
 ORDER BY TABLE_NAME,CONSTRAINT_TYPE,CONSTRAINT_NAME;
SELECT TABLE_NAME,INDEX_NAME,COLUMN_NAME,SEQ_IN_INDEX
 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA=DATABASE()
 ORDER BY TABLE_NAME,INDEX_NAME,SEQ_IN_INDEX;

-- 4. Routines (Stored Procedures) verification
SELECT ROUTINE_NAME,ROUTINE_TYPE FROM information_schema.ROUTINES
 WHERE ROUTINE_SCHEMA=DATABASE() ORDER BY ROUTINE_NAME;

-- Phase 3 Procedures (sp_record_initial_inspection, sp_approve_disposition)
SELECT ROUTINE_NAME,ROUTINE_TYPE FROM information_schema.ROUTINES
 WHERE ROUTINE_SCHEMA=DATABASE() AND ROUTINE_NAME IN
 ('sp_record_initial_inspection','sp_approve_disposition') ORDER BY ROUTINE_NAME;

-- Phase 4 Procedures (8 additional operations)
SELECT ROUTINE_NAME, ROUTINE_TYPE FROM information_schema.ROUTINES
 WHERE ROUTINE_SCHEMA=DATABASE() AND ROUTINE_NAME IN
 ('sp_assign_repair','sp_start_repair','sp_complete_repair','sp_record_postrepair_inspection',
 'sp_move_item','sp_submit_claim','sp_approve_claim','sp_settle_claim') ORDER BY ROUTINE_NAME;

-- 5. Triggers verification
SELECT TRIGGER_NAME,EVENT_OBJECT_TABLE,EVENT_MANIPULATION,ACTION_TIMING FROM information_schema.TRIGGERS
 WHERE TRIGGER_SCHEMA=DATABASE() ORDER BY TRIGGER_NAME;
SELECT TRIGGER_NAME,EVENT_MANIPULATION,ACTION_TIMING FROM information_schema.TRIGGERS
 WHERE TRIGGER_SCHEMA=DATABASE() AND TRIGGER_NAME IN
 ('trg_movement_before_insert','trg_movement_after_insert') ORDER BY TRIGGER_NAME;

-- 6. Operational row metrics
SELECT 'Repair order rows' AS metric,COUNT(*) AS total FROM WorkOrder
UNION ALL SELECT 'Vendor claim rows',COUNT(*) FROM VendorClaim
UNION ALL SELECT 'Movement rows',COUNT(*) FROM InventoryMovement;

-- 7. Workflow check: return items and inspection counts
SELECT i.ReturnID,i.LineNumber,s.Code AS ItemStatus,COUNT(ins.InspectionID) AS Inspections
 FROM ReturnItem i JOIN ReferenceValue s ON s.ReferenceValueID=i.ItemStatusID
 LEFT JOIN Inspection ins ON ins.ReturnID=i.ReturnID AND ins.LineNumber=i.LineNumber
 GROUP BY i.ReturnID,i.LineNumber,s.Code ORDER BY i.ReturnID,i.LineNumber;
