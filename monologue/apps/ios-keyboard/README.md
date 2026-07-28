# iOS/iPadOS custom keyboard + notes-loop app

Two targets sharing one App Group, not one app — a keyboard extension has
different constraints than a long-running transcription session does.

## Custom keyboard extension

- Needs **"Allow Full Access"** turned on by the user — a keyboard
  extension is network-sandboxed by default, and Full Access is the only
  way to let it talk to the Pi hub over the private WLAN link at all. Say
  this plainly in onboarding; it's a real permission with real
  implications the user should understand, not a checkbox to bury.
- Discovers the hub via Bonjour on the local network, connects over the
  same mTLS socket the macOS daemon uses (one hub protocol, multiple
  clients — keep it that way rather than forking a second protocol for
  iOS).
- On receiving transcript text, inserts it at the cursor via
  `UIInputViewController`'s `textDocumentProxy.insertText(_:)` — this is
  the standard, and only, text-injection path a keyboard extension has.
- Keyboard extensions are memory-constrained and expected to be
  short-lived per keystroke — **not** the right place to hold a
  long-running BLE/audio pipeline. It should be a thin network client
  only; all sensing/streaming/ASN happens upstream at the node and hub.

## Notes-loop app (separate target)

- A normal foreground/background app, for the "full-notes-loop"
  continuous-transcription use case the keyboard extension isn't built
  for.
- Same hub connection, but instead of `textDocumentProxy` it appends
  incoming (text, audio-clip, timestamp) tuples to a local transcript
  store — mirrors the macOS daemon's notes-loop mode, sharing format via
  the App Group container so a transcript started on iPad can continue on
  Mac.
- Background execution needs a real strategy (`BGProcessingTask` /
  `BGAppRefreshTask`, or just accept foreground-only for the phase-7
  alpha) — don't assume iOS will let a background app hold an open socket
  indefinitely without one.

## Why this is a README and not a stub Xcode project

Building either target needs an actual Apple Developer account (App Group
entitlement, keyboard extension's Full Access entitlement), an Xcode
toolchain, and a device/simulator to run against — none of which exist in
this environment. A half-built `.xcodeproj` with unbuildable Swift files
would look more finished than it is; the real phase-7 starting point is a
fresh Xcode project with an App Group and a keyboard-extension target,
built against whatever the phase-2 hub protocol looks like once it's
settled on real hardware.
