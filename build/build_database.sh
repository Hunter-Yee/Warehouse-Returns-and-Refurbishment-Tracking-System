#!/usr/bin/env bash
# Warehouse Returns: build a fresh database from an exact GitHub tag.
# Run with Git Bash (Windows) or Bash (macOS):
# bash build/build_database.sh OWNER REPO TAG TARGET_DB
set -euo pipefail

if [ "$#" -ne 4 ]; then
  echo "Usage: bash build/build_database.sh OWNER REPO TAG TARGET_DB" >&2
  exit 2
fi
OWNER=$1
REPO=$2
TAG=$3
TARGET_DB=$4

# Only permit ordinary GitHub repository identifiers, tags, and MySQL database names.
[[ "$OWNER" =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]] || { echo 'Invalid GitHub owner' >&2; exit 2; }
[[ "$REPO" =~ ^[A-Za-z0-9._-]+$ ]] || { echo 'Invalid repository name' >&2; exit 2; }
[[ "$TAG" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { echo 'Invalid tag' >&2; exit 2; }
[[ "$TARGET_DB" =~ ^[A-Za-z][A-Za-z0-9_]*$ ]] && [ "${#TARGET_DB}" -le 64 ] || {
  echo 'Database name must start with a letter and contain only letters, digits, or underscores (max 64)' >&2
  exit 2
}

# If running on Windows / Git Bash and mysql isn't in PATH yet, check standard MySQL directories
if ! command -v mysql >/dev/null 2>&1; then
  for p in "/c/Program Files/MySQL/MySQL Server 8.0/bin" \
           "/c/Program Files/MySQL/MySQL Server 26.7/bin" \
           "/c/Program Files/MySQL/MySQL Workbench 8.0" \
           "C:/Program Files/MySQL/MySQL Server 8.0/bin"; do
    if [ -d "$p" ]; then
      export PATH="$PATH:$p"
      break
    fi
  done
fi

if command -v sha256sum >/dev/null 2>&1; then sha256() { sha256sum "$1" | cut -d' ' -f1; }
elif command -v shasum >/dev/null 2>&1; then sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }
else echo 'Missing tool: sha256sum or shasum' >&2; exit 1; fi

for command_name in git mysql mktemp; do
  command -v "$command_name" >/dev/null 2>&1 || {
    echo "Missing tool: $command_name (install it and add it to PATH)" >&2
    exit 1
  }
done

# Config is LOCAL, not the copy retrieved from GitHub.
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CONFIG_FILE="$SCRIPT_DIR/config.env"
if [ -f "$CONFIG_FILE" ]; then
  # Shell-style KEY=VALUE entries only. Never commit this file.
  set -a
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
  set +a
fi
# Strip Windows CRLF carriage returns if present
DB_HOST="${DB_HOST%$'\r'}"
DB_PORT="${DB_PORT%$'\r'}"
DB_ADMIN_USER="${DB_ADMIN_USER%$'\r'}"
DB_ADMIN_PASSWORD="${DB_ADMIN_PASSWORD%$'\r'}"
DEMO_PASSWORD="${DEMO_PASSWORD:-}"
DEMO_PASSWORD="${DEMO_PASSWORD%$'\r'}"
ALLOW_SHARED_ACCOUNTS="${ALLOW_SHARED_ACCOUNTS:-0}"
ALLOW_SHARED_ACCOUNTS="${ALLOW_SHARED_ACCOUNTS%$'\r'}"
: "${DB_HOST:?Set DB_HOST in build/config.env or environment}"
: "${DB_PORT:=3306}"
: "${DB_ADMIN_USER:?Set DB_ADMIN_USER}"
: "${DB_ADMIN_PASSWORD:?Set DB_ADMIN_PASSWORD}"
# Demo role logins are created LOCKED and only unlocked with this password. No default is
# shipped in source control; choose one locally in build/config.env.
: "${DEMO_PASSWORD:?Set DEMO_PASSWORD in build/config.env (no default is provided)}"
[ "$DEMO_PASSWORD" != 'change_me_locally' ] || { echo 'Set DEMO_PASSWORD in build/config.env to your own value' >&2; exit 2; }
[ "${#DEMO_PASSWORD}" -ge 8 ] || { echo 'DEMO_PASSWORD must be at least 8 characters' >&2; exit 2; }
[[ "$DB_PORT" =~ ^[0-9]+$ ]] || { echo 'DB_PORT must be numeric' >&2; exit 2; }

# Keep local logs outside the tracked repository and don't expose credentials in CLI arguments.
WORK_ROOT="$SCRIPT_DIR/../.build-work"
mkdir -p "$WORK_ROOT"
RUN_DIR=$(mktemp -d "$WORK_ROOT/${REPO}-${TAG}-XXXXXXXX")
LOG="$RUN_DIR/build.log"
ERROR_LOG="$RUN_DIR/error.log"
REPO_DIR="$RUN_DIR/repository"
touch "$LOG" "$ERROR_LOG"

log() { printf '%s | %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG"; }
fail() { log "BUILD FAILED: $*"; echo "Build log: $LOG" >&2; echo "Error log: $ERROR_LOG" >&2; exit 1; }

mysql_admin() {
  MYSQL_PWD="$DB_ADMIN_PASSWORD" mysql --protocol=TCP --host="$DB_HOST" --port="$DB_PORT" \
    --user="$DB_ADMIN_USER" --batch --show-warnings "$@"
}

log "Starting build for $OWNER/$REPO tag=$TAG database=$TARGET_DB"
mysql_admin --execute='SELECT VERSION();' >>"$LOG" 2>>"$ERROR_LOG" || {
  if grep -qi microsoft /proc/version 2>/dev/null; then
    echo "Tip: You are running inside WSL. MySQL is installed on Windows, so 127.0.0.1 is trying to connect inside Linux. Please run this command in Git Bash instead of WSL." >&2
  fi
  fail 'Cannot connect to MySQL'
}

# GitHub authentication for private repositories should use Git's local credential manager.
log "Retrieving repository"
git clone --quiet --no-checkout "https://github.com/${OWNER}/${REPO}.git" "$REPO_DIR" >>"$LOG" 2>>"$ERROR_LOG" || fail 'Git clone failed'
git -C "$REPO_DIR" fetch --quiet origin "refs/tags/$TAG:refs/tags/$TAG" >>"$LOG" 2>>"$ERROR_LOG" || fail "Tag $TAG not found"
git -C "$REPO_DIR" checkout --quiet --detach "refs/tags/$TAG" >>"$LOG" 2>>"$ERROR_LOG" || fail 'Cannot check out tag'
RESOLVED=$(git -C "$REPO_DIR" describe --tags --exact-match HEAD 2>/dev/null || true)
[ "$RESOLVED" = "$TAG" ] || fail "Checked-out commit is not exactly tag $TAG"
SHA=$(git -C "$REPO_DIR" rev-parse HEAD)
log "Verified tag=$TAG commit=$SHA"

MANIFEST="$REPO_DIR/database/manifest.txt"
[ -f "$MANIFEST" ] || fail 'Missing database/manifest.txt in tagged repository'

# Read manifest BEFORE touching the target database. Paths are relative to database/.
SCRIPTS=()
while IFS= read -r entry || [ -n "$entry" ]; do
  entry="${entry%$'\r'}"  # tolerate Windows CRLF
  [[ -z "$entry" || "$entry" =~ ^[[:space:]]*# ]] && continue
  # Also accept professor-style paths beginning with database/.
  entry="${entry#database/}"
  [[ "$entry" =~ ^[A-Za-z0-9_./-]+\.sql$ && "$entry" != /* && "$entry" != *..* ]] || fail "Invalid manifest entry: $entry"
  [ -f "$REPO_DIR/database/$entry" ] || fail "Manifest file missing: database/$entry"
  SCRIPTS+=("$entry")
done < "$MANIFEST"
[ "${#SCRIPTS[@]}" -gt 0 ] || fail 'Manifest is empty'

# A protected fresh build: never replace a pre-existing database.
EXISTING=$(mysql_admin --skip-column-names --execute="SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='${TARGET_DB}';" 2>>"$ERROR_LOG") || fail 'Database existence check failed'
[ "$EXISTING" = '0' ] || fail "Database $TARGET_DB already exists; choose a different new name"

# MySQL accounts and roles are server-wide, not per schema. Another existing build of this
# project on the same server shares wr_role_*, wr_owner and the wr_* logins: this build would
# reset their passwords, and those logins would then reach both schemas. Refuse unless the
# operator explicitly accepts sharing (ALLOW_SHARED_ACCOUNTS=1 in build/config.env).
SHARED=$(mysql_admin --skip-column-names --execute="
SELECT GROUP_CONCAT(DISTINCT p.Db ORDER BY p.Db SEPARATOR ', ') FROM (
  SELECT Db, User FROM mysql.db UNION ALL SELECT Db, User FROM mysql.tables_priv UNION ALL SELECT Db, User FROM mysql.procs_priv
) p JOIN information_schema.SCHEMATA s ON s.SCHEMA_NAME = p.Db
WHERE (p.User LIKE 'wr\\_role\\_%' OR p.User = 'wr_owner') AND p.Db <> '${TARGET_DB}' AND p.Db NOT IN ('performance_schema', 'mysql', 'sys');" 2>>"$ERROR_LOG") || fail 'Shared account check failed'
if [ -n "$SHARED" ] && [ "$SHARED" != 'NULL' ]; then
  if [ "$ALLOW_SHARED_ACCOUNTS" = '1' ]; then
    log "WARNING: wr_* roles/logins are shared with existing schema(s): $SHARED (ALLOW_SHARED_ACCOUNTS=1)"
  else
    fail "wr_* roles/logins already serve schema(s) $SHARED on this server. Drop those schemas (and REVOKE their grants), use another MySQL server, or set ALLOW_SHARED_ACCOUNTS=1 to share the accounts deliberately."
  fi
fi

log "Creating fresh database $TARGET_DB"
mysql_admin --execute="CREATE DATABASE \`$TARGET_DB\`;" >>"$LOG" 2>>"$ERROR_LOG" || fail 'CREATE DATABASE failed'

for entry in "${SCRIPTS[@]}"; do
  sql_file="$REPO_DIR/database/$entry"
  log "Running database/$entry"
  # Supply the database context to each file. Stops on the first SQL/client error.
  if mysql_admin --database="$TARGET_DB" --binary-mode < "$sql_file" >>"$LOG" 2>>"$ERROR_LOG"; then
    log "OK: database/$entry"
  else
    fail "SQL failed: database/$entry (check error log)"
  fi
done

# Set the demo password and unlock each login. Any failure fails the build: a login must never
# be left without the intended password. Quotes/backslashes are escaped for the SQL literal.
SQL_PASSWORD=${DEMO_PASSWORD//\\/\\\\}
SQL_PASSWORD=${SQL_PASSWORD//\'/\'\'}
for u in wr_receiving01 wr_inspector01 wr_technician01 wr_technician02 wr_manager01 wr_admin01; do
  mysql_admin --execute="ALTER USER '$u'@'localhost' IDENTIFIED BY '$SQL_PASSWORD' ACCOUNT UNLOCK;" >>"$LOG" 2>>"$ERROR_LOG" \
    || fail "Could not set the password for $u"
done
log "Demo logins unlocked with DEMO_PASSWORD"

# Record the in-database version stamp (SchemaBuild / SchemaBuildScript).
MANIFEST_SHA=$(sha256 "$MANIFEST")
STAMP_SQL="INSERT INTO SchemaBuild (ReleaseTag, CommitSHA, ManifestSHA256, ScriptCount, MySQLVersion, BuiltBy, BuiltAt)
VALUES ('$TAG', '$SHA', '$MANIFEST_SHA', ${#SCRIPTS[@]}, VERSION(), CURRENT_USER(), UTC_TIMESTAMP(6));
SET @build_id = LAST_INSERT_ID();"
order=0
for entry in "${SCRIPTS[@]}"; do
  order=$((order + 1))
  STAMP_SQL="$STAMP_SQL
INSERT INTO SchemaBuildScript (BuildID, RunOrder, ScriptPath, ScriptSHA256) VALUES (@build_id, $order, 'database/$entry', '$(sha256 "$REPO_DIR/database/$entry")');"
done
mysql_admin --database="$TARGET_DB" --execute="START TRANSACTION; $STAMP_SQL COMMIT;" >>"$LOG" 2>>"$ERROR_LOG" || fail 'Could not record the schema version stamp'
log "Recorded SchemaBuild tag=$TAG commit=$SHA scripts=${#SCRIPTS[@]}"

TABLES=$(mysql_admin --skip-column-names --database="$TARGET_DB" --execute="SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=DATABASE() AND table_type='BASE TABLE' AND table_name NOT LIKE '%History' AND table_name NOT LIKE 'SchemaBuild%';" 2>>"$ERROR_LOG") || fail 'Final verification failed'
HISTORY_TABLES=$(mysql_admin --skip-column-names --database="$TARGET_DB" --execute="SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=DATABASE() AND table_type='BASE TABLE' AND table_name LIKE '%History';" 2>>"$ERROR_LOG") || fail 'Final verification failed'
log "Completed scripts=${#SCRIPTS[@]} base_tables=$TABLES history_tables=$HISTORY_TABLES"
[ "$TABLES" = '15' ] || fail "Expected 15 base tables, found $TABLES"
[ "$HISTORY_TABLES" = '14' ] || fail "Expected 14 history tables, found $HISTORY_TABLES"
log 'BUILD SUCCEEDED (SQL scripts ran; review validation query outputs and business tests in build.log)'
echo "Build log: $LOG"
echo "Error log: $ERROR_LOG"
