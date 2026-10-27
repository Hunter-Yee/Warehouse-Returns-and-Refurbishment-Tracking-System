# Optional presentation sample data

Run `010_add_presentation_data.sql` after the standard build and baseline seed, with the target schema selected and using the setup account. Stop on SQL errors; do not use the mysql client's `--force` option. If a statement fails, roll back the transaction before continuing.

Then run `020_show_presentation_data.sql` to inspect the units, product/vendor joins, grouped counts, open items, and overdue work. The recovery query needs Manager or setup-account access.

The loader adds six return headers and twelve units, including seven LAP-100 laptops supplied by the existing Northstar Electronics vendor. After a fresh baseline plus this loader, expected totals are:

| Record type | Total |
| --- | ---: |
| Product models | 5 |
| Return headers | 11 |
| Returned units | 19 |
| LAP-100 laptop units | 9 |
| Open units before workflow operations | 19 |
| New presentation units older than seven days | 2 |

All new units start AwaitingInspection at INT-01. Scenario labels describe intended demonstrations, not completed work. Existing rows are not reset on repeat runs. Use the business procedures and correct role accounts to perform inspections, approvals, repairs, claims and movements.

## Laptop example

Find `PRES-LAP-REPAIR`, line 1, serial `LAP-PRES-001`; do not assume its generated ReturnID. The intended story is a failed battery inspection, repair costing $10 labor and $25 parts, passing post-repair inspection, a $200 restock estimate, and a $40 vendor claim that settles for $30. Submit the claim before closing the unit. After these operations, expected net recovery is $195, which includes estimated restock value rather than representing only cash received. The SQL query file contains the role-by-role rehearsal sequence.

## Execution verification

Executed against a fresh MySQL 8.4.11 database using the standard manifest, followed by these optional files. Observed 11 headers, 19 units, 9 laptops, 19 open items, 2 overdue presentation units and no orphan items. Repeating the loader produced identical header/item records; all presentation queries executed successfully. This verifies sample loading and queries, not the complete business workflow or remaining project requirements.

The local verified schema is `warehouse_returns_presentation` on the existing server at port 33306. The earlier `warehouse_returns_demo` contains a different headset/lamp implementation and was left unchanged. Other users can choose a different fresh schema name when building.

These files are intentionally outside `database/manifest.txt`: baseline validation still expects seven initial returned units. No TDD, schema, permissions, baseline seed, or existing database is replaced by this extension.
