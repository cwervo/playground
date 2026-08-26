#!/usr/bin/env python3
"""render.py — the session as a 9:16 reel, drawn as a chart of the head.

    python3 video/render.py --scale 1 --preview 4      # 1080x1920, first 4 s
    python3 video/render.py --scale 2                  # 2160x3840, the lot

WHY IT LOOKS LIKE A MAP
    The two references were an EEG montage screenshot -- stacked traces beside
    an inset head with named electrodes and the bipolar chains drawn on it as
    routes -- and an antique world map with a graticule. They want the same
    thing. A montage IS a chart: fixed named places, fixed routes between them,
    and a coordinate grid you read positions off. So the head is drawn as a
    globe in orthographic projection with its own graticule, the five
    anterior-posterior bipolar chains are drawn as the routes a reader
    traverses, and the trace panel gets meridians at the component latencies
    with a cartographer's scale bar underneath, in milliseconds instead of
    miles.

TEMPORAL MAPPING
    Three ways to read time, because one is never enough:
      1. the meridians -- a labelled vertical line at every component latency,
         so a peak has a name and a number at the moment it happens
      2. the playhead -- everything behind it is lit, everything ahead is
         banked down, so the trace is being drawn rather than scrolling
      3. the itinerary -- the discharge order as a route strip that fills in
         as each landmark is reached: O2 287 -> Pz 387 -> Cz 464

COLOUR
    Magnitude is lightness, polarity is hue, azure against amber. See
    common.py for why it is not the green-to-red that was first asked for.
    Everything structural is neutral or parchment, so no reading anywhere on
    the frame depends on telling two hues apart.
"""

import argparse
import json
import os
import sys

try:
    import numpy as np
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    sys.exit("needs numpy and pillow:  pip install numpy pillow")

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import (ACTS, DURATION, FPS, TAIL, TOTAL, ACCENT, CHALK,  # noqa: E402
                    GRATICULE, GRATICULE2, INK, INK_2, PARCH, PARCH_DIM, RULE,
                    act_at, act_start, data_time, ramp_strip, signal_rgb)

FONT_DIR = os.path.join(HERE, "..", "assets", "fonts")

# design space; every number below is in these units and scaled on the way out
DW, DH = 1080, 1920

HEAD_C = (540, 636)
HEAD_R = 258

# panels, in design units
P_HEAD = (120, 290)          # header band
P_ATLAS = (290, 972)
P_CAP = (972, 1046)          # one caption at a time, its own band
P_TRACE = (1046, 1596)
P_METER = (1596, 1730)
P_FOOT = (1736, 1810)

MARGIN = 56


def rgb(c, k=1.0):
    return tuple(int(round(min(255, max(0, v * k)))) for v in c)


class Kit:
    """Fonts and scaling. Everything drawn goes through `p()`."""

    def __init__(self, scale):
        self.s = scale
        self.W, self.H = DW * scale, DH * scale
        def f(name, size):
            return ImageFont.truetype(os.path.join(FONT_DIR, name), int(round(size * scale)))
        self.title = f("IBMPlexSerif-Bold.ttf", 46)
        self.title_s = f("IBMPlexSerif-Regular.ttf", 21)
        self.mono = {}
        for sz in (13, 15, 16, 17, 18, 20, 22, 24, 26, 30, 34, 40, 58):
            self.mono[sz] = f("IBMPlexMono-Regular.ttf", sz)
            self.mono[(sz, "b")] = f("IBMPlexMono-Bold.ttf", sz)

    def p(self, v):
        return int(round(v * self.s))

    def m(self, sz, bold=False):
        return self.mono[(sz, "b")] if bold else self.mono[sz]


def track(d, xy, s, font, fill, tr=0.0, kit=None, anchor="l"):
    """Letterspaced text. Small caps labels want air; PIL will not give it."""
    tr = tr * (kit.s if kit else 1)
    w = sum(d.textlength(c, font=font) + tr for c in s) - tr
    x, y = xy
    if anchor == "m":
        x -= w / 2
    elif anchor == "r":
        x -= w
    for c in s:
        d.text((x, y), c, font=font, fill=fill)
        x += d.textlength(c, font=font) + tr
    return w


def bow(p0, p1, k=0.16, n=18):
    """A route between two places, bowed outward from the head centre, so two
    chains sharing an endpoint stay legible instead of overprinting."""
    (x0, y0), (x1, y1) = p0, p1
    mx, my = (x0 + x1) / 2, (y0 + y1) / 2
    cx, cy = HEAD_C
    dx, dy = mx - cx, my - cy
    n_ = (dx * dx + dy * dy) ** 0.5 or 1.0
    qx, qy = mx + dx / n_ * k * HEAD_R, my + dy / n_ * k * HEAD_R
    out = []
    for i in range(n + 1):
        t = i / n
        a = (1 - t) ** 2
        b = 2 * (1 - t) * t
        c = t * t
        out.append((a * x0 + b * qx + c * x1, a * y0 + b * qy + c * y1))
    return out


def node_xy(pos):
    return (HEAD_C[0] + pos[0] * HEAD_R, HEAD_C[1] + pos[1] * HEAD_R)


def site(name):
    """Channel label -> place on the atlas. The ERP figures are captioned Cz,
    Pz, O2 and the montage table is capitalised CZ, PZ, O2; same electrodes."""
    return name.upper()


# ---------------------------------------------------------------------------
# static furniture
# ---------------------------------------------------------------------------
def ground(kit):
    """Ink with a slow vertical gradient and a little grain, so 4K flat black
    does not band on a phone screen."""
    h = (np.linspace(0, 1, kit.H) ** 1.4)[:, None, None]
    g = np.array(INK)[None, None, :] + (np.array(INK_2) - np.array(INK))[None, None, :] * h
    g = np.repeat(g, kit.W, axis=1)
    rng = np.random.default_rng(20260818)
    grain = rng.normal(0, 1.6, size=(kit.H, kit.W, 1))
    return np.clip(g + grain, 0, 255).astype(np.uint8)


def draw_atlas(d, kit, feats, live, act):
    """The head as a globe: rim, graticule, routes, named places."""
    p = kit.p
    cx, cy = p(HEAD_C[0]), p(HEAD_C[1])
    R = p(HEAD_R)

    # rim, ears, nose
    d.ellipse([cx - R, cy - R, cx + R, cy + R], outline=rgb(GRATICULE), width=p(2))
    d.ellipse([cx - R - p(6), cy - R - p(6), cx + R + p(6), cy + R + p(6)],
              outline=rgb(GRATICULE2), width=p(1))
    nose = p(26)
    d.polygon([(cx, cy - R - nose), (cx - p(17), cy - R + p(7)),
               (cx + p(17), cy - R + p(7))], outline=rgb(GRATICULE), width=p(2))
    for sgn in (-1, 1):
        d.arc([cx + sgn * R - p(20), cy - p(46), cx + sgn * R + p(20), cy + p(46)],
              start=-80 if sgn > 0 else 100, end=80 if sgn > 0 else 260,
              fill=rgb(GRATICULE), width=p(2))

    # graticule: straight parallels, elliptical meridians. Orthographic, which
    # is what you get looking down at a head.
    for v in (-0.75, -0.5, -0.25, 0.25, 0.5, 0.75):
        half = R * (1 - v * v) ** 0.5
        y = cy + v * R
        d.line([cx - half, y, cx + half, y], fill=rgb(GRATICULE2), width=p(1))
    d.line([cx - R, cy, cx + R, cy], fill=rgb(GRATICULE), width=p(1))
    for k in (0.28, 0.58, 0.86):
        d.ellipse([cx - R * k, cy - R, cx + R * k, cy + R],
                  outline=rgb(GRATICULE2), width=p(1))
    d.line([cx, cy - R, cx, cy + R], fill=rgb(GRATICULE), width=p(1))

    # cardinals
    for txt, xy, an in (("ANTERIOR", (cx, cy - R - p(62)), "m"),
                        ("POSTERIOR", (cx, cy + R + p(34)), "m"),
                        ("L", (cx - R - p(46), cy - p(12)), "m"),
                        ("R", (cx + R + p(46), cy - p(12)), "m")):
        track(d, xy, txt, kit.m(15), rgb(PARCH_DIM), tr=1.6, kit=kit, anchor=an)

    # routes: the five bipolar chains, as a chart draws trade routes
    POS = feats["positions"]
    for name, chain in feats["chains"]:
        pts = [node_xy(POS[c]) for c in chain]
        for a, b in zip(pts, pts[1:]):
            path = [(p(x), p(y)) for x, y in bow((a[0], a[1]), (b[0], b[1]))]
            d.line(path, fill=rgb(GRATICULE, 1.35), width=p(2), joint="curve")

    # The places themselves are drawn per frame, in draw_places(), because in
    # the resting act the interpolated field is pasted over this background and
    # would otherwise bury both the rings and their names.


def draw_places(d, kit, feats, live, by_site):
    """Rings, fills and names, drawn on top of whatever is under them."""
    p = kit.p
    lit = {site(n) for n in live}
    for name, pos in feats["positions"].items():
        x, y = node_xy(pos)
        on = name in lit
        r = p(15)
        d.ellipse([p(x) - r, p(y) - r, p(x) + r, p(y) + r],
                  outline=rgb(PARCH if on else GRATICULE, 1.25) + (235,), width=p(2))
        if name in by_site:
            v = by_site[name][0]
            col = tuple(int(q) for q in signal_rgb(v))
            rr = p(9 + 9 * min(1.0, abs(v)))
            d.ellipse([p(x) - rr, p(y) - rr, p(x) + rr, p(y) + rr], fill=col)
            if abs(v) > 0.55:
                gr = int(rr * 2.1)
                d.ellipse([p(x) - gr, p(y) - gr, p(x) + gr, p(y) + gr],
                          outline=col + (int(150 * (abs(v) - 0.55) / 0.45),), width=p(3))
        # halo behind the name: over a bright field, parchment on gold is
        # unreadable, and this is the one place a name has to stay legible
        d.text((p(x), p(y) + r + p(9)), name, font=kit.m(15, bold=on), anchor="ma",
               fill=rgb(CHALK if on else PARCH_DIM, 1.0 if on else 0.85),
               stroke_width=p(3), stroke_fill=(8, 9, 14, 205))


def trace_layer(kit, act, series, feats):
    """Every sample of every channel, drawn once, in full colour.

    Per frame the renderer multiplies this by a per-column gain -- lit behind
    the playhead, banked ahead of it -- which is one broadcast multiply instead
    of seventeen thousand line calls.

    Returns (rgb, alpha, x0, y0, rows) where rows is the per-channel geometry
    the labels and markers are placed against.
    """
    p = kit.p
    x0, x1 = p(MARGIN + 92), p(DW - MARGIN - 16)
    y0, y1 = p(P_TRACE[0] + 74), p(P_TRACE[1] - 74)
    W, H = x1 - x0, y1 - y0

    img = Image.new("RGB", (W, H), (0, 0, 0))
    dd = ImageDraw.Draw(img)
    rows = []

    if act["kind"] == "erp":
        chans = act["channels"]
        gmax = max(abs(v) for c in chans
                   for v in (series["erp"][c]["uv"] if c in series["erp"] else [0]))
        rh = H / len(chans)
        for i, c in enumerate(chans):
            ser = series["erp"][c]
            t = np.asarray(ser["t_ms"], float)
            # the same five-sample window the peak finder uses, so what is on
            # screen and what was measured are the same curve
            y = np.convolve(np.asarray(ser["uv"], float),
                            np.hanning(5) / np.hanning(5).sum(), mode="same")
            base = rh * (i + 0.55)
            amp = rh * 0.40
            px = (t - act["t0"]) / (act["t1"] - act["t0"]) * W
            py = base - y / gmax * amp
            col = signal_rgb(y / gmax)
            for j in range(len(px) - 1):
                dd.line([px[j], py[j], px[j + 1], py[j + 1]],
                        fill=tuple(int(v) for v in col[j]), width=p(5))
            rows.append(dict(name=c, label=ser["label"], base=base, amp=amp,
                             scale=gmax, kind="erp"))
    else:
        r = series["raw"][act["cond"]]
        rej = set(r.get("rejected", []))
        names = [n for n in feats["positions"] if n in r["channels"]]
        # front to back, the order a montage is read in
        names.sort(key=lambda n: (feats["positions"][n][1], feats["positions"][n][0]))
        data = {}
        for n in names:
            v = np.asarray(r["channels"][n], float)
            data[n] = v - v.mean()
        scale = float(np.percentile(np.abs(np.concatenate(
            [data[n] for n in names if n not in rej])), 99.0))
        rh = H / len(names)
        for i, n in enumerate(names):
            v = data[n]
            base = rh * (i + 0.5)
            amp = rh * 0.42
            px = np.linspace(0, W, len(v))
            py = base - np.clip(v / scale, -1.35, 1.35) * amp
            dead = n in rej
            col = (signal_rgb(np.zeros_like(v)) if dead
                   else signal_rgb(np.clip(v / scale, -1, 1)))
            wdt = p(2) if dead else p(3)
            for j in range(len(px) - 1):
                c = (44, 40, 36) if dead else tuple(int(q) for q in col[j])
                dd.line([px[j], py[j], px[j + 1], py[j + 1]], fill=c, width=wdt)
            rows.append(dict(name=n, label=n, base=base, amp=amp, scale=scale,
                             kind="raw", dead=dead))

    arr = np.asarray(img).astype(np.float32)
    alpha = (arr.max(axis=2) > 8).astype(np.float32)
    return arr, alpha, x0, y0, rows


def draw_trace_furniture(d, kit, act, rows, x0, y0, W, H, feats):
    p = kit.p
    # frame
    d.rectangle([x0 - p(2), y0 - p(2), x0 + W + p(2), y0 + H + p(2)],
                outline=rgb(RULE), width=p(2))

    for r in rows:
        yy = y0 + int(r["base"])
        d.line([x0, yy, x0 + W, yy], fill=rgb(GRATICULE2, 0.8), width=p(1))
        nm = r["label"] if r["kind"] == "raw" else r["name"]
        d.text((x0 - p(14), yy), nm, font=kit.m(20 if r["kind"] == "erp" else 15,
                                                bold=r["kind"] == "erp"),
               anchor="rm", fill=rgb(PARCH_DIM if r.get("dead") else PARCH))
        if r.get("dead"):
            d.text((x0 + p(10), yy - p(4)), "rejected", font=kit.m(13),
                   anchor="ls", fill=rgb(PARCH_DIM))

    span = act["t1"] - act["t0"]

    def tx(t):
        return x0 + (t - act["t0"]) / span * W

    # meridians. In the photic act they are the component latencies, which is
    # the whole point: a peak gets its name and its number at the instant it
    # arrives. In the resting act they are seconds.
    if act["kind"] == "erp":
        marks = [(0.0, "STIMULUS", ACCENT, 0)]
        for i, dsc in enumerate(feats["discharge_order"]):
            marks.append((dsc["t_ms"], f'{dsc["channel"]} {dsc["t_ms"]:.0f}',
                          PARCH, 1 + (i % 2)))
        for t in range(-200, 1001, 100):
            X = tx(t)
            d.line([X, y0, X, y0 + H], fill=rgb(GRATICULE2, 0.55), width=p(1))
        # three landmarks inside 180 ms of each other cannot share one line of
        # type, so they step up instead of overprinting
        for t, lab, col, tier in marks:
            X = tx(t)
            d.line([X, y0, X, y0 + H], fill=rgb(col, 0.55), width=p(2))
            track(d, (X, y0 - p(30 + 24 * tier)), lab, kit.m(16, bold=True),
                  rgb(col, 0.9), tr=1.0, kit=kit, anchor="m")
        track(d, (x0 - p(92), p(P_TRACE[1] - 40)), "ALL CHANNELS AT ONE GAIN",
              kit.m(15), rgb(PARCH_DIM), tr=1.4, kit=kit)
    else:
        for t in range(0, int(act["t1"]) + 1):
            X = tx(t)
            d.line([X, y0, X, y0 + H], fill=rgb(GRATICULE2, 0.6), width=p(1))
            if t % 2 == 0:
                d.text((X, y0 - p(26)), f"{t}s", font=kit.m(16), anchor="ma",
                       fill=rgb(PARCH_DIM))
        track(d, (x0 - p(92), p(P_TRACE[1] - 40)),
              "RELATIVE UNITS — THE PRINTOUT DOES NOT STATE ITS GAIN",
              kit.m(15), rgb(PARCH_DIM), tr=1.2, kit=kit)


def draw_scalebar(d, kit, act, px0, pw):
    """A cartographer's scale bar, in milliseconds.

    It is a legend, not an axis, so it is short -- but its segments are the
    real width of 200 ms on the panel above, which is the only thing that makes
    a scale bar worth drawing.
    """
    p = kit.p
    y = p(P_TRACE[1] - 68)
    x0 = px0
    span = act["t1"] - act["t0"]
    step = 200.0 if act["units"] == "ms" else 2.0
    seg = pw / span * step
    n = max(2, int(pw * 0.46 / seg))
    for i in range(n):
        a, b = x0 + i * seg, x0 + (i + 1) * seg
        d.rectangle([a, y, b, y + p(9)],
                    fill=rgb(PARCH_DIM if i % 2 else PARCH),
                    outline=rgb(GRATICULE), width=p(1))
    d.text((x0 + n * seg + p(12), y + p(5)), f"{step * n:g} {act['units']}",
           font=kit.m(16), anchor="lm", fill=rgb(PARCH_DIM))


def draw_ramp(d, kit):
    """The key. Lightness carries size, hue carries sign."""
    p = kit.p
    strip, v = ramp_strip(512)
    y = p(P_METER[0] + 44)
    h = p(26)
    x0 = p(DW - MARGIN - 400)
    x1 = p(DW - MARGIN)
    im = Image.fromarray(strip.reshape(1, -1, 3)).resize((x1 - x0, h), Image.BILINEAR)
    d._image.paste(im, (x0, y))
    d.rectangle([x0, y, x1, y + h], outline=rgb(GRATICULE), width=p(1))
    d.text((x0, y + h + p(6)), "−", font=kit.m(16), anchor="la", fill=rgb(PARCH_DIM))
    d.text(((x0 + x1) // 2, y + h + p(6)), "0", font=kit.m(16), anchor="ma",
           fill=rgb(PARCH_DIM))
    d.text((x1, y + h + p(6)), "+", font=kit.m(16), anchor="ra", fill=rgb(PARCH_DIM))
    track(d, (x0, y - p(26)), "LIGHTNESS = SIZE   HUE = SIGN", kit.m(15),
          rgb(PARCH_DIM), tr=1.4, kit=kit)


def static_frame(kit, act, series, feats, live):
    base = Image.fromarray(ground(kit))
    d = ImageDraw.Draw(base)
    p = kit.p

    # header cartouche
    d.line([p(MARGIN), p(P_HEAD[0] - 26), p(DW - MARGIN), p(P_HEAD[0] - 26)],
           fill=rgb(RULE), width=p(2))
    d.text((p(MARGIN), p(P_HEAD[0] + 4)), act["title"], font=kit.title,
           fill=rgb(CHALK))
    d.text((p(MARGIN), p(P_HEAD[0] + 74)), act["sub"], font=kit.m(18),
           fill=rgb(PARCH))
    track(d, (p(DW - MARGIN), p(P_HEAD[0] - 2)), "SESSION 2026-08-18",
          kit.m(15), rgb(PARCH_DIM), tr=1.6, kit=kit, anchor="r")

    draw_atlas(d, kit, feats, live, act)

    layer, alpha, x0, y0, rows = trace_layer(kit, act, series, feats)
    H, W = layer.shape[0], layer.shape[1]
    draw_trace_furniture(d, kit, act, rows, x0, y0, W, H, feats)
    draw_scalebar(d, kit, act, x0, W)
    draw_ramp(d, kit)

    # footer
    d.line([p(MARGIN), p(P_FOOT[0] - 8), p(DW - MARGIN), p(P_FOOT[0] - 8)],
           fill=rgb(RULE), width=p(2))
    foot = ("Traced from printed figures in the vendor report, not the original "
            "recording.\nNot a diagnosis. n = 1 session.")
    d.multiline_text((p(MARGIN), p(P_FOOT[0] + 12)), foot, font=kit.m(16),
                     fill=rgb(PARCH_DIM), spacing=p(8))

    return np.asarray(base).astype(np.uint8), layer, alpha, x0, y0, rows


# ---------------------------------------------------------------------------
# per-frame dynamics
# ---------------------------------------------------------------------------
def sample_values(act, series, t, rows):
    """Instantaneous value per channel at data time t, normalised to [-1, 1]."""
    out = {}
    if act["kind"] == "erp":
        for r in rows:
            ser = series["erp"][r["name"]]
            v = float(np.interp(t, ser["t_ms"], ser["uv"]))
            out[r["name"]] = (v / r["scale"], v, "uV")
    else:
        rr = series["raw"][act["cond"]]
        for r in rows:
            v = np.asarray(rr["channels"][r["name"]], float)
            v = v - v.mean()
            x = float(np.interp(t, np.linspace(0, act["t1"], len(v)), v))
            out[r["name"]] = (0.0 if r.get("dead") else x / r["scale"], x, "")
    return out


def topo_field(kit, vals, feats, live, grid=160):
    """Inverse-distance interpolation across the scalp, masked to the rim.

    Only drawn in the resting act. In the photic act three electrodes were
    printed and interpolating a whole scalp field from three points would be
    drawing data that was never recorded.
    """
    xs = np.linspace(-1.05, 1.05, grid)
    X, Y = np.meshgrid(xs, xs)
    num = np.zeros_like(X)
    den = np.zeros_like(X)
    for n in live:
        px, py = feats["positions"][site(n)]
        w = 1.0 / (((X - px) ** 2 + (Y - py) ** 2) ** 1.35 + 0.004)
        num += w * vals[n][0]
        den += w
    f = np.clip(num / den, -1.0, 1.0)
    rgbf = signal_rgb(f)
    # soft rim, so the disc does not arrive with a staircase on its edge
    rr = np.sqrt(X ** 2 + Y ** 2)
    mask = (np.clip((1.0 - rr) / 0.035, 0.0, 1.0) * 255).astype(np.uint8)
    im = Image.fromarray(rgbf).convert("RGB")
    mk = Image.fromarray(mask, "L")
    R = kit.p(HEAD_R)
    im = im.resize((2 * R, 2 * R), Image.BICUBIC)
    mk = mk.resize((2 * R, 2 * R), Image.BICUBIC)
    return im, mk


def draw_dynamics(img, kit, act, feats, rows, vals, frac, t, x0, y0, W, H,
                  score, vt, live):
    d = ImageDraw.Draw(img, "RGBA")
    p = kit.p

    # scalp field (resting only)
    if act["kind"] == "raw":
        im, mk = topo_field(kit, vals, feats, live)
        mk = mk.point(lambda q: int(q * 0.58))
        img.paste(im, (p(HEAD_C[0]) - kit.p(HEAD_R), p(HEAD_C[1]) - kit.p(HEAD_R)), mk)
        d = ImageDraw.Draw(img, "RGBA")
        # the routes and the rim go back on top; a field that swallows the
        # chart it is drawn on is a picture, not a map
        cx, cy, R = p(HEAD_C[0]), p(HEAD_C[1]), p(HEAD_R)
        for _, chain in feats["chains"]:
            pts = [node_xy(feats["positions"][c]) for c in chain]
            for a_, b_ in zip(pts, pts[1:]):
                d.line([(p(x), p(y)) for x, y in bow(a_, b_)],
                       fill=rgb(PARCH_DIM) + (120,), width=p(2), joint="curve")
        d.ellipse([cx - R, cy - R, cx + R, cy + R], outline=rgb(PARCH_DIM) + (200,),
                  width=p(2))

    by_site = {site(k): v for k, v in vals.items()}
    draw_places(d, kit, feats, live, by_site)

    # the trace panel is composited by the caller; here go the marks on it
    head_x = x0 + int(frac * W)
    d.line([head_x, y0 - p(14), head_x, y0 + H + p(14)], fill=rgb(ACCENT) + (215,),
           width=p(3))
    d.polygon([(head_x, y0 - p(16)), (head_x - p(11), y0 - p(34)),
               (head_x + p(11), y0 - p(34))], fill=rgb(ACCENT))

    # running readout, in the mono the numbers are set in everywhere else
    unit = "ms" if act["units"] == "ms" else "s"
    txt = f"{t:+.0f} {unit}" if unit == "ms" else f"{t:5.2f} {unit}"
    track(d, (p(DW - MARGIN), p(P_TRACE[1] - 42)), txt, kit.m(34, bold=True),
          rgb(ACCENT), tr=0.5, kit=kit, anchor="r")

    for r in rows:
        if r["kind"] != "erp":
            continue
        v, uv, _ = vals[r["name"]]
        yy = y0 + int(r["base"] - v * r["amp"])
        col = tuple(int(q) for q in signal_rgb(v))
        d.ellipse([head_x - p(9), yy - p(9), head_x + p(9), yy + p(9)], fill=col)
        d.text((head_x + p(18), yy - p(2)), f"{uv:+6.2f} µV", font=kit.m(18, bold=True),
               anchor="lm", fill=col)

    # itinerary: the discharge order as a route strip that fills as it happens
    strip_y = p(P_METER[0] + 56)
    if act["kind"] == "erp":
        stops = feats["discharge_order"]
        sx0, sx1 = p(MARGIN), p(MARGIN + 470)
        d.line([sx0, strip_y + p(13), sx1, strip_y + p(13)], fill=rgb(RULE), width=p(3))
        for i, s in enumerate(stops):
            fx = sx0 + (sx1 - sx0) * i / max(1, len(stops) - 1)
            done = t >= s["t_ms"]
            col = signal_rgb(1.0 if s["polarity"] > 0 else -1.0)
            col = tuple(int(q) for q in col) if done else rgb(GRATICULE)
            rr = p(11 if done else 8)
            d.ellipse([fx - rr, strip_y + p(13) - rr, fx + rr, strip_y + p(13) + rr],
                      fill=col)
            d.text((fx, strip_y - p(6)), s["channel"], font=kit.m(17, bold=True),
                   anchor="mb", fill=rgb(CHALK if done else PARCH_DIM))
            d.text((fx, strip_y + p(30)), f'{s["t_ms"]:.0f}', font=kit.m(16),
                   anchor="mt", fill=rgb(PARCH if done else PARCH_DIM))
        track(d, (sx0, strip_y - p(42)), "DISCHARGE ORDER", kit.m(15),
              rgb(PARCH_DIM), tr=1.4, kit=kit)
    else:
        track(d, (p(MARGIN), strip_y - p(42)), "SCALP FIELD, INTERPOLATED",
              kit.m(15), rgb(PARCH_DIM), tr=1.4, kit=kit)
        hz = feats["raw"][act["cond"]]["mean_hz"]
        track(d, (p(MARGIN), strip_y - p(6)),
              f"15 of 19 electrodes  ·  alpha {hz:.2f} Hz", kit.m(20),
              rgb(PARCH), tr=0.0, kit=kit)

    # Caption band. One caption at a time -- the three landmarks are 180 ms
    # apart in the data, which at this speed is close enough that two of them
    # would print on top of each other. The newest one wins and the older one
    # gets out of the way.
    yb = p(P_CAP[0] + 20)
    live_caps = []
    for e in score["events"]:
        if e["kind"] not in ("principal", "stim"):
            continue
        age = vt - e["t"]
        if -0.12 <= age <= 2.6:
            live_caps.append((age, e))
    if live_caps:
        age, e = min(live_caps, key=lambda q: q[0] if q[0] >= 0 else 99)
        a = float(np.clip(min((age + 0.12) / 0.18, (2.6 - age) / 0.6), 0, 1))
        if e["kind"] == "stim":
            msg, col = "CHECKERBOARD REVERSAL   t = 0", ACCENT
        else:
            comp = e.get("component") or "peak"
            msg = (f'{comp}   {e["channel"]}   {e["t_ms"]:.0f} ms   '
                   f'{e["uv"]:+.2f} µV')
            col = tuple(int(q) for q in signal_rgb(1.0 if e["polarity"] > 0 else -1.0))
        col = tuple(col) + (int(255 * a),)
        track(d, (p(MARGIN + 20), yb), msg, kit.m(26, bold=True), col, tr=1.0, kit=kit)
        d.rectangle([p(MARGIN), yb - p(4), p(MARGIN + 6), yb + p(36)], fill=col)
    elif act["kind"] == "raw":
        # nothing is a "landmark" in a resting run, so the band reports where
        # the field is strongest right now instead
        nm, v = max(((k, q[0]) for k, q in vals.items()), key=lambda q: abs(q[1]))
        col = tuple(int(q) for q in signal_rgb(v)) + (255,)
        track(d, (p(MARGIN + 20), yb), f"STRONGEST NOW   {site(nm)}   "
              f"{v:+.2f} of full scale", kit.m(26, bold=True), col, tr=1.0, kit=kit)
        d.rectangle([p(MARGIN), yb - p(4), p(MARGIN + 6), yb + p(36)], fill=col)


def outro(img, kit, feats, alpha):
    d = ImageDraw.Draw(img, "RGBA")
    p = kit.p
    a = int(255 * alpha)
    d.rectangle([0, 0, kit.W, kit.H], fill=(6, 7, 11, int(248 * alpha)))
    d.line([p(MARGIN), p(P_HEAD[0] - 26), p(DW - MARGIN), p(P_HEAD[0] - 26)],
           fill=rgb(RULE) + (a,), width=p(2))
    y = p(560)
    d.text((p(MARGIN), y), "WHAT THE ORDER SAYS", font=kit.title,
           fill=rgb(CHALK) + (a,))
    y += p(96)
    order = "  →  ".join(f'{s["channel"]} {s["t_ms"]:.0f} ms'
                              for s in feats["discharge_order"])
    d.text((p(MARGIN), y), order, font=kit.m(30, bold=True), fill=rgb(ACCENT) + (a,))
    y += p(84)
    body = ("N100, then the parietal P3b, then the frontocentral P3a.\n"
            "Textbook order puts P3a first. Here the orienting\n"
            "response arrives last — the same story the 0.382\n"
            "P3b/P3a amplitude ratio tells, by a different route.\n\n"
            "Nobody wrote that down. It was in the printed curves.")
    d.multiline_text((p(MARGIN), y), body, font=kit.m(24), spacing=p(14),
                     fill=rgb(PARCH) + (a,))
    hz = feats["raw"]["eyes_closed"]["mean_hz"]
    d.multiline_text((p(MARGIN), p(1420)),
                     "Sonified in G mixolydian. Every note is a peak,\n"
                     "every hit is a polarity reversal, and the flutter\n"
                     f"is the measured {hz:.2f} Hz alpha rhythm.",
                     font=kit.m(20), spacing=p(12), fill=rgb(PARCH_DIM) + (a,))


def compose(kit, act, series, feats, score, bg, layer, alphaL, x0, y0, rows,
            live, vt, frac):
    """One finished frame. The still writer and the video writer share it, so a
    frame lifted out for print is the frame that was in the film."""
    t = data_time(act, frac)
    frame = bg.copy()

    # trace panel: lit behind the playhead, banked ahead of it, with a brighter
    # wake just behind so the drawing edge reads as motion
    H, W = layer.shape[0], layer.shape[1]
    col = np.arange(W, dtype=np.float32)
    head = frac * W
    gain = np.where(col <= head, 1.0, 0.26).astype(np.float32)
    wake = np.clip(1.0 - (head - col) / (0.045 * W), 0.0, 1.0) * (col <= head)
    gain = gain + 0.55 * wake
    lit = np.clip(layer * gain[None, :, None], 0, 255)
    a = alphaL[..., None]
    region = frame[y0:y0 + H, x0:x0 + W].astype(np.float32)
    frame[y0:y0 + H, x0:x0 + W] = (region * (1 - a) + lit * a).astype(np.uint8)

    img = Image.fromarray(frame)
    vals = sample_values(act, series, t, rows)
    draw_dynamics(img, kit, act, feats, rows, vals, frac, t, x0, y0, W, H,
                  score, vt, live)
    if vt > TOTAL - 0.35:
        outro(img, kit, feats, float(np.clip((vt - (TOTAL - 0.35)) / 0.9, 0, 1)))
    return img


# ---------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--series", default="build/video/series.json")
    ap.add_argument("--features", default="build/video/features.json")
    ap.add_argument("--score", default="build/video/score.json")
    ap.add_argument("--audio", default="build/video/track.wav")
    ap.add_argument("--out", default="build/video/photic.mp4")
    ap.add_argument("--scale", type=int, default=2, help="1 = 1080x1920, 2 = 2160x3840")
    ap.add_argument("--preview", type=float, default=0.0, help="render only N seconds")
    ap.add_argument("--stills", default="", help="also write PNG stills at these times")
    ap.add_argument("--stills-only", action="store_true",
                    help="write the stills and no video, for the book")
    args = ap.parse_args()
    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)

    series = json.load(open(args.series))
    feats = json.load(open(args.features))
    score = json.load(open(args.score))
    kit = Kit(args.scale)

    live_by_act = {}
    statics = {}
    for act in ACTS:
        if act["kind"] == "erp":
            live = list(act["channels"])
        else:
            rr = series["raw"][act["cond"]]
            rej = set(rr.get("rejected", []))
            live = [n for n in feats["positions"] if n in rr["channels"] and n not in rej]
        live_by_act[act["id"]] = live
        statics[act["id"]] = static_frame(kit, act, series, feats, live)
        print(f"  built furniture for {act['id']}", file=sys.stderr)

    end = args.preview if args.preview > 0 else DURATION
    nframes = int(round(end * FPS))
    stills = [float(x) for x in args.stills.split(",") if x.strip()]

    if args.stills_only:
        if not stills:
            sys.exit("--stills-only needs --stills")
        for vt in stills:
            act, frac, _ = act_at(min(vt, TOTAL - 1e-6))
            bg, layer, alphaL, x0, y0, rows = statics[act["id"]]
            img = compose(kit, act, series, feats, score, bg, layer, alphaL,
                          x0, y0, rows, live_by_act[act["id"]], vt, frac)
            pth = f"{os.path.splitext(args.out)[0]}-{vt:g}s.png"
            img.save(pth)
            print(f"  still {pth}", file=sys.stderr)
        return

    import imageio_ffmpeg
    writer = imageio_ffmpeg.write_frames(
        args.out, (kit.W, kit.H), fps=FPS, codec="libx264", quality=None,
        macro_block_size=1, pix_fmt_in="rgb24", pix_fmt_out="yuv420p",
        bitrate=None, ffmpeg_log_level="error",
        output_params=["-crf", "17", "-preset", "medium",
                       "-profile:v", "high", "-movflags", "+faststart"],
        audio_path=args.audio if os.path.exists(args.audio) else None,
        audio_codec="aac",
    )
    writer.send(None)

    for i in range(nframes):
        vt = i / FPS
        act, frac, _ = act_at(min(vt, TOTAL - 1e-6))
        bg, layer, alphaL, x0, y0, rows = statics[act["id"]]
        img = compose(kit, act, series, feats, score, bg, layer, alphaL,
                      x0, y0, rows, live_by_act[act["id"]], vt, frac)
        out = np.asarray(img, dtype=np.uint8)
        writer.send(out.tobytes())

        for s in list(stills):
            if abs(vt - s) < 0.5 / FPS:
                pth = f"{os.path.splitext(args.out)[0]}-{s:g}s.png"
                img.save(pth)
                print(f"  still {pth}", file=sys.stderr)
                stills.remove(s)
        if i % 60 == 0:
            print(f"  frame {i}/{nframes}  t={vt:5.2f}s  {act['id']}", file=sys.stderr)

    writer.close()
    print(f"render: wrote {args.out}  {nframes} frames, {kit.W}x{kit.H}, {FPS} fps",
          file=sys.stderr)


if __name__ == "__main__":
    main()
