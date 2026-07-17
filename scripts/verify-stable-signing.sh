#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT_DIR/scripts/stable-signing-config.sh"

SNAPSHOT_DIR="$ROOT_DIR/build/signing-snapshots"
mkdir -p "$SNAPSHOT_DIR"

capture_snapshot() {
  local name="$1"
  local dir="$SNAPSHOT_DIR/$name"
  rm -rf "$dir"
  mkdir -p "$dir"

  "$ROOT_DIR/scripts/package-dev-app.sh" >/dev/null

  /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$OBSERVER_INSTALL_PATH/Contents/Info.plist" > "$dir/bundle-id.txt"
  codesign -d -r- "$OBSERVER_INSTALL_PATH" > "$dir/designated-requirement.txt" 2>&1
  codesign -dv --verbose=4 "$OBSERVER_INSTALL_PATH" > "$dir/signature.txt" 2>&1
  codesign -d --entitlements :- "$OBSERVER_INSTALL_PATH" > "$dir/entitlements.plist" 2>&1
  shasum -a 256 "$dir/entitlements.plist" | awk '{print $1}' > "$dir/entitlements.sha256"
  sed -n '/^Identifier=/p;/^Authority=/p;/^TeamIdentifier=/p' "$dir/signature.txt" > "$dir/stable-fields.txt"
}

capture_snapshot "A"
capture_snapshot "B"

diff -u "$SNAPSHOT_DIR/A/bundle-id.txt" "$SNAPSHOT_DIR/B/bundle-id.txt"
diff -u "$SNAPSHOT_DIR/A/designated-requirement.txt" "$SNAPSHOT_DIR/B/designated-requirement.txt"
diff -u "$SNAPSHOT_DIR/A/stable-fields.txt" "$SNAPSHOT_DIR/B/stable-fields.txt"
diff -u "$SNAPSHOT_DIR/A/entitlements.sha256" "$SNAPSHOT_DIR/B/entitlements.sha256"

echo "Stable signing verification passed for $OBSERVER_INSTALL_PATH"
