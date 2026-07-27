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

## Tests

```sh
tclsh tests/roundtrip.tcl
```

Runs every sample through all round-trip chains (12 checks) and verifies
byte-identical recovery.

## Layout

```
bin/xconv.tcl      extension-driven CLI dispatcher
lib/tclxml.tcl     Tcl <-> canonical XML
lib/pngcodec.tcl   pure-Tcl PNG chunk read/write + tEXt embed/extract
lib/jpgcodec.tcl   pure-Tcl JPEG COM-segment embed/extract
lib/render.tcl     code-to-raster rendering (ImageMagick, with fallback)
docs/SPEC.mermaid  full ecosystem tech spec (built + planned phases)
samples/           sample .tcl programs + pre-generated demo artifacts
tests/             round-trip test suite
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
