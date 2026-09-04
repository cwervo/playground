#!/usr/bin/env python3
"""
Stage 05 - the visual score.

Draws the analysis back onto the footage in a deliberate computer-vision
register - Hershey type, detector brackets, a sampled vector field, a running
readout - so the score shows its own working rather than decorating the video.

  navy      everything about the MUSHROOM: detector frame, corner brackets,
            crosshair, readout chips, the zoom curve in the transport strip
  magenta   everything about the PLANTS: the sampled optical-flow vector field
            and the stipple over the plant mask
  amber     drum cues only, so the two maximum zoom-ins and three maximum
            zoom-outs are visible as well as audible

Outputs the score frames, a filmstrip image sequence, cue plates, and the muxed
video with the stage-04 track.
"""

import json
import os
import pathlib
import shutil
import subprocess

import cv2
import numpy as np

ROOT = pathlib.Path(__file__).resolve().parent.parent
WORK = ROOT / "work"
OUT = ROOT / "out"
FRAMES = WORK / "frames"
SCORE_FRAMES = WORK / "score_frames"

W, H = 720, 1280
AW, AH = 288, 512
SX, SY = W / AW, H / AH

STRIP_H = 168
STRIP_Y = H - STRIP_H

# BGR
NAVY = (138, 58, 30)[::-1]        # #1E3A8A
NAVY_HI = (99, 155, 255)[::-1]    # lighter navy/azure for text
MAGENTA = (255, 0, 170)[::-1]     # #FF00AA
AMBER = (255, 176, 32)[::-1]      # #FFB020
INK = (14, 16, 22)
PAPER = (238, 240, 245)

FONT = cv2.FONT_HERSHEY_SIMPLEX
FONT2 = cv2.FONT_HERSHEY_PLAIN

STOP_NAMES = ["TIGHT", "MID", "WIDE"]


# ---------------------------------------------------------------- helpers ---

def lab_to_bgr(lab):
    px = np.array([[lab]], dtype=np.float32)
    bgr = cv2.cvtColor(px, cv2.COLOR_Lab2BGR)[0, 0]
    return tuple(int(np.clip(v * 255, 0, 255)) for v in bgr)


def smooth_cols(arr, win):
    if win % 2 == 0:
        win += 1
    pad = win // 2
    out = np.empty_like(arr, dtype=float)
    k = np.ones(win) / win
    a2 = np.atleast_2d(arr.T) if arr.ndim > 1 else arr[None, :]
    res = []
    for row in a2:
        res.append(np.convolve(np.pad(row, pad, mode="edge"), k, mode="valid"))
    res = np.array(res)
    return res.T if arr.ndim > 1 else res[0]


def text(img, s, org, scale=0.5, color=PAPER, thick=1, halo=True, font=FONT):
    if halo:
        cv2.putText(img, s, org, font, scale, INK, thick + 2, cv2.LINE_AA)
    cv2.putText(img, s, org, font, scale, color, thick, cv2.LINE_AA)


def chip(img, s, org, fg, bg, scale=0.42, pad=6):
    (tw, th), _ = cv2.getTextSize(s, FONT, scale, 1)
    x, y = org
    cv2.rectangle(img, (x, y - th - pad), (x + tw + 2 * pad, y + pad), bg, -1)
    cv2.rectangle(img, (x, y - th - pad), (x + tw + 2 * pad, y + pad), fg, 1)
    cv2.putText(img, s, (x + pad, y), FONT, scale, fg, 1, cv2.LINE_AA)
    return x + tw + 2 * pad


def brackets(img, x, y, w, h, color, arm=None, t=2):
    """Detector-style corner brackets rather than a closed rectangle."""
    arm = arm or int(np.clip(min(w, h) * 0.28, 10, 46))
    for cx, cy, dx, dy in ((x, y, 1, 1), (x + w, y, -1, 1),
                           (x, y + h, 1, -1), (x + w, y + h, -1, -1)):
        cv2.line(img, (cx, cy), (cx + dx * arm, cy), color, t, cv2.LINE_AA)
        cv2.line(img, (cx, cy), (cx, cy + dy * arm), color, t, cv2.LINE_AA)


def navy_frame(img, x, y, w, h):
    """
    Navy detector frame. A near-black underlay and a thin bright core keep it
    legible where the cap sits against dark bark, without giving up the navy.
    """
    cv2.rectangle(img, (x, y), (x + w, y + h), INK, 5, cv2.LINE_AA)
    cv2.rectangle(img, (x, y), (x + w, y + h), NAVY, 3, cv2.LINE_AA)
    cv2.rectangle(img, (x, y), (x + w, y + h), NAVY_HI, 1, cv2.LINE_AA)
    brackets(img, x, y, w, h, INK, t=6)
    brackets(img, x, y, w, h, NAVY_HI, t=2)


# ------------------------------------------------------------------ main ----

def main():
    d = np.load(WORK / "analysis.npz")
    meta = json.loads((WORK / "analysis.json").read_text())

    zoom = d["zoom"]
    cap_box = smooth_cols(d["cap_box"], 9)
    cap_cx = smooth_cols(d["cap_cx"], 9)
    cap_cy = smooth_cols(d["cap_cy"], 9)
    cap_area = d["cap_area"]
    plant_share = d["plant_share"]
    mean_L = d["mean_L"]
    mean_a = d["mean_a"]
    mean_b = d["mean_b"]
    flow_mag = d["flow_mag"]
    stop_idx = d["stop_idx"]
    GX, GY = d["GX"], d["GY"]
    vec_u = smooth_cols(d["vec_u"].reshape(len(zoom), -1), 5).reshape(d["vec_u"].shape)
    vec_v = smooth_cols(d["vec_v"].reshape(len(zoom), -1), 5).reshape(d["vec_v"].shape)
    vec_w = d["vec_w"]

    n = len(zoom)
    fps = meta["fps"]
    ins = [e["frame"] for e in meta["zoom_in_extrema"]]
    outs = [e["frame"] for e in meta["zoom_out_extrema"]]
    cues = sorted([(f, "IN") for f in ins] + [(f, "OUT") for f in outs])

    sw_m = lab_to_bgr(meta["anchor_mushroom_lab"])
    sw_p = lab_to_bgr(meta["anchor_plant_lab"])

    flow_n = np.clip(flow_mag / (np.percentile(flow_mag, 97) + 1e-9), 0, 1)

    preview = os.environ.get("PREVIEW")

    # Only a full run may clear the output directories. Doing this before
    # checking PREVIEW once wiped 508 finished frames to render a single
    # preview - a preview must never destroy a completed render.
    seq_dir = OUT / "score_seq"
    if not preview:
        for d_ in (SCORE_FRAMES, seq_dir):
            if d_.exists():
                shutil.rmtree(d_)
    SCORE_FRAMES.mkdir(parents=True, exist_ok=True)
    seq_dir.mkdir(parents=True, exist_ok=True)
    (OUT / "plates").mkdir(parents=True, exist_ok=True)

    # Which frames go into the printed filmstrip.
    seq_idx = sorted(set(list(np.linspace(0, n - 1, 36).astype(int))
                         + [f for f, _ in cues]))
    plate_idx = {f: f"cue_{i:02d}_{k}" for i, (f, k) in enumerate(cues)}

    todo = [int(v) for v in preview.split(",")] if preview else list(range(n))
    print(f"rendering {len(todo)} score frames at {W}x{H} ...")
    for i in todo:
        base = cv2.imread(str(FRAMES / f"f_{i + 1:04d}.jpg"), cv2.IMREAD_COLOR)
        if base is None:
            raise SystemExit(f"missing frame {i + 1}")
        img = base.copy()

        # Sit the footage back a little so the overlay reads as an overlay.
        img = cv2.addWeighted(img, 0.88, np.full_like(img, 0), 0.12, 0)

        # ---- magenta vector field over the plants ----------------------
        # Two rules hold this field together.
        #
        # 1. The raw flow during a whip-zoom is almost entirely camera
        #    ego-motion, which draws a starburst over the whole frame and says
        #    nothing about the plants. Subtracting the frame's median vector - a
        #    robust estimate of that global motion - leaves the plants' own
        #    movement relative to the shot, which is what this field claims to
        #    show.
        # 2. Confidence is carried by line weight, never by fading the colour
        #    towards black - scaling the BGR triple just makes a dark purple
        #    that disappears into the bark. Magenta stays magenta, over a dark
        #    underlay that keeps it readable on foliage.
        ego_u = float(np.median(vec_u[i]))
        ego_v = float(np.median(vec_v[i]))
        gain, max_len, min_len = 16.0, 42.0, 7.0
        for r in range(GX.shape[0]):
            for c in range(GX.shape[1]):
                wgt = float(vec_w[i, r, c])
                if wgt < 0.22:
                    continue
                x0 = int(GX[r, c] * SX)
                y0 = int(GY[r, c] * SY)
                u = (float(vec_u[i, r, c]) - ego_u) * gain * SX
                v = (float(vec_v[i, r, c]) - ego_v) * gain * SY
                mag = np.hypot(u, v)
                th = 2 if wgt > 0.55 else 1
                cv2.circle(img, (x0, y0), 2, INK, -1, cv2.LINE_AA)
                cv2.circle(img, (x0, y0), 1, MAGENTA, -1, cv2.LINE_AA)
                if mag > 1.5:
                    # Floor short vectors so slow sway reads; cap long ones so a
                    # violent frame cannot bury the picture.
                    scale = np.clip(mag, min_len, max_len) / mag
                    u, v = u * scale, v * scale
                    x1 = int(np.clip(x0 + u, 2, W - 3))
                    y1 = int(np.clip(y0 + v, 2, STRIP_Y - 3))
                    cv2.arrowedLine(img, (x0, y0), (x1, y1), INK, th + 2,
                                    cv2.LINE_AA, tipLength=0.34)
                    cv2.arrowedLine(img, (x0, y0), (x1, y1), MAGENTA, th,
                                    cv2.LINE_AA, tipLength=0.34)

        # ---- navy detector frame on the mushroom -----------------------
        bx, by, bw, bh = cap_box[i]
        true_w, true_h = int(bw * SX), int(bh * SY)
        # In the tight framings the cap is larger than the frame, so the raw box
        # would put every bracket off-screen. Clamp the drawn box into the live
        # picture area; the readout still reports the measured size.
        x0b, y0b = int(bx * SX), int(by * SY)
        x = int(np.clip(x0b, 8, W - 24))
        y = int(np.clip(y0b, 132, STRIP_Y - 24))
        w = int(np.clip(x0b + true_w, x + 16, W - 8)) - x
        h = int(np.clip(y0b + true_h, y + 16, STRIP_Y - 8)) - y
        navy_frame(img, x, y, w, h)

        cx = int(np.clip(cap_cx[i] * SX, 0, W - 1))
        cy = int(np.clip(cap_cy[i] * SY, 132, STRIP_Y - 1))
        cv2.drawMarker(img, (cx, cy), INK, cv2.MARKER_CROSS, 30, 4, cv2.LINE_AA)
        cv2.drawMarker(img, (cx, cy), NAVY_HI, cv2.MARKER_CROSS, 28, 1, cv2.LINE_AA)

        label = f"MUSHROOM  dE00<{meta['deltaE2000_radius']['mushroom']:.0f}"
        chip(img, label, (x, int(np.clip(y - 12, 148, STRIP_Y - 60))), NAVY_HI, INK)
        chip(img, f"{true_w}x{true_h}px  {cap_area[i] * 100:5.2f}% area",
             (x, int(np.clip(y + h + 26, 176, STRIP_Y - 12))), NAVY_HI, INK, scale=0.38)

        # ---- HUD -------------------------------------------------------
        panel = img[0:126, 0:W].copy()
        img[0:126, 0:W] = cv2.addWeighted(panel, 0.30, np.zeros_like(panel), 0.70, 0)
        cv2.line(img, (0, 126), (W, 126), NAVY, 2, cv2.LINE_AA)

        t = i / fps
        text(img, "MUSHROOM SCORE", (16, 28), 0.58, PAPER, 2, halo=False)
        text(img, "CIELAB / dE00 . IMG_5823", (16, 47), 0.36, NAVY_HI, 1, halo=False)
        text(img, f"{int(t // 60):02d}:{t % 60:05.2f}", (W - 152, 28), 0.58, PAPER, 2, halo=False)
        text(img, f"FRAME {i + 1:04d}/{n}", (W - 152, 47), 0.36, NAVY_HI, 1, halo=False)

        st = STOP_NAMES[stop_idx[i]]
        chip(img, f"STOP {st}", (16, 76), AMBER if st == "TIGHT" else PAPER, INK, scale=0.44)

        # anchor swatches, on their own row under the stop chip
        cv2.rectangle(img, (16, 90), (46, 112), sw_m, -1)
        cv2.rectangle(img, (16, 90), (46, 112), NAVY_HI, 1)
        cv2.rectangle(img, (52, 90), (82, 112), sw_p, -1)
        cv2.rectangle(img, (52, 90), (82, 112), MAGENTA, 1)
        text(img, "ANCHORS", (90, 105), 0.32, (150, 150, 150), 1, halo=False)

        text(img, f"L* {mean_L[i]:5.1f}   a* {mean_a[i]:+5.1f}   b* {mean_b[i]:+5.1f}",
             (200, 80), 0.42, PAPER, 1, halo=False)
        text(img, f"ZOOM {zoom[i]:.3f}   FLOW {flow_n[i]:.2f}   GREEN {plant_share[i] * 100:4.1f}%",
             (200, 105), 0.38, PAPER, 1, halo=False)

        # ---- transport strip -------------------------------------------
        strip = img[STRIP_Y:H, 0:W].copy()
        img[STRIP_Y:H, 0:W] = cv2.addWeighted(strip, 0.20, np.zeros_like(strip), 0.80, 0)
        cv2.line(img, (0, STRIP_Y), (W, STRIP_Y), NAVY, 2, cv2.LINE_AA)

        m = 24
        pw = W - 2 * m
        ribbon_y = STRIP_Y + 20
        # stop-point ribbon
        for k in range(n):
            xx = m + int(k / (n - 1) * pw)
            tone = {0: NAVY_HI, 1: (90, 70, 60), 2: (52, 40, 34)}[int(stop_idx[k])]
            cv2.line(img, (xx, ribbon_y), (xx, ribbon_y + 8), tone, 1)
        text(img, "TIGHT / MID / WIDE", (m, ribbon_y - 6), 0.34, PAPER, 1, halo=False)

        # zoom curve
        cy0 = STRIP_Y + 46
        ch_ = 82
        pts = [(m + int(k / (n - 1) * pw), int(cy0 + ch_ - zoom[k] * ch_))
               for k in range(0, n, 2)]
        cv2.polylines(img, [np.array(pts, np.int32)], False, NAVY, 4, cv2.LINE_AA)
        cv2.polylines(img, [np.array(pts, np.int32)], False, NAVY_HI, 2, cv2.LINE_AA)
        cv2.line(img, (m, cy0 + ch_), (m + pw, cy0 + ch_), (70, 70, 70), 1)

        # cue ticks
        for f, kind in cues:
            xx = m + int(f / (n - 1) * pw)
            col = AMBER
            cv2.line(img, (xx, cy0 - 4), (xx, cy0 + ch_ + 6), col, 1, cv2.LINE_AA)
            tri = np.array([[xx, cy0 - 6], [xx - 5, cy0 - 15], [xx + 5, cy0 - 15]], np.int32) \
                if kind == "IN" else \
                np.array([[xx, cy0 - 15], [xx - 5, cy0 - 6], [xx + 5, cy0 - 6]], np.int32)
            cv2.fillPoly(img, [tri], col, cv2.LINE_AA)

        # playhead
        px = m + int(i / (n - 1) * pw)
        cv2.line(img, (px, STRIP_Y + 14), (px, H - 12), PAPER, 1, cv2.LINE_AA)
        cv2.circle(img, (px, int(cy0 + ch_ - zoom[i] * ch_)), 5, PAPER, -1, cv2.LINE_AA)
        cv2.circle(img, (px, int(cy0 + ch_ - zoom[i] * ch_)), 5, INK, 1, cv2.LINE_AA)

        # ---- cue flash --------------------------------------------------
        for f, kind in cues:
            age = i - f
            if 0 <= age < 6:
                k = 1.0 - age / 6.0
                th = int(3 + 13 * k)
                cv2.rectangle(img, (0, 0), (W - 1, H - 1), AMBER, th, cv2.LINE_AA)
                lab = "MAX ZOOM IN" if kind == "IN" else "MAX ZOOM OUT"
                chip(img, f"{lab}  <  DRUM", (m, STRIP_Y - 18), INK, AMBER, scale=0.5)

        cv2.imwrite(str(SCORE_FRAMES / f"s_{i:04d}.png"), img,
                    [cv2.IMWRITE_PNG_COMPRESSION, 3])

        if i in plate_idx:
            cv2.imwrite(str(OUT / "plates" / f"{plate_idx[i]}_f{i:04d}.png"), img,
                        [cv2.IMWRITE_PNG_COMPRESSION, 6])
        if i in seq_idx:
            k = seq_idx.index(i)
            small = cv2.resize(img, (540, 960), interpolation=cv2.INTER_AREA)
            cv2.imwrite(str(seq_dir / f"score_{k:03d}_f{i:04d}_t{i / fps:06.2f}s.png"),
                        small, [cv2.IMWRITE_PNG_COMPRESSION, 9])

        if i % 50 == 0:
            print(f"  {i:4d}/{n}")

    if preview:
        print("preview only; skipping encode")
        return

    print("encoding video ...")
    subprocess.run([
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
        "-framerate", f"{fps:.6f}", "-i", str(SCORE_FRAMES / "s_%04d.png"),
        "-i", str(OUT / "mushroom_track.wav"),
        "-c:v", "libx264", "-preset", "slower", "-crf", "20",
        "-pix_fmt", "yuv420p", "-profile:v", "high",
        "-c:a", "aac", "-b:a", "192k", "-shortest",
        "-movflags", "+faststart",
        str(OUT / "mushroom_visual_score.mp4"),
    ], check=True)

    # The mini track as a standalone deliverable.
    subprocess.run([
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
        "-i", str(OUT / "mushroom_track.wav"),
        "-c:a", "aac", "-b:a", "256k", str(OUT / "mushroom_track.m4a"),
    ], check=True)

    print("wrote", OUT / "mushroom_visual_score.mp4")
    print("wrote", OUT / "mushroom_track.m4a")
    print(f"wrote {len(seq_idx)} score_seq images, {len(plate_idx)} cue plates")


if __name__ == "__main__":
    main()
