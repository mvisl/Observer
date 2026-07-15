#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/build/Observer.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

if command -v pnpm >/dev/null 2>&1 && [[ -f "$ROOT_DIR/apps/observer-web/package.json" ]]; then
  pnpm --dir "$ROOT_DIR/apps/observer-web" build
fi
swift build --package-path "$ROOT_DIR"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$ROOT_DIR/.build/debug/ObserverApp" "$MACOS_DIR/ObserverApp"
python3 "$ROOT_DIR/scripts/generate-app-icon.py" "$RESOURCES_DIR"
iconutil -c icns "$RESOURCES_DIR/ObserverIcon.iconset" -o "$RESOURCES_DIR/ObserverIcon.icns"
rm -rf "$RESOURCES_DIR/ObserverIcon.iconset"
if [[ -d "$ROOT_DIR/apps/observer-web/dist" ]]; then
  cp -R "$ROOT_DIR/apps/observer-web/dist" "$RESOURCES_DIR/observer-web"
fi

/usr/libexec/PlistBuddy -c "Clear dict" "$CONTENTS_DIR/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleName string Observer" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string Observer" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string local.observer.dev" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string 0.1.0" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 0.1.0" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string ObserverApp" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string ObserverIcon" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSHumanReadableCopyright string Local development build" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSCameraUsageDescription string Observer uses the camera locally to estimate coarse attention signals. Frames are not stored." "$CONTENTS_DIR/Info.plist"

if [[ -n "${OBSERVER_CODESIGN_IDENTITY:-}" ]]; then
  SIGN_IDENTITY="$OBSERVER_CODESIGN_IDENTITY"
elif SIGN_IDENTITY="$("$ROOT_DIR/scripts/ensure-local-codesign-identity.sh" 2>/dev/null)"; then
  :
else
  SIGN_IDENTITY="-"
fi

codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR"

echo "$APP_DIR"
