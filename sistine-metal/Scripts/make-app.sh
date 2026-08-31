#!/bin/bash
# TCC attributes camera + accessibility permission to a bundle identity, not to a
# loose binary, so wrap the SwiftPM product in a minimal .app before granting them.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP=Sistine.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp App/Info.plist "$APP/Contents/Info.plist"
cp "$(swift build -c release --show-bin-path)/Sistine" "$APP/Contents/MacOS/Sistine"
BUNDLE="$(swift build -c release --show-bin-path)/Sistine_Sistine.bundle"
[ -d "$BUNDLE" ] && cp -R "$BUNDLE" "$APP/Contents/Resources/"
[ -f .build/default.metallib ] && cp .build/default.metallib "$APP/Contents/Resources/"
codesign --force --deep --sign - "$APP"
echo "built $APP — open it once, then grant Camera and Accessibility in System Settings"
