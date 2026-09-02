#!/bin/zsh

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$PROJECT_DIR/dist/BetterMeets.app"
ARCHIVE_PATH="$PROJECT_DIR/dist/BetterMeets.zip"
NOTARY_LOG_PATH="$PROJECT_DIR/dist/BetterMeets-notarization-log.json"
NOTARY_PROFILE="${BETTERMEETS_NOTARY_PROFILE:-}"

create_archive() {
    rm -f "$ARCHIVE_PATH"
    /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ARCHIVE_PATH"
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
set +e
SUBMISSION_RESULT="$(xcrun notarytool submit \
    "$ARCHIVE_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait \
    --output-format plist)"
SUBMISSION_EXIT_STATUS="$?"
set -e
SUBMISSION_ID="$(plutil -extract id raw -o - - <<< "$SUBMISSION_RESULT" 2>/dev/null || true)"
SUBMISSION_STATUS="$(plutil -extract status raw -o - - <<< "$SUBMISSION_RESULT" 2>/dev/null || true)"
if [[ -z "$SUBMISSION_ID" ]]; then
    echo "Notary submission did not return an ID: $SUBMISSION_RESULT" >&2
    if (( SUBMISSION_EXIT_STATUS == 0 )); then
        exit 1
    fi
    exit "$SUBMISSION_EXIT_STATUS"
fi
rm -f "$NOTARY_LOG_PATH"
xcrun notarytool log \
    "$SUBMISSION_ID" \
    "$NOTARY_LOG_PATH" \
    --keychain-profile "$NOTARY_PROFILE"
if (( SUBMISSION_EXIT_STATUS != 0 )); then
    echo "Notary submission command failed. See $NOTARY_LOG_PATH" >&2
    exit "$SUBMISSION_EXIT_STATUS"
fi
if [[ "$SUBMISSION_STATUS" != "Accepted" ]]; then
    echo "Notarization failed with status $SUBMISSION_STATUS. See $NOTARY_LOG_PATH" >&2
    exit 1
fi
xcrun stapler staple "$APP_DIR"
xcrun stapler validate "$APP_DIR"
spctl --assess --type execute --verbose=2 "$APP_DIR"
create_archive

echo "$ARCHIVE_PATH"
echo "$NOTARY_LOG_PATH"
