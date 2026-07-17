#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT_DIR/scripts/stable-signing-config.sh"
DB_PATH="${HOME}/Library/Application Support/Observer/observer.sqlite"

echo "Observer workspace: $ROOT_DIR"
echo "App bundle: $OBSERVER_INSTALL_PATH"
echo "Bundle ID: $OBSERVER_PRODUCT_BUNDLE_IDENTIFIER"
echo "Development Team: $OBSERVER_DEVELOPMENT_TEAM"
echo "Code sign identity: $OBSERVER_CODE_SIGN_IDENTITY"
echo

if [[ -d "$OBSERVER_INSTALL_PATH" ]]; then
  codesign --verify --deep --strict --verbose=2 "$OBSERVER_INSTALL_PATH"
  codesign -dv --verbose=4 "$OBSERVER_INSTALL_PATH" 2>&1 | sed -n '/Identifier=/p;/Authority=/p;/TeamIdentifier=/p'
  codesign -d -r- "$OBSERVER_INSTALL_PATH" 2>&1
else
  echo "App bundle not built yet."
fi

echo
if [[ -f "$DB_PATH" ]]; then
  sqlite3 "$DB_PATH" 'SELECT type, COUNT(*) FROM events GROUP BY type ORDER BY type;'
else
  echo "Observer database not found: $DB_PATH"
fi
