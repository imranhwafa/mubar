#!/bin/bash
# Builds MUBAR (Release) and packages it into a drag-to-install DMG with a
# custom background — no third-party tools, just hdiutil + AppleScript.
# Output: MUBAR.dmg in the repo root.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="MUBAR"
VOL="MUBAR"
DMG="${APP_NAME}.dmg"
STAGING="build/dmg-staging"
TMP_DMG="build/${APP_NAME}-tmp.dmg"

mkdir -p build

echo "==> Building Release (.app)…"
xcodebuild -project MUBAR.xcodeproj -scheme MUBAR -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  build \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  SWIFT_OPTIMIZATION_LEVEL='-Osize' \
  | tail -3

APP=$(find ~/Library/Developer/Xcode/DerivedData/MUBAR-*/Build/Products/Release \
  -maxdepth 2 -name "${APP_NAME}.app" -type d 2>/dev/null | head -1)
[ -n "$APP" ] && [ -d "$APP" ] || { echo "build failed: ${APP_NAME}.app not found"; exit 1; }
echo "    app: $APP"

echo "==> Ad-hoc signing…"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP" && echo "    signature OK"

echo "==> Generating DMG background…"
swift tools/make_dmg_background.swift

echo "==> Staging…"
rm -rf "$STAGING"
mkdir -p "$STAGING/.background"
cp -R "$APP" "$STAGING/"
cp tools/dmg/background.png    "$STAGING/.background/background.png"
cp tools/dmg/background@2x.png "$STAGING/.background/background@2x.png"
ln -s /Applications "$STAGING/Applications"

echo "==> Creating writable DMG…"
rm -f "$TMP_DMG" "$DMG"
hdiutil create -srcfolder "$STAGING" -volname "$VOL" -fs HFS+ \
  -format UDRW -ov "$TMP_DMG" >/dev/null

echo "==> Mounting…"
DEV=$(hdiutil attach "$TMP_DMG" -noautoopen -nobrowse | grep -E '^/dev/' | head -1 | awk '{print $1}')
MOUNT="/Volumes/$VOL"
for _ in $(seq 1 20); do [ -d "$MOUNT" ] && break; sleep 0.5; done

echo "==> Styling Finder window…"
osascript <<APPLESCRIPT || echo "    (Finder styling skipped — automation not permitted)"
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 800, 520}
    set vo to the icon view options of container window
    set arrangement of vo to not arranged
    set icon size of vo to 110
    set text size of vo to 13
    set background picture of vo to file ".background:background.png"
    set position of item "${APP_NAME}.app" of container window to {150, 205}
    set position of item "Applications" of container window to {450, 205}
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT

sync
echo "==> Unmounting…"
hdiutil detach "$DEV" >/dev/null || hdiutil detach "$MOUNT" -force >/dev/null

echo "==> Compressing…"
hdiutil convert "$TMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
rm -f "$TMP_DMG"

SIZE=$(du -h "$DMG" | cut -f1)
echo "==> Done: $DMG ($SIZE)"
