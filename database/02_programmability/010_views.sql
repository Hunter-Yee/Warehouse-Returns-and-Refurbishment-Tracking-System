-- Warehouse Returns: reusable reporting views
-- Run after 010_tables.sql and both seed files. MySQL 8.0.16+.
USE warehouse_returns_demo;

-- Nonfinancial operational overview. Reporting queries can apply filters.
CREATE OR REPLACE VIEW vw_open_items AS
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
CREATE OR REPLACE VIEW vw_item_recovery AS
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

SELECT TABLE_NAME FROM information_schema.VIEWS
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME IN ('vw_open_items','vw_item_recovery');
