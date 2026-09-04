#!/usr/bin/env python3
"""
Stage 06 - the postal artifact.

Builds the two images the piece actually gets posted as:

  mushroom_score_post_4x5.png    1080x1350  Instagram feed
  mushroom_score_cover_9x16.png  1080x1920  Instagram story / TikTok cover

Both are laid out from the same data the score is: the three stopping points,
the zoom curve, the cue times, the CIELAB anchors. The palette is the score's
own - navy for the mushroom, magenta for the plant vector field, amber for the
drum cues - so the post and the video read as one object.
"""

import json
import pathlib
import shutil

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
WORK = ROOT / "work"
OUT = ROOT / "out"
SCORE_FRAMES = WORK / "score_frames"
FONTS = pathlib.Path("/mnt/skills/examples/canvas-design/canvas-fonts")

NAVY = (30, 58, 138)
NAVY_DEEP = (11, 16, 32)
NAVY_MID = (23, 34, 74)
MAGENTA = (255, 0, 170)
AMBER = (255, 176, 32)
PAPER = (238, 240, 245)
DIM = (138, 148, 172)

# Video frames chosen to stand for each stopping point.
STOP_FRAMES = {"WIDE": 60, "MID": 110, "TIGHT": 200}

# The live picture area of a score frame, i.e. minus HUD and transport strip.
CROP = (0, 126, 720, 1112)


def font(name, size):
    return ImageFont.truetype(str(FONTS / f"{name}.ttf"), size)


def tracked(draw, xy, s, f, fill, track=0):
    """Draw text with letter-spacing, returning the advance width."""
    x, y = xy
    for ch in s:
        draw.text((x, y), ch, font=f, fill=fill)
        x += draw.textlength(ch, font=f) + track
    return x - xy[0]


def tracked_w(draw, s, f, track=0):
    return sum(draw.textlength(c, font=f) for c in s) + track * max(0, len(s) - 1)


def panel(frame_no, size):
    src = SCORE_FRAMES / f"s_{frame_no:04d}.png"
    if not src.exists():
        raise SystemExit(f"missing {src}; run stage 05 first")
    im = Image.open(src).convert("RGB").crop(CROP)
    # Cover-fit into the target box.
    tw, th = size
    sw, sh = im.size
    s = max(tw / sw, th / sh)
    im = im.resize((int(sw * s + 1), int(sh * s + 1)), Image.LANCZOS)
    left = (im.width - tw) // 2
    top = (im.height - th) // 2
    return im.crop((left, top, left + tw, top + th))


def rule(draw, x0, y, x1, color=NAVY, w=2):
    draw.line([(x0, y), (x1, y)], fill=color, width=w)


def curve_block(draw, x, y, w, h, zoom, cues, n):
    """The zoom curve, drawn as the score's spine."""
    draw.rectangle([x, y, x + w, y + h], fill=NAVY_MID)
    inner = 14
    cx0, cy0 = x + inner, y + inner
    cw, chh = w - 2 * inner, h - 2 * inner

    for g in range(1, 4):
        gy = cy0 + chh * g / 4
        draw.line([(cx0, gy), (cx0 + cw, gy)], fill=(38, 52, 100), width=1)

    pts = [(cx0 + cw * k / (n - 1), cy0 + chh - zoom[k] * chh) for k in range(0, n, 2)]
    draw.line(pts, fill=NAVY, width=8, joint="curve")
    draw.line(pts, fill=(120, 168, 255), width=3, joint="curve")

    for f, kind in cues:
        px = cx0 + cw * f / (n - 1)
        draw.line([(px, cy0 - 6), (px, cy0 + chh + 6)], fill=AMBER, width=2)
        if kind == "IN":
            tri = [(px, cy0 - 8), (px - 8, cy0 - 22), (px + 8, cy0 - 22)]
        else:
            tri = [(px, cy0 - 22), (px - 8, cy0 - 8), (px + 8, cy0 - 8)]
        draw.polygon(tri, fill=AMBER)
    return cx0, cy0, cw, chh


def legend_row(draw, x, y, color, title, body, f_title, f_body, swatch=18):
    draw.rectangle([x, y + 3, x + swatch, y + 3 + swatch], fill=color)
    draw.text((x + swatch + 14, y), title, font=f_title, fill=PAPER)
    draw.text((x + swatch + 14, y + 26), body, font=f_body, fill=DIM)


def build_4x5(zoom, cues, n, meta, ev):
    W, H = 1080, 1350
    im = Image.new("RGB", (W, H), NAVY_DEEP)
    d = ImageDraw.Draw(im)

    f_title = font("BigShoulders-Bold", 132)
    f_kicker = font("IBMPlexMono-Bold", 22)
    f_sub = font("InstrumentSans-Regular", 26)
    f_lab = font("IBMPlexMono-Bold", 22)
    f_small = font("IBMPlexMono-Regular", 19)
    f_tiny = font("IBMPlexMono-Regular", 17)
    f_body = font("InstrumentSans-Regular", 19)

    M = 60
    tracked(d, (M, 54), "VISUAL SCORE / NO. 01", f_kicker, MAGENTA, track=3)
    d.text((M - 6, 84), "MUSHROOM", font=f_title, fill=PAPER)
    d.text((M - 6, 196), "SCORE", font=f_title, fill=NAVY)
    sub_x = M - 6 + d.textlength("SCORE", font=f_title) + 44
    d.text((sub_x, 226), "CIELAB dE2000\n→ MIDI → SYNTH",
           font=f_sub, fill=DIM, spacing=6)
    rule(d, M, 330, W - M, NAVY, 3)

    # three stopping points
    gap = 18
    pw = (W - 2 * M - 2 * gap) // 3
    ph = int(pw * 986 / 720)
    py = 360
    for k, (name, fno) in enumerate(STOP_FRAMES.items()):
        px = M + k * (pw + gap)
        im.paste(panel(fno, (pw, ph)), (px, py))
        d.rectangle([px, py, px + pw - 1, py + ph - 1], outline=NAVY, width=3)
        d.rectangle([px, py + ph, px + pw - 1, py + ph + 34], fill=NAVY)
        tracked(d, (px + 10, py + ph + 8), name, f_lab, PAPER, track=2)
        t0 = fno / meta["fps"]
        d.text((px + pw - 62, py + ph + 9), f"{t0:5.2f}s", font=f_tiny, fill=(180, 200, 255))
    d.text((M, py + ph + 48), "STOPPING POINTS — the three reference photographs, "
           "matched per frame in Lab", font=f_body, fill=DIM)

    cy = py + ph + 92
    curve_block(d, M, cy, W - 2 * M, 240, zoom, cues, n)
    d.text((M, cy + 252), "ZOOM CURVE — apparent cap scale, 508 frames. "
           "Amber = drum cue.", font=f_body, fill=DIM)

    ly = cy + 300
    col = (W - 2 * M) // 3
    legend_row(d, M, ly, NAVY, "NAVY", "mushroom / detector frame", f_lab, f_tiny)
    legend_row(d, M + col, ly, MAGENTA, "MAGENTA", "plant motion / vector field", f_lab, f_tiny)
    legend_row(d, M + 2 * col, ly, AMBER, "AMBER", "drum cue / zoom extremum", f_lab, f_tiny)

    rule(d, M, H - 96, W - M, NAVY, 2)
    am = meta["anchor_mushroom_lab"]
    ap = meta["anchor_plant_lab"]
    d.text((M, H - 78),
           f"MUSHROOM L*{am[0]:.1f} a*{am[1]:+.1f} b*{am[2]:+.1f}    "
           f"PLANT L*{ap[0]:.1f} a*{ap[1]:+.1f} b*{ap[2]:+.1f}",
           font=f_small, fill=DIM)
    d.text((M, H - 52),
           f"{ev['bpm']:.1f} BPM derived from the zoom period  ·  "
           f"{ev['scale']}  ·  {meta['duration_s']:.2f} s",
           font=f_small, fill=DIM)
    return im


def build_9x16(zoom, cues, n, meta, ev):
    W, H = 1080, 1920
    im = Image.new("RGB", (W, H), NAVY_DEEP)
    d = ImageDraw.Draw(im)

    f_title = font("BigShoulders-Bold", 178)
    f_kicker = font("IBMPlexMono-Bold", 26)
    f_sub = font("InstrumentSans-Regular", 32)
    f_lab = font("IBMPlexMono-Bold", 24)
    f_small = font("IBMPlexMono-Regular", 21)
    f_tiny = font("IBMPlexMono-Regular", 19)
    f_body = font("InstrumentSans-Regular", 22)

    M = 64
    # A cover carries one image, not three. The hero is the tight framing at
    # maximum zoom - the loudest moment in the track - and the title sits below
    # it on solid ground rather than overlapping, so nothing clips the edge.
    hero_h = 900
    im.paste(panel(STOP_FRAMES["TIGHT"], (W, hero_h)), (0, 0))

    # Short fade into the ground colour so the cut is not abrupt.
    fade_h = 160
    strip = im.crop((0, hero_h - fade_h, W, hero_h)).convert("RGB")
    arr = np.asarray(strip).astype(np.float32)
    t = np.linspace(0, 1, fade_h, dtype=np.float32)[:, None, None] ** 1.6
    ground = np.array(NAVY_DEEP, dtype=np.float32)[None, None, :]
    im.paste(Image.fromarray((arr * (1 - t) + ground * t).astype(np.uint8)),
             (0, hero_h - fade_h))
    d.line([(0, hero_h), (W, hero_h)], fill=NAVY, width=4)

    y = hero_h + 34
    tracked(d, (M, y), "VISUAL SCORE / NO. 01", f_kicker, MAGENTA, track=3)
    d.text((M - 8, y + 30), "MUSHROOM", font=f_title, fill=PAPER)
    d.text((M - 8, y + 158), "SCORE", font=f_title, fill=NAVY)

    # 178px BigShoulders descends ~165px below its baseline anchor; clear it.
    y += 340
    d.text((M, y), "One sidewalk tree. 16.95 seconds.\nThe camera's zoom is the melody.",
           font=f_sub, fill=DIM, spacing=8)

    y += 108
    rule(d, M, y, W - M, NAVY, 3)

    y += 30
    curve_block(d, M, y, W - 2 * M, 288, zoom, cues, n)
    d.text((M, y + 300), "ZOOM CURVE — apparent cap scale. Amber = drum cue.",
           font=f_body, fill=DIM)

    y += 352
    col = (W - 2 * M) // 3
    legend_row(d, M, y, NAVY, "NAVY", "mushroom", f_lab, f_tiny)
    legend_row(d, M + col, y, MAGENTA, "MAGENTA", "plant motion", f_lab, f_tiny)
    legend_row(d, M + 2 * col, y, AMBER, "AMBER", "drum cue", f_lab, f_tiny)

    rule(d, M, H - 96, W - M, NAVY, 2)
    d.text((M, H - 78),
           f"{ev['bpm']:.1f} BPM from the zoom period · {ev['scale']}",
           font=f_small, fill=DIM)
    d.text((M, H - 50),
           "CIELAB dE2000 masks → optical flow → MIDI → synthesis",
           font=f_small, fill=DIM)
    return im


def main():
    meta = json.loads((WORK / "analysis.json").read_text())
    ev = json.loads((WORK / "midi_events.json").read_text())
    d = np.load(WORK / "analysis.npz")
    zoom = d["zoom"]
    n = len(zoom)
    cues = sorted([(e["frame"], "IN") for e in meta["zoom_in_extrema"]]
                  + [(e["frame"], "OUT") for e in meta["zoom_out_extrema"]])

    (OUT / "plates").mkdir(parents=True, exist_ok=True)
    for name, fno in STOP_FRAMES.items():
        src = SCORE_FRAMES / f"s_{fno:04d}.png"
        if src.exists():
            shutil.copy(src, OUT / "plates" / f"stop_{name}_f{fno:04d}.png")

    a = build_4x5(zoom, cues, n, meta, ev)
    a.save(OUT / "mushroom_score_post_4x5.png")
    b = build_9x16(zoom, cues, n, meta, ev)
    b.save(OUT / "mushroom_score_cover_9x16.png")
    print("wrote", OUT / "mushroom_score_post_4x5.png", a.size)
    print("wrote", OUT / "mushroom_score_cover_9x16.png", b.size)


if __name__ == "__main__":
    main()
