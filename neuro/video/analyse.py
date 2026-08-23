#!/usr/bin/env python3
"""analyse.py — polarity and temporal discharge structure of the traced signals.

Produces the event list that both the picture and the sound are driven from, so
a flash on screen and a note in the ear are always the same event. Nothing here
is decorative: every marker has a latency, an amplitude, a polarity and a
prominence, and the renderer and the synthesiser read the same file.

WHAT IT EXTRACTS
================
per channel
    peaks        local extrema with latency, amplitude, polarity, prominence,
                 and rise/fall slope in uV/ms
    crossings    sign changes -- the moments the field flips polarity
    components   peaks assigned to the conventional evoked-potential windows

across channels
    order        the sequence of principal deflections by latency, which is the
                 "temporal discharge pattern": who fires first and who follows

The cross-channel ordering is the finding worth looking at. Textbook sequence is
N100, then the frontocentral P3a, then the parietal P3b. This record traces as
N100 -> P3b -> P3a, with the frontal orienting response arriving LAST. That is
visible in the printed figures and stated nowhere in the report.

    python3 video/analyse.py --series build/video/series.json --out build/video/features.json
"""

import argparse
import json
import os
import sys

try:
    import numpy as np
except ImportError:
    sys.exit("needs numpy:  pip install numpy")


# Conventional latency windows. Deliberately wide: this subject's components are
# late, and a window tight enough to be textbook would simply fail to find them.
COMPONENTS = [
    ("N100", -1, 70, 320),
    ("P200", +1, 150, 330),
    ("N200", -1, 200, 380),
    ("P3b",  +1, 300, 520),
    ("P3a",  +1, 380, 620),
    ("LPC",  +1, 550, 1000),
]

# Where each electrode sits, in a unit circle looking down on the head with the
# nose at the top. Standard 10-20 projection.
POS = {
    "FP1": (-0.31, -0.85), "FP2": (0.31, -0.85),
    "F7":  (-0.72, -0.51), "F3": (-0.38, -0.44), "FZ": (0.00, -0.42),
    "F4":  (0.38, -0.44),  "F8": (0.72, -0.51),
    "T7":  (-0.86,  0.00), "C3": (-0.43,  0.00), "CZ": (0.00,  0.00),
    "C4":  (0.43,  0.00),  "T8": (0.86,  0.00),
    "P7":  (-0.72,  0.51), "P3": (-0.38,  0.44), "PZ": (0.00,  0.42),
    "P4":  (0.38,  0.44),  "P8": (0.72,  0.51),
    "O1":  (-0.31,  0.85), "O2": (0.31,  0.85),
}

# The anterior-posterior bipolar chains a clinical reader actually traverses.
# Drawn as routes on the atlas so the montage is visible as a path rather than
# implied by the order of the rows.
CHAINS = [
    ("left temporal",   ["FP1", "F7", "T7", "P7", "O1"]),
    ("left parasagittal", ["FP1", "F3", "C3", "P3", "O1"]),
    ("midline",         ["FZ", "CZ", "PZ"]),
    ("right parasagittal", ["FP2", "F4", "C4", "P4", "O2"]),
    ("right temporal",  ["FP2", "F8", "T8", "P8", "O2"]),
]


def smooth(y, k=5):
    if k < 3:
        return y
    w = np.hanning(k)
    w /= w.sum()
    return np.convolve(y, w, mode="same")


def find_peaks(t, y, min_prom):
    """Local extrema with prominence, in both polarities.

    Prominence is measured against the lower of the two neighbouring troughs,
    which is what keeps a wobble on the shoulder of the P3 from being reported
    as a component in its own right.
    """
    out = []
    d = np.diff(y)
    turns = np.flatnonzero(np.sign(d[:-1]) != np.sign(d[1:])) + 1
    for i in turns:
        pol = +1 if y[i] > y[i - 1] else -1
        # walk out to the nearest lower/higher point on each side
        j = i
        while j > 0 and (y[j - 1] - y[i]) * pol <= 0:
            j -= 1
        k = i
        while k < len(y) - 1 and (y[k + 1] - y[i]) * pol <= 0:
            k += 1
        base = max(y[j], y[k]) if pol > 0 else min(y[j], y[k])
        prom = abs(y[i] - base)
        if prom < min_prom:
            continue
        dt = t[1] - t[0]
        rise = (y[i] - y[j]) / max(1e-6, (t[i] - t[j])) if i > j else 0.0
        fall = (y[k] - y[i]) / max(1e-6, (t[k] - t[i])) if k > i else 0.0
        out.append(dict(
            t_ms=round(float(t[i]), 1),
            uv=round(float(y[i]), 3),
            polarity=int(pol),
            prominence=round(float(prom), 3),
            rise_uv_per_ms=round(float(rise), 4),
            fall_uv_per_ms=round(float(fall), 4),
        ))
    return out


def crossings(t, y):
    """Zero crossings -- the instants the scalp field reverses polarity."""
    s = np.sign(y)
    idx = np.flatnonzero(s[:-1] * s[1:] < 0)
    out = []
    for i in idx:
        # linear interpolation to the actual crossing time
        frac = abs(y[i]) / max(1e-9, abs(y[i]) + abs(y[i + 1]))
        out.append(dict(
            t_ms=round(float(t[i] + frac * (t[i + 1] - t[i])), 1),
            direction="rising" if y[i + 1] > y[i] else "falling",
            slope_uv_per_ms=round(float((y[i + 1] - y[i]) / (t[i + 1] - t[i])), 4),
        ))
    return out


def assign_components(peaks):
    """Best peak in each conventional window, by prominence."""
    got = {}
    for name, pol, lo, hi in COMPONENTS:
        cands = [p for p in peaks
                 if p["polarity"] == pol and lo <= p["t_ms"] <= hi]
        if not cands:
            continue
        best = max(cands, key=lambda p: p["prominence"])
        got[name] = best
    return got


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--series", default="build/video/series.json")
    ap.add_argument("--out", default="build/video/features.json")
    args = ap.parse_args()
    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)

    S = json.load(open(args.series))
    feats = {"schema": "neuro/features/v1", "positions": POS, "chains": CHAINS}

    # -- evoked potentials ---------------------------------------------------
    erp = {}
    principal = []
    for key, ser in S["erp"].items():
        t = np.asarray(ser["t_ms"], dtype=float)
        y = smooth(np.asarray(ser["uv"], dtype=float), 5)
        span = float(np.ptp(y))
        pk = find_peaks(t, y, min_prom=0.035 * span)
        cx = crossings(t, y)
        comp = assign_components(pk)

        big = max(pk, key=lambda p: abs(p["uv"])) if pk else None
        if big:
            principal.append((big["t_ms"], key, big["uv"], big["polarity"]))

        erp[key] = dict(
            label=ser["label"], units="uV",
            span_uv=round(span, 3),
            peaks=pk, crossings=cx, components=comp,
            principal=big,
            check=ser.get("check"),
        )
        print(f"  {key:3s} {ser['label']:26s} {len(pk):2d} peaks, {len(cx):2d} polarity "
              f"reversals, components: {', '.join(sorted(comp)) or 'none'}", file=sys.stderr)

    principal.sort()
    feats["erp"] = erp
    feats["discharge_order"] = [
        dict(rank=i + 1, t_ms=t, channel=c, uv=v, polarity=p)
        for i, (t, c, v, p) in enumerate(principal)
    ]

    order = " -> ".join(f"{c} {t:.0f}ms" for t, c, _, _ in principal)
    print(f"\n  temporal discharge order: {order}", file=sys.stderr)
    if len(principal) == 3:
        names = [c for _, c, _, _ in principal]
        if names == ["O2", "Pz", "Cz"]:
            print("  -> N100 then the PARIETAL P3b then the FRONTOCENTRAL P3a.\n"
                  "     Textbook order puts P3a before P3b. Here the orienting response\n"
                  "     arrives last, which is the same story the 0.382 amplitude ratio\n"
                  "     tells, arriving by a different route.", file=sys.stderr)

    # -- resting runs --------------------------------------------------------
    raw = {}
    for cond, r in S["raw"].items():
        n = r["samples"]
        t = np.linspace(0, r["seconds"], n)
        chans = {}
        for name, v in r["channels"].items():
            if v is None:
                chans[name] = None
                continue
            y = np.asarray(v, dtype=float)
            chans[name] = dict(
                rms=round(float(np.sqrt((y ** 2).mean())), 4),
                reversals=int(np.sum(np.sign(y[:-1]) * np.sign(y[1:]) < 0)),
            )
        # Rejected electrodes trace as a flat line; their "zero crossings" are
        # scanner noise and would drag the frequency estimate down.
        live = {k: c for k, c in chans.items()
                if c and k not in set(r.get("rejected", []))}
        # Reversals per second is a crude dominant-frequency proxy: a sinusoid
        # crosses zero twice per cycle, so rate/2 approximates its frequency.
        hz = {k: round(c["reversals"] / r["seconds"] / 2.0, 2) for k, c in live.items()}
        raw[cond] = dict(stats=chans, dominant_hz=hz,
                         mean_hz=round(float(np.mean(list(hz.values()))), 2))
        print(f"  {cond:11s} mean zero-crossing rate implies "
              f"{raw[cond]['mean_hz']:.2f} Hz across {len(live)} channels", file=sys.stderr)
    feats["raw"] = raw

    json.dump(feats, open(args.out, "w"))
    print(f"\nanalyse: wrote {args.out}", file=sys.stderr)


if __name__ == "__main__":
    main()
