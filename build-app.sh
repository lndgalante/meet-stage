#!/bin/zsh

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$PROJECT_DIR/dist/BetterDemos.app"

/bin/zsh "$PROJECT_DIR/scripts/build-and-package.sh" release

echo "$APP_DIR"
