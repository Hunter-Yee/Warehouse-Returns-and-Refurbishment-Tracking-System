# Professor Feedback on Functional Requirements

## 1. Define the item lifecycle and controlled status values

The document frequently refers to an item’s “status,” “approved outcome,” work-order status, and claim status, but it does not define the allowed values or valid transitions between them. For example, an item might be received, awaiting inspection, awaiting manager decision, approved for repair, in repair, awaiting final inspection, approved for restock, restocked, liquidated, disposed, or closed

Without a defined lifecycle, the design may permit invalid states such as:

- A restocked item also marked as awaiting inspection.

- A disposed item receiving a later repair order.

- A closed item being moved back to intake with no reopening process.

- A repair work order created for an item not approved for repair.

- A vendor claim opened after the item has been permanently closed, if that is not allowed.

Add a status/business-rule section like this

| Entity | Suggested controlled values |
|---|---|
| ReturnItem status | Received, Awaiting Inspection, Awaiting Decision, Approved for Repair, In Repair, Awaiting Final Inspection, Approved for Restock, Restocked, Liquidated, Disposed, Closed |
| WorkOrder status | Open, Assigned, In Progress, Completed, Failed Inspection, Cancelled |
| VendorClaim status | Draft, Submitted, Under Review, Approved, Partially Settled, Settled, Denied, Cancelled |
| Inspection result | Pass, Fail, Inconclusive |
| Approved outcome | Repair, Restock, Liquidate, Dispose |

Then add a rule

**BR-09:** A ReturnItem status and approved outcome shall follow defined workflow transitions. A work order may be created only for an item approved for repair. An item may be moved to saleable stock only after manager approval for restocking and a passing applicable inspection.

This revision is important because status transitions are central to the system’s workflow.


## 2. Clarify the difference between “status,” “outcome,” and “completion”

The ReturnItem includes status, location, approved outcome, completion date, and recovery amount, but the document does not define their distinct purposes

Recommended distinction:

- Status: Where the item is currently in its operational workflow.

- Approved outcome: The manager’s selected final disposition path—Repair, Restock, Liquidate, or Dispose.

- Completion date: Date the item’s final disposition is completed and the item is closed.

- Recovery amount: A defined monetary value associated with the selected disposition, not a vague catch-all amount.

State whether recovery amount means:

- Estimated resale value for a restocked item.

- Actual liquidation proceeds.

- Vendor payment.

- Net recovery after repair and disposal costs.

- Something else.


## 3. Improve the financial data model

The recovery-value report requires:

- Restock estimated value or liquidation proceeds.

- Vendor payments received.

- Repair costs.

- Disposal costs.

- Net recovery.

The data requirements include repair costs, vendor payment amounts, and a generic ReturnItem.recovery amount, but they do not explicitly identify where disposal costs, liquidation proceeds, or restock estimated values are stored.

Add fields or entities that directly support the report. For example:

| Needed value | Suggested data location |
|---|---|
| Restock estimated value | ReturnItem.RestockEstimatedValue or a DispositionValue record |
| Liquidation proceeds | ReturnItem.LiquidationProceeds or a separate liquidation/disposition transaction |
| Disposal cost | ReturnItem.DisposalCost or a disposition-cost record |
| Repair labor cost | WorkOrder.LaborCost |
| Repair parts cost | WorkOrder.PartsCost |
| Vendor cash received | VendorClaim.AmountReceived |
| Net recovery | Calculated in SQL; avoid storing unless there is a business need for a historical snapshot |

Suggested additional requirement:

**FR-12:** The system shall record the financial values needed to calculate recovery for a completed return item, including restock estimated value, liquidation proceeds, disposal cost, repair labor cost, repair parts cost, and vendor payments received.

Also clarify that net recovery should normally be calculated, not stored, because it depends on multiple underlying records and should remain accurate if permitted adjustments occur.


## 4. Reconsider “at most one vendor claim”

The document states that each return item can have “at most one vendor claim,” and BR-08 states that an item has at most one vendor claim.

This may be acceptable as a deliberate simplifying assumption, but the requirement should be more precise. The business workflow may need:

- One claim per item ever; or

- One open claim per item, allowing a later replacement/reopened claim; or

- Several claim submissions/adjustments over time.

The document is inconsistent because BR-08 says “at most one … vendor claim,” while the rule’s implementation note refers to “one vendor claim,” and the acceptance criterion rejects a second claim for the item.

If the intended constraint is one claim total, state it clearly:

**BR-10:** A ReturnItem may have zero or one VendorClaim for the lifetime of the item record.

If the intended constraint is only one active claim, use:

**BR-10:** A ReturnItem may have at most one active VendorClaim. A new claim may be created only after the prior claim is settled, denied, cancelled, or closed.


## 5. Clarify repair-parts handling

FR-05 records only total “labor and parts costs” on a work order. This is fine for a simplified repair-cost model, but the phrase “parts costs” could imply individual repair parts, quantities, and inventory tracking.

The document should decide which scope it intends:

| Option | Design implication |
|---|---|
| Total cost only | Keep WorkOrder.LaborCost and WorkOrder.PartsCost; state that repair-parts inventory is out of scope |
| Individual repair parts | Add Part, WorkOrderPart, quantity used, unit cost, and possibly a repair-parts inventory workflow |

Because the current project already focuses on tracking returned inventory rather than repair-parts stock, the simpler option is likely better:

Assumption: The system records total labor and total parts cost for each work order. Inventory of repair parts and individual part consumption are outside the scope of this project.

This prevents an ERD reviewer from expecting an additional parts inventory subsystem.


## 6. Clarify “one unit per return line”

The project assumes “one unit per return line,” while the ReturnItem composite key is ReturnID + LineNumber. This is logically workable, but it should be made explicit that each ReturnItem record represents one physical unit.

That matters because:

- Serialized products naturally need one unit per line.

- Non-serialized products could otherwise be modeled with a quantity field.

- The reports calculate “received units,” so the source of unit counts must be clear.

Suggested wording:

Each ReturnItem record represents exactly one physical product unit. A return containing three units of the same product shall contain three ReturnItem records with separate line numbers.

Alternatively, if quantity is desired:

ReturnItem contains a QuantityReceived field, but serialized items must have QuantityReceived = 1.

The current one-unit-per-line decision is easier for inspection, repair, movement, and serial tracking, so it is a reasonable choice.


## 7. Address the inspection model more precisely

The document says final checks identify the repair order, but this should be expressed as a formal relationship and rule.

Recommended model:

- Inspection has InspectionID.

- Inspection references ReturnID and LineNumber or a surrogate ReturnItemID.

- A final inspection optionally references WorkOrderID.

- An inspection has an inspection type, such as Initial, PostRepair, or Final.

- A result uses controlled values such as Pass, Fail, or Inconclusive.

Suggested requirement:

**FR-13:** The system shall classify each inspection as Initial, Post-Repair, or Final. A post-repair or final inspection shall reference the related work order when the item was repaired.

Suggested business rule:

**BR-11:** A ReturnItem approved for restock after repair must have a passing post-repair or final inspection associated with its most recently completed work order.

This makes FR-06 much easier to implement and test.


## 8. Define the location model

The document uses intake location, current location, source location, destination location, and location codes. This is conceptually correct, but the database design needs to clarify whether locations represent:

- Warehouse zones.

- Shelves or bins.

- Workstations.

- Repair bays.

- Saleable stock.

- Liquidation staging.

- Disposal areas.

- Virtual/administrative locations, such as “Closed” or “Vendor Claim Pending.”

The student should define a Location table with at least:

- LocationID.

- Location code.

- Location name/description.

- Location type.

- Active status.

The data model should not store free-text locations in the ReturnItem or InventoryMovement tables if the report/filter requirements depend on location.

Suggested rule:

**BR-12:** Every active ReturnItem shall reference one valid current Location. An InventoryMovement must reference valid source and destination Location records.


## 9. Tighten security and authorization details

The document correctly says that technicians may update only assigned work orders, managers control approvals/claims/financial reports, and the audit log is read-only. The requirement is conceptually solid but should be more specific about the intended implementation.

Potential issue: application-level role rules and database-level MySQL privileges are not the same thing. If the project will demonstrate the rules with MySQL users/roles, it should state that. If it will simulate users through a User table and stored procedures, it should describe that approach.

For a database implementation project, a practical approach is:

- Store business users and roles in User, Role, and UserRole.

- Use stored procedures or controlled transactions to enforce business authorization.

- Optionally create limited MySQL accounts to demonstrate broad access separation.

- Keep audit records append-only and deny ordinary application roles UPDATE and DELETE access on AuditLog.

Suggested additional requirement:

**FR-14:** The system shall record the authenticated business user responsible for each protected transaction. A Technician may update a WorkOrder only when the WorkOrder’s assigned technician matches that user’s technician record.

The document should also clarify whether an administrator is allowed to inspect but not modify the audit log. “Read-only” should mean that normal staff cannot insert, update, or delete audit records directly; the database trigger or controlled process creates them.


## 10. Add requirements for reference/lookup data administration

The document relies on controlled lists for return reasons, condition grades, statuses, and locations, but it does not say who can create or maintain those lists.

Add a requirement such as:

**FR-15:** The system shall allow an Administrator to manage active reference values for locations, return reasons, inspection grades, statuses, and roles, while preserving historical records that reference inactive values.

This is especially relevant because deleting a location, grade, or reason that appears in history could break referential integrity.


### Specific wording and consistency improvements

- In FR-04, “approve repair, restock, liquidation, or disposal” is understandable, but a manager likely approves an outcome or disposition, not “repair” itself. Consider:

“The system shall allow a Manager to approve a disposition of Repair, Restock, Liquidation, or Disposal after a completed initial inspection.”

- In FR-06, clarify whether a passing inspection is required for direct restock as well as repaired items. The wording suggests yes, which is reasonable, but the exact workflow should state it.

- In FR-07, “update the item’s current location and status in the same transaction” is strong, but the student should identify the event that causes the status change. Not every movement may change status—for example, a move from one repair shelf to another might change location but not workflow status.

- In FR-08, “payments received” should be clarified. The database is not processing payments; it is recording claim settlement amounts received from vendors. Consider:

“The system shall record vendor claims, requested amounts, claim statuses, settlement amounts received, and settlement dates.”

- In FR-09, the phrase “authorized users” should connect to the role model. For example, all operational users may search standard return data, while vendor claim amounts may be restricted to managers.

- In FR-10, the report list is well designed, but give each report an identifier such as RQ-01 through RQ-05. This will make testing and traceability clearer.

- The acceptance table uses FR-10 twice. This is not incorrect because one requirement covers multiple reports, but labelling the report tests as FR-10 / RQ-03 and FR-10 / RQ-05 would improve traceability.


### Recommended additions

- **FR-12:** The system shall record values needed to calculate recovery for completed return items, including restock estimated value, liquidation proceeds, disposal cost, repair labor cost, repair parts cost, and vendor settlement amounts.

- **FR-13:** The system shall classify inspections as Initial, Post-Repair, or Final, and post-repair/final inspections shall identify the related work order when applicable.

- **FR-14:** The system shall allow a Technician to update only work orders assigned to that Technician’s associated user account.

- **FR-15:** The system shall allow an Administrator to manage active reference values for locations, return reasons, grades, statuses, and roles.

- **BR-09:** A ReturnItem, WorkOrder, and VendorClaim shall use controlled status values and permitted lifecycle transitions.

- **BR-10:** A ReturnItem may have zero or one VendorClaim for its lifetime, or at most one active VendorClaim—choose one rule and apply it consistently.

- **BR-11:** A ReturnItem may be restocked only after manager approval and a passing initial, post-repair, or final inspection as required by its workflow.

- **BR-12:** Every active ReturnItem shall have one valid current location, and every InventoryMovement shall reference valid source and destination locations.

- **BR-13:** Once a ReturnItem has reached a completed final disposition, it may not be reopened, reassigned, or moved without a manager-authorized correction process that is audited.
