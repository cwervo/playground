#!/usr/bin/env bash
# Headless build + install of TuringDoodle onto a physical iOS device.
#
# Usage (run on a Mac with Xcode 15+ and the device paired & in Developer Mode):
#   ./build-and-install.sh              # targets a device named 🍰
#   ./build-and-install.sh "cakeEmoji"  # targets a device by exact name
#   DEVELOPMENT_TEAM=ABCDE12345 ./build-and-install.sh
#   DEVICE_UDID=xxxx ./build-and-install.sh   # skip name lookup entirely
set -euo pipefail
cd "$(dirname "$0")"

DEVICE_NAME="${1:-🍰}"
BUNDLE_ID="com.cwervo.turingdoodle"

if ! command -v xcodebuild >/dev/null; then
  echo "error: xcodebuild not found — run this on a Mac with Xcode installed." >&2
  exit 1
fi

# --- resolve device UDID -------------------------------------------------
if [[ -z "${DEVICE_UDID:-}" ]]; then
  DEVICES_JSON="$(mktemp)"
  xcrun devicectl list devices --json-output "$DEVICES_JSON" >/dev/null
  DEVICE_UDID="$(python3 - "$DEVICE_NAME" "$DEVICES_JSON" <<'PY'
import json, sys
name, path = sys.argv[1], sys.argv[2]
data = json.load(open(path))
for dev in data.get("result", {}).get("devices", []):
    if dev.get("deviceProperties", {}).get("name") == name:
        print(dev["hardwareProperties"]["udid"])
        break
PY
)"
  rm -f "$DEVICES_JSON"
  if [[ -z "$DEVICE_UDID" ]]; then
    echo "error: no connected device named \"$DEVICE_NAME\". Connected devices:" >&2
    xcrun devicectl list devices >&2
    echo "Pass the name as \$1 or set DEVICE_UDID directly." >&2
    exit 1
  fi
fi
echo "→ device \"$DEVICE_NAME\" = $DEVICE_UDID"

# --- build ---------------------------------------------------------------
BUILD_ARGS=(
  -project TuringDoodle.xcodeproj
  -scheme TuringDoodle
  -configuration Debug
  -destination "id=$DEVICE_UDID"
  -derivedDataPath build
  -allowProvisioningUpdates
)
if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
  BUILD_ARGS+=("DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM")
fi
xcodebuild "${BUILD_ARGS[@]}" build

APP="build/Build/Products/Debug-iphoneos/TuringDoodle.app"
[[ -d "$APP" ]] || { echo "error: build product not found at $APP" >&2; exit 1; }

# --- install + launch ----------------------------------------------------
echo "→ installing on $DEVICE_UDID"
xcrun devicectl device install app --device "$DEVICE_UDID" "$APP"
echo "→ launching $BUNDLE_ID"
xcrun devicectl device process launch --device "$DEVICE_UDID" "$BUNDLE_ID"
echo "✓ TuringDoodle is running on \"$DEVICE_NAME\""
