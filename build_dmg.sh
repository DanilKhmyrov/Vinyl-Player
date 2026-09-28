#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(tr -d '[:space:]' < VERSION)"
DIST="dist"
DMG="$DIST/Vinyl-$VERSION.dmg"
STAGING="$DIST/staging"

rm -rf "$DIST"
./build_app.sh release --universal --output "$DIST"

echo "==> packaging $DMG"
mkdir -p "$STAGING"
ditto "$DIST/Vinyl.app" "$STAGING/Vinyl.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Vinyl $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG" -quiet
rm -rf "$STAGING"

shasum -a 256 "$DMG" | tee "$DMG.sha256"
echo "==> done: $DMG"
