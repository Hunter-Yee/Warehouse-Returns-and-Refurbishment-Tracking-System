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
| 2 — after (generated columns) | Index lookup on `ix_audit_entity_record`, ~5 rows (a completed unit's `ReturnItem` events), no sort step. |
| 3 — control (index ignored) | Similar to test 1: the generated columns alone do not help. |
| Correctness | `BeforeRows = AfterRows` and `MismatchedGeneratedKeys = 0`. |
| 6 — write cost | Time to insert 10,000 audit rows while maintaining every AuditLog index. |

## Results

Measured 2026-11-27 on MySQL 8.4.11 (macOS arm64, 512 MB buffer pool), default volume, warm run. Full output: [`results/benchmark_20261127T175725Z.txt`](results/benchmark_20261127T175725Z.txt). The data was loaded by an earlier run, which is why the file's loader section says "Already loaded".

| Measurement | Value |
| --- | --- |
| MySQL version | 8.4.11 |
| ReturnItem / AuditLog rows | 100,006 / 451,654 (301,655 `ReturnItem` audit rows) |
| Test 1 (before, JSON filter) | **181 ms**, 301,655 rows read to return 5 |
| Test 2 (after, `ix_audit_entity_record`) | **0.014 ms**, 5 rows read to return 5 |
| Test 3 (control, index ignored) | 205 ms, 301,655 rows read |
| Correctness | BeforeRows = AfterRows = 5, MismatchedGeneratedKeys = 0 |
| Full RQ-02 timeline at scale | 0.036 ms |
| Write cost, 10,000 audit inserts (all indexes) | 64 ms |
| `ix_audit_entity_record` size | 29.6 MB (vs 75.6 MB clustered PRIMARY) |

**Conclusion:** the per-item audit lookup went from a scan of every `ReturnItem` audit row to an index seek, about 12,000× faster at this volume, and its cost now depends on one item's history instead of the size of the log. Test 3 confirms the gain comes from the index, not the generated columns. The cost is about 30 MB of index and a small extra write per audit insert.

Other plans at this volume: RQ-01 (`vw_open_items`, 70,009 open rows) takes about 160 ms, mostly returning and sorting every open row, which is what paged grid loading in the final project should avoid. RQ-04 for one month (2,510 completed units) takes 5 ms via `ix_item_completion`.
