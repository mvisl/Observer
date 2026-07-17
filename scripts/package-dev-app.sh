#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT_DIR/scripts/stable-signing-config.sh"

INSTALL_APP_DIR="$OBSERVER_INSTALL_PATH"
APP_DIR="$ROOT_DIR/build/Observer.app.staging"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ENTITLEMENTS_FILE="$ROOT_DIR/$OBSERVER_ENTITLEMENTS_RELATIVE_PATH"

fail() {
  echo "Observer packaging failed: $*" >&2
  exit 1
}

resolve_signing_identity() {
  local identities matches line
  identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  matches="$(printf '%s\n' "$identities" | grep "\"$OBSERVER_CODE_SIGN_IDENTITY:" | grep "($OBSERVER_DEVELOPMENT_TEAM)" || true)"
  local count
  count="$(printf '%s\n' "$matches" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')"
  if [[ "$count" == "0" ]]; then
    fail "Apple Development certificate for team $OBSERVER_DEVELOPMENT_TEAM was not found in Keychain. Open Xcode Settings → Accounts → Manage Certificates and create/install an Apple Development certificate for this team. Refusing ad-hoc/self-signed fallback."
  fi
  if [[ "$count" != "1" ]]; then
    echo "$matches" >&2
    fail "Expected exactly one Apple Development identity for team $OBSERVER_DEVELOPMENT_TEAM, found $count. Remove duplicates or pin a single certificate before building."
  fi
  line="$(printf '%s\n' "$matches" | head -1)"
  printf '%s\n' "$line" | awk '{print $2}'
}

[[ -f "$ENTITLEMENTS_FILE" ]] || fail "Missing stable entitlements file: $ENTITLEMENTS_FILE"
plutil -lint "$ENTITLEMENTS_FILE" >/dev/null || fail "Invalid entitlements file: $ENTITLEMENTS_FILE"
SIGN_IDENTITY="$(resolve_signing_identity)"

if command -v pnpm >/dev/null 2>&1 && [[ -f "$ROOT_DIR/apps/observer-web/package.json" ]]; then
  pnpm --dir "$ROOT_DIR/apps/observer-web" build
fi
swift build --package-path "$ROOT_DIR"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$ROOT_DIR/.build/debug/$OBSERVER_EXECUTABLE_NAME" "$MACOS_DIR/$OBSERVER_EXECUTABLE_NAME"
python3 "$ROOT_DIR/scripts/generate-app-icon.py" "$RESOURCES_DIR"
iconutil -c icns "$RESOURCES_DIR/ObserverIcon.iconset" -o "$RESOURCES_DIR/ObserverIcon.icns"
rm -rf "$RESOURCES_DIR/ObserverIcon.iconset"
if [[ -d "$ROOT_DIR/apps/observer-web/dist" ]]; then
  cp -R "$ROOT_DIR/apps/observer-web/dist" "$RESOURCES_DIR/observer-web"
fi

/usr/libexec/PlistBuddy -c "Clear dict" "$CONTENTS_DIR/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleName string $OBSERVER_PRODUCT_NAME" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string $OBSERVER_PRODUCT_NAME" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $OBSERVER_PRODUCT_BUNDLE_IDENTIFIER" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string 0.1.0" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 0.1.0" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $OBSERVER_EXECUTABLE_NAME" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string ObserverIcon" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSHumanReadableCopyright string Local development build" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSCameraUsageDescription string Observer uses the camera locally to estimate coarse attention signals. Frames are not stored." "$CONTENTS_DIR/Info.plist"

codesign --force --deep --options runtime --entitlements "$ENTITLEMENTS_FILE" --sign "$SIGN_IDENTITY" "$APP_DIR"
codesign --verify --deep --strict --verbose=4 "$APP_DIR" >/dev/null
codesign -d -r- "$APP_DIR" >/dev/null 2>&1

if pgrep -x "$OBSERVER_EXECUTABLE_NAME" >/dev/null 2>&1; then
  osascript -e "tell application id \"$OBSERVER_PRODUCT_BUNDLE_IDENTIFIER\" to quit" >/dev/null 2>&1 || true
  sleep 1
fi

if pgrep -x "$OBSERVER_EXECUTABLE_NAME" >/dev/null 2>&1; then
  fail "$OBSERVER_PRODUCT_NAME is still running. Quit it before replacing $INSTALL_APP_DIR."
fi

rm -rf "$INSTALL_APP_DIR"
mv "$APP_DIR" "$INSTALL_APP_DIR"
codesign --verify --deep --strict --verbose=4 "$INSTALL_APP_DIR" >/dev/null

echo "$INSTALL_APP_DIR"
