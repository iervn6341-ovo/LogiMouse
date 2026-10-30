#!/usr/bin/env bash
# Builds a universal LogiMouse.app (arm64 + x86_64) into build/ and zips it.
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
APP="build/LogiMouse.app"

swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/LogiMouse" "$APP/Contents/MacOS/LogiMouse"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" Resources/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# App icon drawn by scripts/make-icon.swift.
if swift scripts/make-icon.swift build/AppIcon.iconset; then
    iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
fi

# "-" means ad-hoc signing. Pass SIGN_IDENTITY="Developer ID Application: …" to sign for distribution.
codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" "$APP"

(cd build && rm -f LogiMouse.zip && ditto -c -k --keepParent LogiMouse.app LogiMouse.zip)
echo "Built $APP and build/LogiMouse.zip"
