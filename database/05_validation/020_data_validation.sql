-- Verify initial seed counts and core item relationships.
SELECT 'AppUser' AS TableName,COUNT(*) AS RowCount FROM AppUser
UNION ALL SELECT 'Role',COUNT(*) FROM Role
UNION ALL SELECT 'ReferenceValue',COUNT(*) FROM ReferenceValue
UNION ALL SELECT 'Vendor',COUNT(*) FROM Vendor
UNION ALL SELECT 'Product',COUNT(*) FROM Product
UNION ALL SELECT 'Location',COUNT(*) FROM Location
UNION ALL SELECT 'ReturnHeader',COUNT(*) FROM ReturnHeader
UNION ALL SELECT 'ReturnItem',COUNT(*) FROM ReturnItem
UNION ALL SELECT 'SalesSummary',COUNT(*) FROM SalesSummary;
-- Expected initial counts: 6,5,50,3,5,7,5,7,5, respectively.
SELECT ri.ReturnID,ri.LineNumber,p.SKU,st.Code AS ItemStatus,loc.LocationCode
FROM ReturnItem ri
JOIN Product p ON p.ProductID=ri.ProductID
JOIN ReferenceValue st ON st.ReferenceValueID=ri.ItemStatusID AND st.Domain='ItemStatus'
JOIN Location loc ON loc.LocationID=ri.CurrentLocationID
ORDER BY ri.ReturnID,ri.LineNumber;
-- No row should be returned by these two checks.
SELECT ri.ReturnID,ri.LineNumber FROM ReturnItem ri
LEFT JOIN ReturnHeader rh ON rh.ReturnID=ri.ReturnID
WHERE rh.ReturnID IS NULL;
SELECT ri.ReturnID,ri.LineNumber FROM ReturnItem ri
JOIN Product p ON p.ProductID=ri.ProductID
WHERE p.SerialRequired=1 AND (ri.SerialNumber IS NULL OR TRIM(ri.SerialNumber)='');
