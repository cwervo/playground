# BaiLing — sensor and lens reconstruction from a single screenshot

Reconstruction of the imaging chain behind the photograph in
`data/screenshot_source.png`: an iPhone screenshot of an Instagram feed post
(`welcome.jpeg`, a carousel about Bai Ling's style), whose 15th slide is a
subway selfie with a heavy circular vignette and pronounced grain.

The question was: *from the artifacts alone, what sensor and lens made this?*

**Short answer.** The "fisheye" is not optics. The dark oval is a drawn,
canvas-proportional ellipse; the lens underneath it is a mildly barrel-distorted
wide-angle, and the sensor behind it was severely photon-starved. Every step
below is a measurement with a stated uncertainty, and the places where the image
simply cannot answer the question are marked as such.

---

## 1. What is actually in front of us

The file decodes as **1206 × 2622, 16-bit RGB, Display-P3** (`cICP 12/13/0/1`
— P3 primaries, sRGB transfer, full range). PIL silently truncates 16-bit RGB
PNGs to 8 bits, so `analysis/01_extract.py` implements the PNG unfilter directly
to keep the low byte, which carries real content (low-byte σ = 84).

EXIF/XMP: `exif:UserComment = "Screenshot"`, `photoshop:DateCreated =
2026-08-25T11:04:51`, matching the 11:04 in the status bar.

The chrome background is a uniform `(3076, 4066, 5148)`. Rows that are *not*
that colour isolate the media tile at **rows 330–1937, full width** —
1206 × 1608, exactly 3:4.

**None of this is the camera.** It is three renderings downstream of it. The
first job is to measure how far downstream.

## 2. The pixel chain (stages 02–07)

Interpolating a signal by a factor *s* makes the local interpolation error
periodic, with its comb fundamental at |1 − 1/s| (Popescu & Farid 2005;
Gallagher 2005). Two combs are present in the tile, and neither appears in
OS-rendered UI regions used as controls.

| comb | measured f (cyc/screen-px) | reading |
|---|---|---|
| 1 | 0.104477 (both axes) | s = 1.116666 → source **1080.00 × 1440.00** |
| 2 | 0.248755 / 0.248754 | = 5/18 exactly in the 1080 raster (to 2 × 10⁻⁶) |

Comb 1 lands on 1080 × 1440 to five figures on *both* axes independently. A
continuous scan of block-lattice periods confirms it: the strongest phase-locked
lattice is at **8.9295 px** (vertical) / 8.9437 px (horizontal) against 8.9333
predicted for an 8-px JPEG grid at 1080/1440, plus a second at 17.87 px — the
16-px MCU of **4:2:0 chroma subsampling**.

Comb 2 implies an earlier resize by 18/13, i.e. a pre-upload raster of
**780 × 1040** (upscaled to 1080) or 1380 × 1840 (downscaled). The two readings
are algebraically indistinguishable from the comb alone, and neither one's JPEG
lattice survives (coherence at both predicted periods sits *at or below* the
baseline), so **the direction of that resize is unresolved.**

    sensor ─?─▶ [780×1040 or 1380×1840] ──▶ 1080×1440 JPEG 4:2:0 ──▶ ×1.116667 ──▶ screen

## 3. The dark surround is drawn, not optical (stages 08–10, 29–30)

10.05 % of the tile is exactly `(0,0,0)`, in four clean circular corner cutouts.
Fitting the support as a level set over all 483 k pixels — maximising
Youden's J for the predicate ρ ≤ 1 — gives:

| | value |
|---|---|
| centre | (602.86, 799.63) — offset from frame centre by (−0.14, −4.37) px |
| semi-axis a (x) | 660.09 px |
| semi-axis b (y) | 882.91 px |
| **axis ratio b/a** | **1.3376** |
| rotation | 0.013° |
| Youden J | **0.986** (ellipse) vs 0.878 (circle) |

Two things about that ellipse. Its ratio is the frame's own aspect (4/3 =
1.3333), and its semi-axes are the *same fraction of each frame dimension*:
a/W = 0.5473, b/H = 0.5491 — equal to 0.3 %.

A rotationally symmetric lens projects a **circular** image circle whose radius
is set by the optics and has no reason to track both frame dimensions. So either
the frame was anamorphically stretched by 4/3 (a square crop squeezed into 3:4),
or the oval was drawn in canvas coordinates.

**The grain settles it.** Photosite noise is white; every resize convolves it
with that resize's kernel, so a frame stretched vertically by *k* carries a noise
autocorrelation *k* times wider vertically. Unlike every straightness test — an
affine stretch maps lines to lines, so plumb-line methods are *blind* to it —
this measurement is directly sensitive. Over 1002 flat patches:

    autocorrelation 1/e half-width:  horizontal 2.604 px   vertical 2.644 px
    ratio wy/wx = 1.0157,  95% CI [0.9982, 1.0332]   (400 bootstraps)

    k = 1.0000 (no stretch)  → CONSISTENT
    k = 1.3333 (square→3:4)  → REJECTED
    k = 0.7500               → REJECTED

The pixels are square and unstretched. Therefore the 1.3376 ellipse **cannot** be
a circular image circle. It was applied digitally.

Three further facts agree:

- **Profile shape.** Illumination is flat out to ρ ≈ 0.78, then falls to zero by
  ρ = 1.0. Natural vignetting is cos⁴θ — a smooth decline *from the centre* —
  and fits badly (rms 0.378) against a power law with exponent ≈ 13 or a
  smoothstep. A flat core with a hard shoulder is a field stop or a drawn mask,
  not cos⁴ falloff.
- **Internal inconsistency.** A lens whose image circle falls that far inside its
  sensor is a fisheye or a clip-on converter, and would show 15–50 % barrel
  distortion. We measure ~6 % (§4). The two observations cannot both come from
  one real lens.
- **Order of operations.** σ/μ stays constant (0.030–0.035) from ρ = 0.3 out to
  0.97, so the darkening scales the noise with the signal — it was applied to
  already-noisy data. That rules out a grain layer laid on *after* a mask, but it
  is equally consistent with a filter that vignettes last.

## 4. The lens: mild barrel, not a fisheye (stages 13–19, 26–28)

The naive plumb-line approach fails twice here, and both failures are
instructive:

1. A scale-free straightness objective is **gameable** — the division model can
   contract the frame until every chain collapses toward a point. Bounding the
   parameters is not optional.
2. The straightest long edges in this image (rms 0.40–0.63 px over 265–342 px)
   are all **near-radial** (10–13° from the radial direction). A line through the
   principal point stays straight under *any* rotationally symmetric distortion,
   so their straightness proves nothing. Grouped by tangentiality, bowing does
   **not** increase: median |sagitta| is 9.84 px for near-radial chains and
   10.26 px for near-tangential ones. The residual bowing is the scene's own
   curved grab rails, not the lens.

What does work is **concurrency**. 36 straight segments, spread over x 41–1169,
y 117–913, radii 194–742 px, meet at a single vanishing point to a weighted
angular residual of 0.54°. Under a fisheye projection the images of parallel 3D
lines are curves with no common intersection, so chord fits scatter. Scanning
the division-model parameter *L* and refitting the VP each time:

| L | residual (deg) | |
|---|---|---|
| −0.36 | 1.058 | full fisheye |
| −0.24 | 0.898 | |
| **−0.05** | **0.544** | **minimum, interior** |
| 0.00 | 0.598 | perfect rectilinear |
| +0.20 | 2.172 | pincushion |

**Best estimate L ≈ −0.05 (barrel), ≈ +6 % radial displacement at the field
edge.** Pincushion is firmly excluded (residual rises steeply, and only 9 % of
bootstraps allow L > −0.02). The full sample disfavours a fisheye by roughly a
factor 3.6 in weighted squared residual — but a bootstrap over segments is
bimodal (36 % of resamples run to strong barrel), so the *magnitude* is not
tightly pinned. Honest range: **L ∈ [−0.35, −0.02], best −0.05.**

That is an ordinary wide-angle lens — a phone main or wide camera with its
distortion correction off or partial.

## 5. The focal length is provably not recoverable

The longitudinal vanishing point sits at (461, 751), only **151 px** from the
principal point. The camera was pointed almost straight down the length of the
car — within 6–12° for any plausible *f*.

This is the classical **degenerate configuration** for vanishing-point
calibration (Caprile & Torre 1990). Lines parallel to the optical axis image as
rays through the principal point whose directions depend only on the lines'
lateral offsets, *not* on *f*. The orthogonality constraint

    u₁u₂·(1/fx²) + w₁w₂·(1/fy²) = −1

is uninformative when one VP sits on the principal point. Every VP pair
recoverable from this image returns a positive product (+100978 for the best
transverse/longitudinal pair), which no real camera can produce — confirming the
families are not a usable orthogonal triple rather than indicating a bad fit.

**f cannot be measured from this image**, and no scene object of known size is
visible unforeshortened. From the ~6 % barrel and the scene coverage, a diagonal
FOV of roughly 70–100° (≈ 24–35 mm equivalent) is the most that can be said, and
that is an inference from lens-design convention, not a measurement.

What *is* recoverable is pose. The two horizontal VPs define the horizon:

- **roll = −15.1°** (the car is visibly tilted in frame — handheld selfie)
- horizon offset 88.2 px from the principal point → **pitch = arctan(88.2/f)**,
  i.e. 3.6–7.2° for f = 700–1400 px

## 6. The sensor: photon-starved, and mostly empty resolution

**Photon transfer curve.** Fitted in *linear* light — in a gamma-encoded image
shot noise looks almost flat and the fit is meaningless — over 9167 detrended
12 × 12 tiles spanning μ = 0.0027 … 0.97:

    var ∝ μ^1.36–1.49,   corr(μ, var) = +0.885 … +0.996,   intercept ≈ 0

Variance rises steeply with signal and extrapolates to zero. **The grain is
signal-dependent**, which rules out an additive synthetic grain layer (exponent
0). The exponent sits between Poisson (1) and multiplicative (2), as expected for
photon noise seen through the filter's contrast-boosting tone curve.

The slope gives an effective full-scale of **≈ 137 e⁻ equivalent** — mid-grey
SNR ≈ 5 (14 dB). Bracketing: JPEG and resampling *suppress* measured variance
(pushing the figure up), the contrast boost *inflates* it (pushing it down), so
treat this as an order-of-magnitude statement. It says the capture was
photon-limited at very high gain — a small sensor, wide open, at high ISO, in a
dim car.

**Effective resolution.** The grain autocorrelation has a 1/e half-width of 2.60
screen px (2.31 px in the 1080 raster) with negative side lobes at ±3–4 px — a
windowed-sinc/bicubic kernel signature. The detail spectrum knees at
0.27 cyc/1080-px. Both give **≈ 470 × 610 genuinely independent samples ≈ 0.3
Mpx**, against a delivered 1.55 Mpx file. Most of the delivered pixels carry no
independent information. Some of that width is ISP denoising rather than
resampling, so read it as an upper bound on resolving power, not a native
photosite count.

## 7. Two things this image cannot tell us

- **Lateral chromatic aberration.** Phase correlation between R and B returns
  0.025 px rms — but that is an *artifact of the method*, not a result. Under
  4:2:0 subsampling, R = Y + 1.402·Cr and B = Y + 1.772·Cb both inherit the same
  full-resolution luma, so their high-frequency content is nearly identical by
  construction and the correlation is blind to the original misregistration. A
  fringe-polarity estimator on the chroma planes could partially recover it; it
  is not implemented here. **No CA conclusion is drawn.**
- **Rolling-shutter flicker.** AC lighting at 2× mains would print narrow
  horizontal banding. The row-mean spectrum's strongest peak has **Q = 0.5** —
  broad — and the *column*-mean spectrum peak is stronger still (323 vs 179
  peak/median). That is scene structure, not flicker. No line readout time can be
  extracted, so nothing follows about rolling vs global shutter.

## 8. Reconstruction

| quantity | value | confidence |
|---|---|---|
| Delivered raster | 1080 × 1440, JPEG 4:2:0 | measured, 5 figures |
| Display upscale | ×1.116667 | measured, 6 figures |
| Earlier resize | 18/13 — 780×1040 up, or 1380×1840 down | comb exact; direction unresolved |
| Pixel aspect | square, k = 1.016 ± 0.017 | measured, 4/3 rejected |
| Dark surround | drawn ellipse, a = 660.1, b = 882.9, ratio 1.3376 | measured; synthetic origin established |
| Vignette profile | flat to ρ = 0.78, zero by ρ = 1.0 | measured; cos⁴ excluded |
| Radial distortion | L ≈ −0.05, ~6 % barrel at field edge | best estimate; range [−0.35, −0.02] |
| Focal length / FOV | **not recoverable** | degeneracy proven |
| Camera roll | −15.1° | measured |
| Camera pitch | arctan(88.2 px / f) | coupled to f |
| Optical axis vs car axis | within 6–12° | measured |
| Noise character | signal-dependent, var ∝ μ^1.4 | measured |
| Effective full-scale | ≈ 137 e⁻ equivalent | order of magnitude |
| Effective resolution | ≈ 470 × 610 ≈ 0.3 Mpx | measured, upper bound |

**The picture that emerges:** an ordinary phone camera, wide-ish lens with
uncorrected mild barrel, held at arm's length and rolled 15°, pointed down the
axis of a subway car, shooting at a gain high enough to be photon-limited. Then
a period-camera filter crushed the blacks and painted a 4:3-proportioned oval
vignette over the frame; then a resize; then Instagram's 1080-wide JPEG; then a
1.117× upscale onto a phone screen; then a screenshot. The "fisheye lens" that
the image appears to advertise does not exist.

---

## Running it

```
python3 analysis/01_extract.py     # 16-bit PNG decode, locate the media tile
python3 analysis/04_resample.py    # resampling combs -> delivered raster
python3 analysis/07_blockgrid.py   # JPEG block lattices, chroma MCU
python3 analysis/10_levelset.py    # image-circle support fit
python3 analysis/30_aniso.py       # grain isotropy -> anamorphic test
python3 analysis/26_rectilinearity.py  # distortion via VP concurrency
python3 analysis/23_ptc2.py        # photon transfer curve, banding, vignette
python3 analysis/29_grain.py       # grain autocorrelation, effective resolution
python3 analysis/32_pose_figs.py   # camera pose, figures
```

Stages 14/16/19/27/31 are retained because their **negative** results are part
of the argument: the degeneracies they hit are why §4 uses concurrency and why
§5 concludes what it does.

See `REFERENCES.md` for the papers each method comes from.
