# Warehouse Returns and Refurbishment Tracking System — ERD 2.1

Rajdeep Villuri and Hunter Yee · Database Systems Implementations · October 24, 2026  
Based on `warehouse_returns_frd_simplified_v2_1.md`, FRD version 2.1.

## What to open

Open **warehouse_returns_erd_v2_1.drawio** in draw.io / diagrams.net. It is one editable file containing two tabs:

1. **01 Warehouse workflow**: the 10 operational tables, all proposed attributes and types, and core relationships. Present this tab first.
2. **02 Users and reference data**: the remaining five tables, User–Role M:N mapping, attribute notation examples, and every actor/reference relationship continued from tab 01.

Each SVG is an export of the corresponding tab using the same shapes, text and connector coordinates. The grey cross-page boxes and explicitly marked aliases repeat existing entities; they are not extra tables. There are **15 distinct tables**, not 15 plus the aliases. Both tabs form one complete ERD. The `docs/` folder contains the editable source, both SVGs, this explanation and the matching FRD Markdown.

## Notation

This is a combined conceptual/logical ERD: entities use rectangles listing their relational attributes and SQL type aliases, relationships use named diamonds, and conceptual attribute types are illustrated with Chen ovals on tab 02.

- **1:1**: ReturnItem–VendorClaim. An item has zero or one lifetime claim; each claim belongs to exactly one item.
- **1:N**: Return–ReturnItem and the other parent-to-child relationships. **N:1** is the reverse reading, as shown by Inspection–WorkOrder. These are the same class of relationship in opposite directions.
- **M:N**: User–Role. The upper diamond is conceptual; UserRole implements it with two 1:N relationships and a composite primary key. Do not create an extra direct User–Role FK.
- Endpoint **1**, **N** and **M** indicate maximum cardinality. **T** means total participation, shown with a double line; **P** means partial participation, shown with a single line. A 1:1 relationship can still have optional participation.
- Relationship ratios follow the named relationship's endpoints. Use the endpoint labels when reading a relationship from right to left or bottom to top; the table below provides each direction explicitly.
- The double ReturnItem rectangle and double **contains** diamond identify the weak entity and its identifying relationship. Both Return and ReturnItem have total participation in contains: a committed return has at least one line, and each line requires its owner. WorkOrder is also dependent on its owning item: its double rectangle and double has repairs diamond identify the local-number relationship. An item may have no repairs, but each work order requires its item.
- Underlining and **PK** identify key attributes. ReturnItem.LineNumber is its partial key, illustrated by a dashed underline on tab 02. Its complete key is `(ReturnID, LineNumber)`.
- **FK** identifies a foreign-key column. **FK I** marks a member of the composite ReturnItem key; **FK U** targets User; **FK R** targets ReferenceValue; **FK W** is the conditional same-item work-order relationship. A composite FK is one relationship using several columns together.
- **UK1** mark grouped unique keys within their own table. The same label in different tables does not indicate a shared constraint. `NULL` means nullable; unmarked columns are required.
- Vendor.Contact is composite and decomposes into ContactName, ContactEmail and Phone. Only those atomic columns are stored.
- The double oval for Assigned roles is a multivalued conceptual attribute stored through UserRole, not as text containing a list.
- The dashed oval for Net recovery is derived for RQ-04. It is calculated from item values, repair totals and settled vendor claims; it is not a stored ReturnItem field.

## Complete relationship register

The participation columns refer to participation of the named endpoint in that relationship, not the number of children. For example, Product is partial in its relationship to ReturnItem because a product can exist before any unit is returned; each ReturnItem participates totally because it requires a product.

| From | Named relationship | To | Maximum ratio | From participation | To participation |
| --- | --- | --- | --- | --- | --- |
| Return | contains | ReturnItem | 1:N | total | total |
| Product | identifies | ReturnItem | 1:N | partial | total |
| ReturnItem | has checks | Inspection | 1:N | partial | total |
| ReturnItem | has repairs | WorkOrder | 1:N | partial | total |
| Inspection | checks repair | WorkOrder | N:1 | partial | partial |
| ReturnItem | has moves | InventoryMovement | 1:N | partial | total |
| ReturnItem | has claim | VendorClaim | 1:1 | partial | total |
| Product | summarizes | SalesSummary | 1:N | partial | total |
| Vendor | supplies | Product | 1:N | partial | total |
| Location | holds | ReturnItem | 1:N | partial | total |
| Location (source) | source of | InventoryMovement | 1:N | partial | total |
| Location (destination) | destination of | InventoryMovement | 1:N | partial | total |
| Vendor | receives claim | VendorClaim | 1:N | partial | total |
| User | has membership | UserRole | 1:N | partial | total |
| Role | grants role | UserRole | 1:N | partial | total |
| User (conceptual) | has roles | Role (conceptual) | M:N | partial | partial |
| User | performs | AuditLog | 1:N | partial | total |
| User | receives | Return.ReceivingUserID | 1:N | partial | total |
| User | approves | ReturnItem.ApprovedByUserID | 1:N | partial | partial |
| User | inspects | Inspection.InspectorUserID | 1:N | partial | total |
| User | is assigned | WorkOrder.AssignedTechnicianUserID | 1:N | partial | total |
| User | moves | InventoryMovement.MovedByUserID | 1:N | partial | total |
| User | records claim | VendorClaim.RecordedByUserID | 1:N | partial | total |
| User | enters totals | SalesSummary.EnteredByUserID | 1:N | partial | total |
| ReferenceValue | classifies | ReturnItem.ReturnReasonID | 1:N | partial | total |
| ReferenceValue | classifies | ReturnItem.ItemStatusID | 1:N | partial | total |
| ReferenceValue | classifies | ReturnItem.ApprovedOutcomeID | 1:N | partial | partial |
| ReferenceValue | classifies | Inspection.InspectionTypeID | 1:N | partial | total |
| ReferenceValue | classifies | Inspection.ConditionGradeID | 1:N | partial | total |
| ReferenceValue | classifies | Inspection.InspectionResultID | 1:N | partial | total |
| ReferenceValue | classifies | WorkOrder.WorkOrderStatusID | 1:N | partial | total |
| ReferenceValue | classifies | VendorClaim.ClaimStatusID | 1:N | partial | total |
| ReferenceValue | classifies | Location.LocationTypeID | 1:N | partial | total |
| ReferenceValue | classifies | InventoryMovement.MovementTypeID | 1:N | partial | total |

A User may have no role memberships in the historical model, but an active account requires at least one active role before it can act. Inspection–WorkOrder participation is conditional: Initial has no work order; PostRepair and Final for a repaired item require its most recently completed work order. Final on an unrepaired item has no order.

## Foreign-key mapping

All child columns below reference primary keys unless a supporting unique key is stated. Every composite item FK includes both ReturnID and LineNumber.

| Child column(s) | Parent key | Optional / domain rule |
| --- | --- | --- |
| Product.VendorID | Vendor.VendorID | Required |
| Return.ReceivingUserID | User.UserID | Required |
| ReturnItem.ReturnID | Return.ReturnID | Required; identifying owner |
| ReturnItem.ProductID | Product.ProductID | Required |
| ReturnItem.CurrentLocationID | Location.LocationID | Required |
| ReturnItem.ApprovedByUserID | User.UserID | Nullable until approval; Manager required |
| Inspection.(ReturnID, LineNumber) | ReturnItem.(ReturnID, LineNumber) | Required |
| Inspection.InspectorUserID | User.UserID | Required; Inspector role |
| Inspection.(ReturnID, LineNumber, WorkOrderNumber) | WorkOrder.(ReturnID, LineNumber, WorkOrderNumber) | WorkOrderNumber nullable; composite parent PK; conditional order required |
| WorkOrder.(ReturnID, LineNumber) | ReturnItem.(ReturnID, LineNumber) | Required |
| WorkOrder.AssignedTechnicianUserID | User.UserID | Required; Technician role |
| InventoryMovement.(ReturnID, LineNumber) | ReturnItem.(ReturnID, LineNumber) | Required |
| InventoryMovement.SourceLocationID | Location.LocationID | Required |
| InventoryMovement.DestinationLocationID | Location.LocationID | Required |
| InventoryMovement.MovedByUserID | User.UserID | Required |
| VendorClaim.(ReturnID, LineNumber) | ReturnItem.(ReturnID, LineNumber) | Required; composite UK1 makes the item unique |
| VendorClaim.VendorID | Vendor.VendorID | Required |
| VendorClaim.RecordedByUserID | User.UserID | Required; Manager role |
| SalesSummary.ProductID | Product.ProductID | Required |
| SalesSummary.EnteredByUserID | User.UserID | Required; Manager role |
| UserRole.UserID | User.UserID | Required |
| UserRole.RoleID | Role.RoleID | Required |
| AuditLog.UserID | User.UserID | Required; trusted authenticated actor |
| ReturnItem.ReturnReasonID | ReferenceValue.ReferenceValueID | Required; Domain = ReturnReason |
| ReturnItem.ItemStatusID | ReferenceValue.ReferenceValueID | Required; Domain = ItemStatus |
| ReturnItem.ApprovedOutcomeID | ReferenceValue.ReferenceValueID | Nullable; Domain = Disposition |
| Inspection.InspectionTypeID | ReferenceValue.ReferenceValueID | Required; Domain = InspectionType |
| Inspection.ConditionGradeID | ReferenceValue.ReferenceValueID | Required; Domain = ConditionGrade |
| Inspection.InspectionResultID | ReferenceValue.ReferenceValueID | Required; Domain = InspectionResult |
| WorkOrder.WorkOrderStatusID | ReferenceValue.ReferenceValueID | Required; Domain = WorkOrderStatus |
| VendorClaim.ClaimStatusID | ReferenceValue.ReferenceValueID | Required; Domain = ClaimStatus |
| Location.LocationTypeID | ReferenceValue.ReferenceValueID | Required; Domain = LocationType |
| InventoryMovement.MovementTypeID | ReferenceValue.ReferenceValueID | Required; Domain = MovementType |

The WorkOrder primary key is `(ReturnID, LineNumber, WorkOrderNumber)`. WorkOrderNumber is a local positive number that may repeat on different items. Inspection references all three columns together, so its optional number can identify only a work order on the same item. There is no global work-order identifier or separate supporting unique key. Controlled writes must also check that this is the latest completed order and that the inspection time is at or after completion. An FK cannot enforce those temporal rules alone.

ReferenceValueID is a surrogate ID. The **expected domain and active flag must be checked in controlled writes**: an FK to ReferenceValueID by itself does not prevent assigning a valid ClaimStatus ID as an inspection grade. The unique `(Domain, Code)` key prevents duplicate codes within a category. Code and Domain remain stable once referenced. Administrators edit descriptions/active flags, preserving history; required workflow values cannot be disabled while needed by open work or enabled transitions. Role and Location remain separate tables.

AuditLog.RecordKey identifies the affected record descriptively. It is not an enforced polymorphic FK to all 15 tables. OldValues and NewValues contain historical audit payloads, not a substitute for relational operational columns.

## Controlled values from FRD 2.1

| Domain | Values |
| --- | --- |
| ReturnReason | Damaged, Defective, WrongItem, Unwanted, Other; administrators may add reasons. |
| ConditionGrade | A like new; B usable with wear; C needs repair; D beyond repair. |
| ItemStatus | AwaitingInspection, AwaitingDecision, ApprovedForRepair, InRepair, AwaitingFinalInspection, ApprovedForRestock, ApprovedForLiquidation, ApprovedForDisposal, Restocked, Liquidated, Disposed. |
| WorkOrderStatus | Open, InProgress, Completed, Cancelled. |
| ClaimStatus | Submitted, Approved, Settled, Denied, Cancelled. |
| InspectionType | Initial, PostRepair, Final. |
| InspectionResult | Pass, Fail, Inconclusive. |
| Disposition | Repair, Restock, Liquidate, Dispose. Repair is intermediate. |
| LocationType | Intake, Inspection, Repair, Storage, SaleableStock, LiquidationExit, DisposalExit. |
| MovementType | Relocate, Restock, Liquidate, Dispose. |

These are rows in the same ReferenceValue table, not ten separate entities. Role has its own five defined role codes. Labels and active flags do not redefine workflow transitions or authorization.

## Rules to explain during the midterm

1. Each ReturnItem is one physical unit. Three units of the same product require three line numbers, not Quantity = 3. A required serial cannot be blank; a normalized product/serial pair cannot have two open returns, including concurrent intake.
2. An item has many historical work orders but at most one Open or InProgress order. Create an order only after Repair approval. Only its assigned Technician can start/complete it. Open orders can be cancelled; started orders must complete, even if the repair fails. Completed orders are immutable.
3. Initial inspection occurs at intake. PostRepair or Final checks a completed repair; both are not mandatory for the same order. An optional additional Final check may occur while awaiting decision. Latest Fail or Inconclusive prevents restock. Restock also requires grade A/B and Manager approval.
4. A claim is zero or one for the item's lifetime, enforced by the unique composite item key. New claims cannot be created after item completion; an existing approved claim can settle later. One settlement is recorded; there are no partial-payment records.
5. Routine movement changes location without changing workflow status. Final movement into SaleableStock, LiquidationExit or DisposalExit commits the corresponding terminal state and CompletionAt. The source must match the current location; the destination must be active and different. Movement, item update and audit must commit or roll back together.
6. Separate RestockEstimatedValue, LiquidationProceeds and DisposalCost support the approved path. Work orders store total labor and total parts costs; repair-parts inventory is outside scope. Store financial inputs and calculate net recovery, including received claim settlements. Aggregate work orders per item before joins to avoid duplicated amounts.
7. Net recovery = restock estimate + liquidation proceeds + settled vendor amount − repair labor − repair parts − disposal cost. Keep estimates separate from cash. Non-applicable values contribute zero; negative net recovery is allowed. Completion reports use the item's completion period; later claim settlement updates rerun totals.
8. SalesSummary supports the same-month return-rate denominator. CalendarMonth is the month's first day, unique per product. Rate = received item rows / sold units × 100; missing or zero sales gives N/A.
9. Preserve referenced history by deactivation rather than deletion. No reopening or general correction workflow is added. Terminal items cannot receive new movements, repairs or inspections under the defined states. Audit entries are appended by trusted operations; ordinary users cannot directly edit them.
10. Foreign keys enforce identity, while controlled transactions/procedures enforce permissions, expected reference domains, active flags, temporal order, concurrent open-work restrictions and workflow transitions. The ERD is a proposed design, not evidence that SQL tests already passed.

## Attribute dictionary

Proposed MySQL aliases: INT/BIGINT/SMALLINT are UNSIGNED; TS = DATETIME(6); MONEY = DECIMAL(12,2); Vn = VARCHAR(n); BOOL = TINYINT(1). `NULL` means SQL NULL is allowed. Booleans require 0/1 validation. Amounts are nonnegative decimal inputs; claims/settlements must be positive when submitted/received. CalendarMonth and timestamps use the warehouse's documented time-zone convention. In SQL, quote reserved names such as `Return` and `User`, or consistently map them to names such as ReturnHeader and AppUser.

### Return

| Key flags | Attribute | Proposed type |
| --- | --- | --- |
| PK | ReturnID | INT |
| UK | ExternalReference | V100 |
| — | ReceivedAt | TS |
| FK U | ReceivingUserID | INT |

One or more lines at commit. User references continue on tab 02.

### Inspection

| Key flags | Attribute | Proposed type |
| --- | --- | --- |
| PK | InspectionID | INT |
| FK I | ReturnID | INT |
| FK I | LineNumber | SMALLINT |
| FK U | InspectorUserID | INT |
| — | InspectedAt | TS |
| FK R | InspectionTypeID | INT |
| FK R | ConditionGradeID | INT |
| FK R | InspectionResultID | INT |
| — | Notes | TEXT NULL |
| FK W | WorkOrderNumber | INT NULL |

FK W = item key + local WorkOrderNumber. Initial / PostRepair / Final; latest same-item order.

### WorkOrder

| Key flags | Attribute | Proposed type |
| --- | --- | --- |
| PK FK I | ReturnID | INT |
| PK FK I | LineNumber | SMALLINT |
| PK | WorkOrderNumber | INT |
| FK U | AssignedTechnicianUserID | INT |
| FK R | WorkOrderStatusID | INT |
| — | CreatedAt | TS |
| — | StartedAt | TS NULL |
| — | CompletedAt | TS NULL |
| — | WorkDetails | TEXT NULL |
| — | TotalLaborCost | MONEY |
| — | TotalPartsCost | MONEY |

Weak: PK (ReturnID, LineNumber, WorkOrderNumber). Local number; at most one active order per item.

### Product

| Key flags | Attribute | Proposed type |
| --- | --- | --- |
| PK | ProductID | INT |
| UK | SKU | V64 |
| — | Description | V255 |
| FK | VendorID | INT |
| — | SerialRequired | BOOL |
| — | IsActive | BOOL |

A product has one primary vendor. Required serials checked during intake.

### ReturnItem

| Key flags | Attribute | Proposed type |
| --- | --- | --- |
| PK FK | ReturnID | INT |
| PK | LineNumber | SMALLINT |
| FK | ProductID | INT |
| — | SerialNumber | V100 NULL |
| FK R | ReturnReasonID | INT |
| FK R | ItemStatusID | INT |
| FK | CurrentLocationID | INT |
| FK R | ApprovedOutcomeID | INT NULL |
| FK U | ApprovedByUserID | INT NULL |
| — | ApprovedAt | TS NULL |
| — | CompletionAt | TS NULL |
| — | RestockEstimatedValue | MONEY NULL |
| — | LiquidationProceeds | MONEY NULL |
| — | DisposalCost | MONEY NULL |

WEAK ENTITY: PK (ReturnID, LineNumber). Partial key LineNumber; one physical unit per line.

### InventoryMovement

| Key flags | Attribute | Proposed type |
| --- | --- | --- |
| PK | MovementID | BIGINT |
| FK I | ReturnID | INT |
| FK I | LineNumber | SMALLINT |
| FK | SourceLocationID | INT |
| FK | DestinationLocationID | INT |
| — | MovedAt | TS |
| FK U | MovedByUserID | INT |
| FK R | MovementTypeID | INT |
| — | Notes | TEXT NULL |

Source equals the current location. Movement + item + audit commit together.

### SalesSummary

| Key flags | Attribute | Proposed type |
| --- | --- | --- |
| PK FK | ProductID | INT |
| PK | CalendarMonth | DATE |
| — | UnitsSold | INT |
| — | SourceReference | V150 |
| FK U | EnteredByUserID | INT |
| — | UpdatedAt | TS |

PK (ProductID, CalendarMonth). First day of month; whole nonnegative units.

### Vendor

| Key flags | Attribute | Proposed type |
| --- | --- | --- |
| PK | VendorID | INT |
| — | VendorName | V150 |
| — | ContactName | V150 NULL |
| — | ContactEmail | V255 NULL |
| — | Phone | V40 NULL |
| — | IsActive | BOOL |

Contact is composite conceptually. Stored as separate atomic columns.

### Location

| Key flags | Attribute | Proposed type |
| --- | --- | --- |
| PK | LocationID | INT |
| UK | LocationCode | V40 |
| — | LocationName | V150 |
| FK R | LocationTypeID | INT |
| — | IsActive | BOOL |

Physical area or exit; no free-text locations. Referenced history survives deactivation.

### VendorClaim

| Key flags | Attribute | Proposed type |
| --- | --- | --- |
| PK | ClaimID | INT |
| FK I UK1 | ReturnID | INT |
| FK I UK1 | LineNumber | SMALLINT |
| FK | VendorID | INT |
| — | RequestedAmount | MONEY |
| FK R | ClaimStatusID | INT |
| — | SubmittedAt | TS |
| — | SettlementAmount | MONEY NULL |
| — | SettledAt | TS NULL |
| FK U | RecordedByUserID | INT |
| — | ClaimReference | V150 NULL |

UK1 (ReturnID, LineNumber). Zero or one lifetime claim; one settlement.

### User

| Key flags | Attribute | Proposed type |
| --- | --- | --- |
| PK | UserID | INT |
| UK | LoginIdentifier | V100 |
| — | DisplayName | V150 |
| — | IsActive | BOOL |

Authenticated business identity. An active role is required to act.

### UserRole

| Key flags | Attribute | Proposed type |
| --- | --- | --- |
| PK FK | UserID | INT |
| PK FK | RoleID | INT |

Composite PK (UserID, RoleID). Resolves the conceptual M:N relationship.

### Role

| Key flags | Attribute | Proposed type |
| --- | --- | --- |
| PK | RoleID | INT |
| UK | RoleCode | V32 |
| — | Description | V150 |
| — | IsActive | BOOL |

Receiving / Inspector / Technician / Manager / Administrator; controlled permissions.

### AuditLog

| Key flags | Attribute | Proposed type |
| --- | --- | --- |
| PK | AuditID | BIGINT |
| FK | UserID | INT |
| — | RecordedAt | TS |
| — | Action | V32 |
| — | EntityName | V64 |
| — | RecordKey | JSON |
| — | OldValues | JSON NULL |
| — | NewValues | JSON NULL |
| — | TransactionID | V64 |

Append-only, written by trusted operations. RecordKey is a description, not a generic FK.

### ReferenceValue

| Key flags | Attribute | Proposed type |
| --- | --- | --- |
| PK | ReferenceValueID | INT |
| UK1 | Domain | V32 |
| UK1 | Code | V32 |
| — | Description | V150 |
| — | IsActive | BOOL |

UK1 (Domain, Code); 10 controlled domains. No separate tables for each list.

## Midterm rubric coverage

| Required component | Where to show it |
| --- | --- |
| At least 8–10 entities | 15 distinct table definitions across two tabs. |
| One-to-one | ReturnItem–VendorClaim; optional item side, required claim side. |
| One-to-many / many-to-one | Return–ReturnItem; reverse reading of Inspection–WorkOrder. |
| Many-to-many | User–Role conceptual diamond; UserRole composite-key join table. |
| PK, FK and proposed types | Every table row on both tabs; full dictionary above. |
| Named relationship diamonds | All 33 physical FK relationships plus conceptual User–Role M:N. |
| Weak entity / identifying relationship | ReturnItem/contains and dependent WorkOrder/has repairs use double notation; item partial key LineNumber, order partial key WorkOrderNumber. |
| Participation | T/P labels and double/single lines on every relationship endpoint. |
| Attribute types | Underlined keys; dashed partial-key underline; composite Contact; double-oval Assigned roles; dashed-oval Net recovery. |
| Editable source and SVG exports | One two-tab .drawio and one matching SVG per tab. |

Normalization rationale: independent product/vendor data, repeating inspection/work-order/movement events, monthly product totals, and role memberships have separate tables. Controlled descriptions live in ReferenceValue instead of being copied into transactional rows. Calculated net recovery is not stored. The [technical design](warehouse_returns_technical_design.md) records functional dependencies and the 3NF rationale, including the local composite work-order key. Validate the eventual DDL against that design.

## Presentation path

Start on tab 01 at Return → ReturnItem. Explain one unit per line and the weak composite key. Follow inspections, repair orders and movements; point to the optional single vendor claim. On tab 02, show UserRole resolving M:N and the single ReferenceValue table replacing separate lookup tables. Use the attribute examples to identify key, partial-key, composite, multivalued and derived notation. The lower rows document continued foreign keys; they need not each be narrated during the presentation.

This package supersedes the earlier 24-table ERD for FRD 1.1. Use the files ending in **v2_1** together with FRD 2.1. Earlier output files are retained separately as history.
