# CS437 Project

## Warehouse Returns and Refurbishment Tracking System

Rajdeep Villuri and Hunter Yee

Current design: **FRD 2.1, ERD 2.1 and Technical Design 1.0**, synchronized October 24, 2026. The model has **15 tables**. WorkOrder uses the composite key `(ReturnID, LineNumber, WorkOrderNumber)`; the number is local to each returned item.

## Current documents

- [Functional requirements](docs/warehouse_returns_frd_simplified_v2_1.md)
- [Technical design and normalization](docs/warehouse_returns_technical_design.md)
- [Editable draw.io ER diagram](docs/warehouse_returns_erd_v2_1.drawio) - two tabs in one file
- [Warehouse workflow SVG](docs/warehouse_returns_erd_v2_1_workflow.svg)
- [Users and reference data SVG](docs/warehouse_returns_erd_v2_1_support.svg)
- [ER diagram explanation and attribute dictionary](docs/warehouse_returns_erd_v2_1.md)
- [Midterm readiness checklist](planning/warehouse_returns_midterm_readiness_checklist.md)

Present tab 01 (Warehouse workflow) first; tab 02 contains users, roles, audit, reference values and attribute examples. Both tabs belong to the same system. `NULL` means a field may be empty until applicable; it is not an unfinished placeholder.

## Earlier requirements and feedback

The original [FRD](docs/archive/FRD.md), [PDF](docs/archive/warehouse_returns_functional_requirements.pdf) and [professor feedback](docs/FRD_Feedback.md) are retained for history. Earlier FRD versions are in `docs/archive/`; professor feedback remains in `docs/`. Use the current documents linked above for ongoing design and implementation.

## Implementation status

Requirements, ER modeling and technical design are prepared. Schema/sample-data SQL, implemented reports, database controls and live demonstration evidence are still to be built and tested. Design documents do not establish implementation compliance.

Keep editable diagrams, SVG exports and explanations together under docs/. Each group member should commit their own actual contributions. Do not commit credentials or local backup archives.
