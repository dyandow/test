#!/usr/bin/env bash
# Builds WinterDesk.app (and a zip of it) into ./build
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/WinterDesk"

APP="build/WinterDesk.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/WinterDesk"
cp Info.plist "$APP/Contents/Info.plist"
# Painted backgrounds (and where their lights/smoke/fire go)
cp Resources/bg-*.jpg Resources/bg-*.json "$APP/Contents/Resources/"
codesign --force --sign - "$APP"

rm -f build/WinterDesk.zip
ditto -c -k --keepParent "$APP" build/WinterDesk.zip
echo "Built $APP"
