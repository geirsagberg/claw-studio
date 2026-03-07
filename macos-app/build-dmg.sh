#!/usr/bin/env bash
# Creates a distributable Claw Studio.dmg
# Run from the macos-app/ directory: bash build-dmg.sh

set -euo pipefail

APP_NAME="Claw Studio"
DMG_NAME="Claw Studio Installer"
OUT_DIR="$(pwd)/dist"
STAGING="$(mktemp -d)"

echo "Building $APP_NAME.dmg..."

mkdir -p "$OUT_DIR"

# Copy the .app into staging
cp -R "$APP_NAME.app" "$STAGING/"

# Create a symlink to /Applications for easy drag-install feel
ln -s /Applications "$STAGING/Applications"

# Create the DMG
hdiutil create \
  -volname "$DMG_NAME" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  "$OUT_DIR/$APP_NAME.dmg"

rm -rf "$STAGING"

echo "Done: $OUT_DIR/$APP_NAME.dmg"
