-- READ-ONLY presentation queries. Run in the schema where 010 was loaded.
-- The TDD and baseline manifest are unchanged; this is an optional data extension.

-- 1. Count product models, return events and physical units (different concepts).
SELECT (SELECT COUNT(*) FROM Product) AS ProductModels,
       (SELECT COUNT(*) FROM ReturnHeader) AS ReturnEvents,
       (SELECT COUNT(*) FROM ReturnItem) AS ReturnedUnits;

-- 2. Laptop example: model -> physical returned unit -> supplier.
SELECT h.ExternalReference,i.ReturnID,i.LineNumber,p.SKU,p.Description,
       i.SerialNumber,v.VendorName,reason.Code AS ReturnReason,
       s.Code AS ItemStatus,l.LocationName
FROM ReturnItem i
JOIN ReturnHeader h ON h.ReturnID=i.ReturnID
JOIN Product p ON p.ProductID=i.ProductID
JOIN Vendor v ON v.VendorID=p.VendorID
JOIN ReferenceValue reason ON reason.ReferenceValueID=i.ReturnReasonID
JOIN ReferenceValue s ON s.ReferenceValueID=i.ItemStatusID
JOIN Location l ON l.LocationID=i.CurrentLocationID
WHERE p.SKU='LAP-100'
ORDER BY h.ExternalReference,i.LineNumber;

-- 3. One-to-many: each presentation return contains two physical units.
SELECT h.ExternalReference,COUNT(*) AS UnitsInThisReturn
FROM ReturnHeader h JOIN ReturnItem i ON i.ReturnID=h.ReturnID
WHERE h.ExternalReference IN ('PRES-LAP-REPAIR','PRES-LAP-RESTOCK',
 'PRES-LAP-LIQUIDATE','PRES-LAP-DISPOSE','PRES-LAP-OPEN','PRES-LAP-CLAIM')
GROUP BY h.ReturnID,h.ExternalReference ORDER BY h.ExternalReference;

-- 4. Grouping: how many physical returned units belong to each model?
SELECT p.SKU,p.Description,COUNT(i.ReturnID) AS ReturnedUnits
FROM Product p LEFT JOIN ReturnItem i ON i.ProductID=p.ProductID
GROUP BY p.ProductID,p.SKU,p.Description ORDER BY ReturnedUnits DESC,p.SKU;

-- 5. Open and delayed work; the ten-day-old presentation return is delayed.
SELECT * FROM vw_open_items
ORDER BY ReceivedAt,ReturnID,LineNumber;
SELECT * FROM vw_open_items
WHERE ReceivedAt < UTC_TIMESTAMP() - INTERVAL 7 DAY
ORDER BY ReceivedAt,ReturnID,LineNumber;

-- 6. Manager-only recovery: initially zero/NULL inputs until workflows run.
SELECT r.* FROM vw_item_recovery r
JOIN ReturnHeader h ON h.ReturnID=r.ReturnID
WHERE h.ExternalReference='PRES-LAP-REPAIR' AND r.LineNumber=1;

-- LAPTOP STORY TO REHEARSE (intended operations; not pre-created outcomes):
-- Return PRES-LAP-REPAIR / line 1 / serial LAP-PRES-001:
-- Inspector: Initial C/Fail, "Battery does not hold charge".
-- Manager: approve Repair with amount 0; assign active technician01.
-- Technician: start then complete work; labor 10, parts 25, "Replaced battery".
-- Inspector: PostRepair A/Pass, linked to the returned local work-order number.
-- Manager: submit claim40 BEFORE closing the item; approve claim.
-- Manager: approve Restock with estimate200.
-- Receiving: final Restock movement from current location to SALE-01.
-- Manager: settle existing claim30, even after item completion.
-- Expected recovery after those operations: 200+30-10-25 = 195.
-- The 200 is an estimate; only the settlement is vendor cash received.
-- Resolve all IDs by ExternalReference/SKU/login/code; do not assume ReturnID=1.
-- Run actual workflow calls in the proper role connections, not as root.
-- No claims, repair jobs, inspections, movements or audit events are fabricated here.
