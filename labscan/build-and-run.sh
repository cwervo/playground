#!/usr/bin/env bash
# Build LabScan from the CLI and install + launch it on a connected iPhone.
#
#   ./build-and-run.sh              # targets the first device whose name contains 🍰
#   ./build-and-run.sh "My iPhone"  # or any name substring
#
# Optional: DEVELOPMENT_TEAM=ABCDE12345 ./build-and-run.sh
#   (only needed if xcodebuild can't pick a signing team on its own;
#    find yours in Xcode > Settings > Accounts, or keychain "Apple Development" certs)
#
# First-time device notes:
#  - Developer Mode must be on: Settings > Privacy & Security > Developer Mode
#  - After the first install with a personal team, trust the cert:
#    Settings > General > VPN & Device Management
set -euo pipefail
cd "$(dirname "$0")"

QUERY="${1:-🍰}"
BUNDLE_ID="com.cwervo.LabScan"

# 1. Generate the Xcode project.
if ! command -v xcodegen >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    echo "==> Installing xcodegen via Homebrew…"
    brew install xcodegen
  else
    echo "error: xcodegen not found. Install with: brew install xcodegen" >&2
    exit 1
  fi
fi
echo "==> Generating LabScan.xcodeproj"
xcodegen generate

# 2. Find the device.
echo "==> Looking for a device matching: $QUERY"
DEVICES_JSON="$(mktemp)"
xcrun devicectl list devices --json-output "$DEVICES_JSON" >/dev/null
read -r DEVICE_ID DEVICE_NAME < <(python3 - "$DEVICES_JSON" "$QUERY" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
query = sys.argv[2].lower()
for d in data.get("result", {}).get("devices", []):
    props = d.get("deviceProperties", {})
    name = props.get("name", "")
    if query in name.lower():
        print(d.get("identifier", ""), name)
        break
else:
    sys.exit(f"no connected/paired device matching {query!r}")
PY
)
echo "    Found: $DEVICE_NAME ($DEVICE_ID)"

# 3. Build for the device.
echo "==> Building (this signs with your Xcode account; -allowProvisioningUpdates)"
TEAM_ARGS=()
if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
  TEAM_ARGS=(DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" CODE_SIGN_STYLE=Automatic)
fi
xcodebuild \
  -project LabScan.xcodeproj \
  -scheme LabScan \
  -configuration Debug \
  -destination "platform=iOS,name=$DEVICE_NAME" \
  -derivedDataPath build \
  -allowProvisioningUpdates \
  "${TEAM_ARGS[@]}" \
  build

APP="build/Build/Products/Debug-iphoneos/LabScan.app"
[[ -d "$APP" ]] || { echo "error: build product not found at $APP" >&2; exit 1; }

# 4. Install + launch. (Phone must be unlocked.)
echo "==> Installing on $DEVICE_NAME"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP"
echo "==> Launching $BUNDLE_ID"
xcrun devicectl device process launch --device "$DEVICE_ID" --activate "$BUNDLE_ID" || {
  echo "Launch failed — if this is the first install, trust the developer cert in"
  echo "Settings > General > VPN & Device Management, then tap the LabScan icon."
}
echo "==> Done."
