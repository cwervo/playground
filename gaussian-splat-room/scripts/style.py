"""Step 5: editorial grading of raw splat renders.

Two presets:
  ad   - Architectural Digest: warm white balance, lifted blacks, S-curve,
         strong depth of field, vignette, film grain, 4:5 editorial crop
  ikea - IKEA catalog: bright airy exposure, neutral-cool balance, lifted
         shadows, mild DoF, clean sharpen, 4:3
"""
import argparse
import os

import cv2
import numpy as np


def scurve(x, s):
    return np.clip(x + s * x * (1 - x) * (2 * x - 1) * 2, 0, 1)


def apply_dof(img, z, focus, strength):
    blurs = [img]
    for sig in (2.2, 5.0, 10.0):
        blurs.append(cv2.GaussianBlur(img, (0, 0), sig))
    coc = np.abs(1.0 / np.maximum(z, 0.2) - 1.0 / focus) * focus * strength
    coc = np.clip(coc, 0, 3.0)
    lo = np.floor(coc).astype(int)
    hi = np.minimum(lo + 1, 3)
    t = (coc - lo)[..., None]
    stack = np.stack(blurs, 0)
    H, W = z.shape
    yy, xx = np.mgrid[0:H, 0:W]
    return stack[lo, yy, xx] * (1 - t) + stack[hi, yy, xx] * t


def vignette(img, amount):
    H, W = img.shape[:2]
    yy, xx = np.mgrid[0:H, 0:W]
    r = np.sqrt(((xx - W / 2) / (W / 2)) ** 2 + ((yy - H / 2) / (H / 2)) ** 2)
    v = 1 - amount * np.clip(r, 0, 1.2) ** 2.4
    return img * v[..., None]


def grade(img, z, preset, focus):
    img = img.astype(np.float32) / 255.0  # BGR
    if preset == "ad":
        img = apply_dof(img, z, focus, 1.15)
        img *= np.array([0.90, 1.0, 1.07])  # warm (BGR)
        img = np.clip(img * 0.96 + 0.035, 0, 1)          # lifted blacks
        img = scurve(img, 0.22)
        # saturation
        g = img.mean(-1, keepdims=True)
        img = np.clip(g + (img - g) * 1.14, 0, 1)
        # warm key light falling from upper left
        H, W = img.shape[:2]
        gx = np.linspace(1.09, 0.94, W)[None, :, None]
        gy = np.linspace(1.06, 0.95, H)[:, None, None]
        img = np.clip(img * gx * gy, 0, 1)
        img = vignette(img, 0.30)
        rng = np.random.default_rng(5)
        luma = img.mean(-1, keepdims=True)
        img = np.clip(img + rng.normal(0, 0.014, img.shape) * (0.35 + 0.65 * luma), 0, 1)
    else:  # ikea
        img = apply_dof(img, z, focus, 0.55)
        img *= np.array([1.025, 1.005, 1.0])  # hint of cool (BGR)
        img = 1 - np.exp(-1.85 * img)          # bright filmic lift
        img = np.clip(img / (1 - np.exp(-1.85)), 0, 1)
        img = np.clip(img + 0.05 * (1 - img) ** 2, 0, 1)  # airy shadow lift
        g = img.mean(-1, keepdims=True)
        img = np.clip(g + (img - g) * 0.97, 0, 1)
        blur = cv2.GaussianBlur(img, (0, 0), 1.6)
        img = np.clip(img + 0.30 * (img - blur), 0, 1)   # clean sharpen
        img = vignette(img, 0.07)
    return (img * 255).astype(np.uint8)


def crop_ratio(img, rw, rh):
    H, W = img.shape[:2]
    target = rw / rh
    if W / H > target:
        w = int(H * target)
        x0 = (W - w) // 2
        return img[:, x0:x0 + w]
    h = int(W / target)
    y0 = (H - h) // 2
    return img[y0:y0 + h]


def add_label(img, title, sub):
    """IKEA-style product tag, lower left."""
    H, W = img.shape[:2]
    x0, y0 = 40, H - 150
    cv2.rectangle(img, (x0, y0), (x0 + 430, y0 + 110), (255, 255, 255), -1)
    cv2.rectangle(img, (x0, y0), (x0 + 430, y0 + 110), (60, 50, 20), 2)
    cv2.putText(img, title, (x0 + 18, y0 + 44), cv2.FONT_HERSHEY_DUPLEX,
                1.0, (30, 30, 30), 2, cv2.LINE_AA)
    cv2.putText(img, sub, (x0 + 18, y0 + 84), cv2.FONT_HERSHEY_SIMPLEX,
                0.62, (90, 90, 90), 1, cv2.LINE_AA)
    return img


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--preset", required=True, choices=["ad", "ikea"])
    ap.add_argument("--focus", type=float, default=2.0)
    ap.add_argument("--ratio", default=None, help="e.g. 4:5")
    ap.add_argument("--label", default=None, help="title|subtitle")
    args = ap.parse_args()

    img = cv2.imread(args.src)
    z = np.load(os.path.splitext(args.src)[0] + "_z.npy")
    out = grade(img, z, args.preset, args.focus)
    if args.ratio:
        rw, rh = (int(t) for t in args.ratio.split(":"))
        out = crop_ratio(out, rw, rh)
    if args.label:
        title, sub = args.label.split("|")
        out = add_label(out, title, sub)
    cv2.imwrite(args.out, out, [cv2.IMWRITE_JPEG_QUALITY, 93])
    print("wrote", args.out)


if __name__ == "__main__":
    main()
