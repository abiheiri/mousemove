#!/bin/bash
# Create DMG for mmove
# Usage: ./create-dmg.sh <version> [app-path]
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="mmove"

VERSION="${1:?Usage: ./create-dmg.sh <version> [app-path]}"
APP="${2:-$PROJECT_DIR/.build/DerivedData/Build/Products/Release/$PROJECT.app}"

[ -d "$APP" ] || { echo "❌ App not found: $APP"; exit 1; }

DMG_NAME="${PROJECT}-${VERSION}-macOS-arm64"
STAGING="$PROJECT_DIR/dmg-build"
RELEASE="$PROJECT_DIR/release"

rm -rf "$STAGING" "$RELEASE"
mkdir -p "$STAGING" "$RELEASE"

echo "📦 Staging $APP …"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

echo "💿 Creating DMG…"
TEMP="$RELEASE/${DMG_NAME}-temp.dmg"
hdiutil create -volname "$PROJECT" -srcfolder "$STAGING" -ov -format UDRW "$TEMP"

MOUNT="/Volumes/$PROJECT"
hdiutil attach "$TEMP" -mountpoint "$MOUNT" -quiet
sleep 2

osascript <<EOF
tell application "Finder"
  tell disk "$PROJECT"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {100, 100, 600, 400}
    set opts to icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 72
    set position of item "$PROJECT.app" of container window to {120, 150}
    set position of item "Applications" of container window to {380, 150}
    update without registering applications
    delay 2
  end tell
end tell
EOF

sync
hdiutil detach "$MOUNT" -quiet

FINAL="$RELEASE/${DMG_NAME}.dmg"
hdiutil convert "$TEMP" -format UDZO -o "$FINAL"
rm -f "$TEMP"
rm -rf "$STAGING"

echo "✅ $FINAL  ($(du -h "$FINAL" | cut -f1))"
