"""Step 2c: semantic relief from color segmentation.

MiDaS misjudges this scene (dark door/TVs read as far holes), so object
relief comes from segmentation instead: TVs pop toward the camera like
wall-mounted panels, the door recesses into its frame, papers/frames sit a
touch proud of the wall. Output is a signed pop map in meters (+ = toward
camera) and the final refined depth map.
"""
import os

import cv2
import numpy as np

from common import ROOT

FUSE_W, FUSE_H = 2000, 489
TV_POP = 0.13
DOOR_POP = -0.05
PAPER_POP = 0.02
DEPTH_MIN, DEPTH_MAX = 0.6, 4.5


def main():
    pano = cv2.imread(os.path.join(ROOT, "source", "pano.jpg"))
    small = cv2.resize(pano, (FUSE_W, FUSE_H), interpolation=cv2.INTER_AREA)
    hsv = cv2.cvtColor(small, cv2.COLOR_BGR2HSV)
    Hh = hsv[..., 0].astype(np.int16)
    S = hsv[..., 1].astype(np.int16)
    V = hsv[..., 2].astype(np.int16)

    rows = np.arange(FUSE_H)[:, None] * np.ones((1, FUSE_W))

    dark = (V < 80).astype(np.uint8)
    dark = cv2.morphologyEx(dark, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
    n, lab, stats, cent = cv2.connectedComponentsWithStats(dark, 8)
    tv_mask = np.zeros((FUSE_H, FUSE_W), np.uint8)
    door_mask = np.zeros((FUSE_H, FUSE_W), np.uint8)
    for i in range(1, n):
        area = stats[i, cv2.CC_STAT_AREA]
        cy_c = cent[i][1]
        if area < 150:
            continue
        comp = lab == i
        # door: big dark-brown block in the lower 2/3
        browns = ((Hh[comp] < 35) & (S[comp] > 40)).mean()
        if area > 8000 and cy_c > FUSE_H * 0.3:
            door_mask[comp] = 1
        elif cy_c < FUSE_H * 0.45:
            tv_mask[comp] = 1
        del browns

    # solidify the door: close gaps from light wood grain, then fill holes
    door_mask = cv2.morphologyEx(door_mask, cv2.MORPH_CLOSE, np.ones((17, 17), np.uint8))
    ff = door_mask.copy()
    cv2.floodFill(ff, np.zeros((FUSE_H + 2, FUSE_W + 2), np.uint8), (0, 0), 1)
    door_mask = door_mask | (1 - ff)

    paper = ((V > 195) & (S < 32)).astype(np.uint8)
    paper = cv2.morphologyEx(paper, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    # papers only on the wall band, not the ceiling
    paper[rows < FUSE_H * 0.22] = 0
    # keep only small compact components — sheets of paper, not lit wall areas
    np_, lab_p, stats_p, _ = cv2.connectedComponentsWithStats(paper, 8)
    for i in range(1, np_):
        if stats_p[i, cv2.CC_STAT_AREA] > 2500:
            paper[lab_p == i] = 0

    pop = (tv_mask.astype(np.float32) * TV_POP
           + door_mask.astype(np.float32) * DOOR_POP
           + paper.astype(np.float32) * PAPER_POP
           * (1 - tv_mask) * (1 - door_mask))
    pop = cv2.GaussianBlur(pop, (0, 0), 1.2)
    np.save(os.path.join(ROOT, "depth", "pano_pop.npy"), pop)

    r_prior = np.load(os.path.join(ROOT, "depth", "pano_prior.npy"))
    depth = np.clip(r_prior - pop, DEPTH_MIN, DEPTH_MAX)
    np.save(os.path.join(ROOT, "depth", "pano_depth.npy"), depth.astype(np.float32))
    print("pop px:", {"tv": int(tv_mask.sum()), "door": int(door_mask.sum()),
                      "paper": int(paper.sum())})
    print("refined depth:", depth.min(), depth.max())

    seg = small.copy()
    seg[tv_mask > 0] = (0.4 * seg[tv_mask > 0] + np.array([255, 80, 0]) * 0.6)
    seg[door_mask > 0] = (0.4 * seg[door_mask > 0] + np.array([0, 80, 255]) * 0.6)
    seg[paper > 0] = (0.4 * seg[paper > 0] + np.array([0, 255, 80]) * 0.6)
    dviz = cv2.applyColorMap(
        cv2.normalize(-depth, None, 0, 255, cv2.NORM_MINMAX).astype(np.uint8),
        cv2.COLORMAP_MAGMA)
    both = np.vstack([seg, dviz])
    cv2.putText(both, "segmentation: TV (blue) pops +13cm, door (red) recess -5cm, paper (green) +2cm",
                (12, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 2)
    cv2.putText(both, "final refined depth = layout prior + semantic relief",
                (12, FUSE_H + 30), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 2)
    cv2.imwrite(os.path.join(ROOT, "renders", "03_depth_refined.jpg"), both)
    print("viz written")


if __name__ == "__main__":
    main()
