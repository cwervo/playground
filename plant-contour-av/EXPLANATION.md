# How this was made

**Source:** `IMG_7688.mov` — 10.74 s, 1280×720 recorded portrait (display rotation −90°,
so 720×1280 upright), 322 frames at 30000/1001 fps, stereo AAC. A handheld walk down a
sidewalk toward a weed growing out of the crack where a brick wall meets the concrete,
next to a discarded yellow carton.

**Output:** `out/plant_contour_av.mp4` — the same 322 frames, analysed, annotated and
graded, with a score synthesised from the analysis; plus the full still sequence, the
raw per-frame measurements, and this document.

---

## 1. The constraint, stated exactly

Every algorithm in this piece is written from scratch, in two languages:

| Component | Language | Lines | What it is |
|---|---|---|---|
| `src/pcav.cpp` | C++ | 769 | The vision engine and the colourist |
| `tcl/synth.tcl` | Tcl | 394 | The synthesiser, the arranger and the mixer |
| `tcl/render.tcl` | Tcl | 98 | The pipeline driver |

**No computer-vision library.** No OpenCV, no scikit-image, no PIL, no NumPy. The C++
uses `<cstdio>`, `<cstdlib>`, `<cstring>`, `<cmath>` and `std::vector` — nothing else.
Deliberately *not* `<algorithm>`: the median, the percentile sort and the box sort are
hand-written insertion and selection sorts, so that no sorting routine comes from
outside either. Convolution, morphology, connected components, motion estimation,
segmentation, tone mapping and text rasterisation are all loops over a flat
`unsigned char` buffer.

**No audio library.** No libsndfile, no synthesis toolkit, no MIDI, no sequencer. Tcl
builds its own wavetables with `expr`, renders every voice sample by sample into two
Tcl lists, mixes, limits, and emits the RIFF header and the 16-bit PCM payload with
`binary format`.

**No font.** The 5×7 glyph set for ASCII `0x20`–`0x5F` is a table of 64×5 bytes embedded
in `pcav.cpp` and rasterised bit by bit.

**What is *not* mine, stated plainly:** `ffmpeg` is used as a codec and container tool
only. It turns the H.264/AAC `.mov` into a raw `rgb24` byte stream on stdin, turns the
processed `rgb24` byte stream on stdout back into H.264, decodes the source audio to raw
`s16le`, and muxes the finished picture and sound. It performs no analysis, no
filtering, no drawing, no colour work and no sound synthesis — every pixel it writes was
computed by `pcav.cpp`, and every sample it writes was computed by `synth.tcl`. Writing
an H.264 decoder by hand was outside the scope of the request; if you want that boundary
drawn differently, the engines read and write raw frames and raw PCM, so any other
demuxer can take ffmpeg's place without touching a line of the algorithms.

The pipeline is literally a Unix filter:

```
ffmpeg (demux) → | pcav 720 1280 metrics.tsv boxes.tsv | → ffmpeg (mux)
```

---

## 2. Finding the plant

Foliage is separated from brick, concrete and the yellow carton by **chromatic green
dominance**, not by hue-wheel thresholding.

For each pixel, with R, G, B in 0–255:

```
gn = (2G − R − B) / (R + G + B + 1)
plant ⟺ gn > 0.085  ∧  G > 1.055·R  ∧  G > 1.02·B  ∧  G > 34
```

`gn` is green excess normalised by intensity, so a leaf in shade and the same leaf in
sun score alike — the walk-in changes exposure by roughly a stop and the mask does not
care. The first term alone is not enough: the yellow carton has R ≈ G with B low, so
`2G − R − B` is strongly positive for it too. The `G > 1.055·R` test is what rejects it,
because yellow never has green meaningfully above red. Brick fails on both counts, being
red-dominant. The `G > 34` floor keeps the deep shadow under the carton out.

The raw mask is then cleaned by **morphological opening and closing**, implemented as a
separable min/max filter — a square structuring element decomposes into a horizontal
pass and a vertical pass, so a radius-*r* operation costs O(*r*) per pixel instead of
O(*r*²):

```
erode r=2   →  kill single-pixel speckle in the mortar
dilate r=3  →  rejoin leaf blades split by specular highlights
erode r=2   →  restore the original silhouette
```

**Contours** are the mask boundary, found by testing each set pixel's four neighbours:
a pixel is an edge if any 4-neighbour is unset. Edges are drawn in `#00FF40` at 95%
opacity with a one-pixel falloff on each side, which is what gives the leaves their
traced-in-highlighter outline.

**Bounding boxes** come from a **connected-component labelling** pass — 8-connected,
iterative flood fill with an explicit index stack rather than recursion, so a component
spanning the whole frame cannot blow the call stack. Components under 900 px are
discarded, the survivors are sorted by area, and boxes within 26 px of each other are
merged by a repeated pairwise-union sweep, so that a leaf cluster reads as one plant
rather than seven leaves. The top three become `PLANT` boxes.

Across the clip the mask covers a mean **4.62%** of frame area and produced **521**
`PLANT` boxes.

## 3. Finding the movement

Motion is measured by **block matching** on a half-resolution luma pyramid level —
Rec.601 luma in fixed point, `(77R + 150G + 29B) >> 8`, then 2×2 box-downsampled to
360×640. The frame is divided into 16×16 blocks (22×40 = 880 of them) and each block is
matched against the previous frame with a **three-step logarithmic search**:

```
step = 8, 4, 2, 1
   evaluate the 9 candidates around the current best
   move the centre to the winner, halve the step
```

That is 36 candidate positions per block instead of the 961 an exhaustive ±15 search
would need, at the same maximum displacement. The cost function is sum of absolute
differences, sub-sampled on a 2×2 lattice within the block and abandoned early once it
exceeds the best score so far.

The result is a vector field. Two numbers are pulled out of it:

- **Camera velocity** — the *median* of all 880 block vectors, taken per axis. The
  median is the right estimator here because the dominant motion in the frame is the
  operator walking, and the median is not dragged by the minority of blocks that
  disagree. Mean 3.14 px/frame, peak 12.17 px/frame.
- **Local energy** — the mean magnitude of each block's *residual* after the camera
  vector is subtracted. This is what is left when the walk is removed: parallax between
  the near sidewalk and the far wall, the plant moving in the breeze, the operator's
  hand shake. Mean 6.94 px/frame.

**Velocity zones** are thresholded against the frame's own distribution rather than
against constants, so they mean the same thing whether the operator is standing still or
lunging: the block magnitudes are sorted and the 88th percentile becomes the high
threshold, the 14th percentile the low threshold. A block then survives only if at least
three (high) or four (low) of its eight neighbours agree with it, which is a cheap
morphological open on the block grid and stops isolated mismatches from becoming zones.
Sprawling boxes — larger than 42% of the block grid, or less than a third filled — are
rejected outright. What survives is drawn as `VEL-HI` (dashed navy) and `VEL-LO`
(dotted navy): **462** and **155** boxes respectively across the clip. Fast blocks also
get a short navy velocity tick drawn along their motion vector, on a checkerboard so the
field stays readable.

Physically, `VEL-HI` lands on the near sidewalk and the carton — close to the camera,
so a given walking speed sweeps them across more pixels — and `VEL-LO` lands on the far
brick.

## 4. Finding the shadows

Naïve shadow detection is "dark pixels", and on this footage that is wrong: the wall is
covered in black spray paint, which is dark but is not shade. Three tests separate them.

1. **Relative to illumination, not absolute.** The luma plane is blurred with a radius
   150 box filter to estimate the illumination field, and a pixel is a shadow candidate
   only if it sits below 80% of its *own local illumination* — and below 88% of the
   frame mean. A wide box blur is O(1) per pixel regardless of radius, by running sum,
   so a 301-pixel-wide kernel costs the same as a 3-pixel one.
2. **Scale.** Shade is a region; paint is a stroke. The candidate mask is eroded with a
   radius-10 structuring element, which annihilates anything narrower than ~21 px — the
   graffiti — while a real shadow only shrinks.
3. **Persistence.** Whatever fragments survive the erosion are removed by connected
   component area: any blob under 1100 px is zeroed. Then a radius-14 dilation restores
   the genuine regions and a radius-4 erosion tidies the boundary.

The result tracks the shade band where the wall meets the pavement, the pocket inside
the doorway, and the shadow the carton casts — and ignores every letter of the tag.
Mean coverage **2.99%** of frame.

**The purple.** A binary mask painted directly would put hard staircase edges on soft
shade, so the mask is blurred (radius 11) into a soft occupancy field `w`, smoothstepped,
and used as the mix weight:

- body: `#2E064E` at `(0.17 + 0.45·depth)·smoothstep(w)`, where `depth` is how far the
  pixel falls below the shadow threshold — so the deepest shade takes the most pigment;
- rim: `#9630D6` on the `w = 0.46` iso-contour of the blurred field, feathered over
  ±0.19, which lifts a lighter purple edge exactly where the light is falling off.

Per frame the engine also records how much of the shadow mask *changed* since the last
frame. That signal is the drummer.

## 5. The grade

A hand-built "Nolan" chain, in this order, per pixel:

1. **To scene-linear:** `x^2.2`, then a −⅓ stop pull (×0.78). The whole image is printed
   down; nothing in the frame is allowed to sit at a comfortable midpoint.
2. **Filmic tonemap:** the ACES-style rational curve
   `(x(2.51x + 0.03)) / (x(2.43x + 0.59) + 0.14)`, which rolls the highlights off
   asymptotically instead of clipping them.
3. **Back to display** (`x^(1/2.2)`), then an **S-curve** about a 0.5 pivot at 1.30
   contrast with a −0.035 offset, then a dense-black remap `0.965x + 0.014` — crushed,
   with just enough toe lift that the blacks read as film stock rather than as void.
   Steps 1–3 are per-channel scalar, so they are baked into a 256-entry lookup table
   once at startup.
4. **Split tone:** shadow weight `(1 − l)²·0.80`, highlight weight `l²·0.42`. Shadows go
   to teal — red multiplied by 0.30, blue lifted — and highlights to a warm steel.
5. **Desaturate to 55%**, then push 22% back along the red-minus-blue axis. That is the
   orange-and-teal signature: strip the colour out globally, then reintroduce it on one
   axis only, so skin and brick stay warm and everything else goes cold.
6. **Halation:** the tonemapped highlights above 0.70 are isolated, blurred twice
   (radius 9, then radius 15 — two box passes approximate a Gaussian), and added back
   warm-weighted (1.00 / 0.72 / 0.52), which is what puts the glow around the bright
   concrete.
7. **Vignette** `1 − 0.62·r^2.2`, and **grain** from a deterministic integer hash of
   pixel index and frame number, ±2% and weighted toward the toe, so it lives in the
   shadows where real grain lives.

Overlays are composited *after* the grade, so the navy stays navy, the green stays
`#00FF40`, and the annotation reads as a layer on top of a photographed image rather
than as part of it.

**The coordinates are drawn in literal pure RGB:** each box label prints its kind in
navy, then `X` in `#FF0000`, `Y` in `#00FF00`, and `W`/`H` in `#0000FF` — one primary per
axis, unmixed, at full saturation.

## 6. The score

`pcav` writes one row per frame to `metrics.tsv` — 19 columns, 322 rows. `synth.tcl`
reads it and is handed no other information about the video.

Nothing in the mapping is hard-coded to this clip. The script computes the mean,
standard deviation and 90th percentile of each driver signal first, and normalises
against those, so the same script scores a different video correctly.

### The keyboard follows camera velocity

126 BPM, sixteenth-note grid, 90 steps over the clip. At each step the analysis is
sampled at that instant and a drive value is formed:

```
drive = 0.62 · (camVelocity / camP90) + 0.38 · (localEnergy / localP90)
```

and it decides everything:

| drive | what happens |
|---|---|
| < 0.28 | eighth notes only — the arpeggio halves in density |
| < 0.30 | root octave |
| 0.30 – 0.72 | up an octave |
| > 0.72 | up two octaves |
| > 0.55 | a bell layer fades into the timbre |
| > 0.86 | a second voice a third above, plus a 32nd-note flam an octave up |

Amplitude is `0.17 + 0.33·drive`. Stereo position is taken from the *plant's* centroid:
the arpeggio sits where the plant sits in frame, and pans as the walk swings it across.

The harmony is a four-chord loop of major ninths and a 6/9 — Dmaj9, Bm7, Gmaj9, A6/9 —
changing every two beats, arpeggiated through a 16-step up-and-out pattern. Wide, bright,
unresolved-but-cheerful intervals: the harmonic dialect of a Saturday-morning bumper.

The **timbre** is the "mixed keyboard": a single-cycle wavetable summing a 44%-duty
square (0.46) for the hollow cartoon bite, a saw (0.26) for body, and a triangle (0.34)
to round the top. Each note plays two of these detuned +7 cents against each other, which
produces the chorusing beat of a cheap consumer keyboard. On the attack the pitch starts
3% sharp and settles over 20 ms — the plastic-keyboard chirp. The envelope is a 4 ms
linear attack into an exponential decay reaching −56 dB at the note's end, and the whole
voice runs through a one-pole low-pass whose cutoff tracks the note (7.5× the
fundamental, capped at 8.2 kHz) and opens with the envelope, which both shapes the tone
and keeps wavetable aliasing under the mix at the top octave.

101 keyboard notes were generated.

### The hi-hat follows the shadows

Two mechanisms:

- **Accents.** The shadow-change signal is scanned for local maxima above its own mean.
  Each peak is quantised to the nearest 32nd note, deduplicated, and fired with amplitude
  scaled by how far above the mean it sits. A peak past the 95% mark opens the hat —
  200 ms decay instead of 55 ms, and detuned down slightly, the way a real open hat sits
  lower.
- **Pulse.** A quiet closed hat on every offbeat sixteenth, gated on the frame actually
  containing shadow and on the shadow being in motion. When the shadows go still, the kit
  thins out by itself.

The hat voice is built from scratch: an LCG pseudo-random sequence through a one-pole
high-pass (`y = 0.86·(y + x − x₋₁)`), mixed 76/24 with two inharmonic square partials at
8.3 and 11.7 kHz for the metallic ring, under an exponential decay. It is panned slightly
right, where a hat sits in a kit.

58 hats were generated.

### The mix

A soft sine root under each chord change at −25 dB gives the arpeggio a floor. The
original location sound — traffic, footsteps, the city — is decoded to raw PCM and mixed
in by Tcl at 0.13 linear, so the piece stays anchored to the sidewalk it was shot on.
The master is summed in two passes: the first finds the true peak and applies the head
and tail fades, the second applies make-up gain to −0.7 dBFS (1.79× here) and a rational
soft limiter `x / (1 + 0.32|x|)` — saturation rather than clipping. Output is 44.1 kHz
16-bit stereo, written as a RIFF file by hand.

---

## 7. Running it

```bash
g++ -O2 -ffast-math -o build/pcav src/pcav.cpp
tclsh tcl/render.tcl /path/to/IMG_7688.mov out
```

About 105 s end to end for this clip on one core: ~70 s in the vision pass, ~30 s in the
Tcl synthesiser, the rest in muxing and stills.

### What comes out

| Path | What it is |
|---|---|
| `out/plant_contour_av.mp4` | 720×1280, 10.74 s, H.264 + AAC — picture and score |
| `out/plant_contour_av_frames.zip` | the complete 322-frame still sequence |
| `out/sequence_480/pcav_0001.jpg …` | the same sequence, loose (untracked) |
| `out/frames/frame_0001.jpg …` | full-resolution stills (untracked, ~90 MB) |
| `out/contact_sheet.jpg` | twelve frames across the clip |
| `out/metrics.tsv` | 322 rows × 19 columns — every number the score was made from |
| `out/boxes.tsv` | every bounding box drawn, with frame, kind, x, y, w, h, area |

`metrics.tsv` is the interesting one. It is the whole piece in numbers: what moved, how
fast, where the leaves were, how much of the frame was in shade, and how much that shade
changed — one row per twenty-ninth of a second.
