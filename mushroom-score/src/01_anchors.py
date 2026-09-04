#!/usr/bin/env python3
"""
Stage 01 - CIELAB anchor extraction.

The three reference photographs are the score's *stopping points*: TIGHT, MID,
WIDE. This stage reduces each photograph to a pair of CIELAB anchors -

    MUSHROOM  the white cap    (high L*, near-neutral chroma)
    PLANT     the green weeds  (negative a*, mid L*)

plus a whole-frame Lab signature used later to classify every video frame
against the nearest stopping point.

Each anchor is the median Lab of one connected component selected from a coarse
Lab predicate. The plant anchor takes the largest component. The mushroom
anchor is scored for cap geometry *and* for standing bright against a dark
surround, which is what keeps the WIDE plate - where the cap is only ~0.05% of
frame - off the sidewalk slabs that share its lightness and neutrality.
"""

import json
import pathlib

import cv2
import numpy as np

ROOT = pathlib.Path(__file__).resolve().parent.parent
ASSETS = ROOT / "assets"
WORK = ROOT / "work"

REFS = [
    ("TIGHT", "ref_1_tight.jpg"),
    ("MID", "ref_2_mid.jpg"),
    ("WIDE", "ref_3_wide.jpg"),
]

# Analysis resolution: long edge, preserving aspect.
LONG_EDGE = 900


def to_lab(bgr_u8):
    """8-bit BGR -> CIELAB float32 with L in [0,100], a/b in ~[-128,127]."""
    return cv2.cvtColor(bgr_u8.astype(np.float32) / 255.0, cv2.COLOR_BGR2Lab)


def load_resized(path):
    img = cv2.imread(str(path), cv2.IMREAD_COLOR)
    if img is None:
        raise SystemExit(f"cannot read {path}")
    h, w = img.shape[:2]
    s = LONG_EDGE / max(h, w)
    return cv2.resize(img, (int(round(w * s)), int(round(h * s))), interpolation=cv2.INTER_AREA)


def pick_blob(predicate, cap_like, L=None, min_frac=0.00015, max_frac=0.45):
    """
    Choose one connected component from `predicate`.

    With cap_like=True the winner is scored as a mushroom cap: compact, roughly
    circular, and - decisively - a *bright island in a dark surround*. Shape
    alone is not enough, because a sidewalk slab is also bright, near-neutral
    and convex; what separates them is that the cap is ringed by soil and bark
    while the slab is ringed by more sidewalk. The surround-contrast term is
    what keeps the WIDE plate on the cap.

    With cap_like=False the largest component wins, which is the right rule for
    the sprawling plant mass.
    """
    mask = predicate.astype(np.uint8)
    mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, np.ones((5, 5), np.uint8))
    mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, np.ones((9, 9), np.uint8))
    n, labels, stats, cents = cv2.connectedComponentsWithStats(mask, connectivity=8)
    if n <= 1:
        return None, 0.0, None

    total = float(mask.size)
    best, best_score = None, -1.0
    for i in range(1, n):
        area = float(stats[i, cv2.CC_STAT_AREA])
        frac = area / total
        if frac < min_frac or frac > max_frac:
            continue
        if not cap_like:
            score = frac
        else:
            bw = float(stats[i, cv2.CC_STAT_WIDTH])
            bh = float(stats[i, cv2.CC_STAT_HEIGHT])
            if bw < 4 or bh < 4:
                continue
            extent = area / (bw * bh)          # fill of its bounding box
            aspect = min(bw, bh) / max(bw, bh)  # 1.0 for a circle

            blob = (labels == i).astype(np.uint8)
            r = max(3, int(round(np.sqrt(area) * 0.6)))
            ring = cv2.dilate(blob, np.ones((2 * r + 1, 2 * r + 1), np.uint8)) - blob
            if ring.sum() < 32:
                continue
            inner = float(np.median(L[blob.astype(bool)]))
            outer = float(np.median(L[ring.astype(bool)]))
            # Normalised island-ness: how far the blob rises above its ring.
            contrast = np.clip((inner - outer) / 40.0, 0.0, 1.0)

            # An ellipse fills ~0.785 of its box; reward that, reward roundness,
            # reward standing proud of the surround, and mildly reward size so a
            # speck of glare cannot win.
            score = contrast * extent * aspect * (frac ** 0.25)
        if score > best_score:
            best_score, best = score, i

    if best is None:
        return None, 0.0, None
    sel = labels == best
    return sel, float(sel.sum() / total), (
        int(stats[best, cv2.CC_STAT_LEFT]),
        int(stats[best, cv2.CC_STAT_TOP]),
        int(stats[best, cv2.CC_STAT_WIDTH]),
        int(stats[best, cv2.CC_STAT_HEIGHT]),
        float(cents[best][0]),
        float(cents[best][1]),
    )


def analyse(path, debug_name=None):
    bgr = load_resized(path)
    lab = to_lab(bgr)
    L, a, b = lab[..., 0], lab[..., 1], lab[..., 2]
    chroma = np.sqrt(a * a + b * b)

    # White cap: bright and weakly saturated. The cap carries warm tan scales,
    # so the chroma ceiling is generous rather than strictly neutral.
    white_pred = (L > 78) & (chroma < 26)
    white_sel, white_share, white_box = pick_blob(white_pred, cap_like=True, L=L, max_frac=0.08)
    white_med = np.median(lab[white_sel], axis=0).astype(float) if white_sel is not None else None

    # Green plants: a* well into the green half-plane, b* positive (yellow-green
    # foliage rather than cyan shadow), and not crushed to black.
    green_pred = (a < -6) & (b > 4) & (L > 18) & (L < 82)
    green_sel, green_share, _ = pick_blob(green_pred, cap_like=False, L=L)
    green_med = np.median(lab[green_sel], axis=0).astype(float) if green_sel is not None else None

    if debug_name and white_box is not None:
        dbg = bgr.copy()
        if green_sel is not None:
            dbg[green_sel] = (0.55 * dbg[green_sel] + 0.45 * np.array([255, 0, 255])).astype(np.uint8)
        x, y, w, h, cx, cy = white_box
        cv2.rectangle(dbg, (x, y), (x + w, y + h), (112, 25, 16), 3)
        cv2.drawMarker(dbg, (int(cx), int(cy)), (112, 25, 16), cv2.MARKER_CROSS, 28, 2)
        cv2.imwrite(str(WORK / f"anchor_debug_{debug_name}.jpg"), dbg,
                    [cv2.IMWRITE_JPEG_QUALITY, 88])

    # Whole-frame signature for stop-point classification.
    sig = {
        "L_mean": float(L.mean()),
        "a_mean": float(a.mean()),
        "b_mean": float(b.mean()),
        "chroma_mean": float(chroma.mean()),
        "white_share": float((white_pred).mean()),
        "green_share": float((green_pred).mean()),
    }
    return white_med, white_share, green_med, green_share, sig


def main():
    WORK.mkdir(parents=True, exist_ok=True)
    out = {"analysis_long_edge": LONG_EDGE, "stops": {}}
    whites, greens = [], []

    for name, fn in REFS:
        wm, ws, gm, gs, sig = analyse(ASSETS / fn, debug_name=name.lower())
        if wm is None or gm is None:
            raise SystemExit(f"{fn}: failed to isolate an anchor (white={wm}, green={gm})")
        whites.append(wm)
        greens.append(gm)
        out["stops"][name] = {
            "file": fn,
            "mushroom_lab": [round(v, 3) for v in wm],
            "mushroom_blob_share": round(ws, 5),
            "plant_lab": [round(v, 3) for v in gm],
            "plant_blob_share": round(gs, 5),
            "signature": {k: round(v, 4) for k, v in sig.items()},
        }
        print(
            f"{name:5s} {fn:18s} "
            f"mushroom Lab=({wm[0]:6.2f},{wm[1]:6.2f},{wm[2]:6.2f}) share={ws:.4f}   "
            f"plant Lab=({gm[0]:6.2f},{gm[1]:6.2f},{gm[2]:6.2f}) share={gs:.4f}"
        )

    # Consensus anchors: median across the three stopping points, so neither the
    # tight nor the wide exposure dominates the video-frame matching.
    out["anchor_mushroom_lab"] = [round(float(v), 3) for v in np.median(np.array(whites), axis=0)]
    out["anchor_plant_lab"] = [round(float(v), 3) for v in np.median(np.array(greens), axis=0)]
    print("\nconsensus mushroom Lab:", out["anchor_mushroom_lab"])
    print("consensus plant    Lab:", out["anchor_plant_lab"])

    (WORK / "anchors.json").write_text(json.dumps(out, indent=2) + "\n")
    print("\nwrote", WORK / "anchors.json")


if __name__ == "__main__":
    main()
