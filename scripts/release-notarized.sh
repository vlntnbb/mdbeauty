#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="MDbeaty"
CONFIGURATION="${1:-release}"
VERSION="${VERSION:-1.0.0}"
SIGN_IDENTITY="${SIGN_IDENTITY:-${DEVELOPER_ID_APP:-}}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
DIST_DIR="$ROOT_DIR/dist"
APP_PATH="$DIST_DIR/$APP_NAME.app"
RELEASE_DIR="$DIST_DIR/release"
ZIP_PATH="$RELEASE_DIR/$APP_NAME-$VERSION-macOS.zip"

if [[ "$CONFIGURATION" != "release" ]]; then
  echo "Notarized release supports only release build."
  echo "Usage: ./scripts/release-notarized.sh release"
  exit 1
fi

if [[ -z "$SIGN_IDENTITY" ]]; then
  echo "SIGN_IDENTITY is required."
  echo "Example:"
  echo "  SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' NOTARY_PROFILE='mdbeauty-notary' ./scripts/release-notarized.sh"
  exit 1
fi

if [[ -z "$NOTARY_PROFILE" ]]; then
  echo "NOTARY_PROFILE is required (xcrun notarytool keychain profile name)."
  exit 1
fi

if ! command -v xcrun >/dev/null 2>&1; then
  echo "xcrun is required (install Xcode command line tools)."
  exit 1
fi

if ! command -v ditto >/dev/null 2>&1; then
  echo "ditto is required."
  exit 1
fi

echo "Building app bundle (without initial signing)..."
SKIP_CODESIGN=1 "$ROOT_DIR/scripts/build-app.sh" "$CONFIGURATION"

echo "Signing app with Developer ID..."
CODESIGN_ARGS=(--force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY")
if [[ -n "${ENTITLEMENTS_FILE:-}" ]]; then
  CODESIGN_ARGS+=(--entitlements "$ENTITLEMENTS_FILE")
fi
codesign "${CODESIGN_ARGS[@]}" "$APP_PATH"

echo "Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

mkdir -p "$RELEASE_DIR"
rm -f "$ZIP_PATH"

echo "Creating ZIP for notarization..."
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "Submitting ZIP to Apple notarization service..."
xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

echo "Stapling notarization ticket to app..."
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

echo "Repacking ZIP with stapled app..."
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "Release ready:"
echo "  App: $APP_PATH"
echo "  ZIP: $ZIP_PATH"
