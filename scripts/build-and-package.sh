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

APP_DIR="$PROJECT_DIR/dist/BetterMeets.app"
CONTENTS_DIR="$APP_DIR/Contents"
SIGNING_IDENTITY="${BETTERMEETS_CODESIGN_IDENTITY:-}"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
BUNDLE_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PROJECT_DIR/Resources/Info.plist")"
METAL_SOURCE="$PROJECT_DIR/Sources/MeetStage/IdleStageChrome.metal"
METAL_AIR="$PROJECT_DIR/.build/$CONFIGURATION/IdleStageChrome.air"
METAL_LIBRARY="$PROJECT_DIR/.build/$CONFIGURATION/IdleStageChrome.metallib"
if ! METAL_COMPONENT_JSON="$(xcodebuild -showComponent MetalToolchain -json 2>/dev/null)"; then
    echo "The Metal Toolchain is required. Install it with:" >&2
    echo "  xcodebuild -downloadComponent MetalToolchain" >&2
    exit 1
fi
METAL_TOOLCHAIN_IDENTIFIER="$(
    plutil -extract toolchainIdentifier raw -o - - <<< "$METAL_COMPONENT_JSON"
)"

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

xcrun --sdk macosx --toolchain "$METAL_TOOLCHAIN_IDENTIFIER" \
    metal -c "$METAL_SOURCE" -o "$METAL_AIR"
xcrun --sdk macosx --toolchain "$METAL_TOOLCHAIN_IDENTIFIER" \
    metallib "$METAL_AIR" -o "$METAL_LIBRARY"

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
cp "$PROJECT_DIR/.build/$CONFIGURATION/MeetStage" "$CONTENTS_DIR/MacOS/MeetStage"
cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$PROJECT_DIR/Resources/BetterMeets.icns" "$CONTENTS_DIR/Resources/BetterMeets.icns"
cp "$METAL_LIBRARY" "$CONTENTS_DIR/Resources/IdleStageChrome.metallib"

if [[ -n "$SIGNING_IDENTITY" ]]; then
    # Developer ID builds need the hardened runtime and a trusted timestamp
    # before Apple will accept them for notarization.
    codesign \
        --force \
        --options runtime \
        --timestamp \
        --sign "$SIGNING_IDENTITY" \
        "$APP_DIR"
else
    # A stable designated requirement keeps Screen Recording approval valid
    # across local builds even though the ad-hoc binary hash changes.
    codesign \
        --force \
        --sign - \
        --requirements "=designated => identifier \"$BUNDLE_IDENTIFIER\"" \
        "$APP_DIR"
fi

codesign --verify --strict --verbose=2 "$APP_DIR"
