# Provenance — platonic-shape feature extraction

A dependency-free pipeline, written from scratch in pure **Tcl**, that turns three
hand-drawn field notes into a single self-contained `index.html`.

## Run

The decoded pixel buffers (`assets/note*.raw`) are **committed**, so the Tcl
pipeline runs with nothing but `tclsh`:

```sh
tclsh extract.tcl      # reads assets/note*.{jpg,raw}, writes index.html
```

`decode.cjs` is only needed to regenerate those buffers from scratch — it does
the one step pure Tcl can't (turn a JPEG into pixels; a from-scratch JPEG decoder
is out of scope) and writes a trivially-readable `RAW1` buffer
(`"RAW1" | u32 w | u32 h | w*h*3 RGB`):

```sh
node decode.cjs        # optional: rebuild assets/note*.raw from the JPEGs
```

Everything else — the slicing, downscaling, and PNG encoding of the **real photo
pixels** — happens in `extract.tcl` with no packages and no network. The
generated `index.html` itself makes **zero network requests**.

## What the pipeline does (`extract.tcl`)

1. **Ingest** — reads each note JPEG as raw bytes, parses the *real* image
   dimensions straight out of the JPEG `SOF` marker, and loads the decoded
   `RAW1` pixel buffer.
2. **Model** — an extracted feature manifest per note: salient shapes + text
   tokens with normalized (0..1) 1:1 placement.
3. **Slice** — each salient shape's bounding box is cropped **straight out of
   the photo**, box-averaged down to a thumbnail, and encoded to a PNG with
   hand-rolled **Base64 + CRC-32 + Adler-32 + DEFLATE (stored blocks)** — no
   `zlib`, no `binary encode`.
4. **Compose** — emits `index.html`: **Calcium-Blur** backgrounds on CSS-3D
   planes, **selectable SVG text** laid 1:1 over the ink, and **copyable base64
   PNG** chips (real photo slices) of each shape underneath.

## The deliverable (`index.html`)

Self-contained, zero network requests. Every image (backgrounds + shape PNGs) is
an inlined `data:` URI. Select the SVG text, click any chip to copy its base64
PNG, and drag the **Calcium Blur** slider (default **50 %** — a Gaussian blur
plus bone-white bloom, driven through a 3D-transformed layer).

`assets/note*.jpg` are downscaled copies of the source photos, kept small so the
inlined deliverable stays light; the blur hides the resolution loss.
`assets/note*.raw` are the committed decode buffers (regenerable with
`decode.cjs`). The full-resolution originals live in
[`../InkyPixels/design-notes/`](../InkyPixels/design-notes/).
