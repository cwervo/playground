# oklab_graphemes.tcl

Color-separate any PNG or JPG into **N bins equally spaced along the OKLAB
lightness (L) axis**, then search each bin ("channel") for **graphemes** —
connected marks whose *orientation* and shape are measured. This directly
follows the source notes: every grapheme encodes at least two things,
*orientation* and *meaning*.

Pure **Tcl 8.6+**. The only dependency is the built-in `zlib` command — no Tk,
no Img, no ImageMagick, no external processes. Runs anywhere `tclsh` runs.

## Usage

```sh
tclsh oklab_graphemes.tcl <input.png|input.jpg> [outdir] [options]
```

| option        | default | meaning                                            |
|---------------|---------|----------------------------------------------------|
| `-bins N`     | 6       | number of L bins                                   |
| `-maxdim N`   | 640     | downscale so `max(w,h) <= N` (`0` = no downscale)   |
| `-minarea N`  | auto    | ignore graphemes smaller than N px (~0.02% of area)|
| `-conn 4\|8`  | 8       | connectivity for connected components              |
| `-lrange lo hi` | image range | force an absolute L window instead of the image's |

## Output (in `outdir/`)

| file                      | what it is                                             |
|---------------------------|--------------------------------------------------------|
| `bin_<k>.png`             | pixels whose L falls in bin k, true colour, rest transparent (RGBA) |
| `bin_<k>_graphemes.png`   | that bin with each grapheme drawn: red bbox, cyan orientation whisker (principal axis), yellow centroid |
| `bins_preview.png`        | whole image false-coloured by bin (a 6-level OKLAB-L posterization) |
| `graphemes.tsv`           | one row per grapheme: bin, id, area, centroid, bbox, orientation°, eccentricity, glyph |
| `summary.txt`             | run report + per-bin grapheme counts                   |

The `glyph` column maps each grapheme's morphology to a character by its
principal-axis angle and roundness: `|` vertical, `-` horizontal, `/` `\`
diagonal, `o` round/blob.

## How it works

1. **Decode** — PNG via `zlib` inflate + scanline unfiltering; baseline JPEG
   as its **DC image** (one pixel per 8×8 block). The IDCT of a DC-only block
   is a flat patch `DC/8 + 128`, so the DC image is an exact 8×8 box-downsample
   of a full decode — fast in pure Tcl and a natural working resolution.
2. **OKLAB L** — sRGB → linear → LMS → cube root → L (Björn Ottosson's OKLab).
3. **Bin** — split the L axis into N equal intervals over the image's L range
   (or `-lrange`), assign every pixel a bin.
4. **Grapheme search** — treat each bin as a binary mask; label 8-connected
   components; for each, compute area, bounding box, centroid, and the
   orientation + eccentricity from the second central moments.

Reproducible: the output is a deterministic function of the input bytes and
the flags.

## Supported inputs

- PNG: 8-bit, colour types 0/2/3/4/6, non-interlaced.
- JPEG: baseline (SOF0), greyscale or YCbCr, any 4:x:x chroma subsampling,
  with restart intervals. (Progressive JPEG is rejected with a clear message.)
