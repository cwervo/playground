"""Step 3: back-project the refined pano depth into Gaussian splat models.

Three tiers:
  low    - sparse, chunky, semi-transparent blobs (impressionist)
  medium - dense surface-oriented disks from the refined depth
  arch   - RANSAC line-fit wall planes, snapped depth, thin crisp splats

Each tier writes a standard 3DGS-format .ply (SH degree 0) plus a plain
xyzrgb point-cloud .ply.
"""
import argparse
import os

import cv2
import numpy as np

from common import (ROOT, EYE_HEIGHT, pano_params, pano_dirs,
                    write_ply_gaussian, write_ply_xyzrgb)

H_CEIL = 1.10
FUSE_W, FUSE_H = 2000, 489
DEPTH_MIN, DEPTH_MAX = 0.6, 4.5

TIERS = {
    "low": dict(gw=224, gh=55, overlap=1.7, opacity=0.82, thin=0.35,
                blur=3.0, snap=False, jitter=0.012),
    "medium": dict(gw=768, gh=188, overlap=1.22, opacity=0.93, thin=0.18,
                   blur=0.8, snap=False, jitter=0.0),
    "arch": dict(gw=1600, gh=391, overlap=1.05, opacity=0.97, thin=0.08,
                 blur=0.0, snap=True, jitter=0.0),
}


def ransac_lines(p2d, dist=0.055, max_segs=9, iters=700, seed=3):
    """Sequential RANSAC line segments on the top-down wall profile."""
    rng = np.random.default_rng(seed)
    n_total = len(p2d)
    remaining = np.arange(n_total)
    segs = []
    while len(remaining) > n_total * 0.06 and len(segs) < max_segs:
        pts = p2d[remaining]
        best_inl, best_cnt = None, 0
        for _ in range(iters):
            i, j = rng.choice(len(pts), 2, replace=False)
            a, b = pts[i], pts[j]
            d = b - a
            L = np.hypot(*d)
            if L < 0.35:
                continue
            nv = np.array([-d[1], d[0]]) / L
            resid = np.abs((pts - a) @ nv)
            inl = resid < dist
            if inl.sum() > best_cnt:
                best_cnt, best_inl = inl.sum(), inl
        if best_inl is None or best_cnt < n_total * 0.04:
            break
        # PCA refine on inliers
        q = pts[best_inl]
        mu = q.mean(0)
        _, _, vt = np.linalg.svd(q - mu)
        nv = vt[1]
        c = nv @ mu
        resid = np.abs(pts @ nv - c)
        inl = resid < dist * 1.2
        q = pts[inl]
        th = np.arctan2(q[:, 0], q[:, 1])
        segs.append(dict(n=nv, c=c, th_min=th.min(), th_max=th.max(),
                         count=int(inl.sum())))
        remaining = remaining[~inl]
    return segs


def snap_profile(prof, theta, segs):
    """Snap per-column wall distance to the fitted line segments."""
    snapped = prof.copy()
    pad = np.deg2rad(2.5)
    u = np.stack([np.sin(theta), np.cos(theta)], 1)
    for col in range(len(prof)):
        th = theta[col]
        best, best_err = None, 0.18
        for s in segs:
            if not (s["th_min"] - pad <= th <= s["th_max"] + pad):
                continue
            denom = s["n"] @ u[col]
            if abs(denom) < 1e-3:
                continue
            t = s["c"] / denom
            if t <= 0.4 or t > 5:
                continue
            err = abs(t - prof[col])
            if err < best_err:
                best, best_err = t, err
        if best is not None:
            snapped[col] = best
    return snapped


def quat_from_frames(t1, t2, nrm):
    """Vectorized rotation-matrix (columns t1,t2,n) -> wxyz quaternion."""
    m = np.stack([t1, t2, nrm], axis=-1)  # (...,3,3) columns are axes
    m00, m11, m22 = m[..., 0, 0], m[..., 1, 1], m[..., 2, 2]
    tr = m00 + m11 + m22
    qw = np.sqrt(np.maximum(0, 1 + tr)) / 2
    qx = np.sqrt(np.maximum(0, 1 + m00 - m11 - m22)) / 2
    qy = np.sqrt(np.maximum(0, 1 - m00 + m11 - m22)) / 2
    qz = np.sqrt(np.maximum(0, 1 - m00 - m11 + m22)) / 2
    qx = np.copysign(qx, m[..., 2, 1] - m[..., 1, 2])
    qy = np.copysign(qy, m[..., 0, 2] - m[..., 2, 0])
    qz = np.copysign(qz, m[..., 1, 0] - m[..., 0, 1])
    q = np.stack([qw, qx, qy, qz], axis=-1)
    q /= np.linalg.norm(q, axis=-1, keepdims=True) + 1e-12
    return q


def build_tier(tier):
    cfg = TIERS[tier]
    pano = cv2.imread(os.path.join(ROOT, "source", "pano.jpg"))
    Hp, Wp = pano.shape[:2]
    hfov, f_cyl = pano_params(Wp, Hp)

    depth = np.load(os.path.join(ROOT, "depth", "pano_depth.npy"))

    if cfg["snap"]:
        prof = np.load(os.path.join(ROOT, "depth", "wall_profile.npy"))
        pop = np.load(os.path.join(ROOT, "depth", "pano_pop.npy"))
        theta_cols = (np.arange(FUSE_W) / FUSE_W - 0.5) * hfov
        p2d = np.stack([prof * np.sin(theta_cols), prof * np.cos(theta_cols)], 1)
        segs = ransac_lines(p2d)
        print(f"[arch] RANSAC wall segments: {len(segs)} "
              f"({[s['count'] for s in segs]})")
        d_snap = snap_profile(prof, theta_cols, segs)
        v = (Hp / 2.0 - (np.arange(FUSE_H) + 0.5) * (Hp / FUSE_H)) / f_cyl
        Vg = np.tile(v[:, None], (1, FUSE_W))
        r_wall = d_snap[None, :] * np.sqrt(1 + Vg ** 2)
        with np.errstate(divide="ignore"):
            r_ceil = np.where(Vg > 0.02, H_CEIL * np.sqrt(1 + Vg ** 2) / np.maximum(Vg, 0.02), np.inf)
            r_floor = np.where(Vg < -0.02, EYE_HEIGHT * np.sqrt(1 + Vg ** 2) / np.maximum(-Vg, 0.02), np.inf)
        r = np.minimum(r_wall, np.minimum(r_ceil, r_floor))
        # quantized relief keeps the pop-outs planar
        pop_q = np.where(pop > 0.065, 0.13,
                         np.where(pop < -0.02, -0.05,
                                  np.where(pop > 0.008, 0.02, 0.0)))
        depth = np.clip(r - pop_q, DEPTH_MIN, DEPTH_MAX).astype(np.float32)

    if cfg["blur"] > 0:
        depth = cv2.GaussianBlur(depth, (0, 0), cfg["blur"])

    gw, gh = cfg["gw"], cfg["gh"]
    depth_t = cv2.resize(depth, (gw, gh), interpolation=cv2.INTER_AREA)
    color_t = cv2.resize(pano, (gw, gh), interpolation=cv2.INTER_AREA)
    rgb = cv2.cvtColor(color_t, cv2.COLOR_BGR2RGB).reshape(-1, 3)

    xs, ys = np.meshgrid((np.arange(gw) + 0.5) * (Wp / gw),
                         (np.arange(gh) + 0.5) * (Hp / gh))
    dirs = pano_dirs(Wp, Hp, xs, ys)
    P = dirs * depth_t[..., None]

    dPx = np.gradient(P, axis=1)
    dPy = np.gradient(P, axis=0)
    nrm = np.cross(dPx, dPy)
    nlen = np.linalg.norm(nrm, axis=-1, keepdims=True)
    nrm = np.where(nlen > 1e-9, nrm / np.maximum(nlen, 1e-9), dirs * -1)
    flip = (np.sum(nrm * P, axis=-1, keepdims=True) > 0)
    nrm = np.where(flip, -nrm, nrm)

    t1 = dPx - np.sum(dPx * nrm, -1, keepdims=True) * nrm
    t1l = np.linalg.norm(t1, axis=-1, keepdims=True)
    fallback = np.cross(nrm, np.array([0.0, 1.0, 0.0]))
    t1 = np.where(t1l > 1e-9, t1 / np.maximum(t1l, 1e-9),
                  fallback / (np.linalg.norm(fallback, axis=-1, keepdims=True) + 1e-9))
    t2 = np.cross(nrm, t1)

    s1 = np.linalg.norm(dPx, axis=-1) * cfg["overlap"]
    s2 = np.linalg.norm(dPy, axis=-1) * cfg["overlap"]
    s1 = np.clip(s1, 1e-4, 0.5)
    s2 = np.clip(s2, 1e-4, 0.5)
    s3 = cfg["thin"] * np.minimum(s1, s2)
    scales = np.stack([s1, s2, s3], axis=-1).reshape(-1, 3)

    quats = quat_from_frames(t1, t2, nrm).reshape(-1, 4)
    pts = P.reshape(-1, 3)
    normals = nrm.reshape(-1, 3)

    rng = np.random.default_rng(11)
    if cfg["jitter"] > 0:
        pts = pts + rng.normal(0, cfg["jitter"], pts.shape)
    opacity = np.clip(cfg["opacity"] + rng.normal(0, 0.02, len(pts)), 0.05, 0.995)

    # cull near-black splats along the pano's filled edges (they render as
    # dark floater trails)
    val = rgb.max(axis=1)
    edge = ((ys < 0.07 * Hp) | (xs < 0.02 * Wp) | (xs > 0.98 * Wp)).reshape(-1)
    keep = ~((val < 18) & edge)
    pts, normals, rgb = pts[keep], normals[keep], rgb[keep]
    scales, opacity, quats = scales[keep], opacity[keep], quats[keep]
    print(f"[{tier}] culled {(~keep).sum()} black edge splats")

    gpath = os.path.join(ROOT, "models", f"room_{tier}.ply")
    ppath = os.path.join(ROOT, "models", f"room_{tier}_points.ply")
    write_ply_gaussian(gpath, pts, normals, rgb, scales, opacity, quats)
    write_ply_xyzrgb(ppath, pts, rgb)
    print(f"[{tier}] {len(pts)} splats -> {gpath} "
          f"({os.path.getsize(gpath)/1e6:.1f} MB), points {os.path.getsize(ppath)/1e6:.1f} MB")
    print(f"[{tier}] extent x[{pts[:,0].min():.2f},{pts[:,0].max():.2f}] "
          f"y[{pts[:,1].min():.2f},{pts[:,1].max():.2f}] "
          f"z[{pts[:,2].min():.2f},{pts[:,2].max():.2f}]")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--tier", required=True, choices=list(TIERS))
    args = ap.parse_args()
    build_tier(args.tier)
