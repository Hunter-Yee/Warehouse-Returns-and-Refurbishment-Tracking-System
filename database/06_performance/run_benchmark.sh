#!/usr/bin/env bash
# Load scaled data into an EXISTING scratch database and run the benchmark.
# Output is saved under database/06_performance/results/ so it can be committed as evidence.
#
#   bash build/build_database.sh OWNER REPO TAG wr_perf      # fresh build first
#   bash database/06_performance/run_benchmark.sh wr_perf [RETURNS]
#
# Uses the same build/config.env as the build script. Never point this at the
# baseline demo schema: it adds ~100,000 synthetic units.
set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "Usage: bash database/06_performance/run_benchmark.sh TARGET_DB [RETURNS]" >&2
  exit 2
fi
TARGET_DB=$1
RETURNS=${2:-50000}
[[ "$TARGET_DB" =~ ^[A-Za-z][A-Za-z0-9_]*$ ]] || { echo 'Invalid database name' >&2; exit 2; }
[[ "$RETURNS" =~ ^[0-9]+$ ]] && [ "$RETURNS" -ge 1 ] && [ "$RETURNS" -le 100000 ] || {
  echo 'RETURNS must be 1..100000' >&2; exit 2; }
command -v mysql >/dev/null 2>&1 || { echo 'Missing tool: mysql' >&2; exit 1; }

PERF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CONFIG_FILE="$PERF_DIR/../../build/config.env"
if [ -f "$CONFIG_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
  set +a
fi
DB_HOST="${DB_HOST%$'\r'}"
DB_PORT="${DB_PORT:-3306}"; DB_PORT="${DB_PORT%$'\r'}"
DB_ADMIN_USER="${DB_ADMIN_USER%$'\r'}"
DB_ADMIN_PASSWORD="${DB_ADMIN_PASSWORD%$'\r'}"
: "${DB_HOST:?Set DB_HOST in build/config.env or environment}"
: "${DB_ADMIN_USER:?Set DB_ADMIN_USER}"
: "${DB_ADMIN_PASSWORD:?Set DB_ADMIN_PASSWORD}"

mysql_admin() {
  MYSQL_PWD="$DB_ADMIN_PASSWORD" mysql --protocol=TCP --host="$DB_HOST" --port="$DB_PORT" \
    --user="$DB_ADMIN_USER" --database="$TARGET_DB" --batch --raw --show-warnings "$@"
}

HAS_INDEX=$(mysql_admin --skip-column-names --execute="SELECT COUNT(*) FROM information_schema.STATISTICS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='AuditLog' AND INDEX_NAME='ix_audit_entity_record';") \
  || { echo "Cannot connect to database $TARGET_DB (build it first)" >&2; exit 1; }
[ "$HAS_INDEX" != '0' ] || { echo "$TARGET_DB has no ix_audit_entity_record; build from a tag that includes it" >&2; exit 1; }

mkdir -p "$PERF_DIR/results"
OUT="$PERF_DIR/results/benchmark_$(date -u '+%Y%m%dT%H%M%SZ').txt"

{
  echo "# Warehouse Returns scaled benchmark"
  echo "# database=$TARGET_DB returns=$RETURNS commit=$(git -C "$PERF_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  echo
  echo "## 010_load_scale_data.sql"
  # Pipe instead of the client "source" command so Windows Git Bash paths work.
  { echo "SET @perf_returns=$RETURNS;"; cat "$PERF_DIR/010_load_scale_data.sql"; } | mysql_admin
  echo
  echo "## 020_benchmark.sql (warm-up run, discarded)"
  mysql_admin < "$PERF_DIR/020_benchmark.sql" >/dev/null
  echo "(done)"
  echo
  echo "## 020_benchmark.sql (measured run)"
  mysql_admin < "$PERF_DIR/020_benchmark.sql"
} 2>&1 | tee "$OUT"

echo
echo "Saved: $OUT"
