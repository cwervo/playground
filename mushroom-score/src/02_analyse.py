#!/usr/bin/env python3
"""
Stage 02 - per-frame CIELAB / motion analysis.

For every frame of the source video this stage computes:

  * deltaE2000 distance to the MUSHROOM anchor and to the PLANT anchor,
    thresholded into two masks;
  * the tracked mushroom cap (largest cap-like component of the mushroom mask,
    with temporal gating so the track cannot teleport);
  * Farneback dense optical flow, sampled on a grid, restricted to the plant
    mask - this is the magenta vector field;
  * a zoom curve, taken from apparent cap scale (sqrt of cap area) and
    cross-checked against the radial divergence of the flow field;
  * the nearest reference stopping point (TIGHT / MID / WIDE) per frame.

Output: work/analysis.npz (dense arrays) + work/analysis.json (summary,
extrema, stop-point segments). Nothing here knows about music.
"""

import json
import pathlib

import cv2
import numpy as np

ROOT = pathlib.Path(__file__).resolve().parent.parent
WORK = ROOT / "work"
FRAMES = WORK / "frames"

FPS = 30000.0 / 1001.0          # 29.97
AW, AH = 288, 512               # analysis resolution (portrait, /2.5 of 720x1280)
GRID = 24                       # vector-field sample spacing, analysis px

DE_MUSHROOM = 16.0              # deltaE2000 acceptance radius, cap
DE_PLANT = 20.0                 # deltaE2000 acceptance radius, plants


# ---------------------------------------------------------------- colour ----

def to_lab(bgr_u8):
    return cv2.cvtColor(bgr_u8.astype(np.float32) / 255.0, cv2.COLOR_BGR2Lab)


def delta_e2000(lab_img, lab_ref, kL=1.0, kC=1.0, kH=1.0):
    """
    Vectorised CIEDE2000 between every pixel of `lab_img` (H,W,3) and a single
    reference Lab triplet. Returns (H,W) float32.

    Full CIE formulation including the hue-rotation term - the point of the
    piece is that the colour metric is perceptual, so the cheap CIE76 Euclidean
    distance would undercut it.
    """
    L1 = lab_img[..., 0].astype(np.float64)
    a1 = lab_img[..., 1].astype(np.float64)
    b1 = lab_img[..., 2].astype(np.float64)
    L2, a2, b2 = (float(v) for v in lab_ref)

    C1 = np.sqrt(a1 * a1 + b1 * b1)
    C2 = np.sqrt(a2 * a2 + b2 * b2)
    Cbar = 0.5 * (C1 + C2)

    C7 = Cbar ** 7
    G = 0.5 * (1.0 - np.sqrt(C7 / (C7 + 25.0 ** 7)))

    a1p = (1.0 + G) * a1
    a2p = (1.0 + G) * a2
    C1p = np.sqrt(a1p * a1p + b1 * b1)
    C2p = np.sqrt(a2p * a2p + b2 * b2)

    h1p = np.degrees(np.arctan2(b1, a1p)) % 360.0
    h2p = np.degrees(np.arctan2(b2, a2p)) % 360.0

    dLp = L2 - L1
    dCp = C2p - C1p

    dhp = h2p - h1p
    dhp = np.where(dhp > 180.0, dhp - 360.0, dhp)
    dhp = np.where(dhp < -180.0, dhp + 360.0, dhp)
    dhp = np.where(C1p * C2p == 0.0, 0.0, dhp)
    dHp = 2.0 * np.sqrt(C1p * C2p) * np.sin(np.radians(dhp) / 2.0)

    Lbarp = 0.5 * (L1 + L2)
    Cbarp = 0.5 * (C1p + C2p)

    hsum = h1p + h2p
    hdiff = np.abs(h1p - h2p)
    hbarp = np.where(
        C1p * C2p == 0.0, hsum,
        np.where(hdiff <= 180.0, 0.5 * hsum,
                 np.where(hsum < 360.0, 0.5 * (hsum + 360.0), 0.5 * (hsum - 360.0))))

    T = (1.0
         - 0.17 * np.cos(np.radians(hbarp - 30.0))
         + 0.24 * np.cos(np.radians(2.0 * hbarp))
         + 0.32 * np.cos(np.radians(3.0 * hbarp + 6.0))
         - 0.20 * np.cos(np.radians(4.0 * hbarp - 63.0)))

    dtheta = 30.0 * np.exp(-(((hbarp - 275.0) / 25.0) ** 2))
    Cbarp7 = Cbarp ** 7
    RC = 2.0 * np.sqrt(Cbarp7 / (Cbarp7 + 25.0 ** 7))
    SL = 1.0 + (0.015 * (Lbarp - 50.0) ** 2) / np.sqrt(20.0 + (Lbarp - 50.0) ** 2)
    SC = 1.0 + 0.045 * Cbarp
    SH = 1.0 + 0.015 * Cbarp * T
    RT = -np.sin(np.radians(2.0 * dtheta)) * RC

    dE = np.sqrt(
        (dLp / (kL * SL)) ** 2
        + (dCp / (kC * SC)) ** 2
        + (dHp / (kH * SH)) ** 2
        + RT * (dCp / (kC * SC)) * (dHp / (kH * SH))
    )
    return dE.astype(np.float32)


# ------------------------------------------------------------- utilities ----

def smooth(x, win):
    """Zero-phase moving average with edge padding."""
    if win < 3:
        return x.copy()
    if win % 2 == 0:
        win += 1
    pad = win // 2
    xp = np.pad(x, pad, mode="edge")
    k = np.ones(win) / win
    return np.convolve(xp, k, mode="valid")


def find_extrema(y, min_sep, prominence):
    """
    Local maxima and minima of `y` with true topographic prominence at least
    `prominence`, separated by at least `min_sep` samples. Returns
    (max_idx, min_idx).

    Prominence is measured by descending from each peak until the signal rises
    above it again (or the clip ends), not over a fixed window. A fixed window
    fails badly here: the camera holds at maximum zoom for over a second, so a
    locally-measured prominence for that plateau is near zero even though it is
    one of the two principal peaks of the piece.
    """
    def _peaks(sig):
        n = len(sig)
        cand = [i for i in range(1, n - 1)
                if sig[i] >= sig[i - 1] and sig[i] >= sig[i + 1]]
        scored = []
        for i in cand:
            # Walk left until we exceed the peak; note the deepest valley.
            lmin = sig[i]
            j = i - 1
            while j >= 0 and sig[j] <= sig[i]:
                lmin = min(lmin, sig[j])
                j -= 1
            rmin = sig[i]
            j = i + 1
            while j < n and sig[j] <= sig[i]:
                rmin = min(rmin, sig[j])
                j += 1
            prom = sig[i] - max(lmin, rmin)
            if prom >= prominence:
                scored.append((prom, sig[i], i))
        # Keep the most prominent, enforcing separation.
        scored.sort(reverse=True)
        kept = []
        for _, _, i in scored:
            if all(abs(i - j) >= min_sep for j in kept):
                kept.append(i)
        return sorted(kept)

    return _peaks(y), _peaks(-y)


# ---------------------------------------------------------- cap tracking ----

def track_cap(frame_cands, n, AW, AH, cap_area, cap_cx, cap_cy, cap_box, cap_ok):
    """
    Resolve which candidate blob is the mushroom, for every frame.

    Frame-local scoring cannot do this: in the wide framings a sunlit sidewalk
    slab beats the cap on every static cue, because the cap is only a couple of
    hundred pixels. What separates them is *continuity* - across a frame pair
    the cap barely moves and barely changes size, while jumping to the sidewalk
    means a large positional leap and a hundred-fold area jump.

    So: seed on the frame whose best candidate is most unambiguous, then
    propagate outward in both directions, each step preferring the candidate
    that continues the current position and scale.
    """
    diag = float(np.hypot(AW, AH))

    # Seed: strongest shape x contrast x size anywhere in the clip. In practice
    # this lands inside a tight framing, where the cap is unmistakable.
    seed_i, seed_k, seed_score = None, None, -1.0
    for i, cands in enumerate(frame_cands):
        for k, c in enumerate(cands):
            s = c["shape"] * c["contrast"] * (c["area"] ** 0.5)
            if s > seed_score:
                seed_score, seed_i, seed_k = s, i, k
    if seed_i is None:
        return

    def accept(i, c):
        cap_area[i] = c["area"] / float(AW * AH)
        cap_cx[i], cap_cy[i] = c["cx"], c["cy"]
        cap_box[i] = [c["x"], c["y"], c["w"], c["h"]]
        cap_ok[i] = True

    accept(seed_i, frame_cands[seed_i][seed_k])
    print(f"  cap track seeded at frame {seed_i} "
          f"(area={frame_cands[seed_i][seed_k]['area']:.0f} px, score={seed_score:.1f})")

    def walk(order):
        ref = frame_cands[seed_i][seed_k]
        for i in order:
            best, best_s = None, -1.0
            for c in frame_cands[i]:
                d = np.hypot(c["cx"] - ref["cx"], c["cy"] - ref["cy"]) / diag
                ratio = np.log(max(c["area"], 1.0) / max(ref["area"], 1.0))
                # Position continuity, scale continuity, then static plausibility.
                s = (np.exp(-d / 0.09)
                     * np.exp(-(ratio ** 2) / (2 * 0.55 ** 2))
                     * (0.35 + 0.65 * c["shape"])
                     * (0.35 + 0.65 * c["contrast"]))
                if s > best_s:
                    best_s, best = s, c
            # A weak best means occlusion or a blown-out frame; hold the last
            # good reference and let the gap be interpolated afterwards.
            if best is not None and best_s > 0.02:
                accept(i, best)
                ref = best

    walk(range(seed_i + 1, n))
    walk(range(seed_i - 1, -1, -1))
    print(f"  cap tracked on {int(cap_ok.sum())}/{n} frames")


# ---------------------------------------------------------------- main ------

def main():
    anchors = json.loads((WORK / "anchors.json").read_text())
    lab_mush = anchors["anchor_mushroom_lab"]
    lab_plant = anchors["anchor_plant_lab"]

    # Reference stop-point signatures, for nearest-stop classification.
    stop_names = ["TIGHT", "MID", "WIDE"]
    stop_sig = np.array([
        [anchors["stops"][s]["signature"]["L_mean"],
         anchors["stops"][s]["signature"]["a_mean"],
         anchors["stops"][s]["signature"]["b_mean"],
         anchors["stops"][s]["signature"]["green_share"] * 100.0,
         anchors["stops"][s]["mushroom_blob_share"] * 300.0]
        for s in stop_names
    ])

    files = sorted(FRAMES.glob("f_*.jpg"))
    n = len(files)
    if n == 0:
        raise SystemExit("no frames; run the extract step first")
    print(f"analysing {n} frames at {AW}x{AH} ...")

    cap_area = np.zeros(n)
    cap_cx = np.zeros(n)
    cap_cy = np.zeros(n)
    cap_box = np.zeros((n, 4))
    cap_ok = np.zeros(n, dtype=bool)
    plant_share = np.zeros(n)
    mush_share = np.zeros(n)
    mean_L = np.zeros(n)
    mean_a = np.zeros(n)
    mean_b = np.zeros(n)
    plant_L = np.zeros(n)
    flow_mag = np.zeros(n)
    flow_div = np.zeros(n)
    stop_idx = np.zeros(n, dtype=int)

    gx = np.arange(GRID // 2, AW, GRID)
    gy = np.arange(GRID // 2, AH, GRID)
    GX, GY = np.meshgrid(gx, gy)
    vec_u = np.zeros((n, len(gy), len(gx)), dtype=np.float32)
    vec_v = np.zeros((n, len(gy), len(gx)), dtype=np.float32)
    vec_w = np.zeros((n, len(gy), len(gx)), dtype=np.float32)  # plant weight

    prev_gray = None
    frame_cands = []  # per-frame cap candidates, resolved by tracking in pass B

    for i, f in enumerate(files):
        bgr = cv2.imread(str(f), cv2.IMREAD_COLOR)
        small = cv2.resize(bgr, (AW, AH), interpolation=cv2.INTER_AREA)
        lab = to_lab(small)
        L, a, b = lab[..., 0], lab[..., 1], lab[..., 2]
        mean_L[i], mean_a[i], mean_b[i] = L.mean(), a.mean(), b.mean()

        dE_m = delta_e2000(lab, lab_mush)
        dE_p = delta_e2000(lab, lab_plant)
        m_mask = ((dE_m < DE_MUSHROOM) & (L > 70)).astype(np.uint8)
        p_mask = ((dE_p < DE_PLANT) & (a < -3)).astype(np.uint8)

        m_mask = cv2.morphologyEx(m_mask, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
        m_mask = cv2.morphologyEx(m_mask, cv2.MORPH_CLOSE, np.ones((7, 7), np.uint8))
        p_mask = cv2.morphologyEx(p_mask, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))

        mush_share[i] = m_mask.mean()
        plant_share[i] = p_mask.mean()
        plant_L[i] = float(L[p_mask.astype(bool)].mean()) if p_mask.any() else 0.0

        # --- candidate cap components, scored for shape and island-ness ------
        # No frame-local rule reliably separates the cap from a sunlit sidewalk
        # slab: both are bright, near-neutral and convex. The candidates are
        # only *described* here; which one is the mushroom is decided in pass B
        # by tracking, where scale and position continuity settle it.
        nc, labels, stats, cents = cv2.connectedComponentsWithStats(m_mask, connectivity=8)
        cands = []
        for k in range(1, nc):
            area = float(stats[k, cv2.CC_STAT_AREA])
            if area < 12:
                continue
            bw = float(stats[k, cv2.CC_STAT_WIDTH])
            bh = float(stats[k, cv2.CC_STAT_HEIGHT])
            extent = area / max(1.0, bw * bh)
            aspect = min(bw, bh) / max(bw, bh)

            blob = (labels == k).astype(np.uint8)
            r = int(np.clip(round(np.sqrt(area) * 0.3), 3, 10))
            ring = cv2.dilate(blob, np.ones((2 * r + 1, 2 * r + 1), np.uint8)) - blob
            if ring.sum() < 16:
                continue
            contrast = float(np.clip(
                (float(np.median(L[blob.astype(bool)]))
                 - float(np.median(L[ring.astype(bool)]))) / 30.0, 0.0, 1.0))

            cands.append({
                "area": area, "cx": float(cents[k][0]), "cy": float(cents[k][1]),
                "x": int(stats[k, cv2.CC_STAT_LEFT]), "y": int(stats[k, cv2.CC_STAT_TOP]),
                "w": int(bw), "h": int(bh),
                "shape": float(extent * aspect), "contrast": contrast,
            })
        frame_cands.append(cands)

        # --- optical flow, sampled on the grid, weighted by the plant mask ---
        gray = cv2.cvtColor(small, cv2.COLOR_BGR2GRAY)
        if prev_gray is not None:
            flow = cv2.calcOpticalFlowFarneback(
                prev_gray, gray, None,
                pyr_scale=0.5, levels=3, winsize=21,
                iterations=3, poly_n=5, poly_sigma=1.2, flags=0)
            u = flow[..., 0]
            v = flow[..., 1]
            flow_mag[i] = float(np.sqrt(u * u + v * v).mean())

            # Radial divergence about frame centre: positive = expanding =
            # pushing in. This is the independent check on the zoom curve.
            yy, xx = np.mgrid[0:AH, 0:AW].astype(np.float32)
            rx = xx - AW / 2.0
            ry = yy - AH / 2.0
            rn = np.sqrt(rx * rx + ry * ry) + 1e-6
            flow_div[i] = float(((u * rx + v * ry) / rn).mean())

            pf = cv2.GaussianBlur(p_mask.astype(np.float32), (0, 0), 3)
            vec_u[i] = u[GY, GX]
            vec_v[i] = v[GY, GX]
            vec_w[i] = pf[GY, GX]
        prev_gray = gray

        if i % 60 == 0:
            print(f"  frame {i:4d}/{n}  cands={len(frame_cands[i]):2d} "
                  f"plant={plant_share[i]:.3f}")

    # ---- pass B: resolve the cap track ------------------------------------
    track_cap(frame_cands, n, AW, AH, cap_area, cap_cx, cap_cy, cap_box, cap_ok)

    # ---- nearest reference stopping point, with hysteresis -----------------
    # Plain per-frame argmin flickers between MID and TIGHT during a fast push,
    # and because the pad takes its chord from this state, every flicker became
    # an audible harmonic lurch. A challenger must therefore be clearly better
    # (SWITCH_RATIO) and stay better for SWITCH_HOLD frames before the state
    # moves. The camera's real dwell on a framing is far longer than the hold,
    # so genuine changes still land within ~0.2 s.
    SWITCH_RATIO = 0.88
    SWITCH_HOLD = int(round(0.20 * FPS))

    dists = np.zeros((n, len(stop_names)))
    for i in range(n):
        fv = np.array([mean_L[i], mean_a[i], mean_b[i],
                       plant_share[i] * 100.0, cap_area[i] * 300.0])
        dists[i] = np.linalg.norm(stop_sig - fv, axis=1)

    state = int(np.argmin(dists[0]))
    pending, pending_n = state, 0
    for i in range(n):
        cand = int(np.argmin(dists[i]))
        if cand == state:
            pending, pending_n = state, 0
        elif dists[i][cand] < dists[i][state] * SWITCH_RATIO:
            pending_n = pending_n + 1 if cand == pending else 1
            pending = cand
            if pending_n >= SWITCH_HOLD:
                state, pending_n = cand, 0
        else:
            pending_n = 0
        stop_idx[i] = state

    raw_stop = np.argmin(dists, axis=1)
    print(f"  stop classifier: {int((raw_stop[1:] != raw_stop[:-1]).sum())} raw transitions "
          f"-> {int((stop_idx[1:] != stop_idx[:-1]).sum())} after hysteresis")

    # ---- plant motion, with camera ego-motion removed ---------------------
    # The residual after subtracting each frame's global flow is what actually
    # describes the weeds moving, as opposed to the camera moving past them.
    # Stage 05 draws this; stage 03 uses it to gate the hats, so the kit
    # thickens with plant movement rather than with camera movement.
    ego_u = np.median(vec_u.reshape(n, -1), axis=1)
    ego_v = np.median(vec_v.reshape(n, -1), axis=1)
    ru = vec_u - ego_u[:, None, None]
    rv = vec_v - ego_v[:, None, None]
    rmag = np.sqrt(ru * ru + rv * rv)
    wsum = vec_w.reshape(n, -1).sum(axis=1)
    plant_motion = np.where(
        wsum > 1e-6,
        (rmag * vec_w).reshape(n, -1).sum(axis=1) / np.maximum(wsum, 1e-6),
        0.0)
    plant_motion = smooth(plant_motion, 5)

    # ---- fill cap-track gaps, then build the zoom curve -------------------
    if not cap_ok.any():
        raise SystemExit("cap never tracked; loosen DE_MUSHROOM")
    idx = np.arange(n)
    for arr in (cap_area, cap_cx, cap_cy):
        arr[~cap_ok] = np.interp(idx[~cap_ok], idx[cap_ok], arr[cap_ok])
    for c in range(4):
        cap_box[~cap_ok, c] = np.interp(idx[~cap_ok], idx[cap_ok], cap_box[cap_ok, c])

    cap_scale = np.sqrt(np.maximum(cap_area, 0.0))        # linear apparent size
    zoom_raw = smooth(cap_scale, 9)
    lo, hi = np.percentile(zoom_raw, 1), np.percentile(zoom_raw, 99)
    zoom = np.clip((zoom_raw - lo) / max(1e-9, hi - lo), 0.0, 1.0)
    zoom_s = smooth(zoom, 15)
    zoom_vel = np.gradient(zoom_s) * FPS                   # units/sec

    div_s = smooth(flow_div, 15)
    # Correlation between the two independent zoom estimates, as a sanity read.
    zc = float(np.corrcoef(np.gradient(zoom_s), div_s)[0, 1])

    # ---- extrema = the drum cues ----------------------------------------
    min_sep = int(round(0.9 * FPS))
    maxima, minima = find_extrema(zoom_s, min_sep=min_sep, prominence=0.18)

    # The clip opens wide and ends wide. Neither pole is an interior peak, but
    # both are genuine "maximally out" moments and must be cues. The head cue is
    # the first frame; the tail cue is where the closing pull-out actually
    # settles, not the arbitrary last frame.
    if zoom_s[0] < 0.35 and all(abs(0 - j) >= min_sep for j in minima):
        minima = [0] + minima
    if maxima:
        after = np.where(zoom_s[maxima[-1]:] < 0.05)[0]
        tail = int(maxima[-1] + after[0]) if len(after) else n - 1
        if zoom_s[tail] < 0.35 and all(abs(tail - j) >= min_sep for j in minima):
            minima = sorted(minima + [tail])

    print(f"\nzoom-in  peaks (max zoom): {maxima}")
    print(f"zoom-out peaks (min zoom): {minima}")
    print(f"cap-scale vs flow-divergence correlation: {zc:+.3f}")

    np.savez_compressed(
        WORK / "analysis.npz",
        zoom=zoom_s, zoom_raw=zoom, zoom_vel=zoom_vel,
        cap_area=cap_area, cap_cx=cap_cx, cap_cy=cap_cy, cap_box=cap_box,
        cap_ok=cap_ok, plant_share=plant_share, mush_share=mush_share,
        plant_L=plant_L, mean_L=mean_L, mean_a=mean_a, mean_b=mean_b,
        plant_motion=plant_motion, stop_dists=dists,
        flow_mag=flow_mag, flow_div=div_s, stop_idx=stop_idx,
        vec_u=vec_u, vec_v=vec_v, vec_w=vec_w, GX=GX, GY=GY,
    )

    # Stop-point segments (runs of at least ~0.4 s), for the timing readme.
    segs = []
    run_start = 0
    for i in range(1, n + 1):
        if i == n or stop_idx[i] != stop_idx[run_start]:
            if i - run_start >= int(0.4 * FPS):
                segs.append({"stop": stop_names[stop_idx[run_start]],
                             "start_frame": int(run_start), "end_frame": int(i - 1),
                             "start_s": round(run_start / FPS, 3),
                             "end_s": round((i - 1) / FPS, 3)})
            run_start = i

    summary = {
        "frames": n, "fps": round(FPS, 4), "duration_s": round(n / FPS, 3),
        "analysis_size": [AW, AH], "grid": GRID,
        "deltaE2000_radius": {"mushroom": DE_MUSHROOM, "plant": DE_PLANT},
        "anchor_mushroom_lab": lab_mush, "anchor_plant_lab": lab_plant,
        "zoom_in_extrema": [{"frame": int(i), "t": round(i / FPS, 3),
                             "zoom": round(float(zoom_s[i]), 4)} for i in maxima],
        "zoom_out_extrema": [{"frame": int(i), "t": round(i / FPS, 3),
                              "zoom": round(float(zoom_s[i]), 4)} for i in minima],
        "capscale_vs_divergence_corr": round(zc, 4),
        "stop_segments": segs,
    }
    (WORK / "analysis.json").write_text(json.dumps(summary, indent=2) + "\n")
    print("wrote", WORK / "analysis.npz", "and", WORK / "analysis.json")


if __name__ == "__main__":
    main()
