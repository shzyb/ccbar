#!/bin/bash
set -euo pipefail

APP_NAME="CCBar"
EXECUTABLE_NAME="CCBarApp"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$ROOT_DIR/.build/release"
APP_BUNDLE="$ROOT_DIR/$APP_NAME.app"

echo "==> Building $EXECUTABLE_NAME (release)"
swift build -c release --package-path "$ROOT_DIR"

echo "==> Assembling $APP_NAME.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$EXECUTABLE_NAME" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
cp "$ROOT_DIR/Sources/CCBarApp/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

ICON_SOURCE="$ROOT_DIR/Sources/CCBarApp/Resources/AppIcon.png"
if [ -f "$ICON_SOURCE" ]; then
    echo "==> Generating AppIcon.icns"
    ICONSET_DIR="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "$ICONSET_DIR"
    for size in 16 32 128 256 512; do
        sips -z "$size" "$size" "$ICON_SOURCE" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
        double=$((size * 2))
        sips -z "$double" "$double" "$ICON_SOURCE" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    rm -rf "$(dirname "$ICONSET_DIR")"
else
    echo "==> No AppIcon.png found at Sources/CCBarApp/Resources/ — skipping icon (app will use the default generic icon)"
fi

echo "==> Ad-hoc code signing"
codesign --force --deep -s - "$APP_BUNDLE"

echo "==> Done: $APP_BUNDLE"
