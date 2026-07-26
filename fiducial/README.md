# Rulercode — visible-light CMYK fiducial barcodes

Human-readable-ish colour barcodes whose **printed size is guaranteed** and that
**encode their own physical length**, so a plain 2D camera can recover a rough
`mm-per-pixel` scale from a single glance — no matter which paper size they were
printed on.

Built in the spirit of **Johnny Chung Lee's** visible-light / light-sensor
fiducial work — the [Wiimote projects](http://johnnylee.net/projects/wii/),
*Automatic Projector Calibration with Embedded Light Sensors* (UIST '04), and
*Moveable Interactive Projected Displays Using Projector-Based Tracking*
(UIST '05). Lee's recurring trick is to embed **known physical geometry** in the
visible scene so a cheap sensor can recover pose and scale. A Rulercode does the
same for the Folk-style camera+projector table: it hides a literal ruler and a
self-describing scale inside a barcode.

```
┌───────────────────────────────────────────────── 200 mm (guaranteed) ─────────┐
│  0    50    100   150   200      ← real 10 mm ruler ticks (direct scale)        │
│ ▐  [■][░ C M Y burn-overlap colour data · 12 modules · 36 bits ░]  ▐▐          │  ← 20 mm bars
│ RULERCODE v1   ID 0x04D2 (1234)   L=200.0mm   module=10.00mm   CRC-OK           │  ← human text
└────────────────────────────────────────────────────────────────────────────────┘
```

## Why this shape

Your ask was: *human-readable-ish CMYK barcodes, guaranteed physical size when
printed via PostScript, overlapping bars with a burn/blend mode so they decode
reliably from either the digital file or a photo of the print, and giving rough
scale for 2D camera work.* Every one of those maps to a design decision:

| Requirement | How Rulercode does it |
|---|---|
| Guaranteed print size | Authored entirely in **mm**. PostScript pins a `/mm` operator (`72/25.4` pt); SVG pins `width/height` in `mm` with a mm `viewBox`. A 200 mm bar measures 200 mm. |
| CMYK, overlapping bars | Data track = three ink lanes (**C, M, Y**) sharing the same modules, drawn as overlapping layers. |
| Burn / blend mode | Overlap combined with **multiply** (SVG `mix-blend-mode:multiply`) / **overprint** separations (PostScript `setoverprint`). `C+M→blue`, `C+Y→green`, `M+Y→red`, `C+M+Y→black` — real subtractive ink mixing. |
| Decode from digital **or** print | Cyan ink absorbs red, magenta green, yellow blue → `(C,M,Y) = (1-R, 1-G, 1-B)`, the standard RGB→CMY conversion. The **same threshold maths** reads the vector file or a camera frame. |
| Rough scale for 2D camera | Payload encodes the marker's **true printed length**; decoder divides encoded-mm by measured finder-span-px → `mm/px`. Two free cross-checks: the 10 mm ruler and the printed text. |
| Human-readable-ish | 8 nameable colours, a real ruler, and a plain-text line with id + dimensions. |

## The encoding (v1)

The marker is exactly **20 modules** wide; module width `= length / 20`.

```
[quiet 1][start-finder 2][palette 2][ data 12 ][end-finder 2][quiet 1]
```

- **Finders** are solid-K (black) registration bars. Start = one bar, End = two
  bars → orientation is unambiguous.
- **Palette** = white / C / M / Y / K calibration swatches. The decoder samples
  these to set per-channel thresholds under the actual lighting or printer.
- **Data** = 12 modules × 3 bits (one bit per ink lane) = **36 bits**:

  | field | bits | meaning |
  |---|---|---|
  | `ID` | 16 | marker id, `0..65535` |
  | `LEN` | 12 | printed length in **0.1 mm** units (`200.0 mm → 2000`) |
  | `CRC-8` | 8 | poly `0x07` over the 28 data bits |

Each module's colour is its 3-bit `(C,M,Y)` symbol:

| bits C M Y | colour | | bits C M Y | colour |
|---|---|---|---|---|
| `0 0 0` | white | | `1 1 0` | blue |
| `1 0 0` | cyan | | `1 0 1` | green |
| `0 1 0` | magenta | | `0 1 1` | red |
| `0 0 1` | yellow | | `1 1 1` | black |

The CRC means a corrupted read is **rejected**, never mis-reported as the wrong
id — verified in the tests (see the noise curve below).

## Usage

Pure Python **standard library** — no numpy, PIL, or Ghostscript needed.

```bash
# Print-ready PostScript, guaranteed 200 mm bar on US Letter:
python3 rulercode.py --paper letter --id 1234 --format ps  -o marker.ps

# With true CMYK overprint separations (real "burn" on a RIP):
python3 rulercode.py --paper letter --id 1234 --format ps --separations -o marker.ps

# Digital / on-screen SVG (multiply-blended overlap):
python3 rulercode.py --paper a4 --id 0x04D2 --format svg -o marker.svg

# Raster preview (also used by the round-trip test):
python3 rulercode.py --paper card --format ppm --dpi 300 -o marker.ppm

# Decode a raster (vector-rasterised or a flat photo) back to id + scale:
python3 decode.py -v marker.ppm
#   id     : 0x04D2 (1234)
#   length : 200.0 mm  (encoded)
#   crc    : OK
#   scale  : 0.16947 mm/px   (5.901 px/mm)
```

### Paper sizes

Each marker **self-encodes its length**, so one decoder handles them all.

| `--paper` | page (mm) | default bar length | module |
|---|---|---|---|
| `letter` | 215.9 × 279.4 | 200.0 mm | 10.00 mm |
| `a4` | 210 × 297 | 190.0 mm | 9.50 mm |
| `a5` | 148 × 210 | 128.0 mm | 6.40 mm |
| `a6` | 105 × 148 | 90.0 mm | 4.50 mm |
| `card` | 85.6 × 53.98 (ISO ID-1) | 74.0 mm | 3.70 mm |

Override with `--length <mm>` for any custom size. Pre-generated samples for
every size are in [`samples/`](samples/).

## Tests

```bash
python3 roundtrip_test.py
```

Covers: exact payload round-trip over many id/length combos; CRC catching bit
flips; raster render→decode for every paper size with **scale error < 0.3 %**;
and a simulated-sensor-noise degradation curve:

```
noise sigma=10  ....... 8/8 correct, 0 safely-rejected
noise sigma=25  ....... 8/8 correct, 0 safely-rejected
noise sigma=40  ....... 8/8 correct, 0 safely-rejected
noise sigma=60  ....... 0/8 correct, 8 safely-rejected   ← CRC rejects, never mis-reads
```

## Using it on the Folk camera rig

`decode.py` is the **portable reference** decoder and expects a roughly
axis-aligned image. On the real table the front-end differs but the core maths
is identical:

1. **Find & rectify** — OpenCV locates the four solid-K finder bars (they are
   the most saturated black in the strip), then a perspective warp flattens the
   strip crop. This is the part `opencv/dots.folk` / `folk_qr_demos` already do
   for other markers.
2. **Separate channels** — `(C,M,Y) = (1-R,1-G,1-B)`, thresholded against the
   palette swatches. (Identical to the reference decoder here.)
3. **Decode & scale** — read 12 modules → 36 bits → id + length + CRC; divide
   encoded length by the measured finder span to get `mm/px` for the crop, which
   composes with the warp to give scale anywhere in the camera frame.

Because the finder bars and the 10 mm ruler are known physical geometry, you get
**three independent scale estimates** (ruler pitch, encoded-length ÷ span, and
the printed text) — "rough scale, reliably," which is exactly what 2D camera
projection work needs.

## Files

| file | what |
|---|---|
| `rulercode.py` | library + CLI: encoding, geometry, PostScript / SVG / PPM emitters |
| `decode.py` | pure-Python reference decoder (PPM → id + length + scale) |
| `roundtrip_test.py` | payload, raster, and noise-robustness tests |
| `samples/` | ready-to-print `.ps` and viewable `.svg` for every paper size |
