#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

CONFIG=release
UNIVERSAL=0
OUT="."

while [ $# -gt 0 ]; do
    case "$1" in
        debug|release) CONFIG="$1" ;;
        --universal) UNIVERSAL=1 ;;
        --output) OUT="$2"; shift ;;
        *) echo "usage: $0 [debug|release] [--universal] [--output DIR]" >&2; exit 64 ;;
    esac
    shift
done

VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
APP="$OUT/Vinyl.app"

SWIFT_FLAGS=(-c "$CONFIG")
if [ "$UNIVERSAL" = 1 ]; then
    SWIFT_FLAGS+=(--arch arm64 --arch x86_64)
fi

echo "==> building Vinyl $VERSION ($CONFIG)"
swift build "${SWIFT_FLAGS[@]}"
BIN_DIR="$(swift build "${SWIFT_FLAGS[@]}" --show-bin-path)"

echo "==> assembling $APP"
mkdir -p "$OUT"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Vinyl" "$APP/Contents/MacOS/Vinyl"
cp "$BIN_DIR/libNowPlayingBridge.dylib" "$APP/Contents/Resources/"
cp Vinyl.icns "$APP/Contents/Resources/"
ditto Resources/Sounds "$APP/Contents/Resources/Sounds"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Info.plist > "$APP/Contents/Info.plist"

echo "==> signing (ad-hoc)"
codesign --force --sign - "$APP/Contents/Resources/libNowPlayingBridge.dylib"
codesign --force --sign - "$APP"

echo "==> done: $APP"
