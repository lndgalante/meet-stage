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
UPDATE_FEED_URL="${BETTERMEETS_UPDATE_FEED_URL:-}"
UPDATE_PUBLIC_KEY="${BETTERMEETS_UPDATE_PUBLIC_KEY:-}"
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
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources" "$CONTENTS_DIR/Frameworks"
cp "$PROJECT_DIR/.build/$CONFIGURATION/MeetStage" "$CONTENTS_DIR/MacOS/MeetStage"
cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$PROJECT_DIR/Resources/BetterMeets.icns" "$CONTENTS_DIR/Resources/BetterMeets.icns"
cp "$METAL_LIBRARY" "$CONTENTS_DIR/Resources/IdleStageChrome.metallib"
cp -R "$PROJECT_DIR/Resources/en.lproj" "$CONTENTS_DIR/Resources/en.lproj"

SPARKLE_SOURCE="$PROJECT_DIR/.build/$CONFIGURATION/Sparkle.framework"
SPARKLE_DESTINATION="$CONTENTS_DIR/Frameworks/Sparkle.framework"
if [[ ! -d "$SPARKLE_SOURCE" ]]; then
    echo "SwiftPM did not produce Sparkle.framework at $SPARKLE_SOURCE" >&2
    exit 1
fi
/usr/bin/ditto "$SPARKLE_SOURCE" "$SPARKLE_DESTINATION"
install_name_tool -add_rpath @executable_path/../Frameworks "$CONTENTS_DIR/MacOS/MeetStage"

if [[ -n "$UPDATE_FEED_URL" || -n "$UPDATE_PUBLIC_KEY" ]]; then
    if [[ -z "$UPDATE_FEED_URL" || -z "$UPDATE_PUBLIC_KEY" ]]; then
        echo "Set both BETTERMEETS_UPDATE_FEED_URL and BETTERMEETS_UPDATE_PUBLIC_KEY." >&2
        exit 64
    fi
    if [[ "$UPDATE_FEED_URL" != https://* ]]; then
        echo "BETTERMEETS_UPDATE_FEED_URL must use HTTPS." >&2
        exit 64
    fi
    /usr/libexec/PlistBuddy -c "Add :SUFeedURL string $UPDATE_FEED_URL" "$CONTENTS_DIR/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $UPDATE_PUBLIC_KEY" "$CONTENTS_DIR/Info.plist"
fi

"$PROJECT_DIR/scripts/extract-app-intents-metadata.sh" \
    "$CONFIGURATION" \
    "$APP_DIR" \
    "$SDK_PATH" \
    "$BUNDLE_IDENTIFIER"

ENTITLEMENTS="$PROJECT_DIR/Resources/BetterMeets.entitlements"
DEVELOPMENT_ENTITLEMENTS="$PROJECT_DIR/Resources/BetterMeetsDevelopment.entitlements"

sign_sparkle_component() {
    local component="$1"
    local signing_target="${SIGNING_IDENTITY:--}"
    local signing_arguments=(
        --force
        --options runtime
        --preserve-metadata=entitlements
        --sign "$signing_target"
    )
    if [[ -n "$SIGNING_IDENTITY" ]]; then
        signing_arguments+=(--timestamp)
    fi
    codesign "${signing_arguments[@]}" "$component"
}

SPARKLE_VERSION_DIR="$SPARKLE_DESTINATION/Versions/Current"
sign_sparkle_component "$SPARKLE_VERSION_DIR/XPCServices/Installer.xpc"
sign_sparkle_component "$SPARKLE_VERSION_DIR/XPCServices/Downloader.xpc"
sign_sparkle_component "$SPARKLE_VERSION_DIR/Autoupdate"
sign_sparkle_component "$SPARKLE_VERSION_DIR/Updater.app"
sign_sparkle_component "$SPARKLE_DESTINATION"

if [[ -n "$SIGNING_IDENTITY" ]]; then
    # Developer ID builds need the hardened runtime and a trusted timestamp
    # before Apple will accept them for notarization. The entitlements grant
    # microphone access (Demo Mode) that the hardened runtime blocks by default.
    codesign \
        --force \
        --options runtime \
        --timestamp \
        --entitlements "$ENTITLEMENTS" \
        --sign "$SIGNING_IDENTITY" \
        "$APP_DIR"
else
    # A stable designated requirement keeps Screen Recording approval valid
    # across local builds even though the ad-hoc binary hash changes. Ad-hoc code
    # has no Developer Team ID, so library validation cannot establish that the
    # embedded Sparkle framework belongs to the app. Disable it only for this
    # local package; Developer ID releases keep library validation enabled.
    codesign \
        --force \
        --options runtime \
        --entitlements "$DEVELOPMENT_ENTITLEMENTS" \
        --sign - \
        --requirements "=designated => identifier \"$BUNDLE_IDENTIFIER\"" \
        "$APP_DIR"
fi

codesign --verify --strict --verbose=2 "$APP_DIR"
codesign --verify --strict --verbose=2 "$SPARKLE_DESTINATION"
