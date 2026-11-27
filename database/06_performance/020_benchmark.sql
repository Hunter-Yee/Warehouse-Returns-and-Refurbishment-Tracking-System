-- Scaled performance benchmark (NOT in database/manifest.txt).
-- Run AFTER 010_load_scale_data.sql on the same scratch schema, as the setup account.
-- Read-only except test 6, which rolls back. Requires MySQL 8.0.18+ (EXPLAIN ANALYZE).
-- EXPLAIN ANALYZE executes the query and reports actual time and rows per plan step:
--   "actual time=A..B rows=R loops=L" -> B is ms to the last row, R rows produced.
-- Run twice and keep the second run: the first may include cold buffer-pool reads.
SET time_zone = '+00:00';

SELECT VERSION() AS mysql_version, DATABASE() AS schema_name, UTC_TIMESTAMP() AS run_at_utc;

-- The tuning index must exist (added with the RQ-02 audit index commit).
SELECT COUNT(*) AS ix_audit_entity_record_columns FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'AuditLog' AND INDEX_NAME = 'ix_audit_entity_record';

SELECT 'ReturnHeader' AS table_name, COUNT(*) AS row_count FROM ReturnHeader
UNION ALL SELECT 'ReturnItem', COUNT(*) FROM ReturnItem
UNION ALL SELECT 'AuditLog', COUNT(*) FROM AuditLog
UNION ALL SELECT 'AuditLog (ReturnItem entity)', COUNT(*) FROM AuditLog WHERE EntityName = 'ReturnItem';

-- Benchmark target: a completed unit in the middle of the PERF range (6 audit events).
SELECT ri.ReturnID, ri.LineNumber INTO @report_return_id, @report_line_no
FROM ReturnItem ri JOIN ReturnHeader h ON h.ReturnID = ri.ReturnID
WHERE h.ExternalReference LIKE 'PERF-%' AND ri.CompletionAt IS NOT NULL
  AND ri.ReturnID >= (SELECT (MIN(ReturnID) + MAX(ReturnID)) DIV 2 FROM ReturnHeader
                      WHERE ExternalReference LIKE 'PERF-%')
ORDER BY ri.ReturnID, ri.LineNumber LIMIT 1;
SELECT @report_return_id AS BenchReturnID, @report_line_no AS BenchLineNumber;

-- ---------------------------------------------------------------------------
-- Test 1  RQ-02 audit branch, BEFORE: JSON expression filter (original query).
-- Expected: index on EntityName only, then a JSON parse on every ReturnItem audit row.
EXPLAIN ANALYZE
SELECT a.RecordedAt, a.Action, a.EntityName
FROM AuditLog a
WHERE a.EntityName = 'ReturnItem'
  AND JSON_UNQUOTE(JSON_EXTRACT(a.RecordKey, '$.ReturnID')) = CAST(@report_return_id AS CHAR)
  AND JSON_UNQUOTE(JSON_EXTRACT(a.RecordKey, '$.LineNumber')) = CAST(@report_line_no AS CHAR)
ORDER BY a.RecordedAt;

-- Test 2  RQ-02 audit branch, AFTER: generated key columns + ix_audit_entity_record.
-- Expected: index lookup on ix_audit_entity_record, rows ~= this unit's events, no sort.
EXPLAIN ANALYZE
SELECT a.RecordedAt, a.Action, a.EntityName
FROM AuditLog a
WHERE a.EntityName = 'ReturnItem'
  AND a.AuditReturnID = @report_return_id
  AND a.AuditLineNumber = @report_line_no
ORDER BY a.RecordedAt;

-- Test 3  Control: same query as Test 2 with the new index ignored. Shows that the
-- speed-up comes from the index, not from the generated columns alone.
EXPLAIN ANALYZE
SELECT a.RecordedAt, a.Action, a.EntityName
FROM AuditLog a IGNORE INDEX (ix_audit_entity_record)
WHERE a.EntityName = 'ReturnItem'
  AND a.AuditReturnID = @report_return_id
  AND a.AuditLineNumber = @report_line_no
ORDER BY a.RecordedAt;

-- Correctness: BEFORE and AFTER filters must return the same rows.
SELECT
 (SELECT COUNT(*) FROM AuditLog a WHERE a.EntityName = 'ReturnItem'
   AND JSON_UNQUOTE(JSON_EXTRACT(a.RecordKey, '$.ReturnID')) = CAST(@report_return_id AS CHAR)
   AND JSON_UNQUOTE(JSON_EXTRACT(a.RecordKey, '$.LineNumber')) = CAST(@report_line_no AS CHAR)) AS BeforeRows,
 (SELECT COUNT(*) FROM AuditLog a WHERE a.EntityName = 'ReturnItem'
   AND a.AuditReturnID = @report_return_id AND a.AuditLineNumber = @report_line_no) AS AfterRows,
 (SELECT COUNT(*) FROM AuditLog a
   WHERE JSON_UNQUOTE(JSON_EXTRACT(a.RecordKey, '$.ReturnID')) IS NOT NULL
     AND (a.AuditReturnID IS NULL
          OR CAST(a.AuditReturnID AS CHAR) <> JSON_UNQUOTE(JSON_EXTRACT(a.RecordKey, '$.ReturnID')))) AS MismatchedGeneratedKeys;
-- Expected: BeforeRows = AfterRows, MismatchedGeneratedKeys = 0.

-- ---------------------------------------------------------------------------
-- Test 4  Full RQ-02 item timeline (as in 030_smoke_tests.sql) at scale.
EXPLAIN ANALYZE
SELECT x.EventTime, x.EventType, x.EventDetails, x.StaffName FROM (
 SELECT i.InspectedAt AS EventTime, 'Inspection' AS EventType,
        CONCAT(t.Code, ': ', result.Code, ', grade ', grade.Code) AS EventDetails,
        u.DisplayName AS StaffName, 1 AS TieBreak, CAST(i.InspectionID AS CHAR) AS EventID
 FROM Inspection i
 JOIN ReferenceValue t ON t.ReferenceValueID = i.InspectionTypeID
 JOIN ReferenceValue result ON result.ReferenceValueID = i.InspectionResultID
 JOIN ReferenceValue grade ON grade.ReferenceValueID = i.ConditionGradeID
 JOIN AppUser u ON u.UserID = i.InspectorUserID
 WHERE i.ReturnID = @report_return_id AND i.LineNumber = @report_line_no
 UNION ALL
 SELECT w.CreatedAt, 'Repair assigned', CONCAT('Order ',w.WorkOrderNumber),
        u.DisplayName, 2, CAST(w.WorkOrderNumber AS CHAR)
 FROM WorkOrder w JOIN AppUser u ON u.UserID = w.AssignedTechnicianUserID
 WHERE w.ReturnID = @report_return_id AND w.LineNumber = @report_line_no
 UNION ALL
 SELECT m.MovedAt, 'Movement', CONCAT(src.LocationCode,' -> ',dst.LocationCode),
        u.DisplayName, 3, CAST(m.MovementID AS CHAR)
 FROM InventoryMovement m
 JOIN Location src ON src.LocationID=m.SourceLocationID
 JOIN Location dst ON dst.LocationID=m.DestinationLocationID
 JOIN AppUser u ON u.UserID=m.MovedByUserID
 WHERE m.ReturnID = @report_return_id AND m.LineNumber = @report_line_no
 UNION ALL
 SELECT a.RecordedAt, a.Action, a.EntityName, u.DisplayName, 4, CAST(a.AuditID AS CHAR)
 FROM AuditLog a JOIN AppUser u ON u.UserID=a.UserID
 WHERE a.EntityName='ReturnItem'
   AND a.AuditReturnID=@report_return_id
   AND a.AuditLineNumber=@report_line_no
) x
ORDER BY x.EventTime, x.TieBreak, x.EventID;

-- Test 5  RQ-01 open returns, oldest first (the EXPLAIN ANALYZE that was commented out).
EXPLAIN ANALYZE SELECT * FROM vw_open_items ORDER BY ReceivedAt, ReturnID, LineNumber;

-- Test 5b RQ-04 recovery for one completion month.
SET @period_start = '2026-10-01 00:00:00';
SET @period_end = '2026-11-01 00:00:00';
EXPLAIN ANALYZE
SELECT FinalOutcome, COUNT(*) AS CompletedItems, SUM(NetRecovery) AS TotalNetRecovery
FROM vw_item_recovery
WHERE CompletionAt >= @period_start AND CompletionAt < @period_end
GROUP BY FinalOutcome;

-- ---------------------------------------------------------------------------
-- Test 6  Write cost: insert 10,000 audit rows (maintains all AuditLog indexes,
-- including the new one), time it, then ROLLBACK so nothing is kept.
START TRANSACTION;
SET @t0 = NOW(6);
INSERT INTO AuditLog (UserID, RecordedAt, Action, EntityName, RecordKey, OldValues, NewValues, TransactionID)
SELECT a.UserID, a.RecordedAt, a.Action, a.EntityName, a.RecordKey, NULL,
       JSON_OBJECT('WriteCostTest', TRUE), UUID()
FROM AuditLog a ORDER BY a.AuditID LIMIT 10000;
SELECT ROW_COUNT() AS RowsInserted, TIMESTAMPDIFF(MICROSECOND, @t0, NOW(6)) / 1000 AS InsertMs;
ROLLBACK;

-- Storage cost of each AuditLog index (InnoDB persistent stats; run after ANALYZE TABLE).
SELECT index_name, ROUND(stat_value * @@innodb_page_size / 1024 / 1024, 2) AS size_mb
FROM mysql.innodb_index_stats
WHERE database_name = DATABASE() AND LOWER(table_name) = 'auditlog' AND stat_name = 'size' -- macOS stores lowercase names
ORDER BY index_name;
