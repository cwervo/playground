#!/bin/bash
# Build SendToFolk.app — run this on a Mac (requires Xcode command line tools).
set -euo pipefail
cd "$(dirname "$0")"

APP=build/SendToFolk.app

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Compiling…"
swiftc -O -o "$APP/Contents/MacOS/SendToFolk" Sources/SendToFolk/main.swift

cp Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Ad-hoc sign so macOS will register the app's Services entry.
codesign --force --sign - "$APP"

echo
echo "Built $APP"
echo
echo "To install:"
echo "  cp -R $APP /Applications/"
echo "  open /Applications/SendToFolk.app"
echo
echo "If 'Send To Folk' doesn't appear in the Services menu right away:"
echo "  /System/Library/CoreServices/pbs -update"
echo "  (or log out and back in)"
