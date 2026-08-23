#!/usr/bin/env python3
"""common.py — the timeline and the colour system, shared by picture and sound.

Both the renderer and the synthesiser import this so that a flash and a note are
the same event by construction rather than by two scripts agreeing to be careful.

THE COLOUR SYSTEM
=================
The brief asked for green to red. That is the one ramp to avoid: red-green is
exactly the axis that protanopia and deuteranopia collapse, which is around 8%
of men, and a green-to-red amplitude scale is unreadable to them at any
brightness. The later brief asked for perceptual brightness and
differentiability under colour blindness and low vision, which settles it.

So the ramp keeps the OKLab machinery and re-assigns what carries meaning:

    magnitude  ->  LIGHTNESS, monotonic, 0.30 to 0.93
    polarity   ->  HUE, azure for negative and amber for positive

Lightness is the channel that survives everything -- full achromatopsia, a bad
projector, a phone in sunlight, a greyscale print. Someone who sees no colour at
all still reads amplitude correctly, and loses only the sign. Blue against
amber is additionally the safe hue axis: it is preserved under both common
dichromacies, unlike red against green.

Chroma rises with magnitude instead of peaking mid-scale, so the loudest moments
are vivid rather than washing out toward white, which is what keeps it bright
rather than pastel.

The positive hue is 92 degrees, gold rather than orange. Amber at middling
lightness is, in sRGB, brown -- there is no chroma available there to make it
anything else -- and brown was the specific failure the brief called out. Gold
keeps its chroma all the way down the lightness ramp, so the middle of the
scale reads as a dimmer gold rather than as mud.

Magnitude is expanded by a 0.6 power before it becomes lightness. Linear, a
trace spends most of its time near zero and therefore near black, and the frame
reads as empty with three bright moments in it. The expansion lifts small
deviations into the visible part of the ramp without changing their order, and
the legend strip is generated through the same function, so the key on screen
is the transform.
"""

import numpy as np

# ---------------------------------------------------------------------------
# Timeline. `dur` is seconds of video; `t0`/`t1` are the data window it maps.
# ---------------------------------------------------------------------------
FPS = 30

ACTS = [
    dict(
        id="photic", kind="erp", dur=19.0, t0=-200.0, t1=1000.0, units="ms",
        title="PHOTIC BLOCK",
        sub="checkerboard reversal · averaged evoked response · 1200 ms slowed 16×",
        # anterior first, the order a montage is read in
        channels=["Cz", "Pz", "O2"],
    ),
    dict(
        id="rest_ec", kind="raw", cond="eyes_closed", dur=10.0, t0=0.0, t1=10.0,
        units="s",
        title="RESTING, EYES CLOSED",
        sub="10 s of raw montage · 15 of 19 electrodes usable · real time",
        channels=None,          # the full montage
    ),
]

# The last hit needs somewhere to ring out, and a reel wants an end card. The
# picture holds and the sound decays across the same tail.
TAIL = 1.2

TOTAL = sum(a["dur"] for a in ACTS)
DURATION = TOTAL + TAIL


def act_at(vt):
    """Which act, and how far into it, at video time `vt` seconds."""
    acc = 0.0
    for a in ACTS:
        if vt < acc + a["dur"] or a is ACTS[-1]:
            return a, min(1.0, max(0.0, (vt - acc) / a["dur"])), acc
        acc += a["dur"]
    return ACTS[-1], 1.0, acc


def act_start(act_id):
    acc = 0.0
    for a in ACTS:
        if a["id"] == act_id:
            return acc
        acc += a["dur"]
    return 0.0


def data_time(act, frac):
    return act["t0"] + frac * (act["t1"] - act["t0"])


def video_time(act, t):
    """Data time -> absolute video time. Used to place sound events."""
    span = act["t1"] - act["t0"]
    return act_start(act["id"]) + act["dur"] * (t - act["t0"]) / span


# ---------------------------------------------------------------------------
# OKLab / OKLCh -> sRGB
# ---------------------------------------------------------------------------
_M1 = np.array([[0.8189330101, 0.3618667424, -0.1288597137],
                [0.0329845436, 0.9293118715,  0.0361456387],
                [0.0482003018, 0.2643662691,  0.6338517070]])
_M2 = np.array([[0.2104542553,  0.7936177850, -0.0040720468],
                [1.9779984951, -2.4285922050,  0.4505937099],
                [0.0259040371,  0.7827717662, -0.8086757660]])
_M1i = np.linalg.inv(_M1)
_M2i = np.linalg.inv(_M2)
_XYZ2RGB = np.array([[ 3.2404542, -1.5371385, -0.4985314],
                     [-0.9692660,  1.8760108,  0.0415560],
                     [ 0.0556434, -0.2040259,  1.0572252]])


def oklab_to_srgb(L, a, b):
    """Vectorised. L, a, b are arrays of any matching shape. Returns 0..1 RGB."""
    lab = np.stack([np.asarray(L, float), np.asarray(a, float), np.asarray(b, float)], axis=-1)
    lms = lab @ _M2i.T
    lms = lms ** 3
    xyz = lms @ _M1i.T
    rgb = xyz @ _XYZ2RGB.T
    # gamma
    a_ = 0.0031308
    rgb = np.where(rgb <= a_, 12.92 * rgb, 1.055 * np.clip(rgb, 0, None) ** (1 / 2.4) - 0.055)
    return np.clip(rgb, 0.0, 1.0)


def oklch_to_srgb(L, C, h_deg):
    h = np.deg2rad(h_deg)
    return oklab_to_srgb(L, np.asarray(C) * np.cos(h), np.asarray(C) * np.sin(h))


# Hue anchors. Azure and amber, the dichromacy-safe axis.
HUE_NEG = 252.0
HUE_POS = 92.0

# Perceptual expansion of magnitude before it becomes lightness.
MAG_GAMMA = 0.5


def signal_rgb(v):
    """Signed, normalised signal in roughly [-1, 1] -> sRGB 0..255 uint8.

    v may be a scalar or an array. Magnitude drives lightness monotonically;
    sign drives hue only.
    """
    v = np.asarray(v, dtype=float)
    m = np.clip(np.abs(v), 0.0, 1.0) ** MAG_GAMMA
    L = 0.36 + 0.57 * m
    C = 0.055 + 0.165 * m
    h = np.where(v < 0, HUE_NEG, HUE_POS)
    rgb = oklch_to_srgb(L, C, h)
    return (rgb * 255.0 + 0.5).astype(np.uint8)


def ramp_strip(n=512):
    """A -1..+1 legend strip, for the key drawn on every frame."""
    v = np.linspace(-1.0, 1.0, n)
    return signal_rgb(v), v


# ---------------------------------------------------------------------------
# Static palette. Deep ink ground so the bright ramp has somewhere to be bright.
# The warm greys are the antique-chart register the graticule is drawn in.
# ---------------------------------------------------------------------------
INK        = (10, 12, 18)
INK_2      = (17, 20, 29)
GRATICULE  = (74, 62, 48)
GRATICULE2 = (52, 44, 35)
PARCH      = (196, 174, 138)
PARCH_DIM  = (128, 113, 92)
CHALK      = (238, 234, 226)
RULE       = (58, 56, 62)
ACCENT     = (255, 214, 92)
