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
: "${DB_HOST:?Set DB_HOST in build/config.env or environment}"
: "${DB_PORT:=3306}"
: "${DB_ADMIN_USER:?Set DB_ADMIN_USER}"
: "${DB_ADMIN_PASSWORD:?Set DB_ADMIN_PASSWORD}"
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

TABLES=$(mysql_admin --skip-column-names --database="$TARGET_DB" --execute="SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=DATABASE() AND table_type='BASE TABLE';" 2>>"$ERROR_LOG") || fail 'Final verification failed'
log "Completed scripts=${#SCRIPTS[@]} base_tables=$TABLES"
[ "$TABLES" = '15' ] || fail "Expected 15 base tables, found $TABLES"
log 'BUILD SUCCEEDED (SQL scripts ran; review validation query outputs and business tests in build.log)'
echo "Build log: $LOG"
echo "Error log: $ERROR_LOG"
