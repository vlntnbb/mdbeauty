#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-$ROOT_DIR/dist/MDbeaty.app}"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found: $APP_PATH"
  echo "Build it first: ./scripts/build-app.sh"
  exit 1
fi

if [[ ! -x "$LSREGISTER" ]]; then
  echo "lsregister tool is unavailable on this macOS installation."
  exit 1
fi

"$LSREGISTER" -f "$APP_PATH"

echo "Registered in LaunchServices:"
echo "$APP_PATH"
echo
echo "To set as the default app for .md globally, use Finder:"
echo "Get Info on any .md file -> Open with -> MDbeaty -> Change All..."
