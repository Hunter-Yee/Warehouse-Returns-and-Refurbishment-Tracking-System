#!/usr/bin/env bash
# Shared helpers for tests/*.sh. Source after setting DB (target schema) and NAME (result prefix).
# Reads build/config.env: DB_HOST, DB_PORT, DB_ADMIN_USER, DB_ADMIN_PASSWORD (setup account)
# and DEMO_PASSWORD (wr_* role logins). Output is teed to tests/results/<NAME>_<UTC time>.txt.

[[ "$DB" =~ ^[A-Za-z][A-Za-z0-9_]*$ ]] || { echo 'Invalid database name' >&2; exit 2; }
command -v mysql >/dev/null 2>&1 || { echo 'Missing tool: mysql' >&2; exit 1; }

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CONFIG_FILE="$TESTS_DIR/../build/config.env"
if [ -f "$CONFIG_FILE" ]; then set -a; source "$CONFIG_FILE"; set +a; fi
DB_HOST="${DB_HOST%$'\r'}"; DB_PORT="${DB_PORT:-3306}"; DB_PORT="${DB_PORT%$'\r'}"
DB_ADMIN_USER="${DB_ADMIN_USER%$'\r'}"; DB_ADMIN_PASSWORD="${DB_ADMIN_PASSWORD%$'\r'}"
DEMO_PASSWORD="${DEMO_PASSWORD%$'\r'}"
: "${DB_HOST:?Set DB_HOST}"; : "${DB_ADMIN_USER:?Set DB_ADMIN_USER}"; : "${DB_ADMIN_PASSWORD:?Set DB_ADMIN_PASSWORD}"
: "${DEMO_PASSWORD:?Set DEMO_PASSWORD}"

mkdir -p "$TESTS_DIR/results"
OUT="$TESTS_DIR/results/${NAME}_$(date -u '+%Y%m%dT%H%M%SZ').txt"
exec > >(tee "$OUT") 2>&1

PASS=0; FAIL=0; SKIP=0
# as WHO SQL: run as a role login ("admin" = setup account); prints result rows only.
as() {
  local who=$1 sql=$2 user pw
  if [ "$who" = admin ]; then user=$DB_ADMIN_USER; pw=$DB_ADMIN_PASSWORD; else user=$who; pw=$DEMO_PASSWORD; fi
  MYSQL_PWD="$pw" mysql --protocol=TCP --host="$DB_HOST" --port="$DB_PORT" --user="$user" \
    --database="$DB" --batch --skip-column-names --raw ${SHOW_WARNINGS:+--show-warnings} -e "$sql"
}
step() { echo; echo "## $*"; }
ok()   { PASS=$((PASS+1)); echo "PASS  $1"; }
bad()  { FAIL=$((FAIL+1)); echo "FAIL  $1${2:+ ($2)}"; }
skip() { SKIP=$((SKIP+1)); echo "SKIP  $1${2:+ ($2)}"; }
# check NAME SQL: SQL (run as setup account) must return exactly 1
check() { local v; v=$(as admin "$2" 2>&1); [ "$v" = 1 ] && ok "$1" || bad "$1" "got: $v"; }
# run WHO NAME SQL: statement must succeed
run() { local e; if e=$(as "$1" "$3" 2>&1); then ok "$2"; else bad "$2" "$e"; fi; }
# deny WHO NAME SQL PATTERN: statement must fail with an error matching PATTERN (ERE)
deny() {
  local e; if e=$(as "$1" "$3" 2>&1); then bad "$2" "statement succeeded"
  elif grep -qiE "$4" <<<"$e"; then ok "$2  -> $(sed -E 's/ at line [0-9]+//' <<<"$e" | grep -m1 -oiE 'ERROR [0-9]+ \([0-9A-Z]+\).*' | cut -c1-110)"
  else bad "$2" "$e"; fi
}
# warn WHO NAME SQL PATTERN: statement must succeed AND raise a warning matching PATTERN
warn() {
  local e; if e=$(SHOW_WARNINGS=1 as "$1" "$3" 2>&1); then
    if grep -qiE "$4" <<<"$e"; then ok "$2  -> warning: $(grep -oiE "$4" <<<"$e" | head -1)"; else bad "$2" "no matching warning: $e"; fi
  else bad "$2" "$e"; fi
}
finish() {
  echo
  echo "## Summary: $PASS passed, $FAIL failed, $SKIP skipped"
  echo "Saved: $OUT"
  [ "$FAIL" -eq 0 ]
}
header() {
  echo "# $1  database=$DB  commit=$(git -C "$TESTS_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  echo "# $(as admin 'SELECT CONCAT("MySQL ", VERSION(), "  run at ", UTC_TIMESTAMP(), " UTC")')"
}
