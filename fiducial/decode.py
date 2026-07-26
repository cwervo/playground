#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Reference Rulercode decoder -- pure Python, works on a binary PPM (P6).

This is the *portable reference* decoder. It reads an axis-aligned image (the
vector file rasterised, or a flat-on photo), separates the C/M/Y ink channels
with (C,M,Y) = (1-R, 1-G, 1-B), reads the 12 data modules, verifies the CRC,
and reports id + physical length + a mm-per-pixel scale.

On the Folk camera rig the front-end is different: OpenCV finds the solid-K
finder bars, rectifies perspective, and hands this module a clean crop. The
channel-separation and payload maths below are identical either way -- that is
the whole point of the CMY "burn" scheme. See README.md.
"""

import sys
from rulercode import (DATA_MODULES, TOTAL_MODULES, QUIET_MODULES,
                       FINDER_MODULES, PALETTE_MODULES, decode_payload)

# Content (drawn ink) spans from the left edge of the start finder bar to the
# right edge of the end finder, expressed in module units from the marker left:
CONTENT_LEFT_MOD = QUIET_MODULES                                  # = 1
CONTENT_RIGHT_MOD = (QUIET_MODULES + FINDER_MODULES + PALETTE_MODULES
                     + DATA_MODULES) + 1.15                       # end finder right edge
CONTENT_SPAN_MOD = CONTENT_RIGHT_MOD - CONTENT_LEFT_MOD           # = 17.15
# Data module i centre, in module units measured from content-left:
DATA_OFFSET_MOD = (FINDER_MODULES + PALETTE_MODULES)              # = 4 (data starts here)


def parse_ppm(data):
    if data[:2] != b"P6":
        raise ValueError("not a binary PPM (P6)")
    # read three whitespace-separated ints for width height maxval
    idx = 2
    fields = []
    while len(fields) < 3:
        while idx < len(data) and data[idx:idx + 1].isspace():
            idx += 1
        if data[idx:idx + 1] == b"#":                # comment line
            while idx < len(data) and data[idx:idx + 1] != b"\n":
                idx += 1
            continue
        start = idx
        while idx < len(data) and not data[idx:idx + 1].isspace():
            idx += 1
        fields.append(int(data[start:idx]))
    w, h, _maxval = fields
    idx += 1                                         # single whitespace after maxval
    px = data[idx:idx + w * h * 3]
    return w, h, px


def _pix(px, w, x, y):
    o = (y * w + x) * 3
    return px[o], px[o + 1], px[o + 2]


def _is_ink(rgb, thr=200):
    return min(rgb) < thr


def find_bar_band(px, w, h):
    """Return (y_top, y_bottom, x_left, x_right) of the colour-bar band.

    Uses row/column ink *profiles* (counts over a whole line), not single
    pixels, so isolated sensor-noise specks in the quiet zones can't be
    mistaken for the marker edges.
    """
    ink_per_row = [0] * h
    for y in range(h):
        base = y * w * 3
        c = 0
        for x in range(w):
            o = base + x * 3
            if min(px[o], px[o + 1], px[o + 2]) < 200:
                c += 1
        ink_per_row[y] = c
    peak = max(ink_per_row)
    if peak == 0:
        raise ValueError("blank image")
    # longest run of "wide" rows = the tall colour-bar band
    thr = peak * 0.5
    best_len = best_start = cur_start = cur = 0
    for y in range(h):
        if ink_per_row[y] >= thr:
            cur_start = cur_start if cur else y
            cur += 1
            if cur > best_len:
                best_len, best_start = cur, cur_start
        else:
            cur = 0
    y_top, y_bot = best_start, best_start + best_len - 1
    band_h = y_bot - y_top + 1

    # column ink profile *within the band* -> robust left/right extent.
    col_ink = [0] * w
    for y in range(y_top, y_bot + 1):
        base = y * w * 3
        for x in range(w):
            o = base + x * 3
            if min(px[o], px[o + 1], px[o + 2]) < 200:
                col_ink[x] += 1
    col_thr = band_h * 0.4                       # a real column is inked most of its height
    inked = [x for x in range(w) if col_ink[x] >= col_thr]
    if not inked:
        raise ValueError("no marker columns found")
    return y_top, y_bot, inked[0], inked[-1]


def sample_module(px, w, xc, y_top, y_bot):
    """Median of a tall window down the band centre -> (r,g,b). The vertical
    median rejects noise and the odd separator line."""
    half_x = 3
    ys = range(y_top + (y_bot - y_top) // 4, y_bot - (y_bot - y_top) // 4 + 1, 2)
    chans = ([], [], [])
    for y in ys:
        for dx in range(-half_x, half_x + 1):
            pr, pg, pb = _pix(px, w, xc + dx, y)
            chans[0].append(pr); chans[1].append(pg); chans[2].append(pb)
    def med(vals):
        vals.sort()
        return vals[len(vals) // 2]
    return med(chans[0]), med(chans[1]), med(chans[2])


def decode_ppm(data, verbose=False):
    w, h, px = parse_ppm(data)
    y_top, y_bot, x_left, x_right = find_bar_band(px, w, h)
    span_px = x_right - x_left
    mod_px = span_px / CONTENT_SPAN_MOD               # pixels per module

    # --- colour calibration from the palette swatches (white .. K) ---------
    # palette sits PALETTE offset right of content-left; sample its extremes.
    def content_x(mod_from_left):
        return int(round(x_left + mod_from_left * mod_px))
    # white swatch centre ~ 0.2 module into palette; K swatch ~ 1.8 modules in.
    pal0 = QUIET_MODULES + FINDER_MODULES - CONTENT_LEFT_MOD + 0.2   # from content-left
    white = sample_module(px, w, content_x(pal0), y_top, y_bot)
    blackk = sample_module(px, w, content_x(pal0 + 1.6), y_top, y_bot)
    # per-channel midpoints; fall back to 128 if palette looks degenerate.
    mids = []
    for i in range(3):
        hi, lo = white[i], blackk[i]
        mids.append((hi + lo) / 2.0 if hi - lo > 40 else 128.0)

    # --- read the 12 data modules -----------------------------------------
    modules = []
    for i in range(DATA_MODULES):
        xc = content_x(DATA_OFFSET_MOD + i + 0.5)
        r, g, b = sample_module(px, w, xc, y_top, y_bot)
        c = 1 if r < mids[0] else 0                   # cyan absorbs red
        m = 1 if g < mids[1] else 0                   # magenta absorbs green
        yl = 1 if b < mids[2] else 0                  # yellow absorbs blue
        modules.append((c, m, yl))
        if verbose:
            sys.stderr.write("  mod %2d @x=%4d rgb=(%3d,%3d,%3d) -> CMY %d%d%d\n"
                             % (i, xc, r, g, b, c, m, yl))

    info = decode_payload(modules)
    # scale: encoded length spans the full marker (TOTAL_MODULES); content span
    # is CONTENT_SPAN_MOD of those modules.
    mm_per_px = None
    if info["crc_ok"]:
        content_mm = CONTENT_SPAN_MOD * (info["length_mm"] / TOTAL_MODULES)
        mm_per_px = content_mm / span_px
    info["mm_per_px"] = mm_per_px
    info["px_per_mm"] = (1.0 / mm_per_px) if mm_per_px else None
    info["span_px"] = span_px
    info["module_px"] = mod_px
    return info


def main(argv=None):
    argv = argv if argv is not None else sys.argv[1:]
    verbose = "-v" in argv
    paths = [a for a in argv if not a.startswith("-")]
    if not paths:
        sys.stderr.write("usage: decode.py [-v] marker.ppm\n")
        return 2
    with open(paths[0], "rb") as f:
        data = f.read()
    info = decode_ppm(data, verbose=verbose)
    print("id         : 0x%04X (%d)" % (info["id"], info["id"]))
    print("length     : %.1f mm  (encoded)" % info["length_mm"])
    print("crc        : %s" % ("OK" if info["crc_ok"] else "FAIL"))
    if info["mm_per_px"]:
        print("scale      : %.5f mm/px   (%.3f px/mm)"
              % (info["mm_per_px"], info["px_per_mm"]))
    print("span       : %.1f px   module=%.2f px" % (info["span_px"], info["module_px"]))
    return 0 if info["crc_ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
