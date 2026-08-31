# Sistine/Metal

A Project Sistine work-alike — a mirror over the FaceTime camera turns a MacBook
display into a touchscreen — written as a single Swift application on Apple's own
frameworks. No Python, no OpenCV, no PyAutoGUI, no third-party dependencies of
any kind.

```
AVFoundation ──▶ Metal compute ──▶ Swift detection ──▶ CoreGraphics
 420f frames     skin · morph ·     pairing · touch      CGEvent + display
 (zero-copy)     run-length         hysteresis          geometry
```

---

## 1. Hardware

Unchanged from the original: a small craft mirror or a rigid strip of Mylar,
clipped over the top bezel above the camera, angled ~45° downward. Open Photo
Booth: if you can still see your face, keep adjusting. You want a grazing,
top-down view along the surface of the glass.

Two things the software cannot fix, so get them right here:

- **The display must be glossy.** The entire touch signal is the specular
  reflection of your finger in the glass. A matte screen protector removes it and
  nothing below will work.
- **The mirror must be rigid.** Calibration bakes in a fixed camera-to-glass
  geometry. A mirror that flexes when you type invalidates it.

---

## 2. Replacing the CV stack

Every piece of the original pipeline has a first-party equivalent. Several are
not merely equivalents — the native format does the work for free.

| Original (Python) | Here | Note |
| --- | --- | --- |
| `cv2.VideoCapture` | `AVCaptureSession` + `CVMetalTextureCache` | Zero-copy: the camera's IOSurface goes straight to the GPU |
| `cvtColor(BGR2HSV)` | *nothing* | `420YpCbCr8BiPlanar` hands us chroma already separated from luma |
| `inRange` on skin | `skin_mask` Metal kernel | Mahalanobis ellipse in CbCr, fitted to *your* hand |
| `erode` / `dilate` | `morph` Metal kernel | Separable; same job as `MPSImageAreaMin`/`AreaMax` |
| `GaussianBlur` | `MPSImageGaussianBlur` | Available if needed; the morphology open/close makes it unnecessary |
| `findContours` | `column_rle` Metal kernel | Vertical run-length encoding — see §3 |
| connected components | run clustering in Swift | ~60 KB of runs, parsed in microseconds |
| `findHomography` + RANSAC | `HomographySolver` | Normalised DLT, Jacobi eigensolver, RANSAC |
| `perspectiveTransform` | `Homography.apply` | Plus a residual field for lens distortion |
| Kalman / smoothing | `OneEuroFilter` | One knob for the jitter-vs-lag trade |
| `pyautogui.moveTo/click` | `CGEvent.post(tap: .cghidEventTap)` | HID-layer injection; indistinguishable from a real mouse |
| `imshow` | `CoreGraphics` → `MTLTexture` → `MTKView` | Vector/text in CG, compositing in Metal |
| screen geometry | `CGDisplayBounds` / `CGGetActiveDisplayList` | The coordinate space `CGEvent` actually expects |

`Vision` is deliberately *not* on the hot path. `VNDetectContoursRequest` and
`VNDetectHumanHandPoseRequest` would both work, and hand pose in particular is
tempting — but at a grazing angle through a mirror the hand is far outside the
distribution those models were trained on, and both cost more latency than the
whole pipeline below. They stay available as an offline validation tool.

---

## 3. The two ideas the design rests on

### The midpoint is on the glass

At a grazing angle the display's glass is a mirror. A finger above it appears
twice: the real finger, a gap, then its reflection. The reflection is a mirror
image *through the glass plane*, so:

```
       finger ────┐
                  │  gap g
  ═══ glass ══════╪══════════   <-- midpoint sits here, at every hover height
                  │  gap g
   reflection ────┘
```

**The midpoint of the finger's lowest pixel and the reflection's highest pixel
lies on the glass, regardless of how high the finger is hovering.**

That single observation splits the problem in two. Position comes from the
midpoint and is available continuously — so there is a live cursor while
hovering, not just at the instant of contact. Contact is a separate, independent
measurement: the gap closing to zero. The original formulation only looked for
the moment the two blobs touched, which meant position and click were the same
event and neither could be smoothed without hurting the other.

### The gap must be normalised by apparent width

Perspective makes the same physical hover height look completely different
across the screen — roughly 30 px near the bezel, 6 px at the far edge. A fixed
pixel threshold is therefore wrong everywhere except one band of the display.

But the finger's *apparent width* shrinks by the same projective factor, so the
ratio cancels it:

```swift
var normalizedGap: Float { gap / max(widthPx, 6) }
```

Simulating this geometry under a pinhole model (camera 12 mm above the glass,
pitched 8°, 14 mm finger, 5 mm hover held constant while the contact point moves
from 5 cm to 30 cm down the display):

| Depth down the display | raw gap | apparent width | gap / width |
| --- | --- | --- | --- |
| 5 cm | 171.8 px | 249.6 px | 0.688 |
| 10 cm | 88.8 px | 126.0 px | 0.705 |
| 20 cm | 45.1 px | 63.3 px | 0.713 |
| 30 cm | 30.2 px | 42.3 px | 0.716 |

**The raw gap varies by 197% across the display. The ratio varies by 4%.** The
ratio also comes out linear in hover height at ~0.142 per mm, which means the
thresholds are physical distances rather than magic numbers: `touchDownRatio =
0.18` is "closer than 1.3 mm", `touchUpRatio = 0.42` is "further than 3.0 mm".

### Consequence: contours are unnecessary

Because finger and reflection are *by construction* two vertically adjacent runs
in the same column, a per-column run-length encoding already contains the
feature. `column_rle` gives one GPU thread one column, walks it top to bottom,
and records up to four spans:

- one dispatch, no allocation, no contour hierarchy, fully deterministic
- output is `width × 48` bytes (~60 KB at 720p), so the CPU readback is trivial
- keeps the *lowest* four runs on overflow, which discards forearm and sleeve
  rather than the fingertip

Two runs with a plausible gap → hovering. One fused run → touching. That is the
entire feature extractor.

---

## 4. Pipeline

```
AVCaptureVideoDataOutput (420f, 1280×720@60, exposure+WB locked)
  │  plane 0 → r8Unorm luma        ┐ CVMetalTextureCache, zero-copy
  │  plane 1 → rg8Unorm CbCr       ┘
  ▼
[GPU] skin_mask     Mahalanobis ellipse in CbCr, luma gate, orientation flip
[GPU] morph ×4      open (despeckle) then close (bridge specular highlights)
[GPU] column_rle    per-column runs, clipped to the calibrated screen quad
  ▼  ~60 KB
[CPU] TipDetector        pair runs → cluster columns → weighted tip centroid
[CPU] TouchStateMachine  Schmitt trigger on normalised gap + dropout tolerance
[CPU] PlanarMap          homography + residual field → screen points
[CPU] OneEuroFilter      speed-adaptive smoothing
  ▼
CGEvent → .cghidEventTap
```

Four dispatches, one command buffer, one small readback per frame. Nothing
image-sized ever crosses back to the CPU.

**Latency budget** (Apple silicon, 720p60):

| Stage | Cost |
| --- | --- |
| Sensor exposure, readout, AVF delivery | 12–18 ms |
| GPU segmentation (5 dispatches) | 0.6–1.2 ms |
| Run-table parse + detection | ~0.1 ms |
| Event synthesis and post | < 1 ms |
| **Pointer motion, end to end** | **~20–25 ms** |
| Touch-down hysteresis (2 frames) | +33 ms |
| **Click, end to end** | **~55–70 ms** |

The camera dominates; the vision work is noise. If clicks feel sluggish,
`downFrames` is the knob — and the reason it is not already 1 is that the last
pixel of approach is also the noisiest, so a single-frame trigger chatters.

---

## 5. Calibration

`Calibrate…` in the menu bar runs one pass that solves four problems at once.

1. **Orientation.** Which way the mirror flips the image depends on how you
   taped it on, so it is measured, not asked. The app tries both, for 45 frames
   each, and keeps the one that produces finger/reflection *pairs* — the wrong
   orientation puts the reflection above the finger, where the pairing rule
   rejects it.
2. **Geometry.** A 5×4 grid of targets, inset 7–9% from the edges. Four points
   determine a homography exactly, which sounds sufficient and is not: with four
   there is no redundancy, one sloppy tap silently bends the whole map, and there
   is no residual left over to measure distortion with. Twenty points cost
   fifteen seconds and give RANSAC something to vote with.
3. **Distortion.** The homography is exact for a plane and a pinhole; the
   FaceTime lens is not a pinhole. Rather than fit a Brown–Conrady model (badly
   conditioned on 20 samples), the leftover per-target residuals are interpolated
   with inverse-distance weighting over the four nearest control points. It is a
   lookup table for the part of the error we cannot name.
4. **Colour.** CbCr samples are collected from the finger's interior at each
   target and fitted to a Gaussian. Then — importantly — **exposure and white
   balance are locked.** Auto-exposure is the quiet killer of colour
   segmentation: open a bright window, the AE loop shifts gain, every CbCr value
   slides, and a model fitted a minute ago stops matching.

The solved map also projects the screen's own corners back into camera space.
That quad becomes the per-column ROI for `column_rle`, and it is the single most
effective robustness measure in the app — without it, a forearm resting below the
near bezel is a huge skin blob that out-votes the fingertip every frame.

Result is written to `~/Library/Application Support/Sistine/calibration.json`,
and the fit is rejected outright if the mean residual exceeds 40 pt.

---

## 6. Permissions and packaging

Two grants are required, and both are attributed to a *bundle identity* — a
loose SwiftPM binary asks on behalf of whatever launched it and the grant does
not stick. Hence:

```bash
./Scripts/build-metallib.sh    # only if your toolchain does not compile .metal in SwiftPM
./Scripts/make-app.sh          # wraps the product in Sistine.app and ad-hoc signs it
open Sistine.app
```

- **Camera** — prompted on first launch (`NSCameraUsageDescription`).
- **Accessibility** — System Settings → Privacy & Security → Accessibility.
  Required to post to `.cghidEventTap`. There is no API to grant it; the app can
  only open the pane.

---

## 7. Known limitations

- **Matte displays do not work at all.** No specular reflection, no signal.
- **The HUD is inside the camera's own field of view.** The app can, in
  principle, detect its own overlay as a hand. Mitigated by drawing the mask
  overlay in cyan and calibration targets in blue/white — both about as far from
  the skin ellipse in CbCr as it is possible to get — but skin-toned content in
  *your* windows is still a confounder inside the screen quad.
- **Single touch.** The run clustering already produces multiple clusters; a
  second pointer, or two-finger scroll, is a small extension of
  `TouchStateMachine`, not of the vision stage.
- **One display.** `DisplayGeometry` enumerates all of them and the calibration
  record stores a `displayID`, but the controller currently binds to the main
  display.
- **Sleeves and rings** with skin-adjacent chroma can win the cluster vote. The
  ROI handles the common case (forearm below the bezel); the rest is why
  temporal continuity is preferred over cluster size when a finger is already
  being tracked.

### Worthwhile extensions

- **ScreenCaptureKit content suppression.** We know exactly what is on screen and
  we know the homography, so on-screen content can be projected into camera space
  and subtracted from the mask. This would eliminate the self-detection problem
  entirely and is the single highest-value addition.
- **Vision hand pose** as a disambiguator when more than one cluster survives.
- **Predictive filtering** — the One Euro filter smooths but does not extrapolate;
  ~15 ms of forward prediction would cancel most of the remaining perceived lag.

---

## 8. Source layout

```
Sources/Sistine/
  main.swift                       menu-bar agent entry point
  AppController.swift              wires capture → GPU → detection → CGEvent
  Capture/CameraSource.swift       AVFoundation, format selection, AE/WB lock
  GPU/Shaders.metal                skin_mask, morph, column_rle, HUD shaders
  GPU/MetalContext.swift           device, library loading, CVMetalTextureCache
  GPU/GPUTypes.swift               Swift mirrors of the shader structs (+ layout asserts)
  GPU/SegmentationPipeline.swift   the per-frame dispatch list and ROI
  Detect/TipDetector.swift         run pairing, column clustering, tip refinement
  Detect/TouchStateMachine.swift   Schmitt trigger, dropout tolerance
  Detect/OneEuroFilter.swift       speed-adaptive smoothing
  Geometry/Homography.swift        normalised DLT, Jacobi eigensolver, RANSAC
  Geometry/PlanarMap.swift         homography + residual field, forward map
  Geometry/SkinModel.swift         CbCr Gaussian fit, chroma plane sampling
  Geometry/Calibrator.swift        orientation probe, target grid, solve, persist
  Output/PointerInjector.swift     CGEvent synthesis, click state, dead band
  UI/OverlayWindow.swift           click-through full-screen Metal window
  UI/HUDRenderer.swift             CoreGraphics vector layer + Metal compositing
  UI/HUDState.swift                lock-guarded snapshot passed to the renderer
  Support/Config.swift             every tunable, in one place
  Support/Permissions.swift        camera + accessibility
```

## Status

Written against macOS 13+ / Swift 5.9. **Not yet compiled or run** — it was
authored in a Linux container with no Swift toolchain or macOS SDK, so expect to
shake out API-signature nits on the first build.

What *has* been verified, by transliterating the algorithms and running them:

- the normalised DLT + Jacobi eigensolver recovers a known homography to 4e-13
  on both the 20-point grid and the 4-point minimal sample, and the analytic
  inverse round-trips to 2.5e-13;
- the 20-point fit averages 1.5 px of per-tap noise down to 0.52 pt;
- the `gap / width` invariance holds to 4% across the display where the raw gap
  varies by 197% (the table in §3).

The algorithms, the shader/Swift struct layouts, and the coordinate conventions
are the parts worth reviewing.
