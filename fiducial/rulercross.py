#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Rulercross -- a 2D, pose-capable extension of the Rulercode fiducial.

The 1D Rulercode gives you an id and a rough scale. To place a marker on a real
desk and recover *where it is and how it is turned*, you need 2D structure with a
known origin, a known orientation, and >=4 non-collinear points of known physical
geometry (so a homography / PnP solve is possible).

Design goals from the brief:
  * NOT a square grid -- must not read as QR / AprilTag / DataMatrix.
  * "compass-like": an unambiguous heading.
  * carries data AND its own true physical scale.

Shape: a **surveyor's compass rose**.
  * A concentric-ring BULLSEYE at the centre -> sub-pixel ORIGIN (x, y).
  * Four radial RULER ARMS (a crosshair, not a cell grid). The North-South arms
    are long, the East-West arms short -> the long axis is unambiguous. A single
    filled COMPASS PIP sits at the North tip -> North vs South is resolved. So
    the four arm tips + centre are five coplanar points of known mm geometry.
  * 10 mm ruler ticks along every arm -> direct, redundant physical scale.
  * CMY "burn" data cells along the N and S arms -> id + true arm length + CRC,
    reusing the Rulercode ColorCode payload.

Five known points (marker frame, mm, origin at centre):
    centre (0,0)   N (0,+L)   S (0,-L)   E (+Le,0)   W (-Le,0)
Measure them in pixels and you can solve a homography -> full planar pose
(see pose.py). The long/short asymmetry + pip make the frame right-handed and
oriented, so 3-DoF (x, y, theta) is immediate and 6-DoF follows with intrinsics.

Pure Python standard library. Emits SVG (screen) and PostScript (print), both
pinned to real millimetres. Import for the geometry, or run as a CLI.
"""

import argparse
import math
import sys

from rulercode import (PT_PER_MM, MM_PER_INCH, encode_payload, decode_payload,
                       cmy_to_rgb255, DATA_MODULES)

# Per-paper long-arm half-length L (mm). N-S calibration span = 2*L.
PAPER = {
    # name:      (page_w, page_h, L_mm, landscape)
    "letter":    (215.9, 279.4, 92.0, False),
    "a4":        (210.0, 297.0, 92.0, False),
    "a5":        (148.0, 210.0, 66.0, False),
    "postcard":  (148.0, 105.0, 46.0, True),    # A6 postcard, landscape
    "card":      ( 85.6,  53.98, 22.0, True),   # ISO ID-1 business card
}
SHORT_RATIO = 0.60          # E-W arms are 60% of N-S arms
ARM_W = 0.14                # arm width as fraction of L
BULLSEYE = [0.20, 0.13, 0.075]   # ring radii as fraction of L (outer->inner)
DSTART, DEND = 0.28, 0.70   # data-cell band, as a fraction of L (scale-invariant)


class CrossGeometry:
    def __init__(self, marker_id, L_mm):
        self.id = marker_id
        self.L = float(L_mm)                    # long half-arm (mm)
        self.Le = self.L * SHORT_RATIO          # short half-arm (mm)
        self.arm_w = self.L * ARM_W
        self.rings = [self.L * r for r in BULLSEYE]
        self.modules = encode_payload(marker_id, self.L)   # 12 CMY cells

    # Known physical points in the marker frame (mm), origin at centre.
    def known_points(self):
        return {"C": (0.0, 0.0), "N": (0.0, self.L), "S": (0.0, -self.L),
                "E": (self.Le, 0.0), "W": (-self.Le, 0.0)}

    # Data cells: 6 along +Y (N) arm, 6 along -Y (S) arm, as (cx, cy, w, h, cmy).
    # Positions are purely PROPORTIONAL to L so a marker of any size decodes the
    # same way in normalised marker units (matches the desk-scanner decoder).
    def data_cells(self):
        cells = self.modules
        w = self.arm_w * 0.9
        seg = (DEND - DSTART) * self.L / 6.0
        out = []
        for i in range(6):                                # N arm, outward
            cy = DSTART * self.L + (i + 0.5) * seg
            out.append((0.0, cy, w, seg * 0.66, cells[i]))
        for i in range(6):                                # S arm, outward
            cy = -(DSTART * self.L + (i + 0.5) * seg)
            out.append((0.0, cy, w, seg * 0.66, cells[6 + i]))
        return out

    def ruler_ticks(self):
        """(axis, distance_mm, major) ticks every 10 mm along each arm."""
        for axis, reach in (("y", self.L), ("x", self.Le)):
            d = 10.0
            while d <= reach + 1e-6:
                major = (round(d) % 50 == 0)
                for s in (1, -1):
                    yield (axis, s * d, major)
                d += 10.0

    def human_text(self):
        info = decode_payload(self.modules)
        return ("RULERCROSS  id 0x%04X  L=%.1fmm  span=%.1fmm  %s"
                % (info["id"], self.L, 2 * self.L,
                   "CRC-OK" if info["crc_ok"] else "CRC-BAD"))


# ---------------------------------------------------------------------------
# SVG (origin at centre, placed on the page centre). y-up in marker frame.
# ---------------------------------------------------------------------------
def to_svg(g, page_w, page_h, landscape=False, cx=None, cy=None, show_frame=False):
    if landscape and page_h > page_w:
        page_w, page_h = page_h, page_w
    cx = page_w / 2 if cx is None else cx
    cy = page_h / 2 if cy is None else cy
    S = ['<?xml version="1.0" encoding="UTF-8"?>',
         '<svg xmlns="http://www.w3.org/2000/svg" width="%.3fmm" height="%.3fmm" '
         'viewBox="0 0 %.3f %.3f">' % (page_w, page_h, page_w, page_h),
         '<rect width="%.3f" height="%.3f" fill="white"/>' % (page_w, page_h)]

    def X(mx): return cx + mx
    def Y(my): return cy - my        # SVG y is down; marker y is up

    aw = g.arm_w
    # arms (rounded rectangles -> reads as a crosshair, not a grid)
    S.append('<g fill="none" stroke="#111" stroke-width="0.35">')
    S.append('<rect x="%.3f" y="%.3f" width="%.3f" height="%.3f" rx="%.2f" fill="#fff"/>'
             % (X(-aw/2), Y(g.L), aw, 2*g.L, aw/2))                 # N-S
    S.append('<rect x="%.3f" y="%.3f" width="%.3f" height="%.3f" rx="%.2f" fill="#fff"/>'
             % (X(-g.Le), Y(aw/2), 2*g.Le, aw, aw/2))              # E-W
    S.append('</g>')

    # ruler ticks
    S.append('<g stroke="#111" stroke-width="0.3">')
    for axis, d, major in g.ruler_ticks():
        t = aw * (0.5 if major else 0.32)
        if axis == "y":
            S.append('<line x1="%.3f" y1="%.3f" x2="%.3f" y2="%.3f"/>'
                     % (X(-t), Y(d), X(t), Y(d)))
        else:
            S.append('<line x1="%.3f" y1="%.3f" x2="%.3f" y2="%.3f"/>'
                     % (X(d), Y(-t), X(d), Y(t)))
    S.append('</g>')

    # CMY data cells (burn palette; multiply so overlaps darken)
    S.append('<g style="mix-blend-mode:multiply">')
    for (mx, my, w, h, cmy) in g.data_cells():
        r, gr, b = cmy_to_rgb255(cmy)
        S.append('<rect x="%.3f" y="%.3f" width="%.3f" height="%.3f" fill="rgb(%d,%d,%d)"/>'
                 % (X(mx - w/2), Y(my + h/2), w, h, r, gr, b))
    S.append('</g>')

    # bullseye (concentric rings) -> origin
    ring_fill = ["#111", "#fff", "#111"]
    for rad, fill in zip(g.rings, ring_fill):
        S.append('<circle cx="%.3f" cy="%.3f" r="%.3f" fill="%s" stroke="#111" stroke-width="0.25"/>'
                 % (X(0), Y(0), rad, fill))

    # compass pip -> heading (a triangle, not a square). Contained within the
    # arm tip so it doesn't extend the arm's measured length during decoding.
    S.append('<polygon points="%.3f,%.3f %.3f,%.3f %.3f,%.3f" fill="#E23B4E"/>'
             % (X(0), Y(g.L), X(-aw*0.6), Y(0.82*g.L), X(aw*0.6), Y(0.82*g.L)))
    S.append('<text x="%.3f" y="%.3f" font-family="monospace" font-size="%.2f" '
             'fill="#E23B4E">N</text>' % (X(aw*0.8), Y(g.L), aw*0.8))

    # human-readable text under the marker
    S.append('<text x="%.3f" y="%.3f" font-family="monospace" font-size="2.4" '
             'text-anchor="middle" fill="#111">%s</text>'
             % (X(0), Y(-g.L) + 4.0, g.human_text()))

    if show_frame:   # debug: draw the 5 known points
        for k, (mx, my) in g.known_points().items():
            S.append('<circle cx="%.3f" cy="%.3f" r="0.8" fill="#37E0CE"/>' % (X(mx), Y(my)))
    S.append('</svg>')
    return "\n".join(S)


# ---------------------------------------------------------------------------
# PostScript (mm-accurate, origin at page centre).
# ---------------------------------------------------------------------------
def to_postscript(g, page_w, page_h, landscape=False):
    if landscape and page_h > page_w:
        page_w, page_h = page_h, page_w
    cx, cy = page_w / 2, page_h / 2
    L = ["%!PS-Adobe-3.0",
         "%%%%BoundingBox: 0 0 %d %d" % (round(page_w*PT_PER_MM), round(page_h*PT_PER_MM)),
         "%%Creator: rulercross.py",
         "%%Title: Rulercross id=0x%04X L=%.1fmm" % (g.id, g.L),
         "/mm { %.10f mul } def" % PT_PER_MM,
         "/cx %.4f mm def /cy %.4f mm def" % (cx, cy),
         # x y r  filled circle ;  helper ops use marker mm coords about centre
         "/dot { 3 dict begin /r exch def /y exch def /x exch def "
         "newpath cx x mm add cy y mm add r mm 0 360 arc fill end } def",
         "/ring { 3 dict begin /r exch def /y exch def /x exch def "
         "newpath cx x mm add cy y mm add r mm 0 360 arc stroke end } def",
         "0 setlinewidth 0.3 mm setlinewidth"]

    def rect(x, y, w, h, rgb=None):
        if rgb:
            L.append("%.3f %.3f %.3f setrgbcolor" % rgb)
        L.append("newpath cx %.3f mm add cy %.3f mm add moveto %.3f mm 0 rlineto "
                 "0 %.3f mm rlineto %.3f mm neg 0 rlineto closepath fill"
                 % (x, y, w, h, w))

    aw = g.arm_w
    L.append("1 1 1 setrgbcolor")
    rect(-aw/2, -g.L, aw, 2*g.L); rect(-g.Le, -aw/2, 2*g.Le, aw)
    L.append("0 0 0 setrgbcolor 0.3 mm setlinewidth")
    # arm outlines
    for (x, y, w, h) in [(-aw/2, -g.L, aw, 2*g.L), (-g.Le, -aw/2, 2*g.Le, aw)]:
        L.append("newpath cx %.3f mm add cy %.3f mm add moveto %.3f mm 0 rlineto "
                 "0 %.3f mm rlineto %.3f mm neg 0 rlineto closepath stroke"
                 % (x, y, w, h, w))
    # ticks
    for axis, d, major in g.ruler_ticks():
        t = aw * (0.5 if major else 0.32)
        if axis == "y":
            L.append("newpath cx %.3f mm add cy %.3f mm add moveto %.3f mm 0 rlineto stroke"
                     % (-t, d, 2*t))
        else:
            L.append("newpath cx %.3f mm add cy %.3f mm add moveto 0 %.3f mm rlineto stroke"
                     % (d, -t, 2*t))
    # data cells
    for (mx, my, w, h, cmy) in g.data_cells():
        r, gr, b = [v/255.0 for v in cmy_to_rgb255(cmy)]
        rect(mx - w/2, my - h/2, w, h, (r, gr, b))
    # bullseye
    L.append("0 0 0 setrgbcolor")
    L.append("0 0 %.3f dot" % g.rings[0])
    L.append("1 1 1 setrgbcolor 0 0 %.3f dot" % g.rings[1])
    L.append("0 0 0 setrgbcolor 0 0 %.3f dot" % g.rings[2])
    # compass pip (triangle), contained within the arm tip
    L.append("0.886 0.231 0.306 setrgbcolor")
    L.append("newpath cx %.3f mm add cy %.3f mm add moveto cx %.3f mm add cy %.3f mm add lineto "
             "cx %.3f mm add cy %.3f mm add lineto closepath fill"
             % (0, g.L, -aw*0.6, 0.82*g.L, aw*0.6, 0.82*g.L))
    # text
    L.append("0 0 0 setrgbcolor /Courier findfont 6.8 scalefont setfont")
    txt = g.human_text().replace("(", "\\(").replace(")", "\\)")
    L.append("cx %.3f mm add cy %.3f mm add moveto (%s) dup stringwidth pop 2 div neg 0 rmoveto show"
             % (0, -g.L + 4.0, txt))
    L.append("showpage")
    return "\n".join(L)


def main(argv=None):
    p = argparse.ArgumentParser(description="Generate Rulercross compass fiducials.")
    p.add_argument("--id", type=lambda s: int(s, 0), default=0x2A)
    p.add_argument("--paper", choices=sorted(PAPER), default="letter")
    p.add_argument("--L", type=float, default=None, help="override long half-arm (mm)")
    p.add_argument("--format", choices=["svg", "ps"], default="svg")
    p.add_argument("--frame", action="store_true", help="mark the 5 known points (debug)")
    p.add_argument("-o", "--out", default="-")
    a = p.parse_args(argv)
    pw, ph, L, ls = PAPER[a.paper]
    L = a.L if a.L else L
    g = CrossGeometry(a.id, L)
    if a.format == "svg":
        data = to_svg(g, pw, ph, ls, show_frame=a.frame).encode()
    else:
        data = to_postscript(g, pw, ph, ls).encode()
    if a.out == "-":
        sys.stdout.buffer.write(data)
    else:
        open(a.out, "wb").write(data)
        info = decode_payload(g.modules)
        sys.stderr.write("wrote %s (%s id=0x%04X L=%.1fmm span=%.1fmm %s)\n"
                         % (a.out, a.paper, info["id"], L, 2*L,
                            "CRC-OK" if info["crc_ok"] else "CRC-BAD"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
