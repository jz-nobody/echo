#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/../AgentIsland"
BUILD_DIR="$SCRIPT_DIR/../build"
APP_NAME="AgentIsland"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
DMG_NAME="$APP_NAME.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"
VOLUME_NAME="Agent Island"

echo "==> Cleaning previous build..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Building release binaries..."
cd "$PROJECT_DIR"
swift build -c release 2>&1

RELEASE_DIR="$(swift build -c release --show-bin-path)"

echo "==> Assembling app bundle..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources/Sounds"

cp "$PROJECT_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

cp "$RELEASE_DIR/AgentIsland" "$APP_BUNDLE/Contents/MacOS/AgentIsland"
cp "$RELEASE_DIR/agent-island-bridge" "$APP_BUNDLE/Contents/MacOS/agent-island-bridge"

cp "$PROJECT_DIR/Resources/Sounds/"*.wav "$APP_BUNDLE/Contents/Resources/Sounds/"

echo "==> Ad-hoc code signing..."
codesign --force --deep -s - "$APP_BUNDLE"

echo "==> Creating DMG..."
STAGING="$BUILD_DIR/dmg-staging"
mkdir -p "$STAGING"
cp -R "$APP_BUNDLE" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING" \
    -ov -format UDZO \
    "$DMG_PATH"

rm -rf "$STAGING"

echo ""
echo "==> Done! DMG created at: $DMG_PATH"
echo ""
echo "Note: This is ad-hoc signed. First-time users need to:"
echo "  1. Right-click the app and select 'Open', OR"
echo "  2. Go to System Settings > Privacy & Security > click 'Open Anyway', OR"
echo "  3. Run: xattr -cr /Applications/$APP_NAME.app"
