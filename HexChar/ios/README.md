# HexChar for iOS — CoreGraphics honeycomb

The same keyboard as the web version, as a native iOS app whose entire
keyboard surface is drawn with CoreGraphics: every hexagon, stroke and glyph
is rendered in `HexBoardView.draw(_:)` with a `CGContext` — there are no
per-key views or layers. It bundles the same generated `hexchar-data.json`
the web app uses.

## Build & test — headless, no Xcode IDE

Everything runs from the terminal on macOS with the Xcode toolchain
installed (`xcode-select -p` must point at an Xcode.app; the IDE is never
opened). There is no `.xcodeproj`: the app is compiled with `swiftc`
against the `iphonesimulator` SDK, assembled into an `.app` by hand, and
driven with `xcrun simctl`.

    ./simulate.sh          # build, run tests + perf gate on a simulator,
                           # screenshot, then launch for real
    ./simulate.sh build    # compile the .app only
    ./simulate.sh test     # build + headless tests only

The script picks the first available iPhone simulator (creating one when
none exists), boots it headlessly, installs the app, and launches it with
`simctl launch --console-pty` so the app's stdout is captured.

## Tests

Launching with `-hexchar-selftest -hexchar-perftest` runs in-app checks and
exits 0/1 (see `SelfTest.swift`); `simulate.sh` gates on the output:

- **Correctness**: data decodes and no category is empty; hex hit-testing
  round-trips (the centre of every key resolves to that key, at four board
  widths); corner taps outside a hexagon but inside its bounding box do
  not land on it; backspace deletes one whole grapheme cluster; search
  finds "schwa" and `U+2318`; emoji-default characters are drawn with the
  text-presentation selector.
- **Performance**: every category (plus Recent) is rendered through the
  real `draw(_:)` path at device width — the full board, not just the
  visible part — and the gate fails if any render exceeds **15 ms**
  (best of 3, `HEXCHAR_PERF` lines show per-category timings).

## Why the 15 ms budget holds

The board view is rasterised into its layer's backing store once per
category switch. After that, scrolling and idle frames cost zero draw
calls — the compositor just translates the already-rendered layer — and a
key-press highlight redraws only that key's rect. So the only meaningful
CG work is the one-shot category render, which is exactly what the perf
gate measures, at its worst case (the whole board, largest categories:
178-key search results, the 160-key box-drawing block).

## Fonts

Drop Noto Sans `.ttf`/`.otf` files (e.g. NotoSans-Regular.ttf, and
optionally Noto Sans Symbols 2 / Math / Music) into `ios/Fonts/` and the
build script bundles them; the app registers every bundled font at launch
and prefers Noto Sans for glyphs. With no fonts bundled it falls back to
the system font cascade, which covers everything HexChar ships.

## Files

    Sources/HexData.swift      data model + Unicode helpers + search (pure)
    Sources/HexLayout.swift    honeycomb geometry + hexagonal hit-testing (pure)
    Sources/HexBoardView.swift the CoreGraphics keyboard surface + touch handling
    Sources/CategoryBar.swift  bottom category strip
    Sources/KeyboardViewController.swift  screen assembly, editing, detail card
    Sources/Theme.swift        palette (light/dark) + font registration
    Sources/SelfTest.swift     headless test + perf-gate modes
    Info.plist                 minimal, UILaunchScreen-based (no storyboards)
    simulate.sh                the whole CLI workflow
