#!/usr/bin/env bash
# Audit trail (history table) tests: runs a full unit workflow as the real role logins,
# then verifies history capture, transaction grouping, the audit trail grid/procedure,
# financial redaction, append-only guards, rollback, and audited admin changes.
#
#   bash tests/audit_trail_tests.sh TARGET_DB
#
# TARGET_DB must be a fresh build (build/build_database.sh). Uses build/config.env for the
# setup account (DB_HOST/DB_PORT/DB_ADMIN_USER/DB_ADMIN_PASSWORD) and DEMO_PASSWORD for the
# wr_* role logins. Each run uses a new return reference, so it can be repeated.
# Output is saved to tests/results/ for committing as evidence. Exit code 1 if any check fails.
set -uo pipefail

[ "$#" -eq 1 ] || { echo "Usage: bash tests/audit_trail_tests.sh TARGET_DB" >&2; exit 2; }
DB=$1; NAME=audit_trail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

REF="AUD-$(date -u '+%Y%m%d%H%M%S')"
header "Audit trail tests  reference=$REF"

step "1. Workflow as role logins (repair -> post-repair pass -> restock, vendor claim, final move)"
run wr_receiving01 "Receiving registers a 2-line return" \
  "CALL sp_register_return('$REF', '[{\"sku\":\"LAP-100\",\"serial\":\"$REF-SN1\",\"reason\":\"Defective\",\"location\":\"INT-01\"},{\"sku\":\"KBD-500\",\"reason\":\"Unwanted\",\"location\":\"INT-01\"}]')"
RID=$(as admin "SELECT ReturnID FROM ReturnHeader WHERE ExternalReference='$REF'")
TECH=$(as admin "SELECT UserID FROM AppUser WHERE LoginIdentifier='wr_technician01'")
echo "      ReturnID=$RID"
run wr_inspector01 "Inspector records initial inspection (fail, grade C)" \
  "CALL sp_record_initial_inspection($RID, 1, 'C', 'Fail', 'Battery does not hold charge')"
run wr_manager01  "Manager approves Repair with no amount (NULL)" "CALL sp_approve_disposition($RID, 1, 'Repair', NULL)"
run wr_manager01  "Manager assigns repair to technician" "CALL sp_assign_repair($RID, 1, $TECH)"
run wr_technician01 "Technician starts repair" "CALL sp_start_repair($RID, 1, 1)"
run wr_technician01 "Technician completes repair (labor 10, parts 25)" \
  "CALL sp_complete_repair($RID, 1, 1, 'Replaced battery', 10.00, 25.00)"
run wr_inspector01 "Inspector records post-repair inspection (pass, grade A)" \
  "CALL sp_record_postrepair_inspection($RID, 1, 1, 'A', 'Pass', 'Holds charge')"
run wr_manager01  "Manager approves Restock at 200" "CALL sp_approve_disposition($RID, 1, 'Restock', 200.00)"
run wr_manager01  "Manager submits a 40 vendor claim" "CALL sp_submit_claim($RID, 1, 40.00, 'NS-$REF')"
CLAIM=$(as admin "SELECT ClaimID FROM VendorClaim WHERE ReturnID=$RID AND LineNumber=1")
run wr_manager01  "Manager approves the claim" "CALL sp_approve_claim($CLAIM)"
deny wr_manager01 "Settlement above the claim is rejected (50 > 40)" "CALL sp_settle_claim($CLAIM, 50.00)" "cannot exceed"
run wr_manager01  "Manager settles the claim for 30" "CALL sp_settle_claim($CLAIM, 30.00)"
SRC=$(as admin "SELECT CurrentLocationID FROM ReturnItem WHERE ReturnID=$RID AND LineNumber=1")
DST=$(as admin "SELECT LocationID FROM Location WHERE LocationCode='SALE-01'")
run wr_receiving01 "Receiving makes the final Restock move to SALE-01" \
  "CALL sp_move_item($RID, 1, $SRC, $DST, 'Restock', 'Back to stock')"
check "Unit 1 ends Restocked at SALE-01 with CompletionAt set" \
  "SELECT COUNT(*) FROM ReturnItem ri JOIN ReferenceValue s ON s.ReferenceValueID=ri.ItemStatusID JOIN Location l ON l.LocationID=ri.CurrentLocationID WHERE ri.ReturnID=$RID AND ri.LineNumber=1 AND s.Code='Restocked' AND l.LocationCode='SALE-01' AND ri.CompletionAt IS NOT NULL"
check "Net recovery is 195 (200 restock + 30 settled - 10 labor - 25 parts)" \
  "SELECT NetRecovery=195.00 FROM vw_item_recovery WHERE ReturnID=$RID AND LineNumber=1"

step "2. History capture"
check "ReturnItemHistory has one version per change of unit 1 (8: intake + 7 status/location changes)" \
  "SELECT COUNT(*)=8 FROM ReturnItemHistory WHERE ReturnID=$RID AND LineNumber=1"
check "Exactly one open version per unit (ValidTo = 9999-12-31)" \
  "SELECT COUNT(*)=2 FROM ReturnItemHistory WHERE ReturnID=$RID AND ValidTo='9999-12-31 23:59:59.999999'"
check "Versions are contiguous: each closed version ends when the next begins" \
  "SELECT COUNT(*)=0 FROM (SELECT ValidTo, LEAD(ValidFrom) OVER (PARTITION BY ReturnID, LineNumber ORDER BY ValidFrom, HistoryID) nxt FROM ReturnItemHistory WHERE ReturnID=$RID) v WHERE nxt IS NOT NULL AND ValidTo<>nxt"
check "The open version matches the live row (status, location, amounts)" \
  "SELECT COUNT(*)=1 FROM ReturnItemHistory h JOIN ReturnItem ri USING (ReturnID, LineNumber) WHERE h.ReturnID=$RID AND h.LineNumber=1 AND h.ValidTo='9999-12-31 23:59:59.999999' AND h.ItemStatusID<=>ri.ItemStatusID AND h.CurrentLocationID<=>ri.CurrentLocationID AND h.RestockEstimatedValue<=>ri.RestockEstimatedValue AND h.CompletionAt<=>ri.CompletionAt"
check "Every history row of this return records the acting staff member (no setup account)" \
  "SELECT COUNT(*)=0 FROM (SELECT ChangedByUserID FROM ReturnItemHistory WHERE ReturnID=$RID UNION ALL SELECT ChangedByUserID FROM WorkOrderHistory WHERE ReturnID=$RID UNION ALL SELECT ChangedByUserID FROM VendorClaimHistory WHERE ReturnID=$RID UNION ALL SELECT ChangedByUserID FROM InspectionHistory WHERE ReturnID=$RID UNION ALL SELECT ChangedByUserID FROM InventoryMovementHistory WHERE ReturnID=$RID) x WHERE ChangedByUserID IS NULL"
check "Approval version is attributed to the Manager (Casey Brown)" \
  "SELECT COUNT(*)>=1 FROM ReturnItemHistory h JOIN AppUser u ON u.UserID=h.ChangedByUserID WHERE h.ReturnID=$RID AND h.LineNumber=1 AND h.ApprovedOutcomeID IS NOT NULL AND u.LoginIdentifier='wr_manager01'"

step "3. One transaction ID per business transaction, shared with AuditLog"
check "Intake: both units, the header, and all 3 AuditLog rows share one TransactionID" \
  "SELECT COUNT(DISTINCT t)=1 FROM (SELECT TransactionID t FROM ReturnItemHistory WHERE ReturnID=$RID AND Operation='I' UNION ALL SELECT TransactionID FROM ReturnHeaderHistory WHERE ReturnID=$RID UNION ALL SELECT TransactionID FROM AuditLog WHERE (EntityName='ReturnItem' AND AuditReturnID=$RID AND Action='ITEM_INTAKE') OR (EntityName='ReturnHeader' AND AuditReturnID=$RID)) x"
check "Every history version of this return belongs to a transaction that wrote an AuditLog action" \
  "SELECT COUNT(*)=0 FROM (SELECT TransactionID FROM ReturnItemHistory WHERE ReturnID=$RID UNION ALL SELECT TransactionID FROM WorkOrderHistory WHERE ReturnID=$RID UNION ALL SELECT TransactionID FROM VendorClaimHistory WHERE ReturnID=$RID UNION ALL SELECT TransactionID FROM InspectionHistory WHERE ReturnID=$RID UNION ALL SELECT TransactionID FROM InventoryMovementHistory WHERE ReturnID=$RID) h WHERE NOT EXISTS (SELECT 1 FROM AuditLog a WHERE a.TransactionID=h.TransactionID)"
check "Separate procedure calls get different TransactionIDs (12 workflow transactions for unit 1)" \
  "SELECT COUNT(DISTINCT TransactionID)=12 FROM (SELECT TransactionID FROM ReturnItemHistory WHERE ReturnID=$RID AND LineNumber=1 UNION ALL SELECT TransactionID FROM WorkOrderHistory WHERE ReturnID=$RID UNION ALL SELECT TransactionID FROM VendorClaimHistory WHERE ReturnID=$RID UNION ALL SELECT TransactionID FROM InspectionHistory WHERE ReturnID=$RID) x"
check "Final move: movement row, item update and ITEM_MOVED audit share one TransactionID" \
  "SELECT COUNT(DISTINCT t)=1 FROM (SELECT TransactionID t FROM InventoryMovementHistory WHERE ReturnID=$RID UNION ALL SELECT TransactionID FROM ReturnItemHistory WHERE ReturnID=$RID AND LineNumber=1 AND CompletionAt IS NOT NULL AND Operation='U' UNION ALL SELECT TransactionID FROM AuditLog WHERE EntityName='ReturnItem' AND AuditReturnID=$RID AND Action='ITEM_MOVED') x"

echo "      transactions for this return (TransactionID -> AuditLog actions):"
as admin "SELECT CONCAT(TransactionID, '  ', GROUP_CONCAT(DISTINCT Action ORDER BY AuditID SEPARATOR ', ')) FROM AuditLog WHERE TransactionID IN (SELECT TransactionID FROM ReturnItemHistory WHERE ReturnID=$RID UNION SELECT TransactionID FROM WorkOrderHistory WHERE ReturnID=$RID UNION SELECT TransactionID FROM VendorClaimHistory WHERE ReturnID=$RID UNION SELECT TransactionID FROM InspectionHistory WHERE ReturnID=$RID) GROUP BY TransactionID ORDER BY MIN(AuditID)" | sed 's/^/        /'

step "4. Audit trail grid (vw_item_audit_trail)"
check "Status changes of unit 1 appear in order: intake -> Restocked" \
  "SELECT GROUP_CONCAT(COALESCE(NewValue,'') ORDER BY EventAt, HistoryID SEPARATOR '>')='AwaitingInspection>AwaitingDecision>ApprovedForRepair>InRepair>AwaitingFinalInspection>AwaitingDecision>ApprovedForRestock>Restocked' FROM vw_item_audit_trail WHERE ReturnID=$RID AND LineNumber=1 AND Entity='ReturnItem' AND AttributeName='ItemStatus'"
check "Changed rows carry the previous value (OldValue) for each changed attribute" \
  "SELECT COUNT(*)=1 FROM vw_item_audit_trail WHERE ReturnID=$RID AND LineNumber=1 AND AttributeName='ItemStatus' AND OldValue='ApprovedForRestock' AND NewValue='Restocked' AND ChangedBy='Morgan Lee' AND BusinessAction='ITEM_MOVED'"
check "Unchanged attributes are not repeated on Changed rows" \
  "SELECT COUNT(*)=0 FROM vw_item_audit_trail WHERE ReturnID=$RID AND EventType='Changed' AND OldValue<=>NewValue"
check "Claim status and settlement appear with the Manager and business action" \
  "SELECT COUNT(*)=1 FROM vw_item_audit_trail WHERE ReturnID=$RID AND Entity='VendorClaim' AND AttributeName='SettlementAmount' AND NewValue='30.00' AND IsFinancial=1 AND BusinessAction='CLAIM_SETTLED' AND ChangedBy='Casey Brown'"
check "Rejected 50 settlement left no trace in the trail" \
  "SELECT COUNT(*)=0 FROM vw_item_audit_trail WHERE ReturnID=$RID AND AttributeName='SettlementAmount' AND NewValue='50.00'"
check "Work order labor/parts and inspections are in the same trail" \
  "SELECT SUM(Entity='WorkOrder' AND AttributeName='TotalPartsCost' AND NewValue='25.00')=1 AND SUM(Entity='Inspection' AND AttributeName='InspectionType')=2 FROM vw_item_audit_trail WHERE ReturnID=$RID"

step "5. Audit trail search procedure (paging + redaction)"
MGR_TOTAL=$(as wr_manager01 "CALL sp_get_item_audit_trail('$REF', 1, 1, 10)" | head -1 | cut -f4)
ADMIN_TOTAL=$(as wr_admin01 "CALL sp_get_item_audit_trail('$REF', 1, 1, 10)" | head -1 | cut -f4)
ALL_ROWS=$(as admin "SELECT COUNT(*) FROM vw_item_audit_trail WHERE ReturnID=$RID AND LineNumber=1")
FIN_ROWS=$(as admin "SELECT COUNT(*) FROM vw_item_audit_trail WHERE ReturnID=$RID AND LineNumber=1 AND IsFinancial=1")
echo "      manager total=$MGR_TOTAL  administrator total=$ADMIN_TOTAL  view rows=$ALL_ROWS  financial rows=$FIN_ROWS"
[ "$MGR_TOTAL" = "$ALL_ROWS" ] && ok "Manager sees every trail row, including amounts" || bad "Manager total" "$MGR_TOTAL vs $ALL_ROWS"
[ "$ADMIN_TOTAL" = "$((ALL_ROWS - FIN_ROWS))" ] && [ "$FIN_ROWS" -gt 0 ] && ok "Administrator sees the redacted trail (no financial rows)" || bad "Administrator redaction" "$ADMIN_TOTAL"
deny wr_inspector01 "Operational roles have no audit review (TDD capability matrix)" "CALL sp_get_item_audit_trail('$REF', 1, 1, 10)" "execute command denied"
P1=$(as wr_manager01 "CALL sp_get_item_audit_trail('$REF', 1, 1, 10)" | sed 1d | wc -l | tr -d ' ')
LASTP=$(( (ALL_ROWS + 9) / 10 ))
PL=$(as wr_manager01 "CALL sp_get_item_audit_trail('$REF', 1, $LASTP, 10)" | sed 1d | wc -l | tr -d ' ')
[ "$P1" = 10 ] && [ "$PL" = "$(( ALL_ROWS - (LASTP-1)*10 ))" ] && ok "Paging: page 1 returns 10 rows, last page ($LASTP) returns the remainder ($PL)" || bad "Paging" "p1=$P1 last=$PL"
PAGED=$(for p in $(seq 1 $LASTP); do as wr_manager01 "CALL sp_get_item_audit_trail('$REF', 1, $p, 10)" | sed 1d; done | sort -u | wc -l | tr -d ' ')
[ "$PAGED" = "$ALL_ROWS" ] && ok "Pages do not overlap or skip rows ($PAGED distinct rows)" || bad "Page coverage" "$PAGED vs $ALL_ROWS"
deny wr_manager01 "Unknown reference is reported" "CALL sp_get_item_audit_trail('NO-SUCH-REF', NULL, 1, 10)" "Return reference not found"
deny wr_manager01 "Oversized page is rejected" "CALL sp_get_item_audit_trail('$REF', NULL, 1, 500)" "Page size must be between 1 and 200"
deny wr_manager01 "History tables are not directly readable by roles" "SELECT * FROM ReturnItemHistory LIMIT 1" "SELECT command denied"
deny wr_admin01 "Non-managers cannot read the unredacted grid view" "SELECT * FROM vw_item_audit_trail LIMIT 1" "SELECT command denied"
echo "      first page as shown to the Administrator (redacted):"
as wr_admin01 "CALL sp_get_item_audit_trail('$REF', 1, 1, 10)" | sed 1d | cut -f1,3-9 | sed 's/^/        /'

step "6. History is append-only (even for the setup account)"
deny admin "UPDATE of a history value is blocked" "UPDATE ReturnItemHistory SET ItemStatusID=ItemStatusID+1 WHERE ReturnID=$RID LIMIT 1" "append-only"
deny admin "Re-closing an already closed version is blocked" "UPDATE ReturnItemHistory SET ValidTo=UTC_TIMESTAMP(6) WHERE ReturnID=$RID AND ValidTo<>'9999-12-31 23:59:59.999999' LIMIT 1" "append-only"
deny admin "DELETE from history is blocked" "DELETE FROM ReturnItemHistory WHERE ReturnID=$RID" "append-only"
deny admin "AuditLog UPDATE is still blocked" "UPDATE AuditLog SET Action='X' WHERE AuditReturnID=$RID LIMIT 1" "append-only"

step "7. Rollback leaves no history"
BEFORE=$(as admin "SELECT (SELECT COUNT(*) FROM ReturnItemHistory)+(SELECT COUNT(*) FROM InspectionHistory)+(SELECT COUNT(*) FROM ReturnHeaderHistory)")
deny wr_receiving01 "Intake with an unknown SKU on line 2 fails" \
  "CALL sp_register_return('$REF-BAD', '[{\"sku\":\"KBD-500\",\"reason\":\"Unwanted\",\"location\":\"INT-01\"},{\"sku\":\"NOPE-999\",\"reason\":\"Unwanted\",\"location\":\"INT-01\"}]')" "product|sku"
deny admin "Explicit ROLLBACK after a direct update" "START TRANSACTION; UPDATE ReturnItem SET SerialNumber='ROLLED-BACK' WHERE ReturnID=$RID AND LineNumber=2; ROLLBACK; SELECT 1/0 FROM DUAL WHERE (SELECT COUNT(*) FROM ReturnItemHistory WHERE SerialNumber='ROLLED-BACK')=0 INTO @x; SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='rolled back ok'" "rolled back ok"
AFTER=$(as admin "SELECT (SELECT COUNT(*) FROM ReturnItemHistory)+(SELECT COUNT(*) FROM InspectionHistory)+(SELECT COUNT(*) FROM ReturnHeaderHistory)")
[ "$BEFORE" = "$AFTER" ] && ok "No history rows were left by the failed or rolled-back changes ($BEFORE = $AFTER)" || bad "Rollback history" "$BEFORE -> $AFTER"

step "8. Administration changes are audited"
OLDNAME=$(as admin "SELECT LocationName FROM Location WHERE LocationCode='REP-01'")
run wr_admin01 "Administrator renames location REP-01" "UPDATE Location SET LocationName='Repair bench (east)' WHERE LocationCode='REP-01'"
check "Master-data history shows the rename, old and new value, by Riley Kim" \
  "SELECT COUNT(*)=1 FROM vw_master_data_change_history WHERE Entity='Location' AND AttributeName='LocationName' AND OldValue='$OLDNAME' AND NewValue='Repair bench (east)' AND ChangedBy='Riley Kim'"
N0=$(as admin "SELECT COUNT(*) FROM LocationHistory")
run wr_admin01 "Administrator saves the same value again (no-op update)" "UPDATE Location SET LocationName=LocationName WHERE LocationCode='REP-01'"
N1=$(as admin "SELECT COUNT(*) FROM LocationHistory")
[ "$N0" = "$N1" ] && ok "No-op updates write no history version" || bad "No-op update" "$N0 -> $N1"
run wr_admin01 "Administrator restores the original name" "UPDATE Location SET LocationName='$OLDNAME' WHERE LocationCode='REP-01'"
run wr_admin01 "Administrator removes and re-adds a role assignment" \
  "DELETE FROM UserRole WHERE UserID=$TECH; INSERT INTO UserRole (UserID, RoleID) SELECT $TECH, RoleID FROM Role WHERE RoleCode='Technician'"
check "Role removal and re-grant are both in the history" \
  "SELECT SUM(EventType='Deleted')>=1 AND SUM(EventType='Created')>=2 FROM vw_master_data_change_history WHERE Entity='UserRole' AND EntityKey LIKE '$TECH/%'"

finish
