-- Safe read-only smoke tests. These do not change sample data.
SELECT COUNT(*) AS OpenItems FROM vw_open_items; -- expected 7 initially
SELECT COUNT(*) AS ReturnRateMonthRecords FROM SalesSummary; -- expected 5 initially
SELECT COUNT(*) AS CompletedItems FROM ReturnItem WHERE CompletionAt IS NOT NULL; -- expected 0 initially
SELECT COUNT(*) AS WorkOrders FROM WorkOrder; -- expected 0 initially
SELECT COUNT(*) AS Inspections FROM Inspection; -- expected 0 initially
SELECT COUNT(*) AS MovementEvents FROM InventoryMovement; -- expected 0 initially
SELECT COUNT(*) AS AuditEvents FROM AuditLog; -- expected 0 initially
SELECT COUNT(*) AS RecoveryViewRows FROM vw_item_recovery; -- expected 7 initially
SELECT p.SKU,s.UnitsSold FROM SalesSummary s
JOIN Product p ON p.ProductID=s.ProductID ORDER BY p.SKU;
-- NOTE: constraints, authorization, workflow, audit and rollback tests will be added
-- after the controlled procedures, triggers, and MySQL accounts/grants are installed.


-- FRD 2.1 reports RQ-01 through RQ-05. Run AFTER 010_views.sql.
-- These are SELECT demonstrations, not stored objects. Review result tabs in Workbench.
-- Demo timestamps stored as UTC; set connection time zone before running reports.
SET time_zone = '+00:00';

-- RQ-01 Open returns, oldest first. Add AND ItemStatus='...' / LocationCode='...' for filters.
SELECT * FROM vw_open_items ORDER BY ReceivedAt, ReturnID, LineNumber;

-- RQ-02 Item history, here for return 1, line 1. Money excluded.
SET @report_return_id = 1;
SET @report_line_no = 1;
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
   AND JSON_UNQUOTE(JSON_EXTRACT(a.RecordKey,'$.ReturnID'))=CAST(@report_return_id AS CHAR)
   AND JSON_UNQUOTE(JSON_EXTRACT(a.RecordKey,'$.LineNumber'))=CAST(@report_line_no AS CHAR)
) x
ORDER BY x.EventTime, x.TieBreak, x.EventID;
-- NOTE: This RQ-02 starter includes inspection, work-order creation, movements and item audits.
-- The final version must also include work-order starts/completions and approval/completion events
-- consistently with the audit design once those procedures/triggers are implemented.

-- RQ-03 Monthly return rates by product/month, including sales-only and returns-only months.
-- Use two separately aggregated sources to avoid multiplication of counts.
WITH returns_by_month AS (
 SELECT ri.ProductID, DATE_SUB(DATE(rh.ReceivedAt),INTERVAL DAYOFMONTH(rh.ReceivedAt)-1 DAY) AS CalendarMonth,
        COUNT(*) AS UnitsReturned
 FROM ReturnItem ri JOIN ReturnHeader rh ON rh.ReturnID=ri.ReturnID
 GROUP BY ri.ProductID, DATE_SUB(DATE(rh.ReceivedAt),INTERVAL DAYOFMONTH(rh.ReceivedAt)-1 DAY)
), keys_by_month AS (
 SELECT ProductID, CalendarMonth FROM returns_by_month
 UNION
 SELECT ProductID, CalendarMonth FROM SalesSummary
)
SELECT p.SKU,k.CalendarMonth,COALESCE(r.UnitsReturned,0) AS UnitsReturned,
       s.UnitsSold,
       CASE WHEN s.UnitsSold IS NULL OR s.UnitsSold=0 THEN NULL
            ELSE ROUND(COALESCE(r.UnitsReturned,0)*100.0/s.UnitsSold,2) END AS ReturnRatePct
FROM keys_by_month k
JOIN Product p ON p.ProductID=k.ProductID
LEFT JOIN returns_by_month r ON r.ProductID=k.ProductID AND r.CalendarMonth=k.CalendarMonth
LEFT JOIN SalesSummary s ON s.ProductID=k.ProductID AND s.CalendarMonth=k.CalendarMonth
ORDER BY k.CalendarMonth,p.SKU;
-- NULL ReturnRatePct means N/A (missing/zero sales), not zero.

-- RQ-04 Financial: Manager access ONLY when DB roles/grants are installed.
SET @period_start = '2026-10-01 00:00:00';
SET @period_end = '2026-11-01 00:00:00';
SELECT ReturnID,LineNumber,SKU,FinalOutcome,
       RestockEstimatedValue,LiquidationProceeds,VendorCashReceived,
       TotalLaborCost,TotalPartsCost,DisposalCost,NetRecovery
FROM vw_item_recovery
WHERE CompletionAt >= @period_start AND CompletionAt < @period_end
ORDER BY CompletionAt,ReturnID,LineNumber;
SELECT FinalOutcome,COUNT(*) AS CompletedItems,SUM(NetRecovery) AS TotalNetRecovery
FROM vw_item_recovery
WHERE CompletionAt >= @period_start AND CompletionAt < @period_end
GROUP BY FinalOutcome ORDER BY FinalOutcome;

-- RQ-05 Completed item turnaround in days by disposition.
SELECT disp.Code AS FinalOutcome, COUNT(*) AS CompletedItems,
       ROUND(AVG(TIMESTAMPDIFF(SECOND,rh.ReceivedAt,ri.CompletionAt)/86400.0),2) AS AvgDays
FROM ReturnItem ri
JOIN ReturnHeader rh ON rh.ReturnID=ri.ReturnID
JOIN ReferenceValue disp ON disp.ReferenceValueID=ri.ApprovedOutcomeID AND disp.Domain='Disposition'
WHERE ri.CompletionAt IS NOT NULL
GROUP BY disp.Code ORDER BY disp.Code;
-- RQ-05 open delayed items: strictly older than seven elapsed days.
SELECT * FROM vw_open_items
WHERE ReceivedAt < UTC_TIMESTAMP() - INTERVAL 7 DAY
ORDER BY ReceivedAt,ReturnID,LineNumber;

-- Performance demonstration (compare estimated plan to actual Workbench data volume):
EXPLAIN SELECT * FROM vw_open_items ORDER BY ReceivedAt, ReturnID, LineNumber;
-- When supported by the installed MySQL Server version:
-- EXPLAIN ANALYZE SELECT * FROM vw_open_items ORDER BY ReceivedAt, ReturnID, LineNumber;
