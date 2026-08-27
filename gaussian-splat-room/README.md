# gaussian-splat-room

One iPhone panorama of a small exam room → three Gaussian-splat 3D models
(`.ply`, standard 3DGS format) → Architectural Digest / IKEA-catalog style
renders. Everything runs on CPU with FOSS tooling: numpy, OpenCV,
onnxruntime + MiDaS v2.1 small, and a custom software splat renderer.

## Why not COLMAP / 3DGS training?

A single panorama is taken from one viewpoint: there is no parallax, so
COLMAP's SfM is degenerate and the reference CUDA trainers
(graphdeco-inria/gaussian-splatting, Nerfstudio splatfacto, OpenSplat) have
nothing to optimize against — and this box has no GPU anyway. Instead the
pipeline synthesizes splats from single-view geometry:

1. **Decompose** (`scripts/decompose.py`) — treat the 8000×1953 pano as a
   cylindrical projection (~250° FOV) and slice it into 9 overlapping
   pinhole views.
2. **Monocular depth** (`scripts/depth.py`) — MiDaS v2.1 small (ONNX) per
   view, affine-aligned and feather-fused into pano space. *Finding:* on
   this scene MiDaS reads the dark door and TVs as far holes and mostly
   predicts the lighting gradient, so it is kept only as a documented
   comparison, not the geometry source.
3. **Layout prior** (`scripts/layout.py`) — detect the wall/ceiling
   boundary per pano column (yellow paint vs grey ceiling), take the lower
   envelope across the vaulted-arch scallops, and convert boundary
   elevation to wall distance (d = h_ceil / tan θ). Vertical walls +
   ceiling + floor planes give the base range map.
4. **Semantic relief** (`scripts/relief.py`) — color segmentation pops the
   TVs +13 cm off the wall, recesses the door 5 cm, floats papers +2 cm.
5. **Reconstruct** (`scripts/reconstruct.py`) — back-project to 3D and
   write three tiers of 3DGS `.ply` (SH degree 0, opens in SuperSplat /
   antimatter15 splat / gsplat):

   | tier | splats | character |
   |------|-------:|-----------|
   | `models/room_low.ply` | 12k | chunky semi-transparent blobs, jittered |
   | `models/room_medium.ply` | 100k | surface-oriented disks, organic |
   | `models/room_arch.ply` | 400k | RANSAC line-fit wall planes, snapped depth, thin crisp splats |

   Each tier also ships as a plain point cloud (`room_*_points.ply`).
6. **Render** (`scripts/render.py`) — pure-numpy splatter: project, depth
   sort, 56 equal-count depth buckets composited back-to-front, additive
   accumulation inside a bucket, z-buffer out for depth of field.
7. **Style** (`scripts/style.py`, `scripts/make_shot.py`,
   `scripts/shots.json`) — two grading presets: `ad` (warm white balance,
   lifted blacks, S-curve, DoF, vignette, grain, 4:5) and `ikea` (bright
   filmic lift, airy shadows, clean sharpen, 4:3). Final frames in
   `shots/`.

## Reproduce

```sh
pip install numpy pillow opencv-python-headless onnxruntime
curl -L -o depth/midas_small.onnx \
  https://github.com/isl-org/MiDaS/releases/download/v2_1/model-small.onnx
cd scripts
python3 decompose.py && python3 layout.py && python3 depth.py && python3 relief.py
for t in low medium arch; do python3 reconstruct.py --tier $t; done
python3 make_shot.py --name ikea_wide_arch   # or any name in shots.json
```

Progress/diagnostic images live in `renders/`; the source pano in
`source/pano.jpg`.
