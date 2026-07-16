#!/bin/bash
# Headless build for SplitCam — no Xcode GUI, just swiftc + codesign.
#
#   ./build.sh            build macOS app  → build/macos/SplitCam.app
#   ./build.sh ios        build iOS app    → build/ios/SplitCam.app
#                         (requires a code-signing identity + provisioning
#                          profile; see comments in the ios branch)
set -euo pipefail
cd "$(dirname "$0")"

APP=SplitCam

# Per-build identity icon: a fresh OKLAB metaball mesh, seeded by build time.
mkdir -p build
clang -O2 -fobjc-arc meshicon.m -o build/meshicon \
  -framework Foundation -framework CoreGraphics -framework ImageIO
build/meshicon build/icon.png

if [[ "${1:-macos}" == "ios" ]]; then
  OUT="build/ios/$APP.app"
  SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
  mkdir -p "$OUT"
  cp Info-ios.plist "$OUT/Info.plist"
  sips -z 120 120 build/icon.png --out "$OUT/AppIcon60x60@2x.png" >/dev/null
  sips -z 180 180 build/icon.png --out "$OUT/AppIcon60x60@3x.png" >/dev/null
  if [ -d media ]; then mkdir -p "$OUT/Media" && cp media/* "$OUT/Media/"; fi
  SDKROOT="$SDK" xcrun --sdk iphoneos swiftc -O -parse-as-library \
    -target arm64-apple-ios17.0 -sdk "$SDK" \
    SplitCam.swift -o "$OUT/$APP"
  echo "Built $OUT (unsigned)."
  echo "Sign with:   codesign -f -s 'Apple Development: …' --entitlements ent.plist '$OUT'"
  echo "Install with: xcrun devicectl device install app --device <name-or-udid> '$OUT'"
else
  OUT="build/macos/$APP.app"
  mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
  cp Info-macos.plist "$OUT/Contents/Info.plist"
  sips -z 512 512 build/icon.png --out build/icon512.png >/dev/null
  sips -s format icns build/icon512.png --out "$OUT/Contents/Resources/AppIcon.icns" \
    >/dev/null 2>&1 || echo "icns conversion failed (non-fatal)"
  if [ -d media ]; then mkdir -p "$OUT/Contents/Resources/Media" && cp media/* "$OUT/Contents/Resources/Media/"; fi
  swiftc -O -parse-as-library \
    -target arm64-apple-macos14.0 \
    SplitCam.swift -o "$OUT/Contents/MacOS/$APP"
  codesign --force --sign - "$OUT"
  echo "Built $OUT — run with: open $OUT"
fi
