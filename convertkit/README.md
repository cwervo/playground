# convertkit

A Tcl-based compilation toolkit for the "Time Bandits Storyboards" format
ecosystem (see the sketch). This is **Phase 1**: the seed converters that
everything else will hang off of.

## Architecture

XML is the canonical hub. Every conversion routes through it:

```
.tcl  <->  .xml  <->  .png  <->  .jpg / .jpeg
```

- **`.xml`** — a `<tclprogram>` document carrying the byte-exact source
  (base64 `<source>`) plus a human-readable `<commands>` breakdown parsed
  with Tcl's own `info complete`.
- **`.png`** — the raster shows the code set in a mono font (IBM Plex Mono
  when installed) with a bordered frame, per the sketch; the authoritative
  payload rides in a `tEXt` chunk keyed `convertkit`. Pure-Tcl chunk
  read/write (Tcl 8.6 `zlib` for CRCs).
- **`.jpg` / `.jpeg`** — lossy pixels, so the payload rides in `COM`
  comment segments (`convertkit:i/n:` prefixed, split as needed). Pure-Tcl
  marker-segment surgery; raster transcode via ImageMagick.

Because the payload lives in metadata, every pair is **bidirectional and
byte-exact** for the Tcl source — even `tcl -> jpg -> tcl` through a lossy
codec, and `png -> jpg -> png` chains.

## Usage

```sh
tclsh bin/xconv.tcl samples/hello.tcl hello.xml    # tcl  -> xml
tclsh bin/xconv.tcl hello.xml hello2.tcl           # xml  -> tcl
tclsh bin/xconv.tcl hello.xml hello.png            # xml  -> png
tclsh bin/xconv.tcl hello.png hello3.xml           # png  -> xml
tclsh bin/xconv.tcl samples/hello.tcl hello.jpg    # any pair works
tclsh bin/xconv.tcl hello.jpg recovered.tcl
```

## Phase 2: print-survivable data frame (`bin/folkframe.tcl`)

Total reconstruction from a screenshot or a color-inkjet printout — no
file metadata involved, pixels only:

```sh
tclsh bin/folkframe.tcl encode samples/storyboard.tcl page.png
# print it / screenshot it / photograph it (axis-aligned), then:
tclsh bin/folkframe.tcl decode whatever-came-back.jpg
```

The frame is **minimal by default**: the page grows just enough to hold
the text panel at its physical size, and the band stays as thin as the
format allows (12 cells), widening the perimeter — or, past that,
deepening up to `-maxbandmm` (default 60) — only when the packet needs
it. Fixed geometry is still available via `-pagewmm/-pagehmm/-bandmm`.
The band is a ring of large color cells inside a white quiet margin
(printing comfort only — CV doesn't need it):

- **8-color palette** at the RGB cube corners, 3 bits/cell — maximum
  separation for inkjet inks; a **calibration strip** (all 8 colors in
  a known order) lets the decoder re-learn the palette per print.
- **QR-style finder fiducials** in all four corners give the cell pitch;
  the band thickness and exact grid dimensions are **self-encoded** next
  to the calibration strip, so cell-count recovery is immune to pitch
  measurement error at any scale.
- **Header**: hostname, IP, program id, filename
  (`YYYYMMDD-HHMMSS-mmmZ.folk.png`, UTC), page + cell size in mm — the
  artifact **encodes its own physical scale** (`scale_px_per_mm` is
  reported on decode), created timestamp, and origin URL.
- **Payload**: as much of the program as fits. The whole packet is
  CRC32-guarded and repeated to fill the band; the decoder takes the
  first copy that checks out. If the program is too long
  (`complete=0`), the printed prefix + the human-readable text carry
  most of it, and the full source can be pulled from
  `http://<ip>/folk-data/program/<filename>`.
- The interior shows the code set in the **vendored IBM Plex Mono**
  (`fonts/`, OFL-licensed) at a **minimum of 12pt physical** regardless
  of frame size (never scaled down), in **#1010FF on white** for maximum
  non-black contrast. A `tEXt` chunk still carries the full canonical
  XML as a lossless digital channel.

Decoder assumptions: axis-aligned raster (screenshot, or a deskewed
scan); arbitrary uniform or anisotropic scaling, mild blur, and JPEG
recompression are handled (see `tests/dataframe.tcl`). Perspective /
rotation rectification is the CV layer's job (future work, cf.
`../smokesignal`).

## Tests

```sh
tclsh tests/roundtrip.tcl   # 12 checks: all format-pair roundtrips, byte-exact
tclsh tests/dataframe.tcl   # 18 checks: AST + data frame, incl. simulated
                            # screenshot (up/downscale) and rescan (blur+JPEG)
```

## Layout

```
bin/xconv.tcl      extension-driven CLI dispatcher
bin/folkframe.tcl  print-survivable data-frame encoder/decoder CLI
lib/tclxml.tcl     Tcl <-> canonical XML
lib/tclast.tcl     real Tcl AST: parse, XML emission, source regeneration
lib/pngcodec.tcl   pure-Tcl PNG chunk read/write + tEXt embed/extract
lib/jpgcodec.tcl   pure-Tcl JPEG COM-segment embed/extract
lib/render.tcl     code-to-raster rendering (ImageMagick + vendored font)
lib/dataframe.tcl  pixel-domain data frame: encoder + screenshot/scan decoder
fonts/             vendored IBM Plex Mono (OFL)
docs/SPEC.mermaid  full ecosystem tech spec (built + planned phases)
samples/           sample .tcl programs + pre-generated demo artifacts
tests/             test suites
```

## Requirements

- Tcl 8.6+ (uses built-in `zlib`)
- ImageMagick (`convert`/`magick`) for the visible raster and PNG<->JPEG
  transcodes; PNG payload embed/extract works without it.

## Roadmap (from the sketch — see docs/SPEC.mermaid)

- `.folk.png` with RGB burn-blend barcodes encoding 6DOF position + scale
  (see `../smokesignal` for prior art)
- `.png.folk` — base64 PNG packed into a folk program
- Paper-size render targets: `.folk.A3/A4/A5/A6/A7.png`, usletter, 80x40mm
- `.tcl.folk`, `.tk.folk`, `.c.folk`, `.folk.rs`, `.folk.go`
- Document targets: PDF, HTML, Keynote, PPTX, hypercard(???)
