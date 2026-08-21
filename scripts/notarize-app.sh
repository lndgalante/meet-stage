#!/bin/zsh

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$PROJECT_DIR/dist/BetterMeets.app"
ARCHIVE_PATH="$PROJECT_DIR/dist/BetterMeets.zip"
NOTARY_PROFILE="${BETTERMEETS_NOTARY_PROFILE:-}"

create_archive() {
    rm -f "$ARCHIVE_PATH"
    /usr/bin/ditto -c -k --keepParent "$APP_DIR" "$ARCHIVE_PATH"
}

if [[ -z "$NOTARY_PROFILE" ]]; then
    echo "Set BETTERMEETS_NOTARY_PROFILE to a notarytool Keychain profile." >&2
    exit 64
fi

if [[ ! -d "$APP_DIR" ]]; then
    echo "Build a Developer ID release before notarizing: $APP_DIR" >&2
    exit 66
fi

SIGNING_INFO="$(codesign --display --verbose=4 "$APP_DIR" 2>&1)"
if [[ "$SIGNING_INFO" == *"Signature=adhoc"* ]]; then
    echo "The app is ad-hoc signed. Set BETTERMEETS_CODESIGN_IDENTITY and rebuild." >&2
    exit 65
fi

codesign --verify --strict --verbose=2 "$APP_DIR"
create_archive
xcrun notarytool submit \
    "$ARCHIVE_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
xcrun stapler staple "$APP_DIR"
xcrun stapler validate "$APP_DIR"
spctl --assess --type execute --verbose=2 "$APP_DIR"
create_archive

echo "$ARCHIVE_PATH"
