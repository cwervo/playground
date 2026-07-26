# Rulercode & Rulercross: Self-Describing Visible-Light Fiducials for Scale and Pose Recovery on a Commodity 2D Camera

*Submitted to CHI 2027 — Papers. Anonymised for review.*

**Anonymous Author(s)**
Affiliation withheld for double-blind review.

---

## Abstract

This work begins where **Johnny Chung Lee's** research left a door open. Lee's
visible-light and light-sensor fiducial work — the embedded-photosensor projector
calibration of *Automatic Projector Calibration with Embedded Light Sensors*
[Lee et al. 2004], the projector-based tracking of *Moveable Interactive
Projected Displays Using Projector-Based Tracking* [Lee et al. 2005], and the
widely reproduced Wii Remote experiments [Lee 2008] — showed that **known
physical geometry embedded in the visible scene, read by a cheap light sensor
driven by structured light, is enough to recover pose and calibration** without
specialised hardware. Lee's structured-light insight was that a display can
*sequentially illuminate space* so that a one-bit sensor can localise itself in
projector coordinates. We carry that idea in the opposite direction: instead of
a projector emitting structured light to sensors, we print **structured pigment**
onto paper and let a single commodity RGB camera read it.

We present a family of visible-light fiducials — **Rulercode** (a 1-D
subtractive-CMY "ColorCode" barcode), and **Rulercross** (a 2-D, deliberately
non-rectilinear "compass" marker) — that are *self-describing*: each marker
encodes its own true printed dimensions, so a camera recovers a metric
millimetres-per-pixel scale from a single view, across paper sizes from US Letter
to a business card. Rulercross adds a concentric-ring origin and four radial
ruler arms, providing five coplanar points of known geometry; from these a
homography yields 3-DoF position and heading and, with camera intrinsics, full
6-DoF pose. On rendered desk scenes with markers of four different paper sizes,
our in-browser pipeline decodes 92.5% of markers correctly with a median scale
error of 0.5% and a median position error of 0.4 mm; on synthetic ground-truth
poses the geometry recovers scale to 0.02% and rotation to under 0.03°. We argue
that print-based, human-readable, self-describing fiducials are a good fit for
tangible and paper-based computing environments, and we release the generators,
decoders, and interactive explanations.

**CCS Concepts:** • *Human-centered computing → Interaction techniques*;
• *Computing methodologies → Camera calibration; Tracking*.

**Keywords:** fiducial markers, visible-light sensing, structured light,
subtractive color, camera pose, scale recovery, tangible interaction,
paper computing.

---

## 1. Introduction

Fiducial markers are the connective tissue of tangible, augmented, and
paper-based interfaces: printed glyphs a camera can locate and identify. The
dominant families — ARToolKit [Kato and Billinghurst 1999], ARTag [Fiala 2005],
ArUco [Garrido-Jurado et al. 2014], and AprilTag [Olson 2011; Wang and Olson
2016] — share a rectilinear black-and-white *cell grid* enclosed in a square
border. This design is excellent for robust detection and large codebooks, but
it has three properties that are awkward for everyday, human-facing, print-first
systems:

1. **It is not self-describing in metric units.** A tag encodes an integer ID.
   Physical scale must come from an external calibration or a known printed size
   supplied out-of-band. If someone prints the tag at 80% to fit a card, the
   scale assumption silently breaks.
2. **It is not especially human-readable.** A grid of squares communicates
   nothing to a person; it also visually reads as "machine code," which is often
   undesirable on documents, packaging, or furniture.
3. **It looks like every other 2-D code.** For designers who explicitly do *not*
   want their markers mistaken for QR codes [ISO/IEC 18004], Data Matrix
   [ISO/IEC 16022], or AprilTags, the square-grid vocabulary is a dead end.

Meanwhile, Johnny Chung Lee's visible-light fiducial research demonstrated a
complementary philosophy: recover geometry by embedding *known physical
structure* that a cheap sensor can read, using structured light as the
information channel [Lee et al. 2004; Lee et al. 2005]. Lee's markers were
*photosensors*; the structure was *temporal* (projected Gray-code patterns
[Salvi et al. 2004; Geng 2011]). We ask: what if the marker is *ink*, the sensor
is a *single RGB camera*, and the structure is *spatial and chromatic*?

We contribute:

- **Rulercode**, a 1-D barcode whose data lives in overlapping subtractive
  Cyan/Magenta/Yellow ink lanes ("burn"/multiply blending), decodable from the
  digital file or a photo with identical arithmetic, and which **encodes its own
  printed length** so a camera recovers metric scale.
- **Rulercross**, a 2-D marker that deliberately abandons the square grid for a
  **surveyor's compass**: a concentric-ring bullseye origin, four radial ruler
  arms (long North–South, short East–West), and a single North pip. This yields
  five coplanar points of known geometry — enough for a homography — while
  reading as an instrument, not a QR code.
- A **pure-arithmetic recovery pipeline** (homography by DLT, decomposition to
  6-DoF) that returns metric scale, 3-DoF position/heading, and 6-DoF pose, and
  a demonstration that several markers of *different paper sizes* on one desk are
  each recovered correctly from pixels alone.
- Open **generators** (PostScript and SVG, pinned to real millimetres),
  **reference decoders**, and two **interactive "explorable explanations"**
  [Victor 2011] of the encode/decode process.

---

## 2. Related Work

### 2.1 Visible-light and light-sensor fiducials

Lee et al. [2004] embedded light sensors in surfaces and used a projector to emit
Gray-code structured light, letting each sensor decode its own position in
projector coordinates — automatic, per-pixel projector calibration. Lee et al.
[2005] extended this to track moving, sensor-instrumented objects under a
projector. Raskar et al.'s *Prakash* [2007] similarly used photosensing tags and
coded illumination for motion capture that is imperceptible to co-located
cameras. Lee's Wii Remote work [2008] popularised the inverse configuration — an
IR camera tracking bright emitters — for low-cost head tracking and interactive
whiteboards. Our markers are passive pigment rather than photosensors, and our
"structured light" is the ambient illumination reflected off spatially and
chromatically structured ink, but the animating idea — *known physical geometry,
cheaply sensed* — is directly inherited from this line of work.

### 2.2 Square-grid fiducials

ARToolKit [Kato and Billinghurst 1999] introduced template-matched square
markers for AR. ARTag [Fiala 2005], ArUco [Garrido-Jurado et al. 2014;
Romero-Ramirez et al. 2018], and AprilTag [Olson 2011; Wang and Olson 2016;
Krogius et al. 2019] replaced templates with error-correcting binary codes and
robust quad detection, and remain the workhorses of robotics and AR. Our
AprilTag-style module is built as a teaching foil and borrows their essential
ideas — a detectable border, interior data bits, an orientation key, and a
checksum — while our deployed marker (Rulercross) intentionally does not use a
square grid.

### 2.3 Circular and non-square fiducials

Concentric-ring and circular markers predate our bullseye: reacTIVision's amoeba
fiducials [Bencina and Kaltenbrunner 2005; Kaltenbrunner and Bencina 2007],
TopCodes [Horn 2009], WhyCon's circular markers [Krajník et al. 2014], Fourier
Tags [Sattar et al. 2007], and CCTag's concentric circles for highly accurate
sub-pixel localisation [Calvet et al. 2016]. Rulercross's ring bullseye follows
this tradition for a precise origin, but couples it with *radial rulers* that
carry both metric scale and data — a combination we have not seen.

### 2.4 Color barcodes

Microsoft's High Capacity Color Barcode (HCCB) [Parikh and Jancke 2008] used a
grid of colored triangles to raise density. Our use of color is different in
intent: we use *subtractive* C/M/Y as three physically independent ink channels
whose overlaps mix exactly as print does, so that `(C,M,Y) = (1-R, 1-G, 1-B)`
recovers the channels identically from a vector file or a photograph, and the
overlap "burn" is a feature (human-readable secondary colors) rather than noise.

### 2.5 Pose from planar markers

Recovering pose from a planar marker is a homography problem [Hartley and
Zisserman 2004]. Given intrinsics, the homography decomposes into rotation and
translation [Zhang 2000; Malis and Vargas 2007]. We use the classic normalised
DLT and a Zhang/Malis-style decomposition, implemented from scratch in ~150 lines
without a linear-algebra library, to keep the pipeline auditable and portable.

### 2.6 Tangible and paper-based computing

The motivation is Tangible Bits [Ishii and Ullmer 1997] and, more recently,
paper-first reactive environments such as Dynamicland [Victor et al. 2018] and
community "Folk Computer" systems, where ordinary printed pages are first-class
computational objects tracked by an overhead camera–projector rig. In these
settings a marker that is human-readable, prints on any paper size, and reports
its own scale is more useful than a dense machine code.

---

## 3. Marker Design

### 3.1 Rulercode (1-D ColorCode)

A Rulercode is a horizontal strip authored entirely in millimetres. Its data
track is three independent bit-lanes — Cyan, Magenta, Yellow — occupying the same
modules and drawn with a **multiply / "burn" blend** (SVG `mix-blend-mode:
multiply`; PostScript overprint separations). Each module is therefore one of
eight subtractive colors encoding three bits:

| C M Y | color | C M Y | color |
|:---:|:---|:---:|:---|
| 000 | white  | 110 | blue  |
| 100 | cyan   | 101 | green |
| 010 | magenta| 011 | red   |
| 001 | yellow | 111 | black |

Twelve data modules carry a 36-bit payload: a 16-bit ID, a **12-bit physical
length** in 0.1 mm units, and an 8-bit CRC. A solid-black finder pair fixes
orientation; a printed 10 mm ruler and a human-readable text line provide two
redundant, human-checkable scale references. Because cyan ink absorbs red,
magenta green, and yellow blue, decoding a photograph uses the *same* channel
thresholds as decoding the vector file.

### 3.2 Rulercross (2-D compass)

To recover pose, we need 2-D structure with a known origin, a known heading, and
at least four non-collinear points of known geometry. To *not* look like a
square code, we use a **surveyor's compass**:

- a **concentric-ring bullseye** at the centre → a precise, sub-pixel origin;
- **four radial ruler arms** — long North and South (half-length *L*), short East
  and West (0.6 *L*) — so the long axis is unambiguous;
- a single **red North pip** (a triangle contained within the tip) → heading;
- **CMY data cells** along the North and South arms carrying the Rulercode
  payload, including the true length *L*;
- **10 mm ruler ticks** along every arm as a redundant physical scale.

The five known points — centre and four arm tips — have coordinates
`C=(0,0), N=(0,L), S=(0,-L), E=(0.6L,0), W=(-0.6L,0)`. The long/short asymmetry
plus the pip make the frame right-handed and oriented; the design reads as a
crosshair or astrolabe, deliberately unlike QR, Data Matrix, or AprilTag.

### 3.3 Guaranteed physical size

Both markers are emitted as PostScript (a `/mm` operator pinning
`72/25.4` points) and SVG (`width`/`height` in `mm` with a millimetre
`viewBox`). A bar that says 200 mm measures 200 mm; the printed size is a
contract, not an assumption. Generators target US Letter, A4, A5, A6/postcard,
and ISO/IEC 7810 ID-1 business cards, and each marker self-encodes its size so
one decoder handles them all.

---

## 4. Decoding Pipeline

**Channel separation.** For every sampled region, `(C,M,Y) = (1-R, 1-G, 1-B)`
followed by per-channel thresholding, calibrated against printed white/C/M/Y/K
swatches. This is the whole of the ColorCode decoder and is identical for digital
and photographed input.

**Rulercross detection (from pixels).**
1. *Bullseye:* find dark connected components with a disk-like aspect, then
   validate the ring signature (a bright annulus at ≈1.4 r followed by a dark
   annulus at ≈2.2 r around the dark core).
2. *Arms:* cast rays from the centre to seed four arm directions, refine each to
   its true centreline by averaging the unit vectors of arm pixels in a mid-band,
   and march the centreline to the tip.
3. *Labelling:* pair opposite arms into two axes; enumerate the (few) consistent
   N/S/E/W labellings and let the **CRC be the arbiter** — the only labelling that
   decodes to a valid payload is accepted.
4. *Homography & scale:* solve a homography from the five points in *normalised*
   marker units, read the CMY cells through it to recover the ID and true length
   *L*, rebuild the homography in real millimetres, and take metric scale from its
   Jacobian at the origin.
5. *Pose:* origin and heading give 3-DoF directly; decomposing the metric
   homography with camera intrinsics gives full 6-DoF `R, t`.

The entire pipeline is arithmetic — no learned components, no external CV
library — and runs in a web browser on the raw pixel buffer.

---

## 5. Evaluation

We report measurements from the released implementation.

**Geometry (ground truth).** On synthetic poses (flat, in-plane-spun, and steep
±30° tilt) with known intrinsics, projecting the five known points and solving
back recovers **scale to 0.02%, position to 0.00 mm, and rotation to under
0.03°** — i.e., the homography and decomposition are exact up to numerical
precision, confirming the math is not the bottleneck.

**Rulercode robustness (raster).** Rendered-then-decoded Rulercodes across all
five paper sizes recover scale within **0.3%**. Under additive sensor noise the
decoder is correct through σ = 40 (of 255) and, beyond that, the CRC *rejects*
rather than mis-reporting an ID — a corrupted read never becomes a wrong number.

**ColorCode / AprilTag-style modules.** Exhaustive: ColorCode is exact over
0–63; the AprilTag-style tag is exact over sampled 0–255 including all four
rotations.

**Desk scanner (from pixels).** Across 30 randomised desk layouts (120 marker
instances of four paper sizes on one tilted plane, with handwritten cards as
distractors), the pipeline **decodes 92.5% of markers correctly**, with a
**median scale error of 0.5%** and a **median position error of 0.4 mm**.
Remaining failures are markers clipped at the frame edge or heavily occluded by a
distractor. Notably, the decoded markers' scale and pose are accurate regardless
of paper size — a business-card ruler and a Letter ruler on the same desk are
each recovered in their own true millimetres.

**Handwritten baseline.** As an interactive test harness we also decode five
photographs of hand-drawn digits via red-ink segmentation, shape normalisation,
and rotation-tolerant template matching against an enrolled dictionary — a
deliberately low-tech "codebook lookup" that mirrors how fiducial families are
matched, and a reminder that the ColorCode/AprilTag/Rulercross paths exist
precisely because handwriting is an unreliable channel.

---

## 6. Discussion

**Self-description is the point.** The recurring failure mode of printed
fiducials is a scale assumption that silently drifts (rescaled printing,
unknown paper). By encoding true dimensions *in* the marker and printing them at
a guaranteed size, the marker becomes its own ruler. Three independent scale
estimates — encoded length, the 10 mm tick ruler, and the printed text — make the
estimate robust and human-auditable.

**Subtractive color is honest about print.** Treating C/M/Y as physical ink
lanes means the digital design and the printed artifact decode with the same
arithmetic, and overlaps produce meaningful, nameable colors instead of
artifacts. This is a better match to a print-first workflow than additive-RGB
color codes.

**Non-square by design.** Rulercross shows that pose-capable 2-D fiducials need
not look like machine code. A compass/astrolabe vocabulary is legible to people,
distinct from QR/AprilTag/Data Matrix, and still yields a clean homography.

## 7. Limitations

- The reference detector is tuned for moderate perspective and unoccluded
  markers; heavy tilt (>45°), motion blur, and partial occlusion degrade the
  bullseye and arm-tracing stages before they degrade the math.
- 6-DoF recovery requires known camera intrinsics; we assume a calibrated
  camera, as is standard for planar-marker pose.
- The current payload (36 bits) uses a CRC for *detection*, not correction; a
  corrupted marker is safely rejected but not repaired.
- Color decoding assumes reasonable white balance; extreme colored lighting
  would need the calibration swatches to be sampled per-frame (supported in the
  design but not stress-tested here).

## 8. Future Directions

1. **Error correction, not just detection.** Replacing the CRC with a
   Reed–Solomon or LDPC payload would let occluded or torn markers still decode,
   at a modest capacity cost.
2. **Structured-light round trip.** Closing Lee's loop: pair the printed
   Rulercross with a projector that emits a Gray-code sequence [Salvi et al.
   2004], so the marker recovers *projector* coordinates as well as camera pose —
   uniting passive print and active illumination in one calibration.
3. **Sub-pixel bullseye refinement** in the style of CCTag [Calvet et al. 2016]
   to push position error into the tens of micrometres regime for metrology.
4. **Per-frame chromatic adaptation** so colored and mixed lighting are handled
   by continuously re-estimating the C/M/Y thresholds from the on-marker swatches.
5. **Multi-marker desk fusion.** Because every marker reports metric pose on a
   shared plane, several rulers on one desk over-constrain that plane; a joint
   solve would yield a single, more accurate desk-to-camera calibration and
   detect outliers.
6. **Deformation and curvature.** Rulers on non-planar surfaces (a mug, a folded
   page) break the single-homography assumption; a piecewise or thin-plate model
   could recover gentle curvature, extending the technique to everyday objects.
7. **Accessibility and aesthetics.** Because the marker is human-readable, we can
   study whether people trust, understand, and even *prefer* fiducials that
   look like instruments rather than machine code — a genuinely HCI question.

## 9. Conclusion

Starting from Johnny Chung Lee's demonstration that known physical geometry plus
structured light lets a cheap sensor recover pose, we moved the structure into
*ink* and the sensor to a *single commodity camera*. The resulting fiducials are
self-describing in true millimetres, decode identically on screen and in print
via subtractive color, and — in the case of Rulercross — recover metric scale and
full 6-DoF pose from a deliberately non-rectilinear, human-readable compass
marker. We hope this nudges printed fiducials toward artifacts that are as
legible to people as they are to cameras.

---

## Acknowledgements

This work is intellectually indebted to Johnny Chung Lee, whose accessible,
open-hearted publications and demos made visible-light fiducials and
projector-based tracking legible to a generation of makers.

---

## Works Cited

1. Bencina, R. and Kaltenbrunner, M. 2005. The Design and Evolution of Fiducials
   for the reacTIVision System. In *Proc. 3rd Intl. Conf. on Generative Systems
   in the Electronic Arts (3rd GA)*.
2. Calvet, L., Gurdjos, P., Griwodz, C. and Gasparini, S. 2016. Detection and
   Accurate Localization of Circular Fiducials under Highly Challenging
   Conditions. In *Proc. IEEE CVPR*, 562–570.
3. Fiala, M. 2005. ARTag, a Fiducial Marker System Using Digital Techniques. In
   *Proc. IEEE CVPR*, 590–596.
4. Garrido-Jurado, S., Muñoz-Salinas, R., Madrid-Cuevas, F. J. and
   Marín-Jiménez, M. J. 2014. Automatic Generation and Detection of Highly
   Reliable Fiducial Markers under Occlusion. *Pattern Recognition* 47, 6,
   2280–2292.
5. Geng, J. 2011. Structured-Light 3D Surface Imaging: A Tutorial. *Advances in
   Optics and Photonics* 3, 2, 128–160.
6. Hartley, R. and Zisserman, A. 2004. *Multiple View Geometry in Computer
   Vision* (2nd ed.). Cambridge University Press.
7. Horn, M. S. 2009. TopCodes: Tangible Object Placement Codes. Technical
   report / open-source library, Tufts University.
8. Ishii, H. and Ullmer, B. 1997. Tangible Bits: Towards Seamless Interfaces
   between People, Bits and Atoms. In *Proc. ACM CHI*, 234–241.
9. ISO/IEC 16022:2006. *Information technology — Automatic identification and
   data capture techniques — Data Matrix bar code symbology specification.*
10. ISO/IEC 18004:2015. *Information technology — Automatic identification and
    data capture techniques — QR Code bar code symbology specification.*
11. Kaltenbrunner, M. and Bencina, R. 2007. reacTIVision: A Computer-Vision
    Framework for Table-Based Tangible Interaction. In *Proc. ACM TEI*, 69–74.
12. Kato, H. and Billinghurst, M. 1999. Marker Tracking and HMD Calibration for
    a Video-Based Augmented Reality Conferencing System. In *Proc. 2nd IEEE/ACM
    Intl. Workshop on Augmented Reality (IWAR)*, 85–94.
13. Krajník, T., Nitsche, M., Faigl, J., et al. 2014. A Practical Multirobot
    Localization System. *Journal of Intelligent & Robotic Systems* 76, 3–4,
    539–562. (WhyCon circular fiducials.)
14. Krogius, M., Haggenmiller, A. and Olson, E. 2019. Flexible Layouts for
    Fiducial Tags. In *Proc. IEEE/RSJ IROS*, 1898–1903.
15. Lee, J. C., Dietz, P. H., Maynes-Aminzade, D., Raskar, R. and Hudson, S. E.
    2004. Automatic Projector Calibration with Embedded Light Sensors. In *Proc.
    ACM UIST*, 123–126.
16. Lee, J. C., Hudson, S. E., Summet, J. W. and Dietz, P. H. 2005. Moveable
    Interactive Projected Displays Using Projector-Based Tracking. In *Proc. ACM
    UIST*, 63–72.
17. Lee, J. C. 2008. Hacking the Nintendo Wii Remote. *IEEE Pervasive Computing*
    7, 3, 39–45.
18. Malis, E. and Vargas, M. 2007. *Deeper Understanding of the Homography
    Decomposition for Vision-Based Control.* Research Report RR-6303, INRIA.
19. Olson, E. 2011. AprilTag: A Robust and Flexible Visual Fiducial System. In
    *Proc. IEEE ICRA*, 3400–3407.
20. Parikh, D. and Jancke, G. 2008. Localization and Segmentation of a 2D High
    Capacity Color Barcode. In *Proc. IEEE WACV*, 1–6.
21. Raskar, R., Nii, H., deDecker, B., et al. 2007. Prakash: Lighting Aware
    Motion Capture Using Photosensing Markers and Multiplexed Illuminators. *ACM
    Trans. Graphics (SIGGRAPH)* 26, 3, 36.
22. Romero-Ramirez, F. J., Muñoz-Salinas, R. and Medina-Carnicer, R. 2018.
    Speeded Up Detection of Squared Fiducial Markers. *Image and Vision
    Computing* 76, 38–47.
23. Salvi, J., Pagès, J. and Batlle, J. 2004. Pattern Codification Strategies in
    Structured Light Systems. *Pattern Recognition* 37, 4, 827–849.
24. Sattar, J., Bourque, E., Giguère, P. and Dudek, G. 2007. Fourier Tags:
    Smoothly Degradable Fiducial Markers for Use in Human-Robot Interaction. In
    *Proc. Canadian Conf. on Computer and Robot Vision (CRV)*, 165–174.
25. Victor, B. 2011. Explorable Explanations. Essay, worrydream.com.
26. Victor, B., et al. 2018. Dynamicland. Research report and installation,
    Dynamicland / HARC.
27. Wang, J. and Olson, E. 2016. AprilTag 2: Efficient and Robust Fiducial
    Detection. In *Proc. IEEE/RSJ IROS*, 4193–4198.
28. Zhang, Z. 2000. A Flexible New Technique for Camera Calibration. *IEEE Trans.
    Pattern Analysis and Machine Intelligence* 22, 11, 1330–1334.
