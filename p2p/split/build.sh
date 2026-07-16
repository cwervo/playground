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
# Versioned installs: every build ships as its own app (SplitCam v17, …)
# so versions can be compared side by side on the device.
VER=$(sed -n 's/^let buildTag = "\(v[0-9]*\).*/\1/p' SplitCam.swift)
BUNDLE_ID="com.cwervo.splitcam.$VER"
TEAM_ID="5453PC4UHN"
SIGN_ID="Apple Development: Andres Cuervo (SSXLVBK7F6)"
PROFILE="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/03e9bc1d-4957-4a89-a702-01303be95a0c.mobileprovision"

# Per-build identity icon: a fresh OKLAB metaball mesh, seeded by build time.
mkdir -p build
clang -O2 -fobjc-arc meshicon.m -o build/meshicon \
  -framework Foundation -framework CoreGraphics -framework ImageIO
build/meshicon build/icon.png

brand_plist() { # <plist path>
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$1"
  /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName SplitCam $VER" "$1"
  /usr/libexec/PlistBuddy -c "Set :CFBundleName SplitCam $VER" "$1"
}

if [[ "${1:-macos}" == "ios" ]]; then
  OUT="build/ios/$APP.app"
  SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
  mkdir -p "$OUT"
  cp Info-ios.plist "$OUT/Info.plist"
  brand_plist "$OUT/Info.plist"
  sips -z 120 120 build/icon.png --out "$OUT/AppIcon60x60@2x.png" >/dev/null
  sips -z 180 180 build/icon.png --out "$OUT/AppIcon60x60@3x.png" >/dev/null
  if [ -d media ]; then mkdir -p "$OUT/Media" && cp media/* "$OUT/Media/"; fi
  SDKROOT="$SDK" xcrun --sdk iphoneos swiftc -O -parse-as-library \
    -target arm64-apple-ios17.0 -sdk "$SDK" \
    SplitCam.swift -o "$OUT/$APP"
  echo "Built $OUT as $BUNDLE_ID (unsigned)."

  if [[ "${2:-}" == "deploy" ]]; then
    cat > build/ent.plist <<ENT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>application-identifier</key>
	<string>$TEAM_ID.$BUNDLE_ID</string>
	<key>com.apple.developer.team-identifier</key>
	<string>$TEAM_ID</string>
	<key>get-task-allow</key>
	<true/>
	<key>keychain-access-groups</key>
	<array>
		<string>$TEAM_ID.$BUNDLE_ID</string>
	</array>
</dict>
</plist>
ENT
    cp "$PROFILE" "$OUT/embedded.mobileprovision"
    codesign -f -s "$SIGN_ID" --entitlements build/ent.plist "$OUT"
    for attempt in 1 2 3 4 5 6; do
      result=$(xcrun devicectl device install app --device cakeEmoji "$OUT" 2>&1) || true
      if echo "$result" | grep -q 'App installed'; then
        echo "Installed SplitCam $VER on attempt $attempt"
        exit 0
      fi
      echo "install attempt $attempt: $(echo "$result" | grep -m1 ERROR)"
      sleep 15
    done
    echo "Install failed after 6 attempts"
    exit 1
  fi
else
  OUT="build/macos/$APP.app"
  mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
  cp Info-macos.plist "$OUT/Contents/Info.plist"
  brand_plist "$OUT/Contents/Info.plist"
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
