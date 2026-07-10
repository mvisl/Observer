#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DB_PATH="${HOME}/Library/Application Support/Observer/observer.sqlite"

echo "Observer workspace: $ROOT_DIR"
echo "App bundle: $ROOT_DIR/build/Observer.app"
echo

if [[ -d "$ROOT_DIR/build/Observer.app" ]]; then
  codesign --verify --deep --strict --verbose=2 "$ROOT_DIR/build/Observer.app"
else
  echo "App bundle not built yet."
fi

echo
if [[ -f "$DB_PATH" ]]; then
  sqlite3 "$DB_PATH" 'SELECT type, COUNT(*) FROM events GROUP BY type ORDER BY type;'
else
  echo "Observer database not found: $DB_PATH"
fi
