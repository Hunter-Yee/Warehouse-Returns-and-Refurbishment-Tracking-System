# Scaled performance testing

These files load synthetic volume into a **scratch** database and measure query plans with `EXPLAIN ANALYZE`. They are intentionally outside `database/manifest.txt`, because baseline validation expects 7 initial units.

| File | Purpose |
| --- | --- |
| `010_load_scale_data.sql` | Adds 50,000 return headers (~100,000 units, ~440,000 audit rows). Safe to repeat: it does nothing if `PERF-` data already exists. |
| `020_benchmark.sql` | Runs `EXPLAIN ANALYZE` on the RQ-02 audit lookup before and after tuning, a no-index control, the full RQ-02/RQ-01/RQ-04 reports, a write-cost test (rolled back), and index sizes. |
| `run_benchmark.sh` | Runs both files against an existing database and saves the output to `results/`. |

## Run

```bash
# 1. Fresh build from a tag that includes ix_audit_entity_record
bash build/build_database.sh Hunter-Yee Warehouse-Returns-and-Refurbishment-Tracking-System <TAG> wr_perf

# 2. Load + benchmark (optional second argument = number of return headers, default 50000)
bash database/06_performance/run_benchmark.sh wr_perf
```

The runner reads `build/config.env` just like the build script. It runs the benchmark twice and keeps the second (warm) run. Commit the generated `results/benchmark_*.txt` file as evidence.

Workbench alternative: select the scratch schema, run `010_load_scale_data.sql`, then run `020_benchmark.sql` twice.

## What is being tuned

RQ-02 (item history) originally found an item's audit events with:

```sql
WHERE EntityName = 'ReturnItem'
  AND JSON_UNQUOTE(JSON_EXTRACT(RecordKey, '$.ReturnID')) = CAST(@id AS CHAR)
```

No index can serve that JSON expression, so MySQL reads every `ReturnItem` audit row and parses its JSON. That cost grows with the whole audit log, not with one item's history. The fix adds virtual generated columns `AuditReturnID` and `AuditLineNumber` plus `ix_audit_entity_record (EntityName, AuditReturnID, AuditLineNumber, RecordedAt)`, which turns the lookup into an index seek that returns rows already in time order.

## How to read the output

Each `EXPLAIN ANALYZE` step shows `actual time=first..last rows=R loops=L`. Compare these between tests:

| Test | Expect |
| --- | --- |
| 1 — before (JSON filter) | Index lookup on `EntityName` only, then a filter over all `ReturnItem` audit rows (~300k at default volume), plus a sort. |
| 2 — after (generated columns) | Index lookup on `ix_audit_entity_record`, ~6 rows, no sort step. |
| 3 — control (index ignored) | Similar to test 1: the generated columns alone do not help. |
| Correctness | `BeforeRows = AfterRows` and `MismatchedGeneratedKeys = 0`. |
| 6 — write cost | Time to insert 10,000 audit rows while maintaining every AuditLog index. |

## Results

Not yet run. After running, record the measured numbers here, using the saved results file:

| Measurement | Value |
| --- | --- |
| MySQL version | |
| ReturnItem / AuditLog rows | |
| Test 1 (before), ms / rows examined | |
| Test 2 (after), ms / rows examined | |
| Test 3 (control), ms | |
| Write cost, 10,000 audit inserts, ms | |
| `ix_audit_entity_record` size, MB | |
