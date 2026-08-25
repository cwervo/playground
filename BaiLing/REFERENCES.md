# References

The papers each measurement in `README.md` is built on, grouped by what they
were used for. Where a method was used and then *abandoned* because the image
violated its assumptions, that is noted — the failure is part of the result.

## Lens projection models and fisheye geometry

- **Schneider, D., Schwalbe, E. & Maas, H.-G. (2009).** "Validation of geometric
  models for fisheye lenses." *ISPRS Journal of Photogrammetry and Remote
  Sensing* 64(3):259–266.
  <https://www.sciencedirect.com/science/article/abs/pii/S0924271609000045>
  — The four classical projections (perspective `r = f·tanθ`, stereographic
  `r = 2f·tan(θ/2)`, equidistant `r = f·θ`, equisolid `r = 2f·sin(θ/2)`) tested
  by spatial resection and self-calibrating bundle adjustment. Used in
  `19_forward.py` to compute what sagitta each projection *would* produce for the
  chord geometry actually present (§4), which is how the fisheye hypothesis was
  quantified rather than asserted.

- **Şahin, C. (2016).** "Comparison and Calibration of Mobile Phone Fisheye Lens
  and Regular Fisheye Lens via Equidistant Model." *Journal of Sensors* 2016:
  9379203. <https://onlinelibrary.wiley.com/doi/10.1155/2016/9379203>
  — Establishes that most real fisheye lenses follow equidistant or equisolid
  projection, and that clip-on phone fisheye converters do too. Relevant to §3:
  a converter that produces a visible image circle also produces heavy barrel,
  which is not what §4 measures.

## Radial distortion estimation

- **Brown, D. C. (1971).** "Close-range camera calibration." *Photogrammetric
  Engineering* 37(8):855–866. — The plumb-line principle: straight world lines
  must image straight, so their departure from straightness calibrates
  distortion without a target.

- **Devernay, F. & Faugeras, O. (2001).** "Straight lines have to be straight:
  automatic calibration and removal of distortion from scenes of structured
  environments." *Machine Vision and Applications* 13(1):14–24.
  <https://dl.acm.org/doi/10.1007/PL00013269>
  — Edge extraction → polygonal approximation → distortion parameters that best
  straighten the segments. The Douglas–Peucker splitting in `24_lines.py` follows
  their approach. Their own caveat proved decisive here: *"One cannot compute
  radial distortion if all straight lines supporting the detected segments go
  through a single point in the image."* That is exactly this scene (§5).

- **Fitzgibbon, A. W. (2001).** "Simultaneous linear estimation of multiple view
  geometry and lens distortion." *CVPR 2001.* — The division model
  `p_u = p_d / (1 + λ·r²)` used throughout, chosen because straight lines map to
  circles under it, which makes the arc method below possible.

- **Strand, R. & Hayman, E. (2005).** "Correcting radial distortion by circle
  fitting." *BMVC 2005.*

- **Bukhari, F. & Dailey, M. N. (2013).** "Automatic radial distortion estimation
  from a single image." *Journal of Mathematical Imaging and Vision* 45(1):31–45.
  <https://link.springer.com/article/10.1007/s10851-012-0342-2>
  — The closed form implemented in `16_arcs.py`: for every arc, `(x₀−a)² +
  (y₀−b)² − R² = 1/λ` is the same constant, so differencing pairs linearises in
  the distortion centre. **Abandoned here**: only 4–7 of 95 chains showed any arc
  curvature, and their solutions were mutually inconsistent — this scene has too
  few genuinely curved, genuinely straight-in-the-world edges.

- **Rosten, E. & Loveland, R. (2011).** "Camera distortion self-calibration using
  the plumb-line constraint and minimal Hough entropy." *Machine Vision and
  Applications* 22(1):77–85.
  <https://link.springer.com/article/10.1007/s00138-009-0196-9>

## Vanishing points, calibration, and its degeneracies

- **Caprile, B. & Torre, V. (1990).** "Using vanishing points for camera
  calibration." *International Journal of Computer Vision* 4(2):127–139.
  — Three orthogonal vanishing points give the focal length and put the principal
  point at the orthocentre of their triangle. Section 5 rests on the converse:
  when one VP coincides with the principal point the configuration is degenerate
  and *f* is unrecoverable. The measured 151 px separation makes that the case
  here.

- **Deutscher, J., Isard, M. & MacCormick, J. (2002).** "Automatic camera
  calibration from a single Manhattan image." *ECCV 2002.*

- **Hartley, R. & Zisserman, A. (2004).** *Multiple View Geometry in Computer
  Vision*, 2nd ed., §8.6. — The constraint `v₁ᵀ K⁻ᵀK⁻¹ v₂ = 0`, rearranged in
  `25_vp2.py` into a form linear in `1/fx²` and `1/fy²` so that pinning the
  principal point makes the pixel aspect ratio observable.

## Vignetting and illumination falloff

- **Kang, S. B. & Weiss, R. (2000).** "Can we calibrate a camera using an image of
  a flat, textureless Lambertian surface?" *ECCV 2000.* — The vignetting model
  combining natural cos⁴ falloff with a tilt/mechanical term.

- **Zheng, Y., Lin, S. & Kang, S. B. (2009).** "Single-Image Vignetting
  Correction." *IEEE TPAMI* 31(12):2243–2256. — Recovering the radial
  attenuation from one image of an arbitrary scene; the reason §3 estimates the
  profile from a per-annulus high percentile rather than a mean.

- **Aggarwal, M., Hua, H. & Ahuja, N. (2001).** "On cosine-fourth and vignetting
  effects in real lenses." *ICCV 2001.* — Why real falloff departs from cos⁴,
  and what mechanical vignetting looks like. The measured flat-core-then-cliff
  profile matches neither natural falloff nor a soft mechanical shoulder.

## Sensor noise and the photon transfer curve

- **Janesick, J. R. (2007).** *Photon Transfer: DN → λ.* SPIE Press. — The
  photon transfer method itself: variance against mean signal yields conversion
  gain, read noise, and full well.

- **Healey, G. E. & Kondepudy, R. (1994).** "Radiometric CCD camera calibration
  and noise estimation." *IEEE TPAMI* 16(3):267–276.

- **Foi, A., Trimeche, M., Katkovnik, V. & Egiazarian, K. (2008).** "Practical
  Poissonian-Gaussian noise modeling and fitting for single-image raw-data."
  *IEEE TIP* 17(10):1737–1754. DOI 10.1109/TIP.2008.2001399.
  <https://pubmed.ncbi.nlm.nih.gov/18784024/>
  — `var = a·μ + b`, Poissonian photon term plus Gaussian stationary term,
  fitted from a single image with explicit clipping handling. The model fitted in
  §6, with their warning about clipping the reason the two brightest bins are
  treated as contaminated.

- **Lukáš, J., Fridrich, J. & Goljan, M. (2006).** "Digital camera identification
  from sensor pattern noise." *IEEE TIFS* 1(2):205–214. — PRNU. Not usable here:
  a single heavily recompressed and rescaled frame retains no usable fingerprint,
  which is why no device identification is attempted.

## Resampling, compression, and provenance forensics

- **Popescu, A. C. & Farid, H. (2005).** "Exposing digital forgeries by detecting
  traces of re-sampling." *IEEE Transactions on Signal Processing* 53(2):758–767.
  <https://www.semanticscholar.org/paper/Exposing-digital-forgeries-by-detecting-traces-of-Popescu-Farid/1609781b81ded3cde0d8ff960b43f3cc81c5526a>
  — Resampled signals carry periodic correlations in local prediction error. The
  basis of §2: the comb fundamental at |1 − 1/s| gives the delivered raster to
  five figures.

- **Gallagher, A. C. (2005).** "Detection of linear and cubic interpolation in
  JPEG compressed images." *CRV 2005.* — The second-difference variance is
  periodic under interpolation; the estimator used in `04_resample.py`.

- **Kirchner, M. (2008).** "Fast and reliable resampling detection by spectral
  analysis of fixed linear predictor residue." *ACM MM&Sec 2008.*

- **Fan, Z. & de Queiroz, R. L. (2003).** "Identification of bitmap compression
  history: JPEG detection and quantizer estimation." *IEEE TIP* 12(2):230–235.
  — Blocking-artefact periodicity. Extended in `07_blockgrid.py` to a
  *continuous* period scan, so a JPEG grid that has since been rescaled shows up
  at its fractional period — which is how the 1080-wide grid and the 4:2:0 chroma
  MCU were both identified.

## Chromatic aberration

- **Mallon, J. & Whelan, P. F. (2007).** "Calibration and removal of lateral
  chromatic aberration in images." *Pattern Recognition Letters* 28(1):125–135.
  — LCA as a per-channel radial warp about the optical axis.

- **Johnson, M. K. & Farid, H. (2006).** "Exposing digital forgeries through
  chromatic aberration." *ACM MM&Sec 2006.*
  <https://people.csail.mit.edu/kimo/publications/chromatic/acm06c.pdf>
  — Estimating the LCA field from a single image and using it to locate the
  optical centre. Attempted in `15_tca.py` and **reported as invalid** (§7):
  under 4:2:0 subsampling R and B both inherit the full-resolution luma, so
  R↔B phase correlation is blind to the original misregistration by construction.

## Rolling shutter and AC flicker

- **Meingast, M., Geyer, C. & Sastry, S. (2005).** "Geometric models of
  rolling-shutter cameras." *OMNIVIS 2005.*

- **Sheinin, M., Schechner, Y. Y. & Kutulakos, K. N. (2017).** "Computational
  Imaging on the Electric Grid." *CVPR 2017.*
  <https://openaccess.thecvf.com/content_cvpr_2017/papers/Sheinin_Computational_Imaging_on_CVPR_2017_paper.pdf>

- **Sheinin, M., Schechner, Y. Y. & Kutulakos, K. N. (2018).** "Rolling Shutter
  Imaging on the Electric Grid." *ICCP 2018.*
  <https://www.cs.toronto.edu/~kyros/pubs/18.iccp.rolling-ac.pdf>
  — AC bulbs flicker at twice mains; a rolling shutter prints that as a
  spatiotemporal wave encoding capture time, bulb response, and grid phase. The
  banding test in §7 looks for exactly that signature and finds none (peak
  Q = 0.5, and the column spectrum peaks harder than the row spectrum), so no
  line readout time is claimed.

## Fitting machinery

- **Taubin, G. (1991).** "Estimation of planar curves, surfaces and nonplanar
  space curves defined by implicit equations." *IEEE TPAMI* 13(11):1115–1138.
  — The unbiased algebraic circle fit used on short arcs in `16_arcs.py`.

- **Fitzgibbon, A., Pilu, M. & Fisher, R. B. (1999).** "Direct least square
  fitting of ellipses." *IEEE TPAMI* 21(5):476–480. — The constrained conic fit
  in `09_support.py`, superseded by the level-set fit in `10_levelset.py` once
  ray-traced boundary points proved too noisy (31 px rms).

- **Fischler, M. A. & Bolles, R. C. (1981).** "Random sample consensus." *CACM*
  24(6):381–395.
