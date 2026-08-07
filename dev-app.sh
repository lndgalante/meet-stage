#!/bin/zsh

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$PROJECT_DIR/dist/BetterDemos.app"
CONTENTS_DIR="$APP_DIR/Contents"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
SHOULD_LAUNCH=true

if [[ "${1:-}" == "--no-launch" ]]; then
    SHOULD_LAUNCH=false
elif [[ $# -gt 0 ]]; then
    echo "Usage: ./dev-app.sh [--no-launch]" >&2
    exit 64
fi

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
    -c debug

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
cp "$PROJECT_DIR/.build/debug/MeetStage" "$CONTENTS_DIR/MacOS/MeetStage"
cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$PROJECT_DIR/Resources/BetterDemos.icns" "$CONTENTS_DIR/Resources/BetterDemos.icns"

# Match release builds so Screen Recording approval and pinned shortcuts keep
# working while you alternate between development and release bundles.
codesign \
    --force \
    --deep \
    --sign - \
    --requirements '=designated => identifier "dev.poc.meetstage.v2"' \
    "$APP_DIR"

if [[ "$SHOULD_LAUNCH" == true ]]; then
    if /usr/bin/pgrep -x MeetStage >/dev/null; then
        /usr/bin/pkill -TERM -x MeetStage

        for _ in {1..20}; do
            if ! /usr/bin/pgrep -x MeetStage >/dev/null; then
                break
            fi
            sleep 0.1
        done

        if /usr/bin/pgrep -x MeetStage >/dev/null; then
            echo "BetterDemos is still running. Quit it, then run ./dev-app.sh again." >&2
            exit 1
        fi
    fi

    /usr/bin/open -n "$APP_DIR"
    echo "Built and launched $APP_DIR"
else
    echo "Built $APP_DIR"
fi
