#!/usr/bin/env bash
# HexChar iOS: headless build + test + run on the iOS Simulator.
#
# No Xcode IDE, no .xcodeproj: the app is compiled with swiftc against the
# iphonesimulator SDK, assembled into an .app by hand, and driven entirely
# through `xcrun simctl`. Requires macOS with Xcode's toolchain installed
# (`xcode-select -p` should point at Xcode.app or a CommandLineTools with an
# iOS simulator runtime); Xcode itself is never opened.
#
#   ./simulate.sh          build, run self-test + perf gate, screenshot, launch
#   ./simulate.sh build    build only
#   ./simulate.sh test     build + headless tests only
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-all}"
BUNDLE_ID=com.cwervo.hexchar
MIN_IOS=15.0
BUILD=build
APP="$BUILD/HexChar.app"

if ! command -v xcrun >/dev/null; then
  echo "error: xcrun not found — this script needs macOS with the Xcode toolchain." >&2
  exit 1
fi

# ---------- build ----------
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
case "$(uname -m)" in
  arm64) TARGET="arm64-apple-ios${MIN_IOS}-simulator" ;;
  *)     TARGET="x86_64-apple-ios${MIN_IOS}-simulator" ;;
esac

echo "== compiling (swiftc, $TARGET)"
rm -rf "$APP"
mkdir -p "$APP"
xcrun -sdk iphonesimulator swiftc -O \
  -target "$TARGET" \
  -o "$APP/HexChar" \
  Sources/*.swift

cp Info.plist "$APP/Info.plist"
cp ../hexchar-data.json "$APP/hexchar-data.json"
# Optional: drop Noto Sans (and friends) .ttf/.otf files into ios/Fonts/ and
# they get bundled + registered at launch; without them the app uses the
# system font cascade, which covers every character HexChar ships.
find Fonts -maxdepth 1 \( -name '*.ttf' -o -name '*.otf' \) -exec cp {} "$APP/" \; 2>/dev/null || true

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "== built $APP"
[ "$MODE" = build ] && exit 0

# ---------- simulator ----------
UDID=$(xcrun simctl list devices available | grep -E '^\s+iPhone' \
       | grep -oE '[0-9A-F]{8}-[0-9A-F-]{27}' | head -1 || true)
if [ -z "$UDID" ]; then
  echo "== no available iPhone simulator; creating one"
  DEVTYPE=$(xcrun simctl list devicetypes | grep -E 'iPhone' \
            | grep -oE 'com\.apple\.CoreSimulator\.SimDeviceType\.[^)]*' | tail -1)
  RUNTIME=$(xcrun simctl list runtimes | grep -E '^iOS' \
            | grep -oE 'com\.apple\.CoreSimulator\.SimRuntime\.[^)]*' | tail -1)
  UDID=$(xcrun simctl create HexCharTest "$DEVTYPE" "$RUNTIME")
fi
echo "== simulator $UDID"
xcrun simctl bootstatus "$UDID" -b
xcrun simctl install "$UDID" "$APP"

# ---------- headless tests: correctness + the <15 ms draw budget ----------
echo "== running self-test + perf gate"
LOG="$BUILD/test-output.txt"
set +e
xcrun simctl launch --console-pty --terminate-running-process "$UDID" "$BUNDLE_ID" \
  -hexchar-selftest -hexchar-perftest | tee "$LOG"
set -e
if ! grep -q '^HEXCHAR_RESULT: PASS' "$LOG"; then
  echo "== FAILED — see $LOG" >&2
  exit 1
fi
grep '^HEXCHAR_PERF_RESULT' "$LOG"
[ "$MODE" = test ] && { echo "== tests passed"; exit 0; }

# ---------- interactive launch + screenshot ----------
echo "== launching for real"
xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE_ID"
sleep 3
xcrun simctl io "$UDID" screenshot "$BUILD/hexchar-sim.png"
echo "== screenshot: $BUILD/hexchar-sim.png"
echo "== done — open Simulator.app to interact, or leave it headless"
