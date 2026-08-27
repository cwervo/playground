"""Driver: render + grade one named shot from shots.json."""
import argparse
import json
import os

import cv2
import numpy as np

from common import ROOT, pano_dirs
from render import render
from style import grade, crop_ratio, add_label

RES_W, RES_H = 1440, 1080
PANO_W, PANO_H = 8000, 1953
FUSE_W, FUSE_H = 2000, 489


def polar(az_deg, r, y):
    az = np.deg2rad(az_deg)
    return np.array([r * np.sin(az), y, r * np.cos(az)])


def target_from_px(px, py):
    """Exact 3D point of a pano pixel via the refined depth map."""
    depth = np.load(os.path.join(ROOT, "depth", "pano_depth.npy"))
    fx = np.clip(px * FUSE_W / PANO_W, 0, FUSE_W - 1)
    fy = np.clip(py * FUSE_H / PANO_H, 0, FUSE_H - 1)
    d = cv2.getRectSubPix(depth, (1, 1), (float(fx), float(fy)))[0, 0]
    dirs = pano_dirs(PANO_W, PANO_H, np.array([float(px)]), np.array([float(py)]))
    return dirs[0] * d


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", required=True)
    args = ap.parse_args()

    with open(os.path.join(ROOT, "scripts", "shots.json")) as f:
        shots = json.load(f)
    s = shots[args.name]

    pos = polar(*s["cam"])
    tgt = target_from_px(*s["look_px"]) if "look_px" in s else polar(*s["target"])
    d = tgt - pos
    yaw = np.rad2deg(np.arctan2(d[0], d[2]))
    pitch = np.rad2deg(np.arctan2(d[1], np.hypot(d[0], d[2])))
    focus = float(np.linalg.norm(d))

    model = os.path.join(ROOT, "models", f"room_{s['tier']}.ply")
    # empty coverage reads as soft ambient, not a black void
    bg = (205, 200, 192) if s["preset"] == "ikea" else (52, 46, 40)
    out, out_a, zimg = render(model, pos, yaw, pitch, s["fov"], RES_W, RES_H, bg=bg)

    img8 = np.clip(out * 255, 0, 255).astype(np.uint8)
    holes = (out_a < 0.55).astype(np.uint8)
    if holes.any():
        img8 = cv2.inpaint(img8, holes, 5, cv2.INPAINT_TELEA)
    raw = os.path.join(ROOT, "renders", f"raw_{args.name}.png")
    cv2.imwrite(raw, cv2.cvtColor(img8, cv2.COLOR_RGB2BGR))

    bgr = cv2.cvtColor(img8, cv2.COLOR_RGB2BGR)
    styled = grade(bgr, zimg, s["preset"], focus)
    if s.get("ratio"):
        rw, rh = (int(t) for t in s["ratio"].split(":"))
        styled = crop_ratio(styled, rw, rh)
    if s.get("label"):
        title, sub = s["label"].split("|")
        styled = add_label(styled, title, sub)
    outp = os.path.join(ROOT, "shots", f"{args.name}.jpg")
    cv2.imwrite(outp, styled, [cv2.IMWRITE_JPEG_QUALITY, 93])

    luma = styled.mean() / 255.0
    print(f"shot {args.name}: yaw={yaw:.1f} pitch={pitch:.1f} focus={focus:.2f} "
          f"coverage={out_a.mean():.2f} luma={luma:.2f} -> {outp}")


if __name__ == "__main__":
    main()
