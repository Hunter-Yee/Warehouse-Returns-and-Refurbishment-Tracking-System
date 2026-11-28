#!/usr/bin/env bash
# FRD 2.1 acceptance criteria AC-01 .. AC-11, plus the midterm-feedback security checks.
# Every business step runs as the real role login through the procedures. The only direct
# setup-account writes are the AC-08 turnaround fixtures (receipt times moved into the past,
# because "completed in two days" cannot be produced in real time); they are labelled FIXTURE.
#
#   bash tests/acceptance_tests.sh TARGET_DB
#
# TARGET_DB must be a FRESH build (no completed items yet): AC-08 checks exact averages.
# Output is saved to tests/results/acceptance_<UTC time>.txt. Exit code 1 if any check fails.
set -uo pipefail
[ "$#" -eq 1 ] || { echo "Usage: bash tests/acceptance_tests.sh TARGET_DB" >&2; exit 2; }
DB=$1; NAME=acceptance
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
header "Acceptance tests (FRD 2.1 AC-01..AC-11)"

DONE=$(as admin "SELECT COUNT(*) FROM ReturnItem WHERE CompletionAt IS NOT NULL")
[ "$DONE" = 0 ] || { echo "Needs a fresh build: $DONE completed items already exist"; exit 2; }

# ---- helpers ---------------------------------------------------------------
q()   { as admin "$1"; }                                   # one value as setup account
rid() { q "SELECT ReturnID FROM ReturnHeader WHERE ExternalReference='$1'"; }
loc() { q "SELECT LocationID FROM Location WHERE LocationCode='$1'"; }
status() { q "SELECT s.Code FROM ReturnItem i JOIN ReferenceValue s ON s.ReferenceValueID=i.ItemStatusID WHERE i.ReturnID=$1 AND i.LineNumber=${2:-1}"; }
here() { q "SELECT CurrentLocationID FROM ReturnItem WHERE ReturnID=$1 AND LineNumber=${2:-1}"; }
item() { local serial=null; [ -n "${2:-}" ] && serial="\"$2\""; echo "{\"sku\":\"$1\",\"serial\":$serial,\"reason\":\"${3:-Defective}\",\"location\":\"INT-01\"}"; }
reg()  { as wr_receiving01 "CALL sp_register_return('$1', '[$2]')" >/dev/null; }
move() { as wr_receiving01 "CALL sp_move_item($1, ${2:-1}, $(here "$1" "${2:-1}"), $(loc "$3"), '$4', NULL)" >/dev/null; }
TECH1=$(q "SELECT UserID FROM AppUser WHERE LoginIdentifier='wr_technician01'")
TECH2=$(q "SELECT UserID FROM AppUser WHERE LoginIdentifier='wr_technician02'")
VAL="ERROR 50001 \(45001\)"; AUTH="ERROR 50003 \(45003\)"; NOTF="ERROR 50004 \(45004\)"; CONF="ERROR 50009 \(45009\)"
DENIED="command denied"

# ============================================================================
step "AC-08  FR-10 RQ-03/RQ-05: return rate, N/A, turnaround, delayed items"
run wr_manager01 "Manager adds products AC08-TOA and AC08-NOS (product maintenance is Manager-only)" \
  "INSERT INTO Product (SKU, Description, VendorID, SerialRequired) SELECT 'AC08-TOA','AC-08 toaster',VendorID,0 FROM Vendor WHERE VendorName='Evergreen Home Goods';
   INSERT INTO Product (SKU, Description, VendorID, SerialRequired) SELECT 'AC08-NOS','AC-08 no-sales product',VendorID,0 FROM Vendor WHERE VendorName='Evergreen Home Goods'"
MONTH=$(q "SELECT DATE_FORMAT(UTC_TIMESTAMP(), '%Y-%m-01')")
run wr_manager01 "Manager enters 200 units sold for $MONTH" "CALL sp_enter_monthly_sales('AC08-TOA', '$MONTH', 200, 'AC08 POS export')"
TEN=$(for i in 1 2 3 4 5 6 7 8 9 10; do printf '%s,' "$(item AC08-TOA '' Unwanted)"; done); TEN=${TEN%,}
run wr_receiving01 "Receiving registers 10 returned units of AC08-TOA in one return" "CALL sp_register_return('AC08-RATE', '[$TEN]')"
reg AC08-NOSALE "$(item AC08-NOS)"
check "10 returned / 200 sold = 5.00%" \
  "SELECT UnitsReturned=10 AND UnitsSold=200 AND ReturnRatePct=5.00 FROM vw_monthly_return_rate WHERE SKU='AC08-TOA' AND CalendarMonth='$MONTH'"
check "Returns with missing sales show N/A (NULL), not 0%" \
  "SELECT ReturnRatePct IS NULL AND UnitsSold IS NULL FROM vw_monthly_return_rate WHERE SKU='AC08-NOS' AND CalendarMonth='$MONTH'"
run wr_manager01 "Manager records zero sales for AC08-NOS" "CALL sp_enter_monthly_sales('AC08-NOS', '$MONTH', 0, 'AC08 zero month')"
check "Zero sales also show N/A" "SELECT ReturnRatePct IS NULL AND UnitsSold=0 FROM vw_monthly_return_rate WHERE SKU='AC08-NOS' AND CalendarMonth='$MONTH'"
for d in 2 4; do
  reg "AC08-T$d" "$(item KBD-500 '' Unwanted)"; R=$(rid "AC08-T$d")
  as wr_inspector01 "CALL sp_record_initial_inspection($R, 1, 'A', 'Pass', 'like new')" >/dev/null
  as wr_manager01 "CALL sp_approve_disposition($R, 1, 'Restock', 15.00)" >/dev/null
  move "$R" 1 SALE-01 Restock
  q "UPDATE ReturnHeader h JOIN ReturnItem i ON i.ReturnID=h.ReturnID SET h.ReceivedAt = i.CompletionAt - INTERVAL $d DAY WHERE h.ReturnID=$R"
  echo "      FIXTURE: AC08-T$d receipt time set to $d days before its completion"
done
reg AC08-OPEN "$(item KBD-500 '' Unwanted)"
q "UPDATE ReturnHeader SET ReceivedAt = UTC_TIMESTAMP(6) - INTERVAL 8 DAY WHERE ExternalReference='AC08-OPEN'"
echo "      FIXTURE: AC08-OPEN received 8 days ago, still open"
check "Completed in 2 and 4 days averages 3.00 days" "SELECT CompletedItems=2 AND AvgDays=3.00 FROM vw_turnaround_by_outcome WHERE FinalOutcome='Restock'"
check "The 8-day open item is listed as delayed (> 7 days)" "SELECT COUNT(*)=1 FROM vw_open_items WHERE ExternalReference='AC08-OPEN' AND ReceivedAt < UTC_TIMESTAMP() - INTERVAL 7 DAY"
check "...and is excluded from the completed average" "SELECT SUM(CompletedItems)=2 FROM vw_turnaround_by_outcome"

# ============================================================================
step "AC-01  FR-01/02: intake, duplicate and serial rules"
run wr_receiving01 "Three units of one SKU are recorded as three lines" \
  "CALL sp_register_return('AC01-A', '[$(item LAP-100 AC01-S1),$(item LAP-100 AC01-S2),$(item LAP-100 AC01-S3)]')"
check "Lines 1, 2, 3 exist, each its own unit awaiting inspection at INT-01" \
  "SELECT GROUP_CONCAT(LineNumber ORDER BY LineNumber)='1,2,3' AND COUNT(DISTINCT SerialNumber)=3 FROM ReturnItem WHERE ReturnID=$(rid AC01-A)"
deny wr_receiving01 "Duplicate return reference is rejected" "CALL sp_register_return('AC01-A', '[$(item KBD-500)]')" "$CONF.*Duplicate external reference"
deny wr_receiving01 "Same reference with surrounding spaces is also a duplicate" "CALL sp_register_return('  AC01-A ', '[$(item KBD-500)]')" "Duplicate external reference"
deny wr_receiving01 "Unknown product is rejected" "CALL sp_register_return('AC01-X1', '[$(item NOPE-1)]')" "$VAL.*Invalid or inactive product SKU"
deny wr_receiving01 "Missing required serial is rejected" "CALL sp_register_return('AC01-X2', '[$(item LAP-100)]')" "$VAL.*Serial number required"
deny wr_receiving01 "A second open unit with the same product/serial is rejected" "CALL sp_register_return('AC01-X3', '[$(item LAP-100 ac01-s1)]')" "$CONF.*already has an open return item"
check "Rejected intakes left no header behind" "SELECT COUNT(*)=0 FROM ReturnHeader WHERE ExternalReference LIKE 'AC01-X%'"
echo "      concurrency: two sessions register the same new serial at the same moment"
( as wr_receiving01 "CALL sp_register_return('AC01-RACE1', '[$(item MON-200 AC01-RACE)]')" >/tmp/wr_race1 2>&1 & )
( as wr_receiving01 "CALL sp_register_return('AC01-RACE2', '[$(item MON-200 AC01-RACE)]')" >/tmp/wr_race2 2>&1 & )
sleep 3
check "Exactly one of the two concurrent intakes succeeded (Product row lock serializes them)" \
  "SELECT COUNT(*)=1 FROM ReturnItem WHERE SerialNumber='AC01-RACE'"
grep -h "ERROR" /tmp/wr_race1 /tmp/wr_race2 | sed 's/^/      loser: /'
deny wr_receiving01 "Receiving cannot bypass the procedure with a direct INSERT (midterm finding)" \
  "INSERT INTO ReturnHeader (ExternalReference, ReceivedAt, ReceivingUserID) VALUES ('BYPASS', UTC_TIMESTAMP(), 1)" "INSERT command denied"

# ============================================================================
step "AC-02 / AC-03 / AC-04  FR-03..06, FR-13/14: inspections, repairs, restock eligibility"
reg AC09-A "$(item LAP-100 AC09-SA)"; A=$(rid AC09-A)
run wr_inspector01 "Initial inspection (no order): Fail, grade C" "CALL sp_record_initial_inspection($A, 1, 'C', 'Fail', 'screen flicker')"
check "Initial inspection has no work order link" "SELECT COUNT(*)=1 FROM Inspection i JOIN ReferenceValue t ON t.ReferenceValueID=i.InspectionTypeID WHERE i.ReturnID=$A AND t.Code='Initial' AND i.WorkOrderNumber IS NULL"
deny wr_receiving01 "Receiving staff cannot approve a disposition" "CALL sp_approve_disposition($A, 1, 'Repair', NULL)" "$DENIED"
deny wr_technician01 "AC-03: an order cannot be assigned without Repair approval" "CALL sp_assign_repair($A, 1, $TECH1)" "$DENIED"
deny wr_manager01 "AC-03: Manager cannot assign before Repair approval" "CALL sp_assign_repair($A, 1, $TECH1)" "$CONF.*approved for repair"
run wr_manager01 "Manager approves Repair with no amount" "CALL sp_approve_disposition($A, 1, 'Repair', NULL)"
run wr_manager01 "Manager assigns order 1 to Taylor Reed" "CALL sp_assign_repair($A, 1, $TECH1)"
deny wr_manager01 "AC-03: a second active order is rejected" "CALL sp_assign_repair($A, 1, $TECH2)" "$CONF.*active work order already exists"
deny wr_technician02 "AC-03: another Technician cannot start it" "CALL sp_start_repair($A, 1, 1)" "$CONF.*assigned to actor"
run wr_technician01 "Assigned Technician starts the repair" "CALL sp_start_repair($A, 1, 1)"
deny wr_inspector01 "AC-04: a check before completion is rejected" "CALL sp_record_postrepair_inspection($A, 1, 1, 'A', 'Pass', NULL)" "$CONF.*not awaiting repair inspection"
deny wr_technician01 "AC-03: negative cost is rejected" "CALL sp_complete_repair($A, 1, 1, 'fixed', -1.00, 5.00)" "$VAL.*nonnegative"
deny wr_technician02 "AC-03: another Technician cannot complete it" "CALL sp_complete_repair($A, 1, 1, 'fixed', 10.00, 5.00)" "$CONF.*Only assigned technician"
run wr_technician01 "AC-03: assigned work completed with \$10 labor and \$5 parts" "CALL sp_complete_repair($A, 1, 1, 'Replaced screen', 10.00, 5.00)"
deny wr_inspector01 "AC-02: a check linked to the wrong order is rejected" "CALL sp_record_postrepair_inspection($A, 1, 99, 'A', 'Pass', NULL)" "$CONF.*latest completed order"
run wr_inspector01 "PostRepair Pass (grade A) linked to the latest order" "CALL sp_record_postrepair_inspection($A, 1, 1, 'A', 'Pass', 'works')"
check "PostRepair is linked to order 1 of the same item" "SELECT COUNT(*)=1 FROM Inspection i JOIN ReferenceValue t ON t.ReferenceValueID=i.InspectionTypeID WHERE i.ReturnID=$A AND t.Code='PostRepair' AND i.WorkOrderNumber=1"
run wr_manager01 "AC-04: restock allowed after PostRepair Pass for the latest order" "CALL sp_approve_disposition($A, 1, 'Restock', 60.00)"

reg AC09-B "$(item MON-200 AC09-SB)"; B=$(rid AC09-B)
as wr_inspector01 "CALL sp_record_initial_inspection($B, 1, 'C', 'Fail', 'dead pixels')" >/dev/null
for o in 1 2; do
  as wr_manager01 "CALL sp_approve_disposition($B, 1, 'Repair', NULL)" >/dev/null
  as wr_manager01 "CALL sp_assign_repair($B, 1, $TECH1)" >/dev/null
  as wr_technician01 "CALL sp_start_repair($B, 1, $o)" >/dev/null
  as wr_technician01 "CALL sp_complete_repair($B, 1, $o, 'attempt $o', $([ $o = 1 ] && echo 5.00 || echo 3.00), 0.00)" >/dev/null
  [ $o = 2 ] && deny wr_inspector01 "AC-04: a check of an older order is rejected" "CALL sp_record_postrepair_inspection($B, 1, 1, 'C', 'Fail', NULL)" "$CONF.*latest completed order"
  as wr_inspector01 "CALL sp_record_postrepair_inspection($B, 1, $o, 'D', 'Fail', 'still broken')" >/dev/null
done
check "Unit B went through two repair orders and three inspections" \
  "SELECT (SELECT COUNT(*) FROM WorkOrder WHERE ReturnID=$B)=2 AND (SELECT COUNT(*) FROM Inspection WHERE ReturnID=$B)=3"
deny wr_manager01 "AC-04: a later Fail blocks restock" "CALL sp_approve_disposition($B, 1, 'Restock', 50.00)" "$CONF.*Restock requires latest Pass"
run wr_manager01 "Manager approves liquidation at \$30 instead" "CALL sp_approve_disposition($B, 1, 'Liquidate', 30.00)"

reg AC04-D "$(item KBD-500)"; Dd=$(rid AC04-D)
run wr_inspector01 "Initial Pass, grade A" "CALL sp_record_initial_inspection($Dd, 1, 'A', 'Pass', NULL)"
run wr_manager01 "AC-04: direct restock allowed after Initial Pass A/B" "CALL sp_approve_disposition($Dd, 1, 'Restock', 20.00)"
run wr_manager01 "FRD 5.2: Manager withdraws the unstarted restock approval" "CALL sp_withdraw_approval($Dd, 1, 'Customer wants item re-checked')"
check "Withdrawal returns the item to AwaitingDecision and clears outcome/approver/time/value" \
  "SELECT s.Code='AwaitingDecision' AND i.ApprovedOutcomeID IS NULL AND i.ApprovedByUserID IS NULL AND i.ApprovedAt IS NULL AND i.RestockEstimatedValue IS NULL FROM ReturnItem i JOIN ReferenceValue s ON s.ReferenceValueID=i.ItemStatusID WHERE i.ReturnID=$Dd"
run wr_inspector01 "AC-02: Final inspection in AwaitingDecision (no repair, so no order link): Fail" "CALL sp_record_final_inspection($Dd, 1, 'C', 'Fail', 'cracked key')"
check "Final inspection recorded with no order and the state unchanged" \
  "SELECT COUNT(*)=1 FROM Inspection i JOIN ReferenceValue t ON t.ReferenceValueID=i.InspectionTypeID WHERE i.ReturnID=$Dd AND t.Code='Final' AND i.WorkOrderNumber IS NULL"
deny wr_manager01 "AC-04: the later Final Fail blocks restock" "CALL sp_approve_disposition($Dd, 1, 'Restock', 20.00)" "$CONF.*Restock requires latest Pass"
run wr_inspector01 "Final inspection Pass, grade B" "CALL sp_record_final_inspection($Dd, 1, 'B', 'Pass', 'replaced key')"
run wr_manager01 "AC-04: restock allowed again after Final Pass" "CALL sp_approve_disposition($Dd, 1, 'Restock', 18.00)"

reg AC02-E "$(item TOA-300)"; E=$(rid AC02-E)
warn wr_inspector01 "Inconclusive Initial result succeeds with a warning" "CALL sp_record_initial_inspection($E, 1, 'B', 'Inconclusive', 'needs bench test')" "Inconclusive result"
deny wr_manager01 "AC-02: approval after an Inconclusive result is rejected" "CALL sp_approve_disposition($E, 1, 'Repair', NULL)" "$CONF.*await manager decision"
as wr_inspector01 "CALL sp_record_initial_inspection($E, 1, 'C', 'Fail', 'element broken')" >/dev/null
as wr_manager01 "CALL sp_approve_disposition($E, 1, 'Repair', NULL)" >/dev/null
as wr_manager01 "CALL sp_assign_repair($E, 1, $TECH2)" >/dev/null
run wr_manager01 "FRD 5.2: Manager cancels the unstarted (Open) work order" "CALL sp_cancel_work_order($E, 1, 1, 'Part unavailable')"
check "Order is Cancelled and the item is back in AwaitingDecision with no outcome" \
  "SELECT (SELECT s.Code FROM WorkOrder w JOIN ReferenceValue s ON s.ReferenceValueID=w.WorkOrderStatusID WHERE w.ReturnID=$E AND w.WorkOrderNumber=1)='Cancelled' AND (SELECT ApprovedOutcomeID IS NULL FROM ReturnItem WHERE ReturnID=$E)"
deny wr_technician02 "A cancelled order can no longer be started" "CALL sp_start_repair($E, 1, 1)" "$CONF"
deny wr_manager01 "Withdrawing again is rejected (nothing to withdraw)" "CALL sp_withdraw_approval($E, 1, 'again')" "$CONF.*Only an unstarted approval"
deny wr_manager01 "A withdrawal reason is required" "CALL sp_withdraw_approval($Dd, 1, '  ')" "$VAL.*reason is required"

# ============================================================================
step "AC-05  FR-07/11: movements, rollback, killed transaction"
reg AC05-F "$(item KBD-500)"; F=$(rid AC05-F)
run wr_receiving01 "Routine relocation INT-01 -> INSP-01" "CALL sp_move_item($F, 1, $(loc INT-01), $(loc INSP-01), 'Relocate', NULL)"
check "Relocation moved the item and preserved its status (trigger updated the location)" \
  "SELECT i.CurrentLocationID=$(loc INSP-01) AND s.Code='AwaitingInspection' FROM ReturnItem i JOIN ReferenceValue s ON s.ReferenceValueID=i.ItemStatusID WHERE i.ReturnID=$F"
deny wr_receiving01 "A stale source location is rejected" "CALL sp_move_item($F, 1, $(loc INT-01), $(loc STO-01), 'Relocate', NULL)" "$CONF.*Invalid item/source/destination"
run wr_admin01 "Administrator adds location AC05-OLD and deactivates it (it holds no items)" \
  "INSERT INTO Location (LocationCode, LocationName, LocationTypeID) SELECT 'AC05-OLD','Retired shelf',ReferenceValueID FROM ReferenceValue WHERE Domain='LocationType' AND Code='Storage';
   UPDATE Location SET IsActive=0 WHERE LocationCode='AC05-OLD'"
deny wr_receiving01 "An inactive destination is rejected" "CALL sp_move_item($F, 1, $(loc INSP-01), $(loc AC05-OLD), 'Relocate', NULL)" "$VAL.*Inactive/incorrect movement type or destination"
M0=$(q "SELECT CONCAT((SELECT COUNT(*) FROM InventoryMovement),'/',(SELECT COUNT(*) FROM AuditLog),'/',(SELECT COUNT(*) FROM ReturnItemHistory),'/',(SELECT CurrentLocationID FROM ReturnItem WHERE ReturnID=$F))")
deny wr_receiving01 "Forced error: Restock move of an unapproved item fails inside the trigger" "CALL sp_move_item($F, 1, $(loc INSP-01), $(loc SALE-01), 'Restock', NULL)" "$CONF.*mismatch"
M1=$(q "SELECT CONCAT((SELECT COUNT(*) FROM InventoryMovement),'/',(SELECT COUNT(*) FROM AuditLog),'/',(SELECT COUNT(*) FROM ReturnItemHistory),'/',(SELECT CurrentLocationID FROM ReturnItem WHERE ReturnID=$F))")
[ "$M0" = "$M1" ] && ok "Forced error rolled back movement, audit, history and location ($M0 = $M1)" || bad "Forced error rollback" "$M0 -> $M1"

echo "      killed transaction: session 1 runs sp_move_item; session 2 holds a lock that pauses it"
echo "      after the movement, item update and history are written but before the audit row and COMMIT"
K0=$(q "SELECT CONCAT((SELECT COUNT(*) FROM InventoryMovement WHERE ReturnID=$F),' moves / ',(SELECT COUNT(*) FROM AuditLog WHERE AuditReturnID=$F AND Action='ITEM_MOVED'),' audit / ',(SELECT COUNT(*) FROM ReturnItemHistory WHERE ReturnID=$F)+(SELECT COUNT(*) FROM InventoryMovementHistory WHERE ReturnID=$F),' history / location ',(SELECT CurrentLocationID FROM ReturnItem WHERE ReturnID=$F))")
( as admin "START TRANSACTION; SET @m=(SELECT MAX(AuditID) FROM AuditLog); SELECT COUNT(*) FROM AuditLog WHERE AuditID > @m FOR UPDATE; SELECT SLEEP(10); ROLLBACK;" >/dev/null 2>&1 & )
sleep 1
( as wr_receiving01 "CALL sp_move_item($F, 1, $(loc INSP-01), $(loc STO-01), 'Relocate', 'kill demo')" >/tmp/wr_kill 2>&1 & )
CID=""; for i in 1 2 3 4 5 6 7 8 9 10; do sleep 0.5
  # Inside the DEFINER procedure the session runs as wr_owner, so find it by its lock wait.
  CID=$(q "SELECT trx_mysql_thread_id FROM information_schema.INNODB_TRX WHERE trx_state='LOCK WAIT' LIMIT 1"); [ -n "$CID" ] && break; done
if [ -n "$CID" ]; then
  ROWS=$(q "SELECT trx_rows_modified FROM information_schema.INNODB_TRX WHERE trx_mysql_thread_id=$CID")
  echo "      session 1 (connection $CID) is waiting with $ROWS uncommitted row changes"
  [ "${ROWS:-0}" -gt 0 ] && ok "Session 1 had written uncommitted changes before the kill ($ROWS rows)" || bad "Uncommitted changes" "$ROWS"
  q "KILL $CID"; sleep 1
  K1=$(q "SELECT CONCAT((SELECT COUNT(*) FROM InventoryMovement WHERE ReturnID=$F),' moves / ',(SELECT COUNT(*) FROM AuditLog WHERE AuditReturnID=$F AND Action='ITEM_MOVED'),' audit / ',(SELECT COUNT(*) FROM ReturnItemHistory WHERE ReturnID=$F)+(SELECT COUNT(*) FROM InventoryMovementHistory WHERE ReturnID=$F),' history / location ',(SELECT CurrentLocationID FROM ReturnItem WHERE ReturnID=$F))")
  echo "      before: $K0"; echo "      after:  $K1"
  [ "$K0" = "$K1" ] && ok "KILL rolled back movement, location, history and audit together" || bad "Killed transaction rollback" "$K0 -> $K1"
else bad "Killed transaction" "session 1 never waited on the lock"; fi
sleep 8

# ============================================================================
step "AC-06  FR-08: vendor claims"
run wr_manager01 "Manager submits an \$8 claim for unit A" "CALL sp_submit_claim($A, 1, 8.00, 'NS-A')"
CA=$(q "SELECT ClaimID FROM VendorClaim WHERE ReturnID=$A")
deny wr_manager01 "A second lifetime claim on the same unit is rejected" "CALL sp_submit_claim($A, 1, 3.00, 'NS-A2')" "$CONF.*already has a vendor claim"
run wr_manager01 "Manager approves the claim" "CALL sp_approve_claim($CA)"
move "$A" 1 SALE-01 Restock
check "Unit A is now Restocked (closed)" "SELECT CompletionAt IS NOT NULL FROM ReturnItem WHERE ReturnID=$A"
deny wr_manager01 "A new claim on a closed unit is rejected" "CALL sp_submit_claim($Dd, 1, 3.00, 'x') ; CALL sp_submit_claim($A, 1, 3.00, 'NS-A3')" "$CONF.*(closed item|already has)"
BEFORE=$(q "SELECT CONCAT(ItemStatusID,'/',CurrentLocationID,'/',CompletionAt) FROM ReturnItem WHERE ReturnID=$A")
warn wr_manager01 "Settling \$5 of \$8 after completion succeeds with a partial-recovery warning" "CALL sp_settle_claim($CA, 5.00)" "partial recovery"
AFTER=$(q "SELECT CONCAT(ItemStatusID,'/',CurrentLocationID,'/',CompletionAt) FROM ReturnItem WHERE ReturnID=$A")
[ "$BEFORE" = "$AFTER" ] && ok "Settlement did not change item status, location or completion" || bad "Settlement side effects" "$BEFORE -> $AFTER"
deny wr_manager01 "A settled claim is terminal (cannot be cancelled)" "CALL sp_cancel_claim($CA, 'late')" "$CONF.*Only submitted or approved"
CD=$(q "SELECT ClaimID FROM VendorClaim WHERE ReturnID=$Dd")
run wr_manager01 "Claim exit: Submitted -> Cancelled" "CALL sp_cancel_claim($CD, 'Raised in error')"
run wr_manager01 "Manager submits a \$10 claim for unit B" "CALL sp_submit_claim($B, 1, 10.00, 'NS-B')"
CB=$(q "SELECT ClaimID FROM VendorClaim WHERE ReturnID=$B")
run wr_manager01 "Claim exit: Submitted -> Denied" "CALL sp_deny_claim($CB, 'Out of warranty')"
deny wr_manager01 "A denied claim cannot be approved" "CALL sp_approve_claim($CB)" "$CONF.*Only submitted claims"

# ============================================================================
step "AC-09  FR-10/12 RQ-04: recovery value"
move "$B" 1 LIQ-01 Liquidate
reg AC09-C "$(item CHA-400)"; C=$(rid AC09-C)
as wr_inspector01 "CALL sp_record_initial_inspection($C, 1, 'C', 'Fail', 'broken arm')" >/dev/null
as wr_manager01 "CALL sp_approve_disposition($C, 1, 'Repair', NULL)" >/dev/null
as wr_manager01 "CALL sp_assign_repair($C, 1, $TECH2)" >/dev/null
as wr_technician02 "CALL sp_start_repair($C, 1, 1)" >/dev/null
as wr_technician02 "CALL sp_complete_repair($C, 1, 1, 'attempted weld', 6.00, 0.00)" >/dev/null
as wr_inspector01 "CALL sp_record_postrepair_inspection($C, 1, 1, 'D', 'Fail', 'unsafe')" >/dev/null
as wr_manager01 "CALL sp_approve_disposition($C, 1, 'Dispose', 4.00)" >/dev/null
move "$C" 1 DIS-01 Dispose
check "\$60 restock estimate + \$5 settlement - \$15 repair = \$50 net (unit A)" "SELECT NetRecovery=50.00 FROM vw_item_recovery WHERE ReturnID=$A"
check "\$30 liquidation - \$8 repair over two orders = \$22 net (unit B; denied claim adds nothing)" "SELECT NetRecovery=22.00 AND TotalLaborCost=8.00 AND VendorCashReceived=0 FROM vw_item_recovery WHERE ReturnID=$B"
check "\$4 disposal + \$6 repair = -\$10 net (unit C)" "SELECT NetRecovery=-10.00 FROM vw_item_recovery WHERE ReturnID=$C"
check "Multiple orders, inspections and movements do not multiply rows (one row per unit)" "SELECT COUNT(*)=1 FROM vw_item_recovery WHERE ReturnID=$B"

# ============================================================================
step "AC-07  FR-09/10 RQ-01/RQ-02: search, history, money restricted to Managers"
check "Open items can be searched by serial, SKU, status and location" \
  "SELECT COUNT(*)=1 FROM vw_open_items WHERE SerialNumber='AC01-S2' AND SKU='LAP-100' AND ItemStatus='AwaitingInspection' AND LocationCode='INT-01'"
check "RQ-01 lists the oldest open item first" "SELECT ReceivedAt=(SELECT MIN(ReceivedAt) FROM vw_open_items) FROM vw_open_items ORDER BY ReceivedAt, ReturnID, LineNumber LIMIT 1"
run wr_inspector01 "Inspector can read non-financial item columns" "SELECT ReturnID, ItemStatusID, CurrentLocationID FROM ReturnItem LIMIT 1"
deny wr_inspector01 "Inspector cannot read money columns on ReturnItem" "SELECT RestockEstimatedValue FROM ReturnItem LIMIT 1" "$DENIED"
deny wr_receiving01 "Receiving cannot read the recovery report" "SELECT * FROM vw_item_recovery LIMIT 1" "$DENIED"
deny wr_technician01 "Technician cannot read vendor claims" "SELECT * FROM VendorClaim LIMIT 1" "$DENIED"
run wr_manager01 "Manager reads RQ-04 recovery" "SELECT NetRecovery FROM vw_item_recovery LIMIT 1"
run wr_manager01 "RQ-02 item history via the audit trail procedure" "CALL sp_get_item_audit_trail('AC09-A', 1, 1, 20)"
check "Unit A's history shows every step from intake to Restocked" \
  "SELECT GROUP_CONCAT(NewValue ORDER BY EventAt, HistoryID SEPARATOR '>')='AwaitingInspection>AwaitingDecision>ApprovedForRepair>InRepair>AwaitingFinalInspection>AwaitingDecision>ApprovedForRestock>Restocked' FROM vw_item_audit_trail WHERE ReturnID=$A AND Entity='ReturnItem' AND AttributeName='ItemStatus'"

# ============================================================================
step "AC-10  FR-11/15: administration, audit writes, terminal items"
run wr_admin01 "Administrator adds staff account wr_inspector02 and grants the Inspector role" \
  "INSERT INTO AppUser (LoginIdentifier, DisplayName) VALUES ('wr_inspector02', 'Sam Okafor');
   INSERT INTO UserRole (UserID, RoleID) SELECT u.UserID, r.RoleID FROM AppUser u, Role r WHERE u.LoginIdentifier='wr_inspector02' AND r.RoleCode='Inspector'"
run wr_admin01 "Administrator renames a location label" "UPDATE Location SET LocationName='Inspection bench A' WHERE LocationCode='INSP-01'"
run wr_admin01 "Administrator deactivates the new account (no active work)" "UPDATE AppUser SET IsActive=0 WHERE LoginIdentifier='wr_inspector02'"
reg AC10-H "$(item TOA-300)"; H=$(rid AC10-H)
as wr_inspector01 "CALL sp_record_initial_inspection($H, 1, 'C', 'Fail', NULL)" >/dev/null
as wr_manager01 "CALL sp_approve_disposition($H, 1, 'Repair', NULL)" >/dev/null
as wr_manager01 "CALL sp_assign_repair($H, 1, $TECH1)" >/dev/null
deny wr_admin01 "A technician with an Open work order cannot be deactivated" \
  "UPDATE AppUser SET IsActive=0 WHERE LoginIdentifier='wr_technician01'" "$CONF.*active work orders"
check "Account, role and location changes are recorded with old/new values and the administrator" \
  "SELECT COUNT(DISTINCT Entity)=3 FROM vw_master_data_change_history WHERE ChangedBy='Riley Kim' AND Entity IN ('AppUser','UserRole','Location')"
deny wr_manager01 "Direct audit write is rejected (Manager)" "INSERT INTO AuditLog (UserID, RecordedAt, Action, EntityName, RecordKey, TransactionID) VALUES (1, NOW(), 'X', 'X', '{}', 'x')" "$DENIED"
deny wr_admin01 "Direct audit read/write is rejected (Administrator: redacted views only)" "SELECT * FROM AuditLog LIMIT 1" "$DENIED"
deny admin "Even the setup account cannot edit AuditLog" "UPDATE AuditLog SET Action='X' LIMIT 1" "ERROR 50500 \(45500\).*append-only"
deny wr_manager01 "Terminal item cannot be re-approved (reopened)" "CALL sp_approve_disposition($A, 1, 'Repair', NULL)" "$CONF.*await manager decision"
deny wr_receiving01 "Terminal item cannot be moved" "CALL sp_move_item($A, 1, $(loc SALE-01), $(loc STO-01), 'Relocate', NULL)" "$CONF"
deny wr_manager01 "No role can update protected tables directly" "UPDATE ReturnItem SET CompletionAt=NULL WHERE ReturnID=$A" "$DENIED"
deny wr_manager01 "Monthly sales go through the procedure only" "UPDATE SalesSummary SET UnitsSold=1" "$DENIED"

# ============================================================================
step "AC-11  FR-11/15: reference value administration"
run wr_admin01 "Administrator adds return reason 'Recall'" "INSERT INTO ReferenceValue (Domain, Code, Description) VALUES ('ReturnReason', 'Recall', 'Manufacturer recall')"
run wr_admin01 "Administrator edits a grade label (behavior unchanged)" "UPDATE ReferenceValue SET Description='Like new (no marks)' WHERE Domain='ConditionGrade' AND Code='A'"
reg AC11-G "$(item KBD-500 '' Recall)"; G=$(rid AC11-G)
as wr_inspector01 "CALL sp_record_initial_inspection($G, 1, 'A', 'Pass', NULL)" >/dev/null
as wr_manager01 "CALL sp_approve_disposition($G, 1, 'Restock', 12.00)" >/dev/null
deny wr_admin01 "A reason used by an open item cannot be deactivated" "UPDATE ReferenceValue SET IsActive=0 WHERE Domain='ReturnReason' AND Code='Recall'" "$CONF.*used by open items"
move "$G" 1 SALE-01 Restock
run wr_admin01 "Reason used only by completed items can be deactivated" "UPDATE ReferenceValue SET IsActive=0 WHERE Domain='ReturnReason' AND Code='Recall'"
check "History still resolves the inactive reason" "SELECT COUNT(*)=1 FROM vw_item_audit_trail WHERE ReturnID=$G AND AttributeName='ReturnReason' AND NewValue='Recall'"
deny wr_receiving01 "New use of the inactive reason fails" "CALL sp_register_return('AC11-NEW', '[$(item KBD-500 '' Recall)]')" "$VAL.*inactive return reason"
deny wr_receiving01 "A value from the wrong domain is rejected (grade code as a reason)" "CALL sp_register_return('AC11-DOM', '[$(item KBD-500 '' A)]')" "$VAL.*inactive return reason"
deny wr_admin01 "Recoding a referenced value is rejected" "UPDATE ReferenceValue SET Code='Broken' WHERE Domain='ReturnReason' AND Code='Damaged'" "$CONF.*cannot be recoded"
deny wr_admin01 "Moving a value to another domain is rejected" "UPDATE ReferenceValue SET Domain='ConditionGrade' WHERE Domain='ReturnReason' AND Code='Other'" "$CONF.*another domain"
deny wr_admin01 "Deactivating a workflow value needed by open work is rejected" "UPDATE ReferenceValue SET IsActive=0 WHERE Domain='ItemStatus' AND Code='AwaitingInspection'" "$CONF.*needed by enabled transitions"
deny wr_admin01 "Deleting reference values is not permitted" "DELETE FROM ReferenceValue WHERE Code='Recall'" "$DENIED"
deny admin "Even the setup account cannot delete a referenced value (FK RESTRICT)" "DELETE FROM ReferenceValue WHERE Domain='ReturnReason' AND Code='Recall'" "foreign key constraint fails"
check "Reference edits are audited (label edit with old and new value)" \
  "SELECT COUNT(*)=1 FROM vw_master_data_change_history WHERE Entity='ReferenceValue' AND AttributeName='Description' AND NewValue='Like new (no marks)' AND ChangedBy='Riley Kim'"

# ============================================================================
step "Midterm feedback: accounts, owner, error classes, version stamp"
LOCKED=$(MYSQL_PWD=x mysql --protocol=TCP --host="$DB_HOST" --port="$DB_PORT" --user=wr_owner -e "SELECT 1" 2>&1)
grep -qiE "locked|denied" <<<"$LOCKED" && ok "Routine owner wr_owner cannot log in  -> $(grep -oiE 'ERROR [0-9]+' <<<"$LOCKED")" || bad "wr_owner login" "$LOCKED"
check "All views, routines and triggers are owned by wr_owner (none by root)" \
  "SELECT (SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA='$DB' AND DEFINER<>'wr_owner@localhost')+(SELECT COUNT(*) FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA='$DB' AND DEFINER<>'wr_owner@localhost')+(SELECT COUNT(*) FROM information_schema.VIEWS WHERE TABLE_SCHEMA='$DB' AND DEFINER<>'wr_owner@localhost')=0"
check "Role logins have no direct write access to any protected table" \
  "SELECT COUNT(*)=0 FROM mysql.tables_priv WHERE Db='$DB' AND User LIKE 'wr\\_role\\_%' AND Table_name IN ('ReturnHeader','ReturnItem','Inspection','WorkOrder','InventoryMovement','VendorClaim','SalesSummary','AuditLog') AND (FIND_IN_SET('Insert',Table_priv) OR FIND_IN_SET('Update',Table_priv) OR FIND_IN_SET('Delete',Table_priv))"
TECH2_ROLE=$(q "SELECT RoleID FROM Role WHERE RoleCode='Technician'")
as wr_admin01 "DELETE FROM UserRole WHERE UserID=$TECH2 AND RoleID=$TECH2_ROLE" >/dev/null
deny wr_technician02 "A MySQL grant alone is not enough: with the app role removed, the procedure refuses (class 45003)" \
  "CALL sp_start_repair($E, 1, 1)" "$AUTH.*Technician login required"
as wr_admin01 "INSERT INTO UserRole (UserID, RoleID) VALUES ($TECH2, $TECH2_ROLE)" >/dev/null
deny wr_manager01 "Not-found errors use class 45004" "CALL sp_get_item_audit_trail('NOPE', NULL, 1, 10)" "$NOTF"
if [ "$(q "SELECT COUNT(*) FROM SchemaBuild")" -ge 1 ]; then
  check "In-database version stamp names the release, commit and every script" \
    "SELECT b.ReleaseTag<>'' AND CHAR_LENGTH(b.CommitSHA)=40 AND b.ScriptCount=(SELECT COUNT(*) FROM SchemaBuildScript s WHERE s.BuildID=b.BuildID) FROM SchemaBuild b ORDER BY b.BuildID DESC LIMIT 1"
  q "SELECT CONCAT('      built from ', ReleaseTag, ' @ ', LEFT(CommitSHA, 7), ', ', ScriptCount, ' scripts, MySQL ', MySQLVersion, ', at ', BuiltAt) FROM SchemaBuild ORDER BY BuildID DESC LIMIT 1"
else
  skip "In-database version stamp" "schema was not built by build/build_database.sh"
fi

finish
