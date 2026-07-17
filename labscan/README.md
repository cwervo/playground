# LabScan — a CIELAB red-line document scanner

A small, dependable, **network-last** iOS camera tool:

- A fixed **80 pt tall, full-width red "binarization bar"** sweeps the live
  camera feed, exactly like the read-line of a handheld red-laser or
  white-light wand scanner. Every frame, the pixels under the bar are
  converted to **CIELAB** and collapsed into a 1-D reflectance scanline
  (the "red laser" signal is literally the linear red channel mapped through
  the CIE L\* curve — what a 650 nm laser would see). The scanline is
  adaptively binarized, run-length encoded, and decoded with classic
  old-school 1-D tricks: **EAN-13 / UPC-A** (module-normalized digit
  matching) and **Code 39** (wide/narrow) decoders written in plain Swift.
- The full frame is watched with **traditional Apple CV** —
  `VNDetectRectanglesRequest` (classic edge/quad detection, not a neural
  net) — and every quad is classified in CIELAB by lightness + chroma into
  **paper** or **sticky note** (with a hue name), then outlined live.
- A live oscilloscope of the scanline + its binarization is drawn under the
  bar, so you can *see* what the "laser" sees.

## Offline / local guarantees

- No networking code at all. No SDKs, no analytics, no downloads. Works in
  airplane mode from first launch onward.
- All Vision requests used here run entirely on-device.
- Captures are saved as JPEG + JSON sidecar in the app's local
  `Documents/Scans/` — never touched by iCloud sync (marked
  `isExcludedFromBackup`), never uploaded.

## Building

The project is described with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
cd labscan
xcodegen generate     # produces LabScan.xcodeproj
open LabScan.xcodeproj
```

No XcodeGen? Make a new empty iOS App project named `LabScan` in Xcode
(SwiftUI, iOS 17+), delete its generated sources, and drag the `LabScan/`
folder in. The only Info.plist key you need is
`NSCameraUsageDescription` (see `project.yml`).

Requires a real device (camera). iOS 17+.

## How the 1-D decode works (the old-school part)

1. Average the bar's rows column-by-column → one scanline per frame.
2. Signal = L\*(linear R) — red-laser reflectance in CIELAB lightness.
3. Adaptive threshold: moving mean over a window ≈ width/16, with
   hysteresis so noise near the threshold doesn't chatter.
4. Run-length encode into alternating bar/space widths.
5. EAN/UPC: slide over runs looking for guard `1-1-1`; normalize each
   digit's 4 runs to 7 modules; nearest-pattern match with parity tables
   (L/G/R); verify checksum; try both scan directions.
6. Code 39: estimate narrow width, classify wide/narrow, match 9-element
   characters between `*` delimiters.

A decode is only reported after the same value is seen on several
consecutive frames — the classic wand-scanner debounce.

## V2: the app icon is a Metal shader

`GenerateIcon.swift` is a single-file, reproducible icon generator —
`swift GenerateIcon.swift` on macOS and you get the 1024×1024
`icon-1024.png` dropped straight into
`LabScan/Assets.xcassets/AppIcon.appiconset/`. The PNG is committed,
and `build-and-run.sh` regenerates it automatically if it's ever
missing.

The pipeline is the fun part, and it's meant to be stolen:

1. **CoreText** typesets a dense "page" — alternating lines of Times
   New Roman and IBM Plex Mono (Menlo fallback) set with excerpts from
   Richard Hamming's *"You and Your Research"* — into a bitmap.
2. **Metal** uploads the page as a texture and a ~15-line compute
   kernel composites LabScan's red scan-stripe over it: 100% opacity
   at 50% of the icon height, smoothstep-fading to 0% at 30% and 90%.
3. **ImageIO** writes the readback to PNG. No windows, no Xcode, no
   asset pipeline: shader → image.
