"""Step 2a: single-view room-layout prior from the pano.

Detect the wall/ceiling boundary per pano column (yellow paint vs grey
ceiling), convert boundary elevation to horizontal wall distance
(d = h_ceil / tan(elev)), robustly interpolate through occluders (TVs),
and build a prior range map: vertical walls + ceiling plane + floor plane.
"""
import os

import cv2
import numpy as np

from common import ROOT, EYE_HEIGHT, pano_params

H_CEIL = 1.10          # meters from eye level up to the ceiling edge
D_MIN, D_MAX = 1.0, 3.5
LAYOUT_W = 2000        # columns for the wall profile


def detect_boundary(pano_bgr):
    """Per-column pano row of the wall/ceiling transition, np.nan if occluded."""
    hsv = cv2.cvtColor(pano_bgr, cv2.COLOR_BGR2HSV)
    Hh, S, V = hsv[..., 0].astype(np.int16), hsv[..., 1], hsv[..., 2]
    yellow = (Hh > 10) & (Hh < 45) & (S > 55) & (V > 90)
    dark = V < 70
    H_img, W_img = yellow.shape

    # only search the upper half of the pano for the boundary
    top = yellow[: H_img // 2]
    dark_top = dark[: H_img // 2]
    boundary = np.full(W_img, np.nan)
    run = np.zeros(W_img, np.int32)
    found = np.full(W_img, -1, np.int32)
    NEED = 18
    for r in range(top.shape[0]):
        run = np.where(top[r], run + 1, 0)
        hit = (run == NEED) & (found < 0)
        found[hit] = r - NEED + 1
    boundary[found >= 0] = found[found >= 0]

    # invalidate columns where the transition zone is occluded by something
    # dark (the TVs) — the "boundary" there is the TV bottom, not the wall
    for c in np.flatnonzero(found >= 0):
        r0 = max(found[c] - 250, 0)
        if dark_top[r0:found[c] + 5, c].mean() > 0.15:
            boundary[c] = np.nan
    return boundary


def main():
    pano = cv2.imread(os.path.join(ROOT, "source", "pano.jpg"))
    H, W = pano.shape[:2]
    hfov, f_cyl = pano_params(W, H)

    boundary = detect_boundary(pano)
    valid = np.isfinite(boundary)
    print(f"boundary detected on {valid.sum()}/{W} columns")

    cols = np.arange(W)
    # elevation of boundary; v = tan(elevation) in cylindrical coords
    v_b = (H / 2.0 - boundary) / f_cyl
    d = np.where(v_b > 0.05, H_CEIL / np.maximum(v_b, 0.05), np.nan)
    d[~valid] = np.nan

    ok = np.isfinite(d) & (d > D_MIN * 0.7) & (d < D_MAX * 1.5)
    d_i = np.interp(cols, cols[ok], d[ok])
    # The vaulted ceiling makes the boundary scallop between arches; the wall
    # top is the spring line = the lower envelope (largest distance within a
    # window ~ one arch). 85th-percentile filter, then gentle smoothing.
    k = 801
    pad = np.pad(d_i, k // 2, mode="edge")
    env = np.array([np.percentile(pad[i:i + k], 85) for i in range(0, W, 8)])
    env = cv2.resize(env.reshape(1, -1), (W, 1), interpolation=cv2.INTER_LINEAR).ravel()
    d_s = cv2.GaussianBlur(env.reshape(1, -1).astype(np.float32), (0, 0), 60).ravel()
    d_s = np.clip(d_s, D_MIN, D_MAX)

    # downsample profile to layout resolution
    prof = cv2.resize(d_s.reshape(1, -1), (LAYOUT_W, 1),
                      interpolation=cv2.INTER_AREA).ravel()
    np.save(os.path.join(ROOT, "depth", "wall_profile.npy"), prof.astype(np.float32))

    # ---- prior range map on the fusion grid -----------------------------
    FUSE_W, FUSE_H = 2000, 489
    xs = (np.arange(FUSE_W) + 0.5) * (W / FUSE_W)
    ys = (np.arange(FUSE_H) + 0.5) * (H / FUSE_H)
    theta = (xs / W - 0.5) * hfov
    v = (H / 2.0 - ys) / f_cyl
    Vg, _ = np.meshgrid(v, theta, indexing="ij")  # (FUSE_H later transpose)
    Vg = np.tile(v[:, None], (1, FUSE_W))
    Dg = np.tile(prof[None, :], (FUSE_H, 1))

    r_wall = Dg * np.sqrt(1 + Vg ** 2)
    with np.errstate(divide="ignore"):
        r_ceil = np.where(Vg > 0.02, H_CEIL * np.sqrt(1 + Vg ** 2) / np.maximum(Vg, 0.02), np.inf)
        r_floor = np.where(Vg < -0.02, EYE_HEIGHT * np.sqrt(1 + Vg ** 2) / np.maximum(-Vg, 0.02), np.inf)
    r_prior = np.minimum(r_wall, np.minimum(r_ceil, r_floor)).astype(np.float32)
    np.save(os.path.join(ROOT, "depth", "pano_prior.npy"), r_prior)
    print("prior range:", r_prior.min(), r_prior.max())

    # viz: boundary over pano + top-down profile + prior depth
    viz = pano.copy()
    for c in range(0, W, 3):
        b = boundary[c]
        if np.isfinite(b):
            cv2.circle(viz, (c, int(b)), 3, (0, 255, 0), -1)
        r_s = H / 2.0 - f_cyl * (H_CEIL / d_s[c])
        cv2.circle(viz, (c, int(np.clip(r_s, 0, H - 1))), 2, (0, 0, 255), -1)
    viz = cv2.resize(viz, (2000, 489))

    plan = np.full((500, 500, 3), 30, np.uint8)
    th = (np.arange(LAYOUT_W) / LAYOUT_W - 0.5) * hfov
    px = (250 + prof * np.sin(th) * 55).astype(int)
    pz = (250 - prof * np.cos(th) * 55).astype(int)
    for i in range(LAYOUT_W):
        cv2.circle(plan, (px[i], pz[i]), 1, (120, 220, 255), -1)
    cv2.circle(plan, (250, 250), 4, (0, 0, 255), -1)
    cv2.putText(plan, "top-down wall profile", (10, 25),
                cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 1)

    depth_viz = cv2.applyColorMap(
        cv2.normalize(-r_prior, None, 0, 255, cv2.NORM_MINMAX).astype(np.uint8),
        cv2.COLORMAP_MAGMA)
    depth_viz = cv2.resize(depth_viz, (2000, 489))
    canvas = np.full((489 * 2 + 520, 2000, 3), 15, np.uint8)
    canvas[:489] = viz
    canvas[489:978] = depth_viz
    canvas[988:1488, 750:1250] = plan
    cv2.putText(canvas, "green: detected wall/ceiling boundary   red: smoothed profile",
                (12, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 255, 0), 2)
    cv2.putText(canvas, "layout prior depth (bright = near)", (12, 520),
                cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 2)
    cv2.imwrite(os.path.join(ROOT, "renders", "02_layout_prior.jpg"), canvas)
    print("layout viz written")


if __name__ == "__main__":
    main()
