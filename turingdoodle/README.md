# TuringDoodle

A full-screen camera app that turns hand-drawn marks on paper into a running
Turing machine — no build step, no dependencies, just `index.html`.

The entire app — markup, styles, vision pipeline, Turing machine, math
evaluator — lives in that one file with zero external references, so it works
**completely offline**: open it from disk, airdrop it to a friend, or serve it
from anywhere. (For live camera access browsers require a secure context, so
use `https://`, `localhost`, or the iOS app below; the photo-upload button and
manual tape editor work even from a plain `file://` open.)

There's also a native iOS port in [`ios/`](ios/) — a SwiftUI + WKWebView
wrapper that bundles this same `index.html`, with a one-command headless
`xcodebuild` script to install it on your device.

## The idea

Two symbols are all you need:

- a dash **&minus;** means **0**
- a line **|** means **1**

Draw a row of them on a sheet of white paper, scan it, and TuringDoodle reads
your marks left-to-right into an editable **tape**. Draw a tape shaped like
`| | | − | |` — a group of lines, one dash, then another group of lines —
and hit **Run**: the built-in Turing machine finds the dash, flips it to a
line, sweeps to the end, and deletes the last line. What's left is a tape of
unary ones whose length is the sum of the two numbers you drew. It's the
classic unary-addition Turing machine, made out of your own handwriting.

No camera handy, or the lighting's bad? The tape panel's `+ −` / `+ |` / `⌫`
buttons build and edit a tape by hand, and `⤒` lets you scan a photo instead
of a live frame — the whole app works without a working camera.

## Modes

- **Simple** (default) — the 0/1 tape above. Recognized purely by shape
  (wide-and-short vs. tall-and-narrow), no training required.
- **Math** — the alphabet expands to `0-9`, `A-Z`, operators
  `+ - / % ~ * = ^`, and variables written `$` + a letter (e.g. `$A`).
  Draw a short expression in one row (`12+7`, `$A*$B`) and scan it: each
  mark is matched against symbols you've trained, the recognized expression
  is shown as an AR overlay, and it's evaluated live (assign variable values
  in the panel that appears).
- **Custom** — define your own comma-separated alphabet in Settings and
  explore higher-order Turing machines beyond binary, using the same
  train-then-scan workflow as Math mode.

Math and Custom modes need training: open **Settings → Train symbols**,
draw a symbol large on paper, hold it to the camera so it fills most of the
frame, and tap its tile. TuringDoodle remembers a few samples per symbol
(stored in `localStorage`) and matches new scans against them.

## How recognition works

There's no ML model and no network calls — everything runs client-side with
plain canvas pixel math:

1. Grab a frame, downscale it, convert to grayscale.
2. Binarize with Otsu's method (adjustable via the sensitivity slider in
   Settings, for tricky lighting).
3. Flood-fill connected components (8-connectivity) to find ink blobs, then
   merge blobs that sit close together (so multi-stroke symbols like `+`,
   `=`, or `%` count as one symbol).
4. **Simple mode**: classify each blob by aspect ratio (wide → dash/0,
   tall → line/1).
5. **Math/Custom mode**: downsample each blob into a 16×16 grid and match it
   against your trained samples by nearest-neighbor Hamming distance.

Everything is a single scan-on-demand operation (tap the shutter), not a
continuous per-frame video pipeline, so it stays fast and predictable on
any device.

## Files

- `index.html` — the whole app, self-contained: markup, styles, camera
  handling, vision pipeline, Turing machine, and math evaluator inlined
- `ios/` — native iOS wrapper (SwiftUI + WKWebView) with headless CLI
  build-and-install tooling; see [`ios/README.md`](ios/README.md)
