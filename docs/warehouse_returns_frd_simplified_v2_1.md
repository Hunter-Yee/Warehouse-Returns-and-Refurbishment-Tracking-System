# Warehouse Returns and Refurbishment Tracking System

Functional Requirements Document

Rajdeep Villuri and Hunter Yee
Database Systems Implementations
October 24 2026  |  Version 2.1  |  Simplified midterm scope

## 1 Purpose and scope

Our project tracks each returned product unit from warehouse intake through inspection, repair when needed, and final restocking, liquidation, or disposal. Staff need to know what was returned, its condition, its location, and the next approved action. Managers need reports on open items, return rates, turnaround time, and recovered value.

This version defines a 15-table database covering products and vendors, returned units, inspections, repair orders, movements, claims, monthly sales totals, users and roles, and audit history. One shared ReferenceValue table supports reasons, grades, statuses, and other controlled lists. Administrators maintain reference labels and active flags while preserving history and established workflow rules.

The midterm focuses on the ERD, MySQL schema, sample records, basic data operations, SQL reports, authorization, auditing, and transaction rollback. Later course milestones may add services and a basic interface. Customer refunds, payment processing, shipping integration, a production website, repair-parts inventory, partial claim payments, reopening, and advanced corrections are outside scope.

## 2 Users and responsibilities

| Role | Responsibilities |
| --- | --- |
| Receiving staff | Register returns and units; record permitted item movements; search operational records. |
| Inspector | Record condition grades and Initial, PostRepair, or Final inspection results. |
| Technician | Start and complete assigned repair orders; enter work performed and total labor and parts costs. |
| Manager | Maintain products and vendors; approve dispositions; assign repairs; manage claims and sales summaries; review all reports. |
| Administrator | Maintain accounts, roles, locations, and active reference values; preserve history. Business approvals and financial reporting require Manager access. |

A user may hold several of the five defined roles through UserRole. Vendors are records, not system users. Operational roles may search normal return information; claim amounts and the recovery report are restricted to Managers.

## 3 Functional requirements

High priority supports workflow or required controls; Medium supports retrieval and reporting. FR-01 through FR-15 retain their identifiers. FR-13 includes all three inspection types; FR-15 includes reference administration through one shared table.

| ID | Priority | Required behavior |
| --- | --- | --- |
| FR-01 | High | The system shall maintain products with a unique SKU, description, primary vendor, and serial-number requirement. |
| FR-02 | High | The system shall register a return with a unique external reference, receipt time, and receiving user, and create a separate line for each physical unit, its product, reason, required serial number, and intake location. |
| FR-03 | High | The system shall record each inspection with its item, inspector, time, condition grade, result, and notes, while preserving earlier inspection records. |
| FR-04 | High | The system shall allow only a Manager to approve Repair, Restock, Liquidate, or Dispose after the latest applicable inspection is conclusive, recording the approving user and time. |
| FR-05 | High | The system shall create a repair order only after Repair approval and record its assigned Technician, status, work details, completion time, and total labor and parts costs. |
| FR-06 | High | The system shall allow restocking only with Manager approval, grade A or B, and a passing latest applicable inspection. After repair, the check must identify the most recently completed order. |
| FR-07 | High | The system shall record item movements and atomically update current location, any resulting terminal status, completion time, and audit history. |
| FR-08 | High | The system shall allow a Manager to record at most one lifetime vendor claim per item, its requested amount and status, and one settlement received. It shall record payments, not process them. |
| FR-09 | Medium | The system shall search operational records by return ID, SKU, serial number, status, or location, and apply role restrictions to financial details. |
| FR-10 | Medium | The system shall provide RQ-01 through RQ-05 and allow a Manager to enter one monthly sales summary per product and calendar month. |
| FR-11 | High | The system shall enforce role permissions and append audit entries identifying the user, time, record, action, and old/new values for protected changes. |
| FR-12 | High | The system shall store restock estimated value, liquidation proceeds, disposal cost, repair labor/parts totals, and vendor settlement amounts, and calculate net recovery from them. |
| FR-13 | High | The system shall classify inspections as Initial, PostRepair, or Final, with Pass, Fail, or Inconclusive results. PostRepair and repaired-item Final checks shall reference the latest completed order for the same item. |
| FR-14 | High | The system shall identify the authenticated business user and allow a Technician to update only their assigned InProgress order, or start their assigned Open order. |
| FR-15 | High | The system shall allow an Administrator to maintain accounts, role assignments, locations, and active reference values for reasons, grades, statuses, and roles while preserving referenced history and workflow controls. |

Initial inspection supports intake, PostRepair checks completed work, and Final records an optional additional check before disposition. A passing PostRepair or Final check can qualify a repaired item; both types are not required for the same repair. Section 5 defines their permitted states.

## 4 Data requirements

This 15-table model lists primary keys (PK), foreign keys (FK), and stored facts. Composite keys use every listed column. Controlled lists reference ReferenceValue IDs; SQL types and indexes appear in the ERD and technical design.

| Table | Primary key | Information to store |
| --- | --- | --- |
| Vendor | VendorID | Name, contact name, email, phone, active flag. |
| Product | ProductID | Unique SKU, description, VendorID FK, serial-required flag, active flag. |
| Return | ReturnID | Unique external reference, ReceivedAt, ReceivingUserID FK. |
| ReturnItem | ReturnID + LineNumber | ReturnID FK, ProductID FK, serial, reason/status/outcome FKs, CurrentLocationID FK, ApprovedByUserID FK, ApprovedAt, CompletionAt, restock estimate, liquidation proceeds, disposal cost. |
| Inspection | InspectionID | ReturnID + LineNumber FK, InspectorUserID FK, time, type/grade/result FKs, notes, optional WorkOrderNumber; composite FK with the item key. |
| WorkOrder | ReturnID + LineNumber + WorkOrderNumber | ReturnID + LineNumber FK, AssignedTechnicianUserID FK, status FK, created/started/completed times, work details, total labor cost, total parts cost. |
| InventoryMovement | MovementID | ReturnID + LineNumber FK, SourceLocationID and DestinationLocationID FKs, time, MovedByUserID FK, movement-type FK, notes. |
| Location | LocationID | Unique code, name, location-type FK, active flag. |
| VendorClaim | ClaimID | Unique ReturnID + LineNumber FK, VendorID FK, requested amount, status FK, submitted/settled times, settlement amount, RecordedByUserID FK, claim reference. |
| SalesSummary | ProductID + CalendarMonth | ProductID FK, whole units sold, source reference, EnteredByUserID FK, update time. |
| User | UserID | Unique login identifier, display name, active flag. |
| Role | RoleID | Unique role code, description, active flag; permissions remain controlled. |
| UserRole | UserID + RoleID | Both key columns are FKs; each row assigns one role to one user. |
| AuditLog | AuditID | UserID FK, time, action, entity, record key, old/new values, transaction identifier. |
| ReferenceValue | ReferenceValueID | Domain, code, description, active flag; unique Domain + Code. One table for all controlled lists; Role and Location stay separate. |

Each ReturnItem is one physical unit; three identical units require three lines, with no quantity field. Initial CurrentLocationID is retained in audit history. A Technician is a User with that role. WorkOrderNumber is local to its item; the full key includes ReturnID and LineNumber.

Status identifies the workflow step; approved outcome is the Manager-selected path. Repair is intermediate. CompletionAt is set when Restocked, Liquidated, or Disposed commits. There is no separate Closed status or generic recovery amount.

ReferenceValue domains are ReturnReason, ConditionGrade, ItemStatus, WorkOrderStatus, ClaimStatus, InspectionType, InspectionResult, Disposition, LocationType, and MovementType. Each FK targets ReferenceValueID; controlled writes require the correct domain and active flag.

### 4 1 Relationships for the ERD

| Relationship | Type | Participation and meaning |
| --- | --- | --- |
| Return to ReturnItem | 1:N | Each committed Return has at least one item; each item requires one Return. ReturnItem is weak, with partial key LineNumber and identifying owner ReturnID. |
| Vendor to Product | 1:N | A Vendor may supply many Products or none; each Product requires one primary Vendor. |
| Product to ReturnItem | 1:N | A Product may appear in many returned units or none; each item requires one Product. |
| ReturnItem to events | 1:N | An item may have many inspections, work orders, and movements or none. Each event requires one item. |
| ReturnItem to VendorClaim | 1:1 | The claim is optional for the item. Each claim requires exactly one item; the item key is unique in VendorClaim. |
| User to Role | M:N | Users may have several roles and roles several users, resolved by UserRole. Each acting user requires an active account and at least one role assignment. |
| Other references | 1:N | Locations, users, vendors, and ReferenceValue rows may be referenced by many records. Product has monthly SalesSummary records; WorkOrder has PostRepair/Final checks. Initial checks have no order. |

N:1 reads a 1:N relationship in reverse, such as Inspection to ReturnItem. The ERD must mark total/partial participation, show all attributes and proposed types, and include key, derived, composite, and multivalued examples. Net recovery is derived; vendor contact is composite; user roles are multivalued conceptually and stored through UserRole.

## 5 Business rules and validation

**BR-01  **SKUs, external return references, location codes, and login identifiers are unique. Item/event references must identify existing parent records.

**BR-02  **A committed Return has at least one line. ReturnItem uses ReturnID plus a positive LineNumber as its key. All item events reference both components.

**BR-03  **Serial-required products need a nonblank serial number. The same product/normalized-serial pair cannot have two open items, including concurrent intake attempts.

**BR-04  **Grades are A like new, B usable with wear, C needs repair, and D beyond repair. Restock requires A/B and a passing latest applicable inspection.

**BR-05  **Only a Manager approves outcomes. Repaired restock requires new approval and the latest passing PostRepair or Final check, dated at/after completion of the latest order for the same item. Later Fail/Inconclusive blocks restock.

**BR-06  **Amounts cannot be negative; a submitted claim request and a received settlement must be positive. Sold quantities are nonnegative integers. Calculated net recovery may be negative.

**BR-07  **Each item has at most one active order, meaning Open or InProgress. An order requires Repair approval; only its assigned active Technician may start or complete it.

**BR-08  **A movement starts at the current location and ends at a different valid active location. Movement, item update, and audit entry commit together or all roll back.

**BR-09  **An item has zero or one lifetime claim, created before item closure. Its existing claim may settle later without changing item completion, status, or location.

**BR-10  **Only listed transitions are allowed. Completed items/orders cannot reopen or change. Referenced history is not deleted; accounts, locations, roles, and reference values are deactivated. New uses require active values in the correct domain.

### 5 1 Reference administration

Administrators may add reasons and edit reference descriptions/active flags; Role and Location have their own maintenance. Referenced rows cannot be deleted, recoded, or moved to another domain. Inactive values remain readable in history but cannot be selected for new records. Values needed by open work or enabled transitions cannot be deactivated. Grade meanings, workflow codes, and role permissions change only through a controlled design update; editing a label never changes business behavior.

Seed reasons: Damaged, Defective, WrongItem, Unwanted, Other. Location types: Intake, Inspection, Repair, Storage, SaleableStock, LiquidationExit, DisposalExit. Movement types: Relocate, Restock, Liquidate, Dispose. Grades, statuses, inspection types/results, and dispositions use their established values.

### 5 2 Item workflow

| Current item status | Event and allowed next status |
| --- | --- |
| AwaitingInspection | Initial Pass/Fail -> AwaitingDecision. Inconclusive leaves the item awaiting another Initial inspection. |
| AwaitingDecision | Manager approval -> ApprovedForRepair, ApprovedForRestock, ApprovedForLiquidation, or ApprovedForDisposal. Restock eligibility must pass BR-04/05. |
| ApprovedForRepair | Assigned Technician starts its Open order -> InRepair. Manager may cancel an unstarted order/approval -> AwaitingDecision. |
| InRepair | Assigned Technician completes the order, including unsuccessful repair work and costs -> AwaitingFinalInspection. |
| AwaitingFinalInspection | PostRepair or Final Pass/Fail -> AwaitingDecision. Inconclusive requires another linked check. |
| ApprovedForRestock | Final move into SaleableStock -> Restocked. |
| ApprovedForLiquidation | Final dispatch through LiquidationExit -> Liquidated. |
| ApprovedForDisposal | Final disposal through DisposalExit -> Disposed. |
| Restocked Liquidated Disposed | Terminal; CompletionAt is required. No new item movement, repair order, or reopening is allowed. |

WorkOrder transitions are Open -> InProgress -> Completed, or Open -> Cancelled by a Manager. Started work is completed even if unsuccessful, then inspected. Claim transitions are Submitted -> Approved, Denied, or Cancelled; Approved -> Settled or Cancelled. Settled, Denied, and Cancelled are terminal. Only Settled has a received amount and receipt time.

A Manager may withdraw an unstarted approval to AwaitingDecision, cancelling any Open order and clearing outcome, approver, time, and pending value; AuditLog preserves history. Initial checks require AwaitingInspection and no order. PostRepair requires AwaitingFinalInspection. Final is allowed in AwaitingFinalInspection or AwaitingDecision; it requires the latest completed order if repaired, otherwise no order. In AwaitingDecision, Final leaves the state unchanged; a new conclusive result is needed after Inconclusive.

## 6 Main transaction flows

UC-01 Receive and inspect: Receiving staff validate products, serials, reasons, and locations and commit the return and unit lines together. An Inspector records an Initial result; a conclusive result permits Manager decision. Invalid intake rolls back. Links: FR-01 to FR-04, FR-13.

UC-02 Repair: A Manager approves Repair and assigns an order. Its Technician records work/costs and completes it. A linked PostRepair or Final check returns the item to decision; Fail permits another repair or disposition. Links: FR-05, FR-06, FR-13, FR-14.

UC-03 Complete disposition: A Manager approves the final path and records its required amount, including known zero. Receiving staff confirm movement. Location, eligibility, terminal status, completion, and audit are validated and committed together. Routine moves preserve status. Links: FR-04, FR-06, FR-07, FR-12.

UC-04 Claim and review: A Manager records claims/settlement, sales, and reports. Users search items; Administrators maintain accounts, roles, locations, and reference values. Links: FR-08 to FR-12, FR-15.

## 7 Reports and queries

| ID and report | Required output |
| --- | --- |
| RQ-01 Open returns | Item key, SKU, status, location, receipt time, and elapsed days open. Filter by status/location; include only items without CompletionAt and sort oldest first. |
| RQ-02 Item history | For one item, list inspections, repairs, movements, approvals, and completion in event-time order with staff names. Claim amounts and financial details require Manager access. |
| RQ-03 Monthly return rate | For each product/month: received units, sold units, and received / sold x 100, rounded to two decimals. Count ReturnItem rows by receipt month. Missing or zero sales -> N/A; zero returns with positive sales -> 0%. |
| RQ-04 Recovery value | For items completed in a chosen period: final outcome, restock estimate, liquidation proceeds, vendor settlement, labor cost, parts cost, disposal cost, and net recovery, with totals by outcome. Manager only. |
| RQ-05 Turnaround and delays | Count completed items and average elapsed days from receipt to completion by final outcome. Separately list open items older than seven elapsed days, oldest first; exclude open items from completion averages. |

Monthly return rate compares same-month activity, not a sales cohort. SalesSummary is unique by product/month, with CalendarMonth represented by the first day of the month. Date filters include the start and exclude the end; reporting uses one documented warehouse time zone.

Net recovery equals restock estimated value plus liquidation proceeds plus received vendor settlement, minus all repair labor, repair parts, and disposal cost. Store the inputs and calculate the total. Show estimates separately from cash; unpaid claims contribute zero. Only the value matching the approved disposition is populated. Aggregate work orders per item before joining other events to prevent duplicate totals. A later settlement changes the report when rerun for that completed item.

## 8 Security and audit history

User, Role, and UserRole represent business identities and entitlements. A trusted login or controlled demonstration session establishes the acting UserID; a caller cannot gain permission by supplying another user ID. Controlled procedures or transactions check active account, role, workflow state, and Technician assignment. Limited MySQL accounts or grants demonstrate broad access separation without unrestricted writes to protected tables.

Technicians update only their assigned active work and labor/parts totals. Managers control approvals, assignments, claims, disposition values, sales entry, and financial reports. Administrators maintain accounts, roles, locations, and reference values; permission changes remain controlled. Active work requires reassignment before account deactivation; occupied locations and required roles remain active.

AuditLog records protected inserts and changes to status, location, approval, costs, claims, accounts, assignments, roles, and reference values, with actor, time, key, action, old/new values, and transaction identifier. A trigger or trusted process appends entries in the same transaction. Ordinary roles cannot directly write or delete audit rows. Manager and Administrator may inspect authorized views; financial values require Manager access.

For the course trigger demonstration, an authorized movement insert updates CurrentLocationID through one designated trigger. The controlled transaction validates and locks the item and commits the movement, status/completion changes, and audit history together. A forced error or killed transaction rolls back every uncommitted effect, including audit entries for those changes.

## 9 Assumptions and constraints

The system covers one warehouse, one physical unit per line, one primary vendor per product, and USD amounts with decimal cents. A serialized unit may return again as a new item only after its earlier item closes. Sales totals and all demonstration records are fictional and entered manually.

Costs are total labor and total parts per order. A completed repair or disposition is not edited or reopened; staff verify amounts before completion. There are no partial claim settlements or general correction procedures. A valid saleable restock uses the latest passing inspection; earlier checks remain historical.

The project uses MySQL and a 15-table model designed for third normal form. One shared ReferenceValue table replaces ten separate lookup tables. Role supports UserRole membership; Location supports physical movement history. Foreign keys and controlled writes enforce category, active-value, and workflow rules. SQL types, indexes, authentication, integration, performance targets, and normalization evidence belong in the technical design.

## 10 Acceptance criteria

These are planned implementation tests. Use cases for direct restock, successful and failed repair, liquidation, disposal, settlement, and delayed open items. Collect successful SQL results and rejected operations; the tests are not claims of completed implementation.

| Test | Requirement links | Expected demonstration |
| --- | --- | --- |
| AC-01 | FR-01 FR-02 | Create three units of one SKU as three lines. Reject duplicate SKU/reference, unknown product, missing required serial, and a second concurrent open product/serial pair. |
| AC-02 | FR-03 FR-04 FR-13 | Record all three inspection types. Initial has no order; repaired PostRepair/Final links to the same item's latest completed order. Reject a wrong-item link and approval after Inconclusive or by Receiving staff. |
| AC-03 | FR-05 FR-14 | Reject an order without Repair approval, a second active order, negative cost, and another Technician's update. Complete assigned work with $10 labor and $5 parts. |
| AC-04 | FR-06 FR-13 | Allow direct restock after Initial/Final Pass with A/B and approval. After repair, allow PostRepair or Final Pass for the latest order. Reject older-order or pre-completion checks; a later Fail/Inconclusive blocks restock. |
| AC-05 | FR-07 FR-11 | Confirm routine relocation preserves status. Reject a stale source or inactive destination. Force an error and kill an uncommitted movement; verify movement, location, status, completion, and audit all roll back. |
| AC-06 | FR-08 | Reject a second lifetime claim and a new claim on a closed item. Settle an existing approved claim after completion without changing item status/location/completion. |
| AC-07 | FR-09 FR-10 / RQ-01 RQ-02 | Search by every required key/filter; show item history and oldest open items. Restrict claim and financial details to Managers. |
| AC-08 | FR-10 / RQ-03 RQ-05 | Show 10 returned / 200 sold = 5%; missing/zero sales = N/A. Completion in two and four days averages three days; an eight-day open item is delayed and excluded from that average. |
| AC-09 | FR-10 FR-12 / RQ-04 | Show $60 restock estimate + $5 settlement - $15 repair cost = $50 net. Show $30 liquidation - $8 repair = $22; disposal $4 plus repair $6 gives -$10. Multiple events do not multiply totals. |
| AC-10 | FR-11 FR-15 | Maintain accounts, locations, and role assignments. Reject direct audit writes and terminal-item reopening. Verify actor/time/old-new capture and the location-update trigger. |
| AC-11 | FR-11 FR-15 | Administrator adds a reason and edits a grade/status label. Deactivate a reason used only by completed items: history still resolves it; new use fails. Reject referenced deletion/recoding, wrong-domain values, and deactivation needed by open work. Confirm reference edits are audited. |

Midterm evidence will include the ERD, schema and sample-data build scripts, 3NF explanation, role grants and access tests, JOIN/subquery/GROUP BY reports, constraint failures, trigger output, audit capture, and rollback results. Store the FRD in repository Markdown and diagrams as editable .drawio sources with SVG exports and an explanation.

