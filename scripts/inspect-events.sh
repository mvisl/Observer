#!/usr/bin/env bash
set -euo pipefail

DB_PATH="${HOME}/Library/Application Support/Observer/observer.sqlite"

if [[ ! -f "$DB_PATH" ]]; then
  echo "Observer database not found: $DB_PATH" >&2
  exit 1
fi

sqlite3 "$DB_PATH" <<'SQL'
.headers on
.mode column
SELECT timestamp, type, app_id, display_role, substr(payload_json, 1, 120) AS payload
FROM events
ORDER BY timestamp DESC
LIMIT 40;
SQL
