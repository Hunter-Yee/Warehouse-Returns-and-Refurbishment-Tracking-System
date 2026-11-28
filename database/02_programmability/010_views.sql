-- Warehouse Returns: reusable reporting views
-- Run after 010_tables.sql and both seed files. MySQL 8.0.16+.

-- Nonfinancial operational overview. Reporting queries can apply filters.
CREATE OR REPLACE DEFINER='wr_owner'@'localhost' SQL SECURITY DEFINER VIEW vw_open_items AS
SELECT ri.ReturnID, ri.LineNumber, rh.ExternalReference,
       rh.ReceivedAt, p.SKU, p.Description AS ProductDescription,
       ri.SerialNumber, st.Code AS ItemStatus,
       loc.LocationCode, loc.LocationName,
       TIMESTAMPDIFF(DAY, rh.ReceivedAt, UTC_TIMESTAMP()) AS DaysOpen
FROM ReturnItem ri
JOIN ReturnHeader rh ON rh.ReturnID = ri.ReturnID
JOIN Product p ON p.ProductID = ri.ProductID
JOIN ReferenceValue st ON st.ReferenceValueID = ri.ItemStatusID AND st.Domain = 'ItemStatus'
JOIN Location loc ON loc.LocationID = ri.CurrentLocationID
WHERE ri.CompletionAt IS NULL;

-- One row per item; aggregate repair totals BEFORE joining claim and item.
-- IMPORTANT: financial view; grant SELECT only to authorized Manager accounts.
CREATE OR REPLACE DEFINER='wr_owner'@'localhost' SQL SECURITY DEFINER VIEW vw_item_recovery AS
SELECT ri.ReturnID, ri.LineNumber, rh.ExternalReference,
       rh.ReceivedAt, ri.CompletionAt,
       p.SKU, disp.Code AS FinalOutcome,
       COALESCE(ri.RestockEstimatedValue,0.00) AS RestockEstimatedValue,
       COALESCE(ri.LiquidationProceeds,0.00) AS LiquidationProceeds,
       CASE WHEN cs.Code = 'Settled' THEN COALESCE(vc.SettlementAmount,0.00) ELSE 0.00 END AS VendorCashReceived,
       COALESCE(wo.TotalLaborCost,0.00) AS TotalLaborCost,
       COALESCE(wo.TotalPartsCost,0.00) AS TotalPartsCost,
       COALESCE(ri.DisposalCost,0.00) AS DisposalCost,
       COALESCE(ri.RestockEstimatedValue,0.00)
       + COALESCE(ri.LiquidationProceeds,0.00)
       + CASE WHEN cs.Code = 'Settled' THEN COALESCE(vc.SettlementAmount,0.00) ELSE 0.00 END
       - COALESCE(wo.TotalLaborCost,0.00)
       - COALESCE(wo.TotalPartsCost,0.00)
       - COALESCE(ri.DisposalCost,0.00) AS NetRecovery
FROM ReturnItem ri
JOIN ReturnHeader rh ON rh.ReturnID = ri.ReturnID
JOIN Product p ON p.ProductID = ri.ProductID
LEFT JOIN ReferenceValue disp ON disp.ReferenceValueID = ri.ApprovedOutcomeID AND disp.Domain = 'Disposition'
LEFT JOIN VendorClaim vc ON vc.ReturnID = ri.ReturnID AND vc.LineNumber = ri.LineNumber
LEFT JOIN ReferenceValue cs ON cs.ReferenceValueID = vc.ClaimStatusID AND cs.Domain = 'ClaimStatus'
LEFT JOIN (
    SELECT ReturnID, LineNumber,
           SUM(TotalLaborCost) AS TotalLaborCost,
           SUM(TotalPartsCost) AS TotalPartsCost
    FROM WorkOrder GROUP BY ReturnID, LineNumber
) wo ON wo.ReturnID = ri.ReturnID AND wo.LineNumber = ri.LineNumber;

-- RQ-03 Monthly return rate by product/month, including sales-only and returns-only months.
-- Returns and sales are aggregated separately before joining so neither multiplies the other.
-- ReturnRatePct is NULL (shown as N/A) when sales are missing or zero.
CREATE OR REPLACE DEFINER='wr_owner'@'localhost' SQL SECURITY DEFINER VIEW vw_monthly_return_rate AS
WITH returns_by_month AS (
 SELECT ri.ProductID, DATE_SUB(DATE(rh.ReceivedAt), INTERVAL DAYOFMONTH(rh.ReceivedAt)-1 DAY) AS CalendarMonth,
        COUNT(*) AS UnitsReturned
 FROM ReturnItem ri JOIN ReturnHeader rh ON rh.ReturnID = ri.ReturnID
 GROUP BY ri.ProductID, DATE_SUB(DATE(rh.ReceivedAt), INTERVAL DAYOFMONTH(rh.ReceivedAt)-1 DAY)
), keys_by_month AS (
 SELECT ProductID, CalendarMonth FROM returns_by_month
 UNION
 SELECT ProductID, CalendarMonth FROM SalesSummary
)
SELECT p.SKU, k.ProductID, k.CalendarMonth, COALESCE(r.UnitsReturned, 0) AS UnitsReturned, s.UnitsSold,
       CASE WHEN s.UnitsSold IS NULL OR s.UnitsSold = 0 THEN NULL
            ELSE ROUND(COALESCE(r.UnitsReturned, 0) * 100.0 / s.UnitsSold, 2) END AS ReturnRatePct
FROM keys_by_month k
JOIN Product p ON p.ProductID = k.ProductID
LEFT JOIN returns_by_month r ON r.ProductID = k.ProductID AND r.CalendarMonth = k.CalendarMonth
LEFT JOIN SalesSummary s ON s.ProductID = k.ProductID AND s.CalendarMonth = k.CalendarMonth;

-- RQ-05 Completed-item turnaround by final outcome, in precise elapsed days (seconds / 86400).
-- Only completed items count; open delayed items are listed from vw_open_items instead.
CREATE OR REPLACE DEFINER='wr_owner'@'localhost' SQL SECURITY DEFINER VIEW vw_turnaround_by_outcome AS
SELECT disp.Code AS FinalOutcome, COUNT(*) AS CompletedItems,
       ROUND(AVG(TIMESTAMPDIFF(SECOND, rh.ReceivedAt, ri.CompletionAt) / 86400.0), 2) AS AvgDays
FROM ReturnItem ri
JOIN ReturnHeader rh ON rh.ReturnID = ri.ReturnID
JOIN ReferenceValue disp ON disp.ReferenceValueID = ri.ApprovedOutcomeID AND disp.Domain = 'Disposition'
WHERE ri.CompletionAt IS NOT NULL
GROUP BY disp.Code;

SELECT TABLE_NAME FROM information_schema.VIEWS
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME IN ('vw_open_items','vw_item_recovery','vw_monthly_return_rate','vw_turnaround_by_outcome');
