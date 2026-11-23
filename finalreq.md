# Final Project — Presentation & Deliverable Requirements

Final Project Requirements — Please Read Carefully

For your final project, your team will build and present an end-to-end data system in two parts: a live operational application, and a data warehouse that feeds reporting. Both parts run on the same operational data.

Part 1 — Operational Application: ODS → App Service → GUI

Build a flow from an Operational Data Store (ODS) through an application service to a GUI with:

- A dashboard showing daily operational metrics.
- Drill-down grids from those metrics into the underlying records.
- Dynamic screens and validations driven by metadata — specifically workflow metadata and INDICATOR / VALUE metadata. Screens and their validation rules should be generated from the metadata, not hard-coded screen by screen.
- Paged grid loading: the grid loads only enough records to display on screen, with a separate load for each offset/page as the user scrolls or pages — smooth scrolling, never a full-table load into the grid.

Part 2 — Data Warehouse & Reporting

Separately, set up a data warehouse database:

- Extract from the ODS and load into the warehouse in columnar storage.
- The warehouse feeds a reporting database that would serve Power BI. You do not need to implement Power BI — instead, run queries against the reporting database to simulate a Power BI pull.
- Example reporting: quarterly revenue and profit numbers by region (your queries should demonstrate this style of aggregate reporting).
The warehouse must be loaded on an intraday basis — incremental loads during the day, not a single end-of-day batch (e.g., watermark-based sweeps, as covered in class).

Data

Populate the ODS with dummy data — a reasonable number of records: enough volume that pagination, filtering, drill-down, and aggregation are visibly meaningful in your demo.

Deliverables (same set as the midterm)

- Functional Requirements Document (FRD)
- ER diagram — covering the ODS and the warehouse / reporting schemas
- Technical Design Document (TDD)
- Testing Plan
- Traceability — a mapping from each functional requirement to its implementation and to the test case(s) that verify it

Presentation

- Presentations run Dec 7–16 in your team's scheduled slot. Your presentation must include a live demonstration of both flows: the dashboard → drill-down GUI over the ODS, and an intraday warehouse load followed by reporting queries simulating the Power BI pull.
- All deliverables are due Friday, Dec 18, 11:59 PM ET.
Update to the Final Project requirements (added Nov 9): In addition to the previously announced requirements, every project must include an Audit Trail query screen. For at least one core business entity in your system — for example, an Order or a Reservation — your application must record an audit history of changes (who made the change, what changed, and when) and provide a screen where a user can query and view that audit trail (for example, search by order or reservation ID and see the full history of events for that record). Today's class covers this design end to end, from the database schema to the GUI implementation.

 

Design direction for the audit trail: implement the audit as a history (temporal) table for each core table in your schema — each history table mirrors its table's columns and keeps every version of a record with its validity period and who made the change — rather than a single generic log table. Build your audit query screen on a denormalized grid view that combines the history tables, with one row each time an event changes an important attribute of a record. Today's class presentation covers this design from schema to GUI.