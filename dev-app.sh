#!/bin/zsh

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$PROJECT_DIR/dist/BetterMeets.app"
SHOULD_LAUNCH=true

if [[ "${1:-}" == "--no-launch" ]]; then
    SHOULD_LAUNCH=false
elif [[ $# -gt 0 ]]; then
    echo "Usage: ./dev-app.sh [--no-launch]" >&2
    exit 64
fi

/bin/zsh "$PROJECT_DIR/scripts/build-and-package.sh" debug

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
            echo "BetterMeets is still running. Quit it, then run ./dev-app.sh again." >&2
            exit 1
        fi
    fi

    /usr/bin/open -n "$APP_DIR"
    echo "Built and launched $APP_DIR"
else
    echo "Built $APP_DIR"
fi
