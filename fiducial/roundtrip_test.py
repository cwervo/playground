#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Round-trip + robustness tests for Rulercode. Pure stdlib, run directly:

    python3 roundtrip_test.py
"""
import random
import sys

import rulercode as rc
from decode import decode_ppm


def add_noise(ppm_bytes, sigma, seed=0):
    """Add Gaussian sensor noise to the pixel data of a P6 PPM."""
    w, h, px = _split(ppm_bytes)
    rng = random.Random(seed)
    out = bytearray(px)
    for i in range(len(out)):
        v = out[i] + int(rng.gauss(0, sigma))
        out[i] = 0 if v < 0 else 255 if v > 255 else v
    return _join(w, h, out)


def _split(data):
    from decode import parse_ppm
    w, h, px = parse_ppm(data)
    return w, h, bytearray(px)


def _join(w, h, px):
    return ("P6\n%d %d\n255\n" % (w, h)).encode() + bytes(px)


def test_payload_unit():
    """encode -> decode is exact for many ids/lengths, and CRC catches flips."""
    n = 0
    for mid in [0, 1, 1234, 0xFFFF, 42, 0xABCD]:
        for length in [200.0, 190.0, 128.0, 90.0, 74.0, 55.5]:
            mods = rc.encode_payload(mid, length)
            got = rc.decode_payload(mods)
            assert got["id"] == mid, (mid, got)
            assert got["crc_ok"], (mid, length)
            assert abs(got["length_mm"] - round(length * 10) / 10.0) < 1e-9
            n += 1
    # flip one bit in one module -> CRC must fail (very high probability)
    mods = rc.encode_payload(1234, 200.0)
    c, m, y = mods[5]
    mods[5] = (c ^ 1, m, y)
    assert not rc.decode_payload(mods)["crc_ok"], "CRC failed to catch a bit flip"
    print("payload unit .......... OK (%d id/length combos + CRC flip)" % n)


def test_raster_roundtrip():
    """Render every paper size to a raster and decode it back."""
    for paper in sorted(rc.PAPER):
        pw, ph, length, _ls = rc.PAPER[paper]
        mid = random.Random(paper).randint(0, 0xFFFF)
        geom = rc.MarkerGeometry(mid, length)
        ppm, (w, h, ppmm, _m) = rc.to_ppm(geom, dpi=200)
        info = decode_ppm(ppm)
        assert info["id"] == mid, (paper, info["id"], mid)
        assert info["crc_ok"], paper
        assert abs(info["length_mm"] - length) < 0.05, (paper, info["length_mm"])
        true_mm_per_px = 1.0 / ppmm
        err = abs(info["mm_per_px"] - true_mm_per_px) / true_mm_per_px
        assert err < 0.01, (paper, err)                # scale within 1%
        print("raster %-7s ....... OK  id=0x%04X L=%.1fmm scale=%.4f mm/px (err %.2f%%)"
              % (paper, mid, info["length_mm"], info["mm_per_px"], err * 100))


def test_noise_robustness():
    """Graceful-degradation curve under simulated sensor noise.

    Two things matter for a barcode: (1) it decodes correctly under realistic
    noise, and (2) when noise is extreme it *rejects* via CRC rather than
    emitting a wrong id. We assert both: perfect through moderate noise, and
    zero wrong-id-accepted at any level.
    """
    geom = rc.MarkerGeometry(0x04D2, 200.0)
    ppm, _ = rc.to_ppm(geom, dpi=200)
    wrong_accepted = 0
    for sigma in (10, 25, 40, 60, 80):
        good = rejected = 0
        for seed in range(8):
            info = decode_ppm(add_noise(ppm, sigma, seed))
            if info["crc_ok"]:
                if info["id"] == 0x04D2:
                    good += 1
                else:
                    wrong_accepted += 1          # CRC let a bad id through -- bad!
            else:
                rejected += 1                    # detected corruption, safe
        print("noise sigma=%-3d ....... %d/8 correct, %d safely-rejected"
              % (sigma, good, rejected))
        if sigma <= 40:
            assert good == 8, "should decode cleanly at sigma<=40"
    assert wrong_accepted == 0, "CRC accepted a corrupted id -- unsafe!"


def main():
    random.seed(1)
    test_payload_unit()
    test_raster_roundtrip()
    test_noise_robustness()
    print("\nALL TESTS PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
