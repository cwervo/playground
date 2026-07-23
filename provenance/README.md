# Provenance — platonic-shape feature extraction

A dependency-free pipeline, written from scratch in pure **Tcl**, that turns three
hand-drawn field notes into a single self-contained `index.html`.

## Run

```sh
tclsh extract.tcl      # reads assets/note*.jpg, writes index.html
```

No packages, no external tools, **no network** — at build time or in the page.

## What the pipeline does (`extract.tcl`)

1. **Ingest** — reads each note JPEG as raw bytes and parses the *real* image
   dimensions straight out of the JPEG `SOF` marker.
2. **Model** — an extracted feature manifest per note: salient shapes + text
   tokens with normalized (0..1) 1:1 placement.
3. **Raster** — every salient shape is re-drawn as a *platonic* RGBA raster on a
   tiny from-scratch drawing surface, then encoded to a PNG with hand-rolled
   **Base64 + CRC-32 + Adler-32 + DEFLATE (stored blocks)** — no `zlib`, no
   `binary encode`.
4. **Compose** — emits `index.html`: **Calcium-Blur** backgrounds on CSS-3D
   planes, **selectable SVG text** laid 1:1 over the ink, and **copyable base64
   PNG** chips of each shape underneath.

## The deliverable (`index.html`)

Self-contained, zero network requests. Every image (backgrounds + shape PNGs) is
an inlined `data:` URI. Select the SVG text, click any chip to copy its base64
PNG, and drag the **Calcium Blur** slider (default **50 %** — a Gaussian blur
plus bone-white bloom, driven through a 3D-transformed layer).

`assets/note*.jpg` are downscaled copies of the source photos, kept small so the
inlined deliverable stays light; the blur hides the resolution loss.
