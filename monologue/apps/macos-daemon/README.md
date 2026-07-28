# macOS daemon

A `LaunchAgent` that receives transcript text/audio from the Pi Zero hub
over the private WLAN link and either types it into the focused app or
appends it to a running transcript log ("full-notes-loop" mode).

## Responsibilities

1. Connect to the hub's mTLS socket (client side of `architecture.md`'s
   WLAN transport), reconnecting on hub discovery via Bonjour so the
   wearer doesn't have to hand-configure an IP each session.
2. Two operating modes, switchable from a menu-bar item:
   - **Dictation mode**: incoming text goes to the focused text field via
     synthetic keystrokes (`CGEvent` keyboard events) — works in any app,
     no per-app integration needed.
   - **Notes-loop mode**: incoming text/audio is appended to a running,
     timestamped transcript file instead of being typed anywhere,
     alongside the audio clip it came from (for later correction —
     phase-1/7 ASR won't be perfect, keep the audio to re-check against).
3. Local ASR fallback: if the Pi hub isn't running transcription itself
   (see `gateway/pi_zero/monologue_gateway.py`'s `Transcriber` stub), the
   daemon can run it on-device instead (Apple's `Speech` framework, or a
   local whisper.cpp/WhisperKit build) — decide per phase-7 once the Pi
   Zero 2's actual spare compute is measured against battery/thermal
   budget in the field.

## Why a `CGEvent` skeleton and not a finished daemon here

Nothing in this repo can build or run a signed LaunchAgent — no Xcode
toolchain, no macOS runtime, no signing identity. Sketching a plausible-
looking `main.swift` here would just be dead code nobody can compile-check.
The real starting point for phase 7 is a fresh `swift package init
--type executable`, an `NSXPCConnection`-or-plain-socket client against
whatever the phase-2 mTLS server ends up looking like, and:

```swift
// dictation-mode text injection, once a transcript string arrives:
func typeText(_ text: String) {
    for scalar in text.unicodeScalars {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
        event?.keyboardSetUnicodeString(stringLength: 1, unicodeString: [UniChar(scalar.value)])
        event?.post(tap: .cghidEventTap)
    }
}
```

— i.e. build it against a real Mac once the phase-2 hub protocol is
settled, not sketched blind here.
