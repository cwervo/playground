# TuringDoodle — iOS port

A thin native SwiftUI wrapper: a full-screen `WKWebView` that bundles the
single-file `../index.html` (the Xcode project references it directly from the
parent directory, so there's exactly one copy of the app — edit the HTML and
rebuild). Camera access works because `file://` URLs are secure contexts in
WebKit; the wrapper grants WebKit's media-capture prompt automatically and the
OS-level camera permission (with a proper usage string) gates access instead.

Everything runs on-device and offline — no network access at all.

## Requirements

- macOS with **Xcode 15+** (command-line builds use `xcodebuild` + `xcrun devicectl`)
- iPhone/iPad on **iOS 16+**, paired with the Mac, **Developer Mode** enabled
  (Settings → Privacy & Security → Developer Mode)
- An Apple ID signing team (free personal team works)

## One-command headless build + install

```sh
cd turingdoodle/ios
./build-and-install.sh "cakeEmoji"          # exact device name as it appears in Finder
# or, if your phone is literally named with the cake emoji:
./build-and-install.sh                      # defaults to 🍰
```

The script resolves the device UDID via `devicectl`, builds Debug for that
device, installs, and launches the app. If signing complains, pass your team:

```sh
DEVELOPMENT_TEAM=YOURTEAMID ./build-and-install.sh "cakeEmoji"
```

(Find your team ID in Xcode → Settings → Accounts, or in any working
project's Signing pane.)

## Manual steps, if you prefer

```sh
xcrun devicectl list devices    # find your device's name/UDID

xcodebuild -project TuringDoodle.xcodeproj -scheme TuringDoodle \
  -configuration Debug -destination 'platform=iOS,name=cakeEmoji' \
  -derivedDataPath build -allowProvisioningUpdates build

xcrun devicectl device install app --device <UDID> \
  build/Build/Products/Debug-iphoneos/TuringDoodle.app
xcrun devicectl device process launch --device <UDID> com.cwervo.turingdoodle
```

First launch on a free provisioning profile: trust the developer cert under
Settings → General → VPN & Device Management.

## Files

- `TuringDoodle/TuringDoodleApp.swift` — SwiftUI entry point
- `TuringDoodle/WebView.swift` — WKWebView host (inline media, camera grant)
- `TuringDoodle/Info.plist` — camera usage string, orientations, launch screen
- `TuringDoodle.xcodeproj` — bundles `../index.html` as the app's only resource
- `build-and-install.sh` — headless build → install → launch
