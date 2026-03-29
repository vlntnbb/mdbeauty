#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${APP_NAME:-MDbeaty}"
VERSION="${VERSION:-1.0.0}"
CONFIGURATION="${1:-release}"
SKIP_BUILD="${SKIP_BUILD:-0}"
DIST_DIR="$ROOT_DIR/dist"
APP_PATH="$DIST_DIR/$APP_NAME.app"
RELEASE_DIR="$DIST_DIR/release"
DMG_PATH="$RELEASE_DIR/$APP_NAME-$VERSION-unsigned.dmg"
VOLUME_NAME="$APP_NAME"

if [[ "$CONFIGURATION" != "release" && "$CONFIGURATION" != "debug" ]]; then
  echo "Unsupported configuration: $CONFIGURATION"
  echo "Usage: ./scripts/make-dmg.sh [release|debug]"
  exit 1
fi

if ! command -v hdiutil >/dev/null 2>&1; then
  echo "hdiutil is required on macOS."
  exit 1
fi

if [[ "$SKIP_BUILD" != "1" ]]; then
  echo "Building app bundle..."
  "$ROOT_DIR/scripts/build-app.sh" "$CONFIGURATION"
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH"
  echo "Build it first with ./scripts/build-app.sh $CONFIGURATION"
  exit 1
fi

mkdir -p "$RELEASE_DIR"
rm -f "$DMG_PATH"

STAGING_DIR="$(mktemp -d "/tmp/${APP_NAME}-dmg-staging.XXXXXX")"
cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

echo "Creating DMG..."
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

echo "Unsigned DMG created:"
echo "$DMG_PATH"
