# Webcam + color-channel markers: prior art & sources

Research notes for the idea: replace a rolling feed scanner with a ~$100 4K autofocus
webcam, slice the (stabilized) frame into R/G/B channels, and hide ChromaTag-style /
hand-drawn markers in the RGB (digital) ↔ CMYK (physical) channels. The open question
was whether "color-printer-ink printable markers that separate cleanly in OKLAB/CIELAB"
is an existing tool or an existing research area.

**Verdict: both exist.** The exact combination you want has no off-the-shelf open-source
tool, but every piece is published, and one piece (imperceptible chroma-domain codes
printed with ordinary process inks, read by a phone camera) is a shipping commercial
product (Digimarc). The genuinely open niche is a *hackable/hand-drawable* version.

---

## 1. Directly on target: CIELAB-separable printed markers

- **ChromaTag** — DeGol, Bretl, Hoiem, ICCV 2017. Exactly the math you described:
  the marker is designed so its colors sit at known positions in the CIELAB **A**
  (red–green) and **B** (yellow–blue) opponent channels; detection scans the A channel
  (red/green adjacency is rare in natural scenes → cheap false-positive rejection) and
  uses grayscale rings for precise localization. Significantly faster than AprilTag at
  similar accuracy.
  - Paper: https://arxiv.org/abs/1708.02982
  - ICCV PDF: https://openaccess.thecvf.com/content_ICCV_2017/papers/DeGol_ChromaTag_A_Colored_ICCV_2017_paper.pdf
  - Code (research-grade C++): https://github.com/CogChameleon/ChromaTag
- **E2ETag** — end-to-end *learned* marker + detector; the network invents whatever
  colors/patterns survive the camera pipeline. Relevant if you ever want to co-optimize
  marker design against your specific printer + webcam.
  https://www.researchgate.net/publication/352104654_E2ETag_An_End-to-End_Trainable_Method_for_Generating_and_Detecting_Fiducial_Markers

## 2. The commercial existence proof: Digimarc

Digimarc Barcode embeds an imperceptible 2D code into packaging artwork as **small
chrominance deviations in individual ink channels** (including spot colors), printed
with ordinary process inks and read by ordinary phone/retail cameras. This is
"printer-ink printable, color-opponent-math separable" as a product — it works because
human vision is far less sensitive to chroma than to luminance, but a camera + math
can recover the signal.

- Chroma watermark technical brief: https://dmrcsitefinity.blob.core.windows.net/publicimages/support/digimarc-barcode-for-digital-images/dfi-chroma-technical-brief.pdf
- *Watermarking spot colors in packaging* (Digimarc research): https://www.researchgate.net/publication/283655833_Watermarking_spot_colors_in_packaging
- Product page: https://www.digimarc.com/product-digitization/data-carriers/digital-watermarks

Adjacent academic lineage: data hiding in printed **halftones** (embed bits in the dot
pattern of each ink channel, recover after print–scan) is a whole subfield, e.g.
https://pmc.ncbi.nlm.nih.gov/articles/PMC9455272/ and
https://www.sciencedirect.com/science/article/abs/pii/S092359651630114X

## 3. The "hard part" is a known-hard, well-studied problem

Classifying printed/projected colors from a camera under uncontrolled light =
**color constancy**, and the structured-light community spent a decade on it:

- Zhang, Curless, Seitz 2002 used ~8 hues in a **De Bruijn sequence** so that *context*
  (a window of neighbors) identifies each stripe even when individual hue reads are
  noisy, decoded with multi-pass dynamic programming. Survey: *Pattern codification
  strategies in structured light systems* —
  https://www.academia.edu/17609685/Pattern_codification_strategies_in_structured_light_systems
- Color classification for De Bruijn patterns via clustering (don't threshold hue;
  learn the cluster centroids your camera actually sees):
  https://www.researchgate.net/publication/290562081_Color_Classification_for_Structured_Light_of_De_Bruijn_Based_on_Clustering_Analysis
- Robustness tricks: https://link.springer.com/chapter/10.1007/978-3-540-76390-1_50

Lesson: nobody who succeeded used raw channel thresholds. Small palette (4–8 colors),
calibrated cluster centroids, redundancy/context in the code itself.

Also telling: most recent "invisible marker" research **fled the visible spectrum
entirely** because visible-chroma separation under arbitrary lighting is annoying —
InfraredTags (CHI 2022, IR-transparent 3D print, https://arxiv.org/abs/2202.06165),
iMarkers (https://arxiv.org/html/2501.15505v3), cholesteric liquid-crystal
retroreflectors (https://arxiv.org/abs/2105.05800). You're deliberately staying visible
+ cheap, which is the ChromaTag/Digimarc corner of the design space.

## 4. Designing "printable AND separable" colors: the math exists

- **Spectral prediction of printed halftones**: Roger Hersch (EPFL) — the Yule–Nielsen
  modified spectral Neugebauer model predicts the reflectance spectrum (hence LAB/OKLab
  coordinates) of any CMYK halftone combination. This is literally the forward model for
  "which CMYK mixtures land at maximally separated points in LAB."
  https://people.epfl.ch/rd.hersch/?lang=en (his security-printing work — PhotoProtect,
  metameric/fluorescent hidden images — is the same idea weaponized).
- **Practical shortcut — you don't need to implement Neugebauer**: characterize your
  printer with an ICC profile (ArgyllCMS + any cheap colorimeter, or even a printed
  chart measured by the webcam itself). The profile *is* the CMYK→LAB map; then pick a
  marker palette by maximizing pairwise ΔE (in OKLab) over the printer's gamut, subject
  to "camera can still tell them apart after Bayer-filter crosstalk."
- **OKLab** — Björn Ottosson, 2020. Fixes CIELAB's hue non-uniformity (especially blue),
  cheap to compute, now in CSS Color 4. Fine choice for the ΔE / nearest-centroid math.
  https://bottosson.github.io/posts/oklab/ · https://en.wikipedia.org/wiki/Oklab_color_space

## 5. Field-tested by people we know: Dynamicland's colored dots

Realtalk identifies paper programs by **wedges of 5 colored dots** at each corner
(~5 colors → ~600 unique pages), chosen to be classifiable under changing room light;
the CV happily accepts M&Ms and painted fingernails as dots. Existence proof that a
tiny, well-separated printed color palette + spatial code is robust enough for daily
communal use. Paper Programs is the open reimplementation.

- https://dynamicland.org/archive/2017/Dotframes
- https://tashian.com/articles/dynamicland/
- https://paperprograms.org/

## 6. Practical notes for the webcam build

1. **RGB channels ≈ CMY negatives, with crosstalk.** Yellow ink is ~invisible in the
   camera's R and G channels but dark in B; magenta shows in G; cyan shows in R. So
   "slice into R/G/B" really does give ~3 multiplexed layers from a CMY print — but
   real inks and Bayer filters leak (magenta absorbs some blue, cyan some green).
   Budget for ~3 clean channels or a 4–6 color classified palette, not 8+.
2. **Lock the camera.** Auto white balance and auto exposure will move your color
   clusters mid-session (`v4l2-ctl --set-ctrl=white_balance_automatic=0,auto_exposure=1`).
   Autofocus can stay on.
3. **Calibrate, don't assume.** Print a chart of the candidate palette, image it with
   the actual webcam in the actual room, do nearest-centroid classification in OKLab
   (optionally normalize by a white patch in frame for cheap color constancy).
4. **Put redundancy in the code, not the colors** — De Bruijn windows / checksums, à la
   structured light and Dynamicland's 5-dot wedges.
