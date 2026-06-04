#!/bin/bash
#
# create_dmg.sh
# Creates a DMG installer for SRT Workbench from the most recent Release build.
#
# Usage:
#   ./Scripts/create_dmg.sh [--app "/path/to/SRT Workbench.app"] [--expect-version X.Y.Z]
#
#   --app             Package this exact .app instead of auto-detecting.
#   --expect-version  Refuse to package unless the built app reports this
#                     CFBundleShortVersionString. Use this in your release flow
#                     so a stale build can never be shipped by mistake.
#
# When auto-detecting, ALL candidate Release builds are considered (build/ and
# every Xcode DerivedData folder) and the MOST RECENTLY MODIFIED one is chosen —
# so leftover stale builds can't be packaged ahead of a fresh one.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="SRT Workbench"
DMG_NAME="SRTWorkbench"

EXPLICIT_APP=""
EXPECT_VERSION=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --app)            EXPLICIT_APP="${2:-}"; shift 2;;
        --expect-version) EXPECT_VERSION="${2:-}"; shift 2;;
        -h|--help)        sed -n '2,18p' "$0"; exit 0;;
        *) echo "Unknown argument: $1" >&2; exit 2;;
    esac
done

app_version() {
    /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$1/Contents/Info.plist" 2>/dev/null || echo "?"
}

APP_PATH=""

if [[ -n "$EXPLICIT_APP" ]]; then
    if [[ ! -d "$EXPLICIT_APP" ]]; then
        echo "Error: --app path does not exist: $EXPLICIT_APP" >&2
        exit 1
    fi
    APP_PATH="$EXPLICIT_APP"
else
    # Gather every candidate Release .app, then pick the most recently modified.
    newest=""
    newest_mtime=0
    consider() {
        local c="$1"
        [[ -d "$c" ]] || return 0
        local mtime
        mtime="$(stat -f %m "$c")"
        if (( mtime > newest_mtime )); then
            newest_mtime="$mtime"
            newest="$c"
        fi
    }

    consider "$PROJECT_DIR/build/Release/${APP_NAME}.app"
    consider "$PROJECT_DIR/build/Build/Products/Release/${APP_NAME}.app"
    # There can be more than one DerivedData folder for the project.
    for d in "$HOME/Library/Developer/Xcode/DerivedData"/SRTWorkbench-*/Build/Products/Release/"${APP_NAME}.app"; do
        consider "$d"
    done

    APP_PATH="$newest"
fi

if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
    echo "Error: Could not find a built ${APP_NAME}.app" >&2
    echo "Build the Release configuration first, e.g.:" >&2
    echo "  xcodebuild -project SRTWorkbench.xcodeproj -scheme SRTWorkbench -configuration Release build" >&2
    exit 1
fi

VERSION="$(app_version "$APP_PATH")"
echo "Selected app : $APP_PATH"
echo "Version      : $VERSION"
echo "Built        : $(stat -f '%Sm' "$APP_PATH")"

if [[ -n "$EXPECT_VERSION" && "$VERSION" != "$EXPECT_VERSION" ]]; then
    echo "Error: built app is version '$VERSION' but --expect-version '$EXPECT_VERSION' was requested." >&2
    echo "Refusing to package a mismatched build. Rebuild Release, then retry." >&2
    exit 1
fi

# --- Create DMG ---
STAGING_DIR=$(mktemp -d)
DMG_PATH="$PROJECT_DIR/${DMG_NAME}.dmg"

echo "Creating DMG..."
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"
rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov -format UDZO \
    "$DMG_PATH"
rm -rf "$STAGING_DIR"

echo ""
echo "=== DMG created ==="
echo "Location: $DMG_PATH"
echo "Version : $VERSION"
echo "Size    : $(du -h "$DMG_PATH" | cut -f1)"
