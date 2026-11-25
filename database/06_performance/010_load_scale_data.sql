-- Optional scaled performance data (NOT in database/manifest.txt).
-- Run AFTER a normal build + baseline seed, as the database setup account, on a
-- SCRATCH schema. Baseline validation expects 7 items, so never load this into the
-- schema you use for the baseline demo.
--
-- Default volume: 50,000 return headers, ~100,000 units, ~440,000 AuditLog rows.
-- Override before running:  SET @perf_returns = 10000;
--
-- Everything is synthetic and tagged: ExternalReference 'PERF-nnnnnn', serials
-- 'PERF-SN-...', audit NewValues {"Synthetic": true}. Rows are inserted directly as
-- the setup account (like the presentation loader) because the goal is data VOLUME
-- for EXPLAIN ANALYZE, not a workflow test. The audit history is representative
-- event volume per unit; it does not have matching Inspection/Movement rows.
--
-- Safe to repeat: if any PERF- header exists, nothing is inserted.
-- One transaction: stop on the first error and ROLLBACK (do not use --force).

SET @perf_returns = COALESCE(@perf_returns, 50000);
SET @perf_loaded = (SELECT COUNT(*) > 0 FROM ReturnHeader WHERE ExternalReference LIKE 'PERF-%');
SELECT @perf_returns AS RequestedReturns,
       IF(@perf_loaded, 'Already loaded: no rows will be inserted', 'Loading') AS LoaderAction;

SET @u_recv = (SELECT UserID FROM AppUser WHERE LoginIdentifier = 'wr_receiving01');
SET @u_insp = (SELECT UserID FROM AppUser WHERE LoginIdentifier = 'wr_inspector01');
SET @u_mgr  = (SELECT UserID FROM AppUser WHERE LoginIdentifier = 'wr_manager01');

DROP TEMPORARY TABLE IF EXISTS tmp_perf_seq;
DROP TEMPORARY TABLE IF EXISTS tmp_perf_product;
DROP TEMPORARY TABLE IF EXISTS tmp_perf_reason;
DROP TEMPORARY TABLE IF EXISTS tmp_perf_state;

-- 0..99,999 (supports @perf_returns up to 100,000).
CREATE TEMPORARY TABLE tmp_perf_seq (n INT UNSIGNED PRIMARY KEY) ENGINE=InnoDB;
INSERT INTO tmp_perf_seq (n)
WITH d AS (SELECT 0 AS v UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
           UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9)
SELECT a.v + 10*b.v + 100*c.v + 1000*e.v + 10000*f.v
FROM d a CROSS JOIN d b CROSS JOIN d c CROSS JOIN d e CROSS JOIN d f;

CREATE TEMPORARY TABLE tmp_perf_product ENGINE=InnoDB AS
SELECT ROW_NUMBER() OVER (ORDER BY ProductID) - 1 AS k, ProductID, SKU, SerialRequired
FROM Product WHERE IsActive = 1;
SET @n_products = (SELECT COUNT(*) FROM tmp_perf_product);

CREATE TEMPORARY TABLE tmp_perf_reason ENGINE=InnoDB AS
SELECT ROW_NUMBER() OVER (ORDER BY ReferenceValueID) - 1 AS k, ReferenceValueID
FROM ReferenceValue WHERE Domain = 'ReturnReason' AND IsActive = 1;
SET @n_reasons = (SELECT COUNT(*) FROM tmp_perf_reason);

-- States 0-2 are completed (30% of units), 3-6 are open (70%).
CREATE TEMPORARY TABLE tmp_perf_state (
 k TINYINT UNSIGNED PRIMARY KEY,
 StatusCode VARCHAR(32) NOT NULL,
 LocationCode VARCHAR(40) NOT NULL,
 OutcomeCode VARCHAR(32) NULL,
 IsComplete TINYINT(1) NOT NULL
) ENGINE=InnoDB;
INSERT INTO tmp_perf_state VALUES
 (0, 'Restocked',          'SALE-01', 'Restock',   1),
 (1, 'Liquidated',         'LIQ-01',  'Liquidate', 1),
 (2, 'Disposed',           'DIS-01',  'Dispose',   1),
 (3, 'AwaitingInspection', 'INT-01',  NULL,        0),
 (4, 'AwaitingDecision',   'INSP-01', NULL,        0),
 (5, 'InRepair',           'REP-01',  'Repair',    0),
 (6, 'ApprovedForRestock', 'STO-01',  'Restock',   0);

START TRANSACTION;

INSERT INTO ReturnHeader (ExternalReference, ReceivedAt, ReceivingUserID)
SELECT CONCAT('PERF-', LPAD(s.n, 6, '0')),
       TIMESTAMP('2026-11-01') - INTERVAL (s.n MOD 365) DAY - INTERVAL (s.n MOD 600) MINUTE,
       @u_recv
FROM tmp_perf_seq s
WHERE s.n < @perf_returns AND @perf_loaded = 0;

-- 1-3 units per header; unit key i = header n * 3 + line.
INSERT INTO ReturnItem
 (ReturnID, LineNumber, ProductID, SerialNumber, ReturnReasonID, ItemStatusID, CurrentLocationID,
  ApprovedOutcomeID, ApprovedByUserID, ApprovedAt, CompletionAt,
  RestockEstimatedValue, LiquidationProceeds, DisposalCost)
SELECT x.ReturnID, x.ln, p.ProductID,
       IF(p.SerialRequired = 1, CONCAT('PERF-SN-', x.ReturnID, '-', x.ln), NULL),
       r.ReferenceValueID, st.ReferenceValueID, loc.LocationID,
       oc.ReferenceValueID,
       IF(oc.ReferenceValueID IS NULL, NULL, @u_mgr),
       IF(oc.ReferenceValueID IS NULL, NULL, x.ReceivedAt + INTERVAL 1 DAY),
       IF(ps.IsComplete = 1, x.ReceivedAt + INTERVAL (2 + x.i MOD 20) DAY, NULL),
       IF(ps.OutcomeCode = 'Restock' AND ps.IsComplete = 1, 50 + x.i MOD 200, NULL),
       IF(ps.OutcomeCode = 'Liquidate', 10 + x.i MOD 50, NULL),
       IF(ps.OutcomeCode = 'Dispose', 5 + x.i MOD 15, NULL)
FROM (
 SELECT h.ReturnID, h.ReceivedAt, l.ln,
        CAST(SUBSTRING(h.ExternalReference, 6) AS UNSIGNED) * 3 + l.ln AS i
 FROM ReturnHeader h
 JOIN (SELECT 1 AS ln UNION ALL SELECT 2 UNION ALL SELECT 3) l
   ON l.ln <= 1 + CAST(SUBSTRING(h.ExternalReference, 6) AS UNSIGNED) MOD 3
 WHERE h.ExternalReference LIKE 'PERF-%'
   AND NOT EXISTS (SELECT 1 FROM ReturnItem e WHERE e.ReturnID = h.ReturnID)
) x
JOIN tmp_perf_product p ON p.k = x.i MOD @n_products
JOIN tmp_perf_reason r ON r.k = x.i MOD @n_reasons
JOIN tmp_perf_state ps ON ps.k = IF(x.i MOD 10 < 3, x.i MOD 3, 3 + x.i MOD 4)
JOIN ReferenceValue st ON st.Domain = 'ItemStatus' AND st.Code = ps.StatusCode
JOIN Location loc ON loc.LocationCode = ps.LocationCode
LEFT JOIN ReferenceValue oc ON oc.Domain = 'Disposition' AND oc.Code = ps.OutcomeCode
WHERE @perf_loaded = 0;

-- Audit history: completed units get 6 events, open units 2-4.
INSERT INTO AuditLog (UserID, RecordedAt, Action, EntityName, RecordKey, OldValues, NewValues, TransactionID)
SELECT CASE ev.e WHEN 2 THEN @u_insp WHEN 3 THEN @u_mgr ELSE @u_recv END,
       h.ReceivedAt + INTERVAL ev.e HOUR,
       ev.Action, ev.EntityName,
       JSON_OBJECT('ReturnID', ri.ReturnID, 'LineNumber', ri.LineNumber),
       NULL, JSON_OBJECT('Synthetic', TRUE), UUID()
FROM ReturnItem ri
JOIN ReturnHeader h ON h.ReturnID = ri.ReturnID
JOIN (SELECT 1 AS e, 'ITEM_INTAKE' AS Action, 'ReturnItem' AS EntityName
      UNION ALL SELECT 2, 'INSPECTION_CREATED', 'Inspection'
      UNION ALL SELECT 3, 'DISPOSITION_APPROVED', 'ReturnItem'
      UNION ALL SELECT 4, 'ITEM_MOVED', 'ReturnItem'
      UNION ALL SELECT 5, 'ITEM_MOVED', 'ReturnItem'
      UNION ALL SELECT 6, 'ITEM_MOVED', 'ReturnItem') ev
  ON ev.e <= IF(ri.CompletionAt IS NOT NULL, 6,
                2 + (CAST(SUBSTRING(h.ExternalReference, 6) AS UNSIGNED) * 3 + ri.LineNumber) MOD 3)
WHERE h.ExternalReference LIKE 'PERF-%' AND @perf_loaded = 0;

INSERT INTO AuditLog (UserID, RecordedAt, Action, EntityName, RecordKey, OldValues, NewValues, TransactionID)
SELECT @u_recv, h.ReceivedAt, 'RETURN_REGISTERED', 'ReturnHeader',
       JSON_OBJECT('ReturnID', h.ReturnID), NULL, JSON_OBJECT('Synthetic', TRUE), UUID()
FROM ReturnHeader h
WHERE h.ExternalReference LIKE 'PERF-%' AND @perf_loaded = 0;

COMMIT;

DROP TEMPORARY TABLE tmp_perf_state;
DROP TEMPORARY TABLE tmp_perf_reason;
DROP TEMPORARY TABLE tmp_perf_product;
DROP TEMPORARY TABLE tmp_perf_seq;

-- Refresh optimizer statistics so plans reflect the new volume.
ANALYZE TABLE ReturnHeader, ReturnItem, AuditLog;

SELECT 'ReturnHeader' AS table_name, COUNT(*) AS row_count FROM ReturnHeader
UNION ALL SELECT 'ReturnItem', COUNT(*) FROM ReturnItem
UNION ALL SELECT 'ReturnItem (open)', COUNT(*) FROM ReturnItem WHERE CompletionAt IS NULL
UNION ALL SELECT 'AuditLog', COUNT(*) FROM AuditLog
UNION ALL SELECT 'AuditLog (ReturnItem entity)', COUNT(*) FROM AuditLog WHERE EntityName = 'ReturnItem';
