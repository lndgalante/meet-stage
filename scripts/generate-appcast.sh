#!/bin/zsh

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
UPDATES_DIR="${1:-}"
GENERATE_APPCAST="$PROJECT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"

if [[ -z "$UPDATES_DIR" || ! -d "$UPDATES_DIR" ]]; then
    echo "Usage: scripts/generate-appcast.sh <updates-directory>" >&2
    exit 64
fi

if [[ ! -x "$GENERATE_APPCAST" ]]; then
    echo "Resolve Swift packages before generating an appcast: swift package resolve" >&2
    exit 66
fi

"$GENERATE_APPCAST" "$UPDATES_DIR"
