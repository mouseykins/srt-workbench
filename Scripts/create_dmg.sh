#!/bin/bash
#
# create_dmg.sh
# Creates a DMG installer for SRT Workbench.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="SRT Workbench"
DMG_NAME="SRTWorkbench"

# Find the built .app
BUILD_DIR="$PROJECT_DIR/build"
APP_PATH=""

# Check common Xcode build output locations
for candidate in \
    "$BUILD_DIR/Release/${APP_NAME}.app" \
    "$BUILD_DIR/Build/Products/Release/${APP_NAME}.app" \
    "$HOME/Library/Developer/Xcode/DerivedData"/SRTWorkbench-*/Build/Products/Release/"${APP_NAME}.app"; do
    if [[ -d "$candidate" ]]; then
        APP_PATH="$candidate"
        break
    fi
done

if [[ -z "$APP_PATH" ]]; then
    echo "Error: Could not find ${APP_NAME}.app"
    echo "Build the project in Xcode first (Product > Build, Release configuration)"
    exit 1
fi

echo "Found app: $APP_PATH"

# --- Create DMG ---
STAGING_DIR=$(mktemp -d)
DMG_PATH="$PROJECT_DIR/${DMG_NAME}.dmg"

echo "Creating DMG..."

# Copy app to staging
cp -R "$APP_PATH" "$STAGING_DIR/"

# Create Applications symlink for drag-to-install
ln -s /Applications "$STAGING_DIR/Applications"

# Remove old DMG if exists
rm -f "$DMG_PATH"

# Create DMG
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov -format UDZO \
    "$DMG_PATH"

# Cleanup
rm -rf "$STAGING_DIR"

echo ""
echo "=== DMG created ==="
echo "Location: $DMG_PATH"
echo "Size: $(du -h "$DMG_PATH" | cut -f1)"
