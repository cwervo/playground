#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Rulercode -- visible-light CMYK fiducial barcodes for camera scale recovery.

Inspired by Johnny Chung Lee's visible-light / light-sensor fiducial work
(the Wiimote whiteboard, "Automatic Projector Calibration with Embedded Light
Sensors", and "Moveable Interactive Projected Displays Using Projector-Based
Tracking"). Lee's trick was to hide *known physical geometry* in the visible
scene so a cheap sensor could recover pose/scale. A Rulercode does the same for
a plain 2D camera: it is a human-readable-ish colour barcode whose printed size
is guaranteed, and which *encodes its own physical length* so the camera can
recover a rough mm-per-pixel scale no matter which paper size it was printed on.

Key ideas
---------
* GUARANTEED PHYSICAL SIZE. Everything is authored in millimetres. The
  PostScript and SVG emitters both pin real-world mm, so a bar that says
  200 mm is 200 mm on paper (measure it with a ruler -- that is the point).

* CMY "burn" OVERLAP. The data track is three independent bit-lanes, one per
  subtractive primary ink: Cyan, Magenta, Yellow. They occupy the *same*
  modules and are drawn as overlapping layers combined with a multiply / "burn"
  blend (SVG mix-blend-mode:multiply; PostScript overprint separations). Where
  inks overlap they subtract light exactly the way real ink does:

      C+M -> blue,  C+Y -> green,  M+Y -> red,  C+M+Y -> black

  So each module is one of 8 human-distinguishable colours = 3 data bits.

* DECODES FROM DIGITAL *OR* PRINT with the same maths. Cyan ink absorbs red,
  magenta absorbs green, yellow absorbs blue -- i.e. (C,M,Y) = (1-R, 1-G, 1-B),
  the standard RGB->CMY conversion. Threshold each channel, get the 3 bits back,
  whether you read the vector file or a photo of the print.

* SELF-DESCRIBING SCALE. The payload carries the marker's true printed length
  (0.1 mm units). A decoder measures the finder-to-finder span in pixels, reads
  the encoded length, and divides -> mm-per-pixel. Two independent cross-checks
  come free: a real 10 mm-tick ruler printed along the top, and the same numbers
  printed as human-readable text along the bottom.

This file is pure Python standard library: no numpy, no PIL, no Ghostscript.
It is both an importable library and a CLI (see `python3 rulercode.py --help`).
"""

import argparse
import sys

MM_PER_INCH = 25.4
PT_PER_MM = 72.0 / MM_PER_INCH          # PostScript points per millimetre
VERSION = 1

# ---------------------------------------------------------------------------
# Layout constants (in "modules"). The marker is exactly TOTAL_MODULES wide.
# ---------------------------------------------------------------------------
QUIET_MODULES   = 1     # white margin each side
FINDER_MODULES  = 2     # start / end finder (solid-K bar + tick), each side
PALETTE_MODULES = 2     # colour-calibration swatches (start side only)
DATA_MODULES    = 12    # 12 modules * 3 bits = 36 payload bits
# left quiet, start finder, palette, data, end finder, right quiet
TOTAL_MODULES = (QUIET_MODULES + FINDER_MODULES + PALETTE_MODULES +
                 DATA_MODULES + FINDER_MODULES + QUIET_MODULES)  # = 20

# Vertical bands (mm, fixed regardless of length so text/ruler stay legible).
RULER_H = 3.0
TEXT_H  = 4.0
GAP_H   = 0.8

# Default marker length (mm) chosen per paper size to leave sane margins.
PAPER = {
    # name:     (page_w_mm, page_h_mm, marker_len_mm, landscape_page)
    "letter":   (215.9, 279.4, 200.0, False),
    "a4":       (210.0, 297.0, 190.0, False),
    "a5":       (148.0, 210.0, 128.0, False),
    "a6":       (105.0, 148.0,  90.0, False),
    "card":     ( 85.6,  53.98, 74.0, True),   # ISO/IEC 7810 ID-1 business card
}

# 8 composite colours as (name, C, M, Y) ink bits -> used for humans + preview.
SYMBOL_NAMES = {
    (0, 0, 0): "white",
    (1, 0, 0): "cyan",
    (0, 1, 0): "magenta",
    (0, 0, 1): "yellow",
    (1, 1, 0): "blue",
    (1, 0, 1): "green",
    (0, 1, 1): "red",
    (1, 1, 1): "black",
}


# ---------------------------------------------------------------------------
# CRC-8 (poly 0x07, init 0x00) -- small, standard, good enough for 28 bits.
# ---------------------------------------------------------------------------
def crc8(data_bytes):
    crc = 0
    for b in data_bytes:
        crc ^= b
        for _ in range(8):
            crc = ((crc << 1) ^ 0x07) & 0xFF if (crc & 0x80) else (crc << 1) & 0xFF
    return crc


def _bits_to_bytes(bits):
    """Pack an MSB-first bit list into bytes (right-pad the final byte)."""
    out = bytearray()
    for i in range(0, len(bits), 8):
        byte = 0
        for j in range(8):
            byte = (byte << 1) | (bits[i + j] if i + j < len(bits) else 0)
        out.append(byte)
    return bytes(out)


def _int_to_bits(value, width):
    return [(value >> (width - 1 - i)) & 1 for i in range(width)]


def _bits_to_int(bits):
    v = 0
    for b in bits:
        v = (v << 1) | (b & 1)
    return v


# ---------------------------------------------------------------------------
# Payload  (36 bits total = 12 modules * 3 CMY bits)
#   [ ID : 16 ] [ LEN_0p1mm : 12 ] [ CRC8 : 8 ]
# ---------------------------------------------------------------------------
ID_BITS, LEN_BITS, CRC_BITS = 16, 12, 8
assert ID_BITS + LEN_BITS + CRC_BITS == DATA_MODULES * 3 == 36


def encode_payload(marker_id, length_mm):
    """Return a list of 12 (C,M,Y) tuples encoding id + physical length."""
    if not (0 <= marker_id < (1 << ID_BITS)):
        raise ValueError("id must fit in %d bits (0..%d)" % (ID_BITS, (1 << ID_BITS) - 1))
    len_units = int(round(length_mm * 10.0))       # 0.1 mm resolution
    if not (0 <= len_units < (1 << LEN_BITS)):
        raise ValueError("length %.1fmm out of range (max %.1fmm)"
                         % (length_mm, ((1 << LEN_BITS) - 1) / 10.0))

    payload = _int_to_bits(marker_id, ID_BITS) + _int_to_bits(len_units, LEN_BITS)
    crc = crc8(_bits_to_bytes(payload))            # CRC over the 28 data bits
    bits = payload + _int_to_bits(crc, CRC_BITS)   # 36 bits

    modules = []
    for i in range(DATA_MODULES):
        c, m, y = bits[3 * i], bits[3 * i + 1], bits[3 * i + 2]
        modules.append((c, m, y))
    return modules


def decode_payload(modules):
    """Inverse of encode_payload. Returns dict with id, length_mm, crc_ok."""
    if len(modules) != DATA_MODULES:
        raise ValueError("expected %d data modules" % DATA_MODULES)
    bits = []
    for (c, m, y) in modules:
        bits += [c & 1, m & 1, y & 1]
    id_bits  = bits[0:ID_BITS]
    len_bits = bits[ID_BITS:ID_BITS + LEN_BITS]
    crc_bits = bits[ID_BITS + LEN_BITS:]
    marker_id = _bits_to_int(id_bits)
    length_mm = _bits_to_int(len_bits) / 10.0
    crc_ok = (crc8(_bits_to_bytes(id_bits + len_bits)) == _bits_to_int(crc_bits))
    return {"id": marker_id, "length_mm": length_mm, "crc_ok": crc_ok}


# ---------------------------------------------------------------------------
# Geometry: turn (paper, id) into an abstract, unit-agnostic marker description.
# All coordinates are in millimetres, origin at the marker's bottom-left.
# ---------------------------------------------------------------------------
class MarkerGeometry:
    def __init__(self, marker_id, length_mm, height_mm=None):
        self.id = marker_id
        self.length_mm = float(length_mm)
        self.module = self.length_mm / TOTAL_MODULES
        # Colour-bar band height: nominal 1:10 aspect (200mm -> 20mm).
        self.bar_h = height_mm if height_mm else self.length_mm / 10.0
        self.total_h = RULER_H + GAP_H + self.bar_h + GAP_H + TEXT_H
        self.modules = encode_payload(marker_id, self.length_mm)

        # X boundaries (module index -> mm), left to right.
        m = self.module
        x = QUIET_MODULES * m
        self.start_finder_x = x
        x += FINDER_MODULES * m
        self.palette_x = x
        x += PALETTE_MODULES * m
        self.data_x = x
        x += DATA_MODULES * m
        self.end_finder_x = x

        # Y boundaries of the colour-bar band.
        self.bar_y0 = TEXT_H + GAP_H
        self.bar_y1 = self.bar_y0 + self.bar_h
        self.ruler_y0 = self.bar_y1 + GAP_H
        self.ruler_y1 = self.ruler_y0 + RULER_H

    # -- iterators over drawable primitives, in mm --------------------------
    def data_rects(self):
        """Yield (x, w, (c,m,y)) for each data module."""
        for i, cmy in enumerate(self.modules):
            yield (self.data_x + i * self.module, self.module, cmy)

    def palette_swatches(self):
        """Yield (x, w, (c,m,y)) calibration swatches: white,C,M,Y,K."""
        swatches = [(0, 0, 0), (1, 0, 0), (0, 1, 0), (0, 0, 1), (1, 1, 1)]
        w = (PALETTE_MODULES * self.module) / len(swatches)
        for i, cmy in enumerate(swatches):
            yield (self.palette_x + i * w, w, cmy)

    def finder_bars(self):
        """Solid-K registration bars. Start = 1 bar; End = 2 bars (asymmetric)."""
        m = self.module
        bars = []
        # start: one full-width K bar in the first finder module
        bars.append((self.start_finder_x, m * 0.6))
        # end: two K bars (thin, thick) so orientation is unambiguous
        bars.append((self.end_finder_x + m * 0.15, m * 0.25))
        bars.append((self.end_finder_x + m * 0.6, m * 0.55))
        return bars

    def ruler_ticks(self):
        """Yield (x_mm, is_major, label_or_None) genuine 10 mm ruler ticks
        spanning the whole marker length -- a literal physical ruler."""
        d = 0.0
        while d <= self.length_mm + 1e-6:
            major = (round(d) % 50 == 0)
            label = ("%d" % round(d)) if major else None
            yield (d, major, label)
            d += 10.0

    def human_text(self):
        info = decode_payload(self.modules)
        return ("RULERCODE v%d   ID 0x%04X (%d)   L=%.1fmm   module=%.2fmm   %s"
                % (VERSION, info["id"], info["id"], self.length_mm, self.module,
                   "CRC-OK" if info["crc_ok"] else "CRC-BAD"))


# ---------------------------------------------------------------------------
# Colour helpers
# ---------------------------------------------------------------------------
def cmy_to_rgb(cmy):
    """Ideal subtractive mix -> (r,g,b) in 0..1. This *is* the burn/multiply
    result of overlapping the three ink layers."""
    c, m, y = cmy
    return (1.0 - c, 1.0 - m, 1.0 - y)


def cmy_to_rgb255(cmy):
    r, g, b = cmy_to_rgb(cmy)
    return (int(round(r * 255)), int(round(g * 255)), int(round(b * 255)))


# ---------------------------------------------------------------------------
# SVG emitter (digital / screen). Guarantees mm via width/height + viewBox.
# Overlap is expressed literally: three ink layers with mix-blend-mode:multiply.
# ---------------------------------------------------------------------------
def to_svg(geom, page_w, page_h, landscape=False):
    if landscape and page_h > page_w:
        page_w, page_h = page_h, page_w
    ox = (page_w - geom.length_mm) / 2.0
    oy = (page_h - geom.total_h) / 2.0

    def Y(y):  # SVG y grows downward; flip about the page.
        return page_h - y

    S = []
    S.append('<?xml version="1.0" encoding="UTF-8"?>')
    S.append('<svg xmlns="http://www.w3.org/2000/svg" '
             'width="%.4fmm" height="%.4fmm" viewBox="0 0 %.4f %.4f">'
             % (page_w, page_h, page_w, page_h))
    S.append('<rect x="0" y="0" width="%.4f" height="%.4f" fill="white"/>'
             % (page_w, page_h))

    def rect(x, y0, y1, w, fill, extra=""):
        S.append('<rect x="%.4f" y="%.4f" width="%.4f" height="%.4f" fill="%s"%s/>'
                 % (ox + x, Y(oy + y1), w, y1 - y0, fill, extra))

    # -- colour data + palette as three multiplied ink layers ---------------
    inks = [("cyan", 0, "#00FFFF"), ("magenta", 1, "#FF00FF"), ("yellow", 2, "#FFFF00")]
    cells = list(geom.data_rects()) + list(geom.palette_swatches())
    S.append('<g style="isolation:isolate">')
    for _, idx, hexcol in inks:
        S.append('<g style="mix-blend-mode:multiply">')
        for (x, w, cmy) in cells:
            if cmy[idx]:
                rect(x, geom.bar_y0, geom.bar_y1, w, hexcol)
        S.append('</g>')
    S.append('</g>')

    # thin separators between data modules (human readability)
    for (x, w, _) in geom.data_rects():
        S.append('<line x1="%.4f" y1="%.4f" x2="%.4f" y2="%.4f" stroke="black" '
                 'stroke-width="0.15"/>' % (ox + x, Y(oy + geom.bar_y0),
                                            ox + x, Y(oy + geom.bar_y1)))

    # -- solid-K finder bars ------------------------------------------------
    for (x, w) in geom.finder_bars():
        rect(x, geom.bar_y0, geom.bar_y1, w, "black")

    # -- ruler --------------------------------------------------------------
    rect(0, geom.ruler_y0, geom.ruler_y0 + 0.2, geom.length_mm, "black")  # baseline
    for (x, major, label) in geom.ruler_ticks():
        th = geom.ruler_y1 if major else geom.ruler_y0 + RULER_H * 0.55
        S.append('<line x1="%.4f" y1="%.4f" x2="%.4f" y2="%.4f" stroke="black" '
                 'stroke-width="0.25"/>' % (ox + x, Y(oy + geom.ruler_y0),
                                            ox + x, Y(oy + th)))
        if label is not None:
            S.append('<text x="%.4f" y="%.4f" font-family="monospace" '
                     'font-size="2" text-anchor="middle">%s</text>'
                     % (ox + x, Y(oy + geom.ruler_y1) - 0.3, label))

    # -- human-readable text ------------------------------------------------
    S.append('<text x="%.4f" y="%.4f" font-family="monospace" font-size="2.6">%s</text>'
             % (ox, Y(oy + 0.8), geom.human_text()))

    S.append('</svg>')
    return "\n".join(S)


# ---------------------------------------------------------------------------
# PostScript emitter (print). Guarantees mm via a /mm operator. Colours use
# native setcmykcolor; --separations turns on overprint so the C/M/Y plates
# physically overlap ("burn") on a real RIP.
# ---------------------------------------------------------------------------
def to_postscript(geom, page_w, page_h, landscape=False, separations=False):
    if landscape and page_h > page_w:
        page_w, page_h = page_h, page_w
    ox = (page_w - geom.length_mm) / 2.0
    oy = (page_h - geom.total_h) / 2.0

    L = []
    L.append("%!PS-Adobe-3.0")
    L.append("%%%%BoundingBox: 0 0 %d %d"
             % (round(page_w * PT_PER_MM), round(page_h * PT_PER_MM)))
    L.append("%%Creator: rulercode.py")
    L.append("%%Title: Rulercode id=0x%04X len=%.1fmm" % (geom.id, geom.length_mm))
    L.append("%%EndComments")
    L.append("/mm { %.10f mul } def" % PT_PER_MM)
    # box: x y w h  ->  filled rectangle path (consumes current colour)
    L.append("/box { newpath 4 dict begin /h exch def /w exch def /y exch def "
             "/x exch def x mm y mm moveto w mm 0 rlineto 0 h mm rlineto "
             "w mm neg 0 rlineto closepath fill end } def")
    L.append("/K { 0 0 0 1 setcmykcolor } def")

    def box(x, y, w, h):
        L.append("%.4f %.4f %.4f %.4f box" % (ox + x, oy + y, w, h))

    def cmyk(c, m, y, k):
        L.append("%.3f %.3f %.3f %.3f setcmykcolor" % (c, m, y, k))

    cells = list(geom.data_rects()) + list(geom.palette_swatches())

    if separations:
        L.append("true setoverprint")
        for idx, (c, m, y) in ((0, (1, 0, 0)), (1, (0, 1, 0)), (2, (0, 0, 1))):
            for (x, w, cmy) in cells:
                if cmy[idx]:
                    cmyk(c, m, y, 0.0)
                    box(x, geom.bar_y0, w, geom.bar_h)
        L.append("false setoverprint")
    else:
        # flattened composite -- identical appearance on any device
        for (x, w, cmy) in cells:
            c, m, y = cmy
            k = 1.0 if (c and m and y) else 0.0
            cmyk(c if not k else 0, m if not k else 0, y if not k else 0, k)
            box(x, geom.bar_y0, w, geom.bar_h)

    # module separators
    L.append("K 0.15 setlinewidth")
    for (x, w, _) in geom.data_rects():
        L.append("newpath %.4f mm %.4f mm moveto 0 %.4f mm rlineto stroke"
                 % (ox + x, oy + geom.bar_y0, geom.bar_h))

    # finder bars
    L.append("K")
    for (x, w) in geom.finder_bars():
        box(x, geom.bar_y0, w, geom.bar_h)

    # ruler
    L.append("K")
    box(0, geom.ruler_y0, geom.length_mm, 0.2)
    L.append("0.25 setlinewidth")
    for (x, major, label) in geom.ruler_ticks():
        th = RULER_H if major else RULER_H * 0.55
        L.append("newpath %.4f mm %.4f mm moveto 0 %.4f mm rlineto stroke"
                 % (ox + x, oy + geom.ruler_y0, th))
    L.append("/Courier findfont 6 scalefont setfont")
    for (x, major, label) in geom.ruler_ticks():
        if label is not None:
            L.append("%.4f mm %.4f mm moveto (%s) dup stringwidth pop 2 div neg "
                     "0 rmoveto show" % (ox + x, oy + geom.ruler_y1 + 0.3, label))

    # human text
    L.append("/Courier findfont 7.2 scalefont setfont")
    L.append("%.4f mm %.4f mm moveto (%s) show"
             % (ox, oy + 1.0, geom.human_text().replace("(", "\\(").replace(")", "\\)")))

    L.append("showpage")
    return "\n".join(L)


# ---------------------------------------------------------------------------
# Pure-Python PPM raster (no PIL) -- used to *prove* encode/decode round-trips
# and to give a viewable image without Ghostscript. Renders the subtractive
# composite the same way a printer+camera would present it.
# ---------------------------------------------------------------------------
def to_ppm(geom, dpi=150, margin_mm=6.0, bg=(255, 255, 255)):
    px_per_mm = dpi / MM_PER_INCH
    W = int(round((geom.length_mm + 2 * margin_mm) * px_per_mm))
    H = int(round((geom.total_h + 2 * margin_mm) * px_per_mm))
    buf = bytearray(bytes(bg) * (W * H))

    def fill_rect_mm(x, y, w, h, rgb):
        x0 = int(round((x + margin_mm) * px_per_mm))
        x1 = int(round((x + w + margin_mm) * px_per_mm))
        # PPM y grows downward; flip.
        yb0 = int(round((geom.total_h - (y + h) + margin_mm) * px_per_mm))
        yb1 = int(round((geom.total_h - y + margin_mm) * px_per_mm))
        r, g, b = rgb
        for py in range(max(0, yb0), min(H, yb1)):
            row = py * W * 3
            for px in range(max(0, x0), min(W, x1)):
                o = row + px * 3
                buf[o] = r; buf[o + 1] = g; buf[o + 2] = b

    # data + palette composite colours
    for (x, w, cmy) in list(geom.data_rects()) + list(geom.palette_swatches()):
        fill_rect_mm(x, geom.bar_y0, w, geom.bar_h, cmy_to_rgb255(cmy))
    # finder bars (black)
    for (x, w) in geom.finder_bars():
        fill_rect_mm(x, geom.bar_y0, w, geom.bar_h, (0, 0, 0))

    header = ("P6\n%d %d\n255\n" % (W, H)).encode("ascii")
    return header + bytes(buf), (W, H, px_per_mm, margin_mm)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def main(argv=None):
    p = argparse.ArgumentParser(description="Generate Rulercode CMYK fiducial markers.")
    p.add_argument("--id", type=lambda s: int(s, 0), default=0x04D2,
                   help="marker id (0..65535), e.g. 1234 or 0x04D2")
    p.add_argument("--paper", choices=sorted(PAPER), default="letter")
    p.add_argument("--length", type=float, default=None,
                   help="override marker length in mm (default: per-paper)")
    p.add_argument("--format", choices=["svg", "ps", "ppm"], default="svg")
    p.add_argument("--separations", action="store_true",
                   help="PostScript: overprint C/M/Y plates (real burn)")
    p.add_argument("--dpi", type=int, default=150, help="PPM render dpi")
    p.add_argument("-o", "--out", default="-", help="output file (default stdout)")
    args = p.parse_args(argv)

    page_w, page_h, def_len, landscape = PAPER[args.paper]
    length = args.length if args.length else def_len
    geom = MarkerGeometry(args.id, length)

    if args.format == "svg":
        data = to_svg(geom, page_w, page_h, landscape).encode("utf-8")
    elif args.format == "ps":
        data = to_postscript(geom, page_w, page_h, landscape,
                             args.separations).encode("utf-8")
    else:
        data, _ = to_ppm(geom, dpi=args.dpi)

    if args.out == "-":
        sys.stdout.buffer.write(data)
    else:
        with open(args.out, "wb") as f:
            f.write(data)
        info = decode_payload(geom.modules)
        sys.stderr.write("wrote %s  (%s, id=0x%04X, L=%.1fmm, module=%.2fmm, %s)\n"
                         % (args.out, args.paper, info["id"], length, geom.module,
                            "CRC-OK" if info["crc_ok"] else "CRC-BAD"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
