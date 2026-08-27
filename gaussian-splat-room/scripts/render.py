"""Step 4: CPU software renderer for 3DGS .ply files.

Pure numpy splatting: project gaussians, sort by depth, split into
equal-count depth buckets (back to front); inside a bucket splats are
accumulated additively (weight = opacity * gaussian falloff) and buckets are
alpha-composited over each other. Also writes a z-buffer for depth of field.
"""
import argparse
import os

import cv2
import numpy as np

from common import read_ply_gaussian

N_BUCKETS = 56
SAT = 1.6           # weight -> alpha saturation inside a bucket
SIG_DIV = 1.95      # projected radius -> gaussian sigma (higher = crisper)


def render(model, pos, yaw_deg, pitch_deg, fov_deg, W, H, bg=(24, 22, 20)):
    pts, normals, rgb, opacity, scales, quats = read_ply_gaussian(model)

    yaw, pitch = np.deg2rad(yaw_deg), np.deg2rad(pitch_deg)
    fwd = np.array([np.sin(yaw) * np.cos(pitch), np.sin(pitch),
                    np.cos(yaw) * np.cos(pitch)])
    right = np.array([np.cos(yaw), 0.0, -np.sin(yaw)])
    up = np.cross(right, fwd) * -1  # right-handed, y-up
    if up[1] < 0:
        up = -up

    rel = pts - np.asarray(pos)[None]
    x = rel @ right
    y = rel @ up
    z = rel @ fwd

    f = (W / 2.0) / np.tan(np.deg2rad(fov_deg) / 2.0)
    keep = z > 0.06
    x, y, z = x[keep], y[keep], z[keep]
    rgbk, opk = rgb[keep], opacity[keep]
    r_world = np.max(scales[keep][:, :2], axis=1)

    u = f * x / z + W / 2.0
    v = H / 2.0 - f * y / z
    r_px = np.clip(f * r_world / z, 0.7, 26.0)

    inb = (u > -30) & (u < W + 30) & (v > -30) & (v < H + 30)
    u, v, z, r_px = u[inb], v[inb], z[inb], r_px[inb]
    rgbk, opk = rgbk[inb], opk[inb]
    n = len(u)
    if n == 0:
        raise SystemExit("no splats visible")

    # z-buffer from splat centers for DoF (min filter closes small holes)
    zbuf = np.full(W * H, 50.0, np.float32)
    ui = np.clip(u.round().astype(np.int64), 0, W - 1)
    vi = np.clip(v.round().astype(np.int64), 0, H - 1)
    np.minimum.at(zbuf, vi * W + ui, z.astype(np.float32))
    zimg = zbuf.reshape(H, W)
    zimg = cv2.erode(zimg, np.ones((7, 7), np.uint8))
    zimg = cv2.GaussianBlur(zimg, (0, 0), 3)

    order = np.argsort(-z)  # far first
    u, v, z, r_px = u[order], v[order], z[order], r_px[order]
    rgbk, opk = rgbk[order], opk[order]

    out = np.zeros((H, W, 3), np.float32)
    out[:] = np.asarray(bg, np.float32) / 255.0
    out_a = np.zeros((H, W), np.float32)

    bounds = np.linspace(0, n, N_BUCKETS + 1).astype(int)
    for b in range(N_BUCKETS):
        s, e = bounds[b], bounds[b + 1]
        if e <= s:
            continue
        ub, vb, rb = u[s:e], v[s:e], r_px[s:e]
        cb, ab = rgbk[s:e], opk[s:e]
        sig = rb / SIG_DIV
        R = int(np.clip(np.ceil(np.percentile(rb, 96) * 1.2), 2, 22))
        u0 = ub.round().astype(np.int64)
        v0 = vb.round().astype(np.int64)
        fu = ub - u0
        fv = vb - v0
        acc_c = np.zeros((H * W, 3), np.float32)
        acc_w = np.zeros(H * W, np.float32)
        inv2s = 1.0 / (2 * sig * sig)
        wc = ab
        for dy in range(-R, R + 1):
            py = v0 + dy
            oky = (py >= 0) & (py < H)
            for dx in range(-R, R + 1):
                d2 = (dx - fu) ** 2 + (dy - fv) ** 2
                wg = wc * np.exp(-d2 * inv2s)
                m = oky & (wg > 0.004)
                px = u0 + dx
                m &= (px >= 0) & (px < W)
                if not m.any():
                    continue
                idx = py[m] * W + px[m]
                np.add.at(acc_w, idx, wg[m])
                np.add.at(acc_c, idx, wg[m, None] * cb[m])
        A = 1.0 - np.exp(-SAT * acc_w)
        nz = acc_w > 1e-6
        C = np.zeros_like(acc_c)
        C[nz] = acc_c[nz] / acc_w[nz, None]
        A = A.reshape(H, W)
        C = C.reshape(H, W, 3)
        out = out * (1 - A[..., None]) + C * A[..., None]
        out_a = out_a * (1 - A) + A

    return out, out_a, zimg


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--pos", default="0,0,0")
    ap.add_argument("--yaw", type=float, default=0)
    ap.add_argument("--pitch", type=float, default=0)
    ap.add_argument("--fov", type=float, default=60)
    ap.add_argument("--width", type=int, default=1440)
    ap.add_argument("--height", type=int, default=1080)
    args = ap.parse_args()

    pos = [float(t) for t in args.pos.split(",")]
    out, out_a, zimg = render(args.model, pos, args.yaw, args.pitch,
                              args.fov, args.width, args.height)

    img8 = np.clip(out * 255, 0, 255).astype(np.uint8)
    # fill low-coverage holes from neighbors
    holes = (out_a < 0.35).astype(np.uint8)
    if holes.any():
        img8 = cv2.inpaint(img8, holes, 5, cv2.INPAINT_TELEA)
    cv2.imwrite(args.out, cv2.cvtColor(img8, cv2.COLOR_RGB2BGR))
    np.save(os.path.splitext(args.out)[0] + "_z.npy", zimg)
    print("wrote", args.out)


if __name__ == "__main__":
    main()
