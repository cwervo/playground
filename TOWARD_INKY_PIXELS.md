# Toward Inky Pixels

A line of experiments about treating **pixels as ink** — dithering, halftoning,
CMYK deposition, ink budgets — that grows from three hand-drawn notes into a
reusable, dependency-free rendering engine.

Everything here runs from this repository alone. No build servers, no CDNs, no
network requests at runtime. Each demo is either a **standalone HTML file** you
can open directly, or a **Tcl program** you run with `tclsh` and nothing else.

---

## The idea

Screens emit light; ink absorbs it. If you pretend a display is paper, a lot of
lovely, physical behaviour falls out for free:

- **Dithering** — approximate a continuous tone with two colors by scattering
  dots (ordered / Bayer).
- **Halftoning** — approximate color with overlapping C, M, Y, K dot screens at
  different angles, the way newsprint does.
- **Ink as a budget** — if only so much of the page can be non-white, ink
  becomes a scarce resource: it dries, it fades, it gets "stolen" by change.
- **Provenance** — a pixel can carry a claim about where it came from.

The three notes in [`InkyPixels/design-notes/`](InkyPixels/design-notes/) are the
origin: "CIELAB circle-brush," "amplify `$color` pixels," and "Provenance."

## The arc of the work

| Stage | Artifact | What it explores |
|------|----------|------------------|
| 1 · Black & white | [`bwindex.html`](bwindex.html) | 2-bit **ordered (Bayer 8×8) dithering** in a WebGL shader — 12 gray steps from pure `#000`/`#FFF`. |
| 2 · RGB | [`RGBindex.html`](RGBindex.html) | 3-bit **RGB newspaper halftone** — rotated per-channel screens as additive circle "dots," DPR-locked. |
| 3 · CMYK | [`CIELABindex.html`](CIELABindex.html) | **CIELAB → CMYK ink deposition** with 32px blobs, multiply blend, and the "inky data" UI: FIFO ink dries, fades after 1s, changes steal ink at 32px/200ms, coverage capped by a 3-way 76/86/97 % budget. |
| 4 · Provenance | [`provenance/`](provenance/) | A **pure-Tcl** feature-extraction pipeline: slices salient shapes out of the note photos and hand-encodes them to base64 PNG (from-scratch Base64/CRC-32/Adler-32/DEFLATE), with selectable SVG text laid 1:1 over the ink and a "Calcium-Blur" CSS-3D background. |
| 5 · Engine | [`InkyPixels/`](InkyPixels/) | A **Tcl authoring library** that generates pages driven by one progressively-enhanced render loop — **WebGPU → WebGL2 → Canvas2D** — running **off the main thread** in an `OffscreenCanvas` worker. Two demos: a *History of Photographic Color* with live CMYK data wells, and a full modern UI kit. |

## The rendering approach (stage 5)

One loop, three tiers, off the main thread:

```
createRenderer()  tries  WebGPU → WebGL2 → Canvas2D   (first that initializes wins)
        │
        └─ preferred: run it inside a Web Worker on an OffscreenCanvas
           (the worker is built from an inline Blob URL — no network)
```

The worker owns the heavy per-pixel CMYK halftone; the main thread stays awake
and only nudges small DOM widgets — the four inkwells and the tier/FPS badge —
once per animation frame. If `OffscreenCanvas` (or a GPU tier) is missing it
degrades to a main-thread `Canvas2D` loop. The badge (top-right of each demo)
tells you which tier and thread you got, next to a live main-thread FPS counter,
so you can *see* that the pixels never block the UI.

---

## Run the demos

Clone the repo; everything you need is in it.

### Standalone HTML (just open the file)

```
bwindex.html                          # B/W Bayer dither (needs sibling test.jpg or a camera)
RGBindex.html                         # RGB newspaper halftone
CIELABindex.html                      # CMYK ink deposition + inky-data UI
provenance/index.html                 # self-contained: base64 slices + SVG + Calcium-Blur
InkyPixels/history-of-color/index.html# off-thread CMYK engine + 4 data wells
InkyPixels/ui-kit/index.html          # modern component kit over the same engine
InkyPixels/design-notes/index.html    # the three original notes, full-res gallery
```

Open them from a local web server for full fidelity (camera, `Save PNG`,
workers):

```sh
python3 -m http.server 8000     # then visit http://localhost:8000/…
```

Most also work straight off `file://`; the InkyPixels engine falls back to a
main-thread loop if a `file://` origin blocks its Blob worker.

### Tcl (regenerate the deliverables)

Only `tclsh` is required — nothing else.

```sh
cd provenance && tclsh extract.tcl     # rebuilds provenance/index.html
cd InkyPixels && tclsh build.tcl       # rebuilds both InkyPixels demos
```

`provenance/extract.tcl` reads committed inputs (`assets/note*.jpg` +
`assets/note*.raw`). `InkyPixels/build.tcl` needs only its sibling
`inkypixels.tcl`. The one optional step that is *not* pure Tcl is
`provenance/decode.cjs` (Node + headless Chromium), used only to regenerate the
`RAW1` pixel buffers from the JPEGs — those buffers are committed, so you never
need it just to run the pipeline.

---

## Layout

```
bwindex.html  RGBindex.html  CIELABindex.html   ← stages 1–3 (standalone HTML)
provenance/          ← stage 4: pure-Tcl slice extractor  (tclsh extract.tcl)
InkyPixels/          ← stage 5: the engine + library
  inkypixels.tcl       the library (namespace ::inkypixels)
  build.tcl            generates the demos
  history-of-color/    "A History of Photographic Color" + CMYK data wells
  ui-kit/              a modern component kit on one page
  design-notes/        the three original notes, full-resolution + gallery
TOWARD_INKY_PIXELS.md  ← you are here
```
