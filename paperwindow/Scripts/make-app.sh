#!/usr/bin/env bash
# Build paperwindow and wrap it in a .app bundle.
#
# macOS hands out Screen Recording and Accessibility permissions per
# application, and a bare command line binary inherits whatever the terminal
# was granted. A real bundle with a stable identifier gets its own entry in
# System Settings, which is much less confusing.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="PaperWindow"
BUNDLE_ID="net.playground.paperwindow"
APP_DIR="build/${APP_NAME}.app"

echo "building release binary…"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$(swift build -c release --show-bin-path)/PaperWindow" "$APP_DIR/Contents/MacOS/${APP_NAME}"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature. Note that this changes on every rebuild, so macOS may ask
# for the permissions again after a rebuild; sign with a real identity
# (codesign -s "Developer ID Application: …") if that gets annoying.
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP_DIR" >/dev/null

echo "built $APP_DIR"
echo
echo "run it with:"
echo "  open -a \"\$PWD/$APP_DIR\"                 # picker"
echo "  \"$APP_DIR/Contents/MacOS/${APP_NAME}\" --list"
