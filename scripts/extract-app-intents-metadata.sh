#!/bin/zsh

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-}"
APP_DIR="${2:-}"
SDK_PATH="${3:-}"
BUNDLE_IDENTIFIER="${4:-}"

if [[ -z "$CONFIGURATION" || -z "$APP_DIR" || -z "$SDK_PATH" || -z "$BUNDLE_IDENTIFIER" ]]; then
    echo "Usage: scripts/extract-app-intents-metadata.sh <configuration> <app> <sdk> <bundle-id>" >&2
    exit 64
fi

BETTERMEETS_ARCH="$(uname -m)"
DEPLOYMENT_TARGET="26.0"
TARGET_TRIPLE="$BETTERMEETS_ARCH-apple-macosx$DEPLOYMENT_TARGET"
TOOLCHAIN_DIR="$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain"
XCODE_BUILD_VERSION="$(xcodebuild -version | awk 'NR == 2 { print $3 }')"
WORK_DIR="$PROJECT_DIR/.build/$CONFIGURATION/app-intents"
INTENTS_SOURCE="$PROJECT_DIR/Sources/MeetStage/BetterMeetsIntents.swift"
STUB_SOURCE="$PROJECT_DIR/scripts/AppIntentMetadataStubs.swift"
PROTOCOLS_FILE="$PROJECT_DIR/scripts/app-intents-const-protocols.json"
CONST_VALUES="$WORK_DIR/BetterMeets.swiftconstvalues"
METADATA_OBJECT="$WORK_DIR/BetterMeetsIntents.metadata.o"
SOURCE_LIST="$WORK_DIR/sources.list"
CONST_VALUES_LIST="$WORK_DIR/const-values.list"

mkdir -p "$WORK_DIR"

CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/clang-module-cache" \
SWIFT_MODULECACHE_PATH="$PROJECT_DIR/.build/swiftpm-module-cache" \
swiftc \
    -c \
    -whole-module-optimization \
    -parse-as-library \
    -module-name MeetStage \
    -target "$TARGET_TRIPLE" \
    -sdk "$SDK_PATH" \
    -swift-version 6 \
    -Xfrontend -const-gather-protocols-file \
    -Xfrontend "$PROTOCOLS_FILE" \
    -emit-const-values-path "$CONST_VALUES" \
    "$INTENTS_SOURCE" \
    "$STUB_SOURCE" \
    -o "$METADATA_OBJECT"

printf '%s\n' "$INTENTS_SOURCE" "$STUB_SOURCE" > "$SOURCE_LIST"
printf '%s\n' "$CONST_VALUES" > "$CONST_VALUES_LIST"

xcrun appintentsmetadataprocessor \
    --output "$APP_DIR/Contents/Resources" \
    --toolchain-dir "$TOOLCHAIN_DIR" \
    --module-name MeetStage \
    --sdk-root "$SDK_PATH" \
    --xcode-version "$XCODE_BUILD_VERSION" \
    --platform-family macOS \
    --deployment-target "$DEPLOYMENT_TARGET" \
    --target-triple "$TARGET_TRIPLE" \
    --source-file-list "$SOURCE_LIST" \
    --swift-const-vals-list "$CONST_VALUES_LIST" \
    --binary-file "$APP_DIR/Contents/MacOS/MeetStage" \
    --bundle-identifier "$BUNDLE_IDENTIFIER" \
    --compile-time-extraction \
    --deployment-aware-processing \
    --no-app-shortcuts-localization
