# Warehouse Returns and Refurbishment Tracking System

## Functional Requirements Document

**Authors:** Rajdeep Villuri, Hunter Yee  
**Course:** Database Systems Implementations

## 1. Purpose and Scope

This project models a warehouse that receives returned products. Staff need to know when and if an item was returned, the condition, where it is stored, and what should happen next.

A shared database will help prevent lost items, duplicate records, and delays in repair work.

The system will track intake, inspection, repairs, restocking, liquidation, disposal, and vendor claims. It will also support basic management reports. Customer refunds, online payments, shipping integrations, and a complete website are outside the scope of this project.

## 2. Users and Responsibilities

| User | Responsibility |
|---|---|
| Receiving staff | Enter returns and record item movements. |
| Inspector | Record condition grades, test results, and final repair checks. |
| Technician | Update assigned repair work orders and costs. |
| Manager | Approve item outcomes, assign repairs, manage claims, and review reports. |
| Administrator | Manage user accounts and role assignments. |

## 3. Functional Requirements

High-priority requirements support the main workflow. Medium-priority requirements support searches and reports.

| ID | Requirement | Priority |
|---|---|---|
| FR-01 | The system shall store product details, including SKU, description, vendor, and whether a serial number is required. | High |
| FR-02 | The system shall register a return and its individual items, including receipt date, product, reason, serial number when required, and intake location. | High |
| FR-03 | The system shall record inspections with the inspector, date, condition grade, test result, and notes. | High |
| FR-04 | The system shall allow a manager to approve repair, restock, liquidation, or disposal after inspection. | High |
| FR-05 | The system shall create repair work orders and record the assigned technician, status, work completed, and labor and parts costs. | High |
| FR-06 | The system shall require a passing inspection before an item is restocked, including a final check after repair. | High |
| FR-07 | The system shall record each movement and update the item's current location and status in the same transaction. | High |
| FR-08 | The system shall record vendor claims, requested amounts, claim status, and payments received. | High |
| FR-09 | The system shall let authorized users search by return ID, SKU, serial number, status, or location. | Medium |
| FR-10 | The system shall provide the reports in Section 7 using stored return, cost, outcome, and monthly sales data. | Medium |
| FR-11 | The system shall restrict changes by user role and keep a history of important updates. | High |

## 4. Data Requirements and Relationships

The following records provide the starting point for the ER diagram. Each record needs a primary key (unique identifier), and related records must reference valid parent records.

| Record | Main information |
|---|---|
| Product / Vendor | Product ID, SKU, name, serial-tracking flag, and vendor ID; vendor name and contact details. |
| Return | Return ID, unique external reference, receipt date, and receiving staff member. |
| ReturnItem | Return ID and line number, product, serial number, reason, status, location, approved outcome, completion date, and recovery amount. |
| Inspection | Inspection ID, item, inspector, date, grade, test result, and notes. Final checks also identify the repair order. |
| WorkOrder | Work order ID, item, technician, repair details, status, completion date, labor cost, and parts cost. |
| InventoryMovement | Movement ID, item, source and destination locations, date, and staff member. |
| VendorClaim | Claim ID, item, vendor, amount requested, status, amount received, and settlement date. |
| User / Role | User ID, name, active status, and assigned roles. UserRole links users to roles. |
| SalesSummary | Product, calendar month, units sold, and source reference. |
| Supporting records | Location codes, allowed return reasons and grades, and an AuditLog of important changes. |

One return contains one or more items. ReturnItem uses ReturnID and LineNumber together as its key, so it depends on the parent return. Each item can have several inspections, work orders, and movements, but at most one vendor claim. Users and roles have a many-to-many relationship through UserRole. Each product has one primary vendor; a vendor may supply many products.

## 5. Business Rules and Validation

| ID | Rule | Likely database control |
|---|---|---|
| BR-01 | Return references and product SKUs must be unique. | UNIQUE constraint |
| BR-02 | Each item must belong to an existing return and product. | Foreign keys; required fields |
| BR-03 | A serial-tracked product requires a serial number. The same product/serial pair cannot have two open returns. | Validation in a controlled transaction |
| BR-04 | Grades are A: like new, B: usable with wear, C: needs repair, and D: beyond repair. | Reference list or CHECK |
| BR-05 | Only a manager can approve an outcome. Restocking also requires a passing inspection after the latest repair, if any. | Role and workflow checks |
| BR-06 | Costs cannot be negative. Sold quantities must be whole numbers of zero or more. | CHECK constraints |
| BR-07 | A movement must start at the item's current location. The movement, item update, and audit entry succeed together or all roll back. | Transaction with rollback |
| BR-08 | An item has at most one open repair order and one vendor claim. Referenced history cannot be deleted by staff. | Uniqueness checks; restricted deletion |

## 6. Main Transaction Flows

**Receive and inspect:** Staff create or find a return, add each physical item, and enter its intake location. The system checks required fields and duplicates before saving. An inspector records the condition and test result. The manager then approves the next step.

**Repair and restock:** The manager assigns a work order for an item approved for repair. The technician records the completed work and cost. An inspector checks the item. A pass allows manager approval for restocking, and a failure would either send it back for repair or another decision. Staff confirm the final movement, and the system closes the item. If that update fails, its location and status remain unchanged.

## 7. Reports and Queries

| Report | Required output |
|---|---|
| Open returns | Item ID, SKU, status, location, and days since receipt. Filter by status or location; sort oldest first. |
| Item history | For a selected item, show inspections, repairs, and movements by date, with staff names. Claim details are visible to managers. |
| Monthly return rate | For each product: received units, sold units, and received / sold x 100. Missing or zero sales produces N/A. |
| Recovery value | For items completed in a chosen period: restock estimated value or liquidation proceeds, vendor payments received, repair costs, disposal costs, and net recovery. |
| Turnaround and delays | Average days from receipt to completion, grouped by final outcome. Separately list open items older than seven days. |

Return rate compares same-month activity, not the return rate of a sales cohort. Net recovery adds recovery amounts and vendor payments, then subtracts repair and disposal costs. Show estimates separately from cash received. Aggregate repairs per item before joining other events to avoid duplicate totals.

## 8. Security and Audit History

Staff may change only records related to their roles. Technicians may update only assigned work orders. Managers control approvals, claims, and financial reports. The read-only audit log records the user, time, record, and old/new values for status, location, approval, cost, claim, and role changes.

## 9. Assumptions and Constraints

The project covers one warehouse, one unit per return line, and one settlement per claim. Sales totals are entered manually. The MySQL database will use fictional data and third normal form. SQL queries will demonstrate reports in the OLAP part of the Project.

## 10. Acceptance Criteria

The database will be checked using sample records that include a direct restock, a successful repair, a failed repair, a liquidation, a disposal, and a vendor claim. These are planned tests for the implementation.

| Requirement | Test and expected result |
|---|---|
| FR-01, FR-02; BR-01 to BR-03 | Create products and a return containing two items. Reject a duplicate SKU, an unknown product, and a missing required serial number. Reject a second open return for the same product and serial number. |
| FR-03, FR-04; BR-04, BR-05 | Record an inspection and manager decision. Reject an invalid condition grade, a decision before inspection, and an approval attempted by receiving staff. |
| FR-05, FR-06; BR-06, BR-08 | Complete a repair with $10 labor and $5 parts. Reject a negative cost and a second open work order. A failed final check blocks restocking; a later pass permits approval. |
| FR-07; BR-07 | Move an approved item to saleable stock. Confirm its movement and updated location. Force a failure during another move and verify that neither record changes. |
| FR-08, FR-09; BR-08 | Create a claim, record its settlement, and retrieve the related item by serial number. Reject a second claim for that item. |
| FR-10 | For 10 returned units and 200 sold, show a 5% return rate. For a $60 restock estimate, $5 vendor payment, and $15 repair cost, show $50 net recovery. |
| FR-10 | For items completed in two and four days, show a three-day average. Include an eight-day open item in the delayed-items report, but exclude it from the completed-items average. |
| FR-11 | Confirm that a technician cannot approve a final outcome or change claim amounts. Change an approved status and verify that the user, time, and old/new values appear in the audit log. |

Evidence will include INSERT and UPDATE statements, failed validations, JOIN and GROUP BY results, access tests, and rollback results. The ER diagram will connect these requirements to records and relationships.
