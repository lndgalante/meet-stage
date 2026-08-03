#!/bin/zsh

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$PROJECT_DIR/dist/Meet Stage.app"
CONTENTS_DIR="$APP_DIR/Contents"
SDK_PATH="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"

if [[ ! -d "$SDK_PATH" ]]; then
    SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
fi

cd "$PROJECT_DIR"
mkdir -p \
    "$PROJECT_DIR/.build/clang-module-cache" \
    "$PROJECT_DIR/.build/swiftpm-module-cache" \
    "$PROJECT_DIR/.build/swiftpm-cache"

SDKROOT="$SDK_PATH" \
CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/clang-module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_DIR/.build/swiftpm-module-cache" \
XDG_CACHE_HOME="$PROJECT_DIR/.build/swiftpm-cache" \
swift build --disable-sandbox -c release

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
cp "$PROJECT_DIR/.build/release/MeetStage" "$CONTENTS_DIR/MacOS/MeetStage"
cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"

codesign --force --deep --sign - "$APP_DIR"

echo "$APP_DIR"
