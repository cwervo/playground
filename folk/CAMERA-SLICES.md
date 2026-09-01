# Folk camera-slice experiments — collated

A camera **slice** in Folk is a crop of the live camera frame under (or near) a
page's quad, claimed back into the reactive database so other programs can match
on it:

```tcl
Wish $this has camera slice
When $this has camera slice /slice/ { ... }
Wish $this displays camera slice $slice
```

(The folklang BNF work on `claude/folklang-bnf-descriptor-iqk154` documents the
vocabulary as: *"Crop of the camera image under a page's quad, claimed back as
`has camera slice /slice/`"*.)

This file collates every slice experiment in this repo across `main` and the
unmerged Claude Code session branches, so nothing stays stranded on a branch.

---

## 1. Core slice experiments (`folk/`, on `main`)

| File | What it explores |
|------|------------------|
| [`basic-slice-display.folk`](basic-slice-display.folk) | The minimal loop: take the whole camera frame, `image subimage` a 300×300 crop at the page's top-left (via `projectorToCamera`), display it on a virtual page moved 110% down, and claim it as a `template`. Also saves the slice to `/home/folk/folk-images/slice.jpg`. |
| [`250slice.folk`](250slice.folk) | Cropping a *sub*-slice out of a page's own camera slice — `image subimage $s {*}$coords 200 200` on a virtual page below. Carries a known open bug: changing the **x** of the crop responds correctly, but changing **y** jumps in large steps across image space (see the comment in the file). |
| [`sliceDisplay.folk`](sliceDisplay.folk) | Persisting slices: whenever anything has a `template`, delete all prior `/home/folk/folk-images/slice*.jpg`, save the new one under an incrementing name, and `Commit` a `has a template at $path` claim (with an `On unmatch` cleanup). The incrementing-filename scheme is still marked TODO. |
| [`sliceButtonMod.folk`](sliceButtonMod.folk) | Save-once semantics using `When /nobody/ claims ... { ... Commit }` so the JPEG is written a single time, then re-displayed from disk. Header comment notes it **runs out of allocation slots** — a real failure mode worth remembering. |
| [`saveSliceAsJpeg.folk`](saveSliceAsJpeg.folk) | A pointer tool: point this page up at another page `/p/`, and when `$p has camera slice /slice/`, save both the slice and the full camera frame as JPEGs. |
| [`sliceColorFilter.folk`](sliceColorFilter.folk) | **Recovered from session branch `claude/folk-slice-color-filter-8g7e84`** (previously unmerged). A standalone GPU color filter for slices: `Wish $thing displays slice $s with only color: 0x1010FF red rgb(255,0,221) tolerance:0.15`. Parses named/hex/rgb() colors, compiles a per-color-set fragment-shader variant of the builtin `image` pipeline that makes every pixel farther than `tolerance` (0–1 RGB distance) from all allowed colors fully transparent, caches pipelines by color set, and includes a back-compat shim mapping plain `displays slice` onto `displays image`. |

## 2. Slice consumers elsewhere on `main`

Programs that build on the slice idiom rather than exploring it directly:

- [`btn.folk`](btn.folk) — displays a camera slice of the left half of the page as part of a button experiment.
- [`ocv-demo.folk`](ocv-demo.folk) and [`../opencv/OpenCVThreshold.folk`](../opencv/OpenCVThreshold.folk) — run `opencvAdaptiveThreshold` over a virtual page's camera slice and display the result.
- [`animation/binder/frames.folk`](animation/binder/frames.folk) and [`../updateFrameAnimation.folk`](../updateFrameAnimation.folk) — grab a slice per animation frame region and cycle through them on the clock. `updateFrameAnimation.folk`'s header notes the open problem: virtual regions don't inherently carry quad information (see `virtual-programs/images.folk` upstream for how slices get theirs).
- [`../templateMatcher/templateMatcher.folk`](../templateMatcher/templateMatcher.folk) — shares/receives `has camera slice` statements across processes and template-matches saved slices against the board image.
- [`../folk_qr_demos/scanner.folk`](../folk_qr_demos/scanner.folk) / [`generator.folk`](../folk_qr_demos/generator.folk) — define a reusable wish, `Wish /scanner/ scans its camera slice for QR codes with /...options/`, implemented `-serially` over the scanner's slice.

## 3. Work still on unmerged Claude Code session branches

- **`claude/folk-slice-color-filter-8g7e84`** — the shader slice color filter, now copied into `folk/sliceColorFilter.folk` here (§1).
- **`claude/cielab-document-scanner-c5fjsp`** — besides the LabScan iOS app, its "Add p2p and ios and labscan stuff" commit carries a batch of slice-consuming folk programs not on `main`: `folk/color/probe.folk` (C-level per-pixel RGB probe into an `Image`), `folk/vision/ball.folk` (probe a slice at geometry-relative coordinates for ball tracking), `folk/laserKit/detectBrightestInQuad.folk` (C scan for the brightest pixel in a slice, for laser pointing), `folk/soundcloudKit/soundcloudPlayer.folk` (QR-from-slice → yt-dlp player), plus `folk/pongKit/` (camera-simulation learnings).
- **`claude/folklang-bnf-descriptor-iqk154`** — the folklang grammar/vocabulary description, which includes the canonical definitions of the `has camera slice` / `displays camera slice` statements.

## 4. Related non-Folk camera experiments (context)

Session branches that circle the same "carve up what the camera sees" idea
outside Folk proper: `claude/webcam-color-segmentation-kq9bu7` (fullscreen
webcam color segmentation page), `claude/webcam-unicode-grid-yuka5k` (webcam →
unicode grid), `claude/webcam-color-markers-6n1b8u` (prior-art notes),
`claude/visible-light-fiducial-markers-ei2dtt` (Rulercode/Rulercross fiducials),
`claude/uw-motion-camera-p2p-wtjs53` (motion-triggered camera sims), and the
`SplitCam` branch (`p2p/split/`, a Swift/Metal split-view camera app).

## Open threads

1. The y-coordinate jump when sub-slicing a slice (`250slice.folk`).
2. Allocation-slot exhaustion in the save-once pattern (`sliceButtonMod.folk`).
3. Unique-filename persistence for saved slices (`sliceDisplay.folk` TODO).
4. Virtual regions lacking quad info for slice capture (`updateFrameAnimation.folk`).
5. Merging the `claude/cielab-document-scanner-c5fjsp` folk-program batch (§3) onto `main` so `probe`/`ball`/`laserKit` aren't stranded either.
