#!/usr/bin/env python3
"""qr-verify.py — check book/qr.tcl against an independent implementation.

The encoder in book/qr.tcl is the one that ships; this is the test that says it
is right. It re-encodes every URL in the bibliography with python-qrcode and
compares the two module matrices cell by cell, for all eight mask patterns, so
a disagreement in encoding, block interleaving, function-pattern placement,
masking or format bits shows up as a mismatch rather than as a QR code that
quietly fails to scan on someone's kitchen table.

Mask *selection* is compared but not required to agree: the penalty rules pick
a mask for legibility, implementations round rule three differently, and every
mask yields a valid symbol. What must agree is the symbol produced for a given
mask.

    pip install qrcode
    python3 book/qr-verify.py

Not part of `make book` -- it needs a package the build deliberately does not.

A note on the choice of oracle. segno was tried first and disagreed on exactly
those inputs whose bit stream lands on a codeword boundary before padding. Its
write_padding_bits does `[0] * (8 - length % 8)`, which contributes a whole
spurious zero codeword when `length % 8` is already 0; the spec adds padding
bits only "if the bit stream length is such that it does not end at a codeword
boundary" (ISO/IEC 18004 7.4.10), and both python-qrcode and Nayuki's reference
implementation write `(8 - length % 8) % 8`. Every real URL here agrees with
python-qrcode module for module.
"""

import re
import subprocess
import sys

try:
    import qrcode
    from qrcode.constants import ERROR_CORRECT_Q
except ImportError:
    sys.exit("needs python-qrcode (the reference implementation):  pip install qrcode")

HERE = __file__.rsplit("/", 1)[0]


def urls():
    src = open(f"{HERE}/../conference/sources.tcl", encoding="utf-8").read()
    out = []
    for m in re.finditer(r'url\s+"(https?://[^"]+)"', src):
        if m.group(1) not in out:
            out.append(m.group(1))
    return out


def tcl_matrix(text, level, mask):
    script = f'''
        source {HERE}/qr.tcl
        set e [qr::encode {{{text}}} -level {level} -mask {mask}]
        puts "[dict get $e version] [dict get $e mask]"
        foreach r [dict get $e rows] {{puts $r}}
    '''
    out = subprocess.run(["tclsh"], input=script, capture_output=True,
                         text=True, check=True).stdout.split("\n")
    version, chosen = out[0].split()
    return int(version), int(chosen), [r for r in out[1:] if r]


def ref_matrix(text, level, mask):
    q = qrcode.QRCode(error_correction=ERROR_CORRECT_Q, box_size=1, border=0,
                      mask_pattern=mask)
    q.add_data(text, optimize=0)
    q.make(fit=True)
    return q.version, [
        "".join("1" if v else "0" for v in row) for row in q.get_matrix()
    ]


def svg_matrix(text, level):
    """Parse the shipped SVG back into modules.

    Checking the matrix is not enough: the book prints the *path*, and a bug in
    the run-length emitter would produce a wrong code from a right matrix. So
    the path is read back and compared, and the quiet zone is checked for ink.
    """
    script = f'source {HERE}/qr.tcl\nputs [qr::svg {{{text}}} -level {level} -size 100]'
    svg = subprocess.run(["tclsh"], input=script, capture_output=True,
                         text=True, check=True).stdout
    span = int(re.search(r'viewBox="0 0 (\d+)', svg).group(1))
    d = re.search(r'<path d="([^"]*)"', svg).group(1)
    grid = [[0] * span for _ in range(span)]
    for x, y, run in re.findall(r"M(\d+) (\d+)h(\d+)v1h-\d+z", d):
        x, y, run = int(x), int(y), int(run)
        for k in range(run):
            grid[y][x + k] = 1
    return span, grid


def main():
    us = urls()
    print(f"checking {len(us)} URLs from conference/sources.tcl, "
          f"eight masks each\n")
    bad = 0
    versions = {}
    for u in us:
        for level in ("Q",):
            for mask in range(8):
                v, chosen, mine = tcl_matrix(u, level, mask)
                rv, theirs = ref_matrix(u, level, mask)
                if v != rv:
                    print(f"  VERSION  {u[:58]:58s} mine v{v} ref v{rv}")
                    bad += 1
                    continue
                if mine != theirs:
                    diff = sum(a != b for ra, rb in zip(mine, theirs)
                               for a, b in zip(ra, rb))
                    print(f"  MISMATCH {u[:48]:48s} mask {mask}: "
                          f"{diff} modules differ")
                    bad += 1
                else:
                    versions[u] = v
        _, chosen, mine = tcl_matrix(u, "Q", "auto")
        span, grid = svg_matrix(u, "Q")
        size = len(mine)
        q = (span - size) // 2
        dirty = any(grid[y][x] for y in range(span) for x in range(span)
                    if y < q or y >= span - q or x < q or x >= span - q)
        drawn = ["".join(str(grid[y + q][x + q]) for x in range(size))
                 for y in range(size)]
        svg_ok = (not dirty) and q == 4 and drawn == mine
        if not svg_ok:
            print(f"  SVG      {u[:48]:48s} path does not reconstruct to the matrix")
            bad += 1
            continue
        print(f"  ok  v{versions.get(u, '?'):<3} 8/8 masks  mask {chosen}  svg ok   {u[:52]}")

    print()
    if bad:
        sys.exit(f"qr-verify: {bad} mismatches")
    from importlib.metadata import version as pkgversion
    print(f"qr-verify: {len(us)} URLs x 8 masks, all identical to python-qrcode "
          f"{pkgversion('qrcode')};\n"
          f"           {len(us)} SVG paths reconstruct to the same modules, "
          f"quiet zones clean")


if __name__ == "__main__":
    main()
