#!/usr/bin/env python3
"""Decode an Amazon / Whole Foods "In-Store Code" QR payload into its fields.

Usage:
    python3 decode_instore_code.py [--redact] <image.png | base64-string> ...

Image inputs need `opencv-python-headless` and `zxing-cpp`; base64 strings need
nothing beyond the standard library.  See README.md for the field layout.
"""
import argparse
import base64
import datetime as dt
import os
import sys
import uuid

MAGIC = b"AMZ"


def read_qr(path):
    import cv2  # noqa: E402
    import zxingcpp  # noqa: E402

    results = zxingcpp.read_barcodes(cv2.imread(path))
    if not results:
        raise SystemExit(f"{path}: no QR code found")
    r = results[0]
    return r.text, r.ec_level, r.orientation


def parse(payload_b64):
    raw = base64.b64decode(payload_b64)
    if raw[:3] != MAGIC:
        raise ValueError(f"unexpected magic {raw[:3]!r}")
    if len(raw) != 89:
        raise ValueError(f"unexpected length {len(raw)} (expected 89)")
    ts = int.from_bytes(raw[4:8], "big")
    return {
        "magic": raw[:3].decode(),
        "version": raw[3],
        "timestamp": ts,
        "timestamp_utc": dt.datetime.fromtimestamp(ts, dt.timezone.utc).isoformat(),
        "uuid": uuid.UUID(bytes=raw[8:24]),
        "byte24": raw[24],
        "tail": raw[25:],
    }


def show(fields, redact):
    u = str(fields["uuid"])
    tail = fields["tail"].hex()
    if redact:
        u = u[:4] + "…" + u[-4:]
        tail = tail[:8] + "…" + tail[-8:]
    print(f"  magic/version : {fields['magic']} / 0x{fields['version']:02x}")
    print(f"  timestamp     : {fields['timestamp']} ({fields['timestamp_utc']})")
    print(f"  uuid (v{fields['uuid'].version}) : {u}")
    print(f"  byte 24       : 0x{fields['byte24']:02x}")
    print(f"  tail (64 B)   : {tail}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("inputs", nargs="+")
    ap.add_argument("--redact", action="store_true", help="mask identity and signature bytes")
    args = ap.parse_args()
    for item in args.inputs:
        if os.path.exists(item):
            text, ec, orient = read_qr(item)
            print(f"{item}: QR ec_level={ec} orientation={orient}° chars={len(text)}")
        else:
            text = item
            print(f"(inline base64): chars={len(text)}")
        try:
            show(parse(text), args.redact)
        except ValueError as e:
            print(f"  not an In-Store Code payload: {e}", file=sys.stderr)


if __name__ == "__main__":
    main()
