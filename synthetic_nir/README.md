# Synthetic NIR vein-finder imagery from a single visible photograph

Reconstructs physically parameterised skin chromophore fields from an ordinary
sRGB photograph by inverting a two-layer skin optics model in the CIELAB chroma
plane, re-renders them at simulated vein-finder wavelengths (760 / 850 / 940 nm),
and analyses the result with remote-sensing band math and probabilistic
contouring. Processing is piecewise over an adaptive, overlapping quadtree.

**These NIR bands are simulated, not measured.** The pipeline re-renders
evidence already present in the source photograph under a different spectral
weighting. It cannot recover structure that left no trace in the original
frame. Nothing here is a medical device or fit for clinical use.

## The result on the supplied photograph

**No vein structure is detectable, and the reason is exposure, not method.**

| quantity | value |
|---|---|
| hand segmented | 36.7% of frame, class separation 1.20 |
| analysed interior (eroded) | 30.8% of frame |
| interior with usable support | **3.9%** |
| observed mean ridge response | 0.0347 |
| null mean ridge response (same noise, no structure) | **0.0670** |
| pixels surviving BH FDR q=0.05 | **0** |

The observed ridge response is *lower* than what the same detector produces on
structure-free surrogates carrying the measured noise. Measured on the
full-resolution 8-bit file, the palm sits at a mean sRGB code of about
(1.2, 0.5, 0.5) out of 255 and the back of the hand at (7.5, 2.6, 1.4). Only the
sunlit finger edges reach (95, 90, 76). Over most of the hand the chroma the
inversion consumes is quantisation noise.

`out/06_vein_contours.png` shows this directly: the null panel — pure noise, no
structure by construction — produces a dense, convincing vein-like web. That is
what any detector without a calibrated null would have reported as veins.

## Validation: the detector works when signal exists

`out/07_validation.png`. A phantom with a known vein network is rendered to 8-bit
sRGB through the same forward model, with shot and read noise, at a sweep of
exposures, then passed through the identical detection code.

| mean tissue code | ROC AUC | recall @ FDR 0.05 | precision |
|---|---|---|---|
| 65 | **0.930** | 0.42 | 0.994 |
| 36 | 0.901 | 0.00 | — |
| 19 | 0.835 | 0.00 | — |
| 9.6 | 0.601 | 0.00 | — |
| 6.2 | **0.502** (chance) | 0.00 | — |

The supplied photograph's hand sits at codes 1–8. The method is sound; the
exposure is roughly five stops short. Re-shoot the hand exposed for the *hand*
rather than the window behind it — even a phone at ISO 800 with the hand
metered — and this pipeline has something to work with.

## Method

1. **Colorimetry** (`spectra.py`, `colorimetry.py`) — CIE 1931 CMFs via the
   Wyman–Sloan–Shirley analytic fit; Planckian illuminant; exact sRGB ↔ XYZ ↔
   CIELAB.
2. **Skin optics** (`skin.py`) — melanin-bearing epidermal sheet (modified
   Beer–Lambert) over a semi-infinite dermal slab carrying whole blood, water
   and a baseline absorber (Kubelka–Munk). Inverted through a 12,544-entry LUT
   matched in the CIELAB chroma plane, which is shading-invariant by
   construction; the luminance divided out becomes the illumination field.
3. **Quadtree** (`quadtree.py`) — subdivision on a Laplacian quantile, halos at
   35% overlap, raised-cosine partition of unity (exact to 1e-16). The guide is
   presmoothed: L\* is a cube root of luminance, so shadow noise is amplified
   enough that the near-black hand scored *higher* detail (0.180) than the
   in-focus bookshelf (0.108) until this was fixed.
4. **Probabilistic segmentation** (`probcontour.py`) — global 2-component GMM
   prior, per-leaf MAP-EM shrunk toward it, feather-fused posteriors,
   mean-field logit regularisation, marching-squares isolines. Features:
   darkness, defocus (the hand is nearest and blurred), and CIELAB residual
   against the skin locus.
5. **Band synthesis and band math** (`rsindices.py`) — per-tile dark-object
   subtraction, NDVI/NDWI/SAVI-form indices, Gram–Schmidt tasseled cap
   (Brightness / Vascularity / Hydration), and MNF, which orders components by
   SNR rather than variance — the right choice on a frame this noisy.
6. **Ridge detection** (`vessel.py`) — multiscale Frangi vesselness with a
   ridge-crest gate. Plain Frangi scored only 1.8× ridge-over-edge on a
   synthetic test because a smoothed step edge's shoulder mimics half a ridge;
   gating on Eberly's crest condition (across-ridge gradient must vanish, made
   dimensionless against curvature) raises that to 18.6×.
7. **Empirical null** (`noise.py`) — per-pixel sensor noise from a Laplacian MAD
   plus a quantisation floor, transformed to linear light through the sRGB
   slope; structure-free surrogates pushed through the *identical* chain give a
   null needing no distributional assumption. Support requires both a
   detectability index d' (modelled vein contrast over propagated index noise)
   and a photometric floor — d' alone is fooled when the LUT inversion collapses.

## Usage

```bash
pip install numpy scipy pillow matplotlib
python -m synthetic_nir.pipeline path/to/image.jpg -o out
python -c "from synthetic_nir.validate import sweep; print(sweep()[0])"
```

Options: `--max-side --max-depth --min-tile --overlap --detail-thresh --cct --fdr-q`.
Runs in ~160 s at 1400 px on one core; most of it is the noise-null resampling.

## Physical basis

Vein contrast is real and this model reproduces it: whole-blood µa at 760 nm is
25.2 cm⁻¹ deoxygenated versus 6.5 cm⁻¹ oxygenated, and the ordering reverses
above the 800 nm isosbestic point. Melanin absorption falls as λ^-3.33, dropping
about 3× from 550 to 760 nm while the haemoglobin band does not — which is why
NIR raises blood contrast relative to pigment. The model also reproduces the
known clinical limitation: reference vein index contrast falls from 0.063 to
0.017 between lightly and deeply pigmented skin.

Sources: Prahl/Gratzer haemoglobin extinction; Hale & Querry water absorption;
Jacques (1998, 2013) melanin, baseline and scattering power laws; Wyman, Sloan &
Shirley (2013) CMF fits; Frangi et al. (1998) vesselness; Benjamini & Hochberg
(1995) FDR; He, Sun & Tang guided filter.

## Caveats

- Kubelka–Munk two-flux, not Monte Carlo: relative band behaviour is sound,
  absolute reflectances are approximate.
- StO₂ is a *modelled* field, not a retrieval — visible colour cannot measure
  oxygenation through skin. It encodes one stated assumption.
- The illuminant is a Planckian approximation to mixed window light.
- Haemoglobin ε below 450 nm is coarse; blood is effectively opaque there.
- The segmentation's lower region includes some dark background adjoining the
  wrist; the eroded ROI limits but does not eliminate this.
