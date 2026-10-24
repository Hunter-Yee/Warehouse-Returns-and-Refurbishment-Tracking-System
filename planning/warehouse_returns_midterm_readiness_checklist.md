# Warehouse Returns — Midterm Readiness Check

Reviewed October 22, 2026; technical-design status updated October 24, 2026 against the supplied course requirements and 12-week project plan. Current design baseline: FRD 2.1 and ERD 2.1, 15 tables.

This review covers files available in this chat's workspace. It does not verify a GitHub repository, work done elsewhere, or professor/TA approval. A requirement described in the FRD is not evidence that its implementation works.

## Overall finding

The requirements document and ER model are prepared. The Week 6 midterm also requires working database components; documents and diagrams alone do not satisfy that milestone.

## Requirements and current evidence

| Requirement | Current status | Remaining work / evidence |
| --- | --- | --- |
| Complete FRD with traceability | Prepared as a design document | Use FRD 2.1. FR-01–15, use cases, business rules, reports and acceptance cases are present. Add actual SQL/evidence references as implementation is completed. |
| ERD with at least 8–10 meaningful entities | Prepared | ERD 2.1 has 15 distinct tables over two tabs. Submit both tabs and both SVG exports. |
| 1:1, 1:N and M:N; weak entity; attributes/types; named diamonds; participation and attribute types | Represented in ERD 2.1 | Optional item–claim 1:1; Return–ReturnItem 1:N; User–Role M:N through UserRole; weak ReturnItem; key, composite, multivalued and derived examples. This is design coverage, not professor approval. |
| Technical Design Document | Design prepared October 24 | See docs/warehouse_returns_technical_design.md. The local composite work-order key is selected and synchronized with the FRD/ERD. No SQL has been run. |
| Demonstrate 3NF | Per-table keys/dependencies and 3NF rationale prepared | TDD Section 3 uses (ReturnID, LineNumber, WorkOrderNumber), with a local number unique within each item. The 15-table design is synchronized; implementation compliance still requires DDL review and tests. |
| Architecture and earlier design milestones | Textual architecture/data-flow specification drafted; diagrams still missing | The plan lists architecture, integration, data flow, API specifications and wireframes before Week 6. Supply brief designs appropriate to this project; record any explicit TA/instructor waiver. Implementing the web interface is a later milestone. |
| Working MySQL schema with indexes and constraints | Not found | CREATE TABLE and supporting indexes/constraints for all 15 tables; actually build and inspect the schema in MySQL. |
| Schema build file and reproducible build with initial data | Not found | Supply schema SQL, seed SQL and a documented command/script for building a fresh project database from the repository. Avoid assuming a local existing database. |
| Basic CRUD demonstration | Not found | Demonstrate insert/select/update and a valid delete of an unreferenced disposable sample row. Preserve historical records through deactivation; do not delete protected return/audit history. |
| SQL reports and transactions | Requirements only | Implement RQ-01–05 and transactions. Show joins, updates, subqueries, aggregates and exception handling as required by the course. |
| Denormalized reporting views | Not found | Build reporting views over the normalized tables, such as item recovery and open-item summaries. Avoid multiplying cost totals when joining multiple event streams. |
| Role definitions and entitlements | Requirements only | Provide an explicit permission matrix and implement limited grants/controlled procedures. Demonstrate allowed and denied access, including Technician assignment restrictions. |
| Audit mechanism, record-updating trigger and constraint enforcement | Requirements only | Demonstrate old/new audit capture, a movement-trigger location update, and rejected invalid operations. Audit changes must be in the same transaction. |
| Killed transaction and rollback demonstration | Planned only | Use two database sessions: perform an uncommitted transaction, kill its connection, then verify every affected table and audit history reverted. Also demonstrate ordinary rollback/error handling. Follow the separate Canvas notes referenced by the course plan. |
| Progress report and presentation | Not found | Prepare a short completed/in-progress/remaining report with member contributions and a rehearsed working-demo sequence. The plan requires a progress report; slides are a presentation aid, not a separately stated deliverable in these PDFs. |
| Authoritative GitHub submission under docs/ | Files packaged locally; repository status unverified | Commit FRD Markdown, draw.io, both SVGs and diagram explanation under docs/. Include scripts, setup instructions and evidence. Send the repository references to the TA as directed. A local ZIP alone is not the authoritative submission. |
| Regular commits and contribution evidence | Unverified | Preserve real commit history and contribution records. The plan recommends weekly standups, TA check-ins and at least four commits per member; do not manufacture history. |

## Keep implementation small

Do not add tables merely to fill these gaps. The baseline remains 15 tables. WorkOrder uses its item key plus a local WorkOrderNumber; no extra association table is needed.

1. **Compact technical design** — TDD, 3NF evidence, role matrix, index strategy and brief architecture/data-flow/API/wireframe designs. Document explicit permission, status, domain and time-order checks.
2. **Reproducible database build** — schema, reference seeds, fictional operational sample data and setup/build instructions.
3. **Queries and controlled transactions** — five required reports, reporting views and the minimum workflow operations needed for a coherent demo.
4. **Verification evidence** — CRUD, joins, subqueries, aggregates, exception handling, access denials, constraints, audit capture, updating trigger and killed-transaction rollback.
5. **Submission and presentation** — progress report, demo script, repository commits and TA references.

## Minimum sample scenarios

Use a small, deliberate dataset covering direct restock; successful repair; failed repair followed by liquidation/disposal; an existing claim settled after completion; and a delayed open item. Include multiple users/roles, grade/status reference values, locations and monthly sales totals. The supplied PDFs do not specify a universal minimum row count; use enough data to show each required behavior and report edge case.

## Important implementation checks for this model

- ReferenceValue IDs must match the expected Domain and be active for new uses. An FK alone cannot enforce the category rule.
- Use the composite (ReturnID, LineNumber, WorkOrderNumber) relationship. Controlled writes must enforce the latest completed order and valid timing; foreign keys alone cannot establish “latest.”
- Serialize conflicting intake/work-order/movement writes so concurrent operations cannot bypass the one-open-serial, one-active-order or current-location rules.
- Historical/audit records cannot be edited through ordinary roles. Financial values remain restricted to Managers.
- Restock requires the latest applicable Pass, grade A/B and Manager approval; a later Fail/Inconclusive blocks it.
- Movement, current location, terminal status, completion and audit effects must commit or roll back together.

## What can remain later

The course plan schedules microservice development in Week 7 and the web-interface prototype in Week 8, followed by integration/security/performance testing in Weeks 9–10. A production website and full service implementation are not needed merely to demonstrate the Week 6 working schema. Earlier architecture/API/wireframe design milestones still appear in the course plan.

## Source locations

- `database_group_project_requirements.pdf`: deliverables on pages 3–4; architecture/design on page 5; ERD requirements on pages 6–7; demonstrations on page 10; SQL operations on page 11; 3NF, entitlements and performance on page 12.
- `group project for a 12 week co.pdf`: authoritative repository requirements and early design milestones on page 1; Week 5 implementation and Week 6 review on page 2; Week 6 rubric on page 3; group-management recommendations on page 4.
- Current local FRD and ERD 2.1 outputs, including their Markdown explanations.

The separate Canvas commit/rollback instructions and any later announcements were not provided in the reviewed files, so their exact procedures/deadlines remain unverified.
