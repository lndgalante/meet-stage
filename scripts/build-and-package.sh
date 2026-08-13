#!/bin/zsh

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-}"

case "$CONFIGURATION" in
    debug|release) ;;
    *)
        echo "Usage: scripts/build-and-package.sh <debug|release>" >&2
        exit 64
        ;;
esac

APP_DIR="$PROJECT_DIR/dist/BetterDemos.app"
CONTENTS_DIR="$APP_DIR/Contents"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
BUNDLE_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PROJECT_DIR/Resources/Info.plist")"

cd "$PROJECT_DIR"
mkdir -p \
    "$PROJECT_DIR/.build/clang-module-cache" \
    "$PROJECT_DIR/.build/swiftpm-module-cache" \
    "$PROJECT_DIR/.build/swiftpm-cache" \
    "$PROJECT_DIR/.build/swiftpm-config" \
    "$PROJECT_DIR/.build/swiftpm-security"

SDKROOT="$SDK_PATH" \
CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/clang-module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_DIR/.build/swiftpm-module-cache" \
XDG_CACHE_HOME="$PROJECT_DIR/.build/swiftpm-cache" \
swift build \
    --disable-sandbox \
    --cache-path "$PROJECT_DIR/.build/swiftpm-cache" \
    --config-path "$PROJECT_DIR/.build/swiftpm-config" \
    --security-path "$PROJECT_DIR/.build/swiftpm-security" \
    -c "$CONFIGURATION"

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
cp "$PROJECT_DIR/.build/$CONFIGURATION/MeetStage" "$CONTENTS_DIR/MacOS/MeetStage"
cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$PROJECT_DIR/Resources/BetterDemos.icns" "$CONTENTS_DIR/Resources/BetterDemos.icns"

# A stable designated requirement keeps Screen Recording approval valid across
# debug and release builds even though the ad-hoc binary hash changes.
codesign \
    --force \
    --deep \
    --sign - \
    --requirements "=designated => identifier \"$BUNDLE_IDENTIFIER\"" \
    "$APP_DIR"
