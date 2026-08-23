#!/usr/bin/env python3
"""trace.py — recover time series from the printed figures.

WHAT THIS IS AND IS NOT
=======================
There is no continuous multichannel EEG in this record. The five documents are
scanned printouts. What exists is:

  * three AVERAGED evoked-potential traces from the checkerboard/target block --
    Cz (P300a), Pz (P300b), O2 (N100), each about 1200 ms of an averaged epoch.
    The checkerboard block IS the photic stimulation in this battery, so this is
    the photic data, and there is no more of it.

  * two 10-second raw EEG samples, eyes open and eyes closed, 19 electrode rows
    of which 15 carry signal. Resting, not photic.

So this script does curve tracing on the printed plots. Every sample it produces
is a measurement of ink, not of a subject. That is a real limitation and it is
recorded in the output rather than smoothed over: each series carries a
`provenance` field saying it was digitised, from which figure, at what
resolution, and how it was calibrated.

CALIBRATION
===========
Both axes are calibrated from the plots' own printed tick marks, which are
detected rather than assumed:

    x  13 ticks under the axis, evenly spaced, spanning -200 to 1000 ms,
       so one tick interval is 100 ms and the third tick is t = 0.
    y  ticks on the left spine at a fixed microvolt step (5, 2 and 5 uV for
       Cz, Pz and O2). Zero is the tick that coincides with the dotted
       baseline drawn across the plot.

Nothing in that chain uses the report's printed peak values, which means those
values are available as an independent check: if the traced extremum lands at
+17.26 uV / 468 ms without having been told to, the digitisation is sound. That
comparison is printed for every series and a disagreement is an error, not a
rounding.

    P300a  peak  +17.26 uV at 468 ms
    P300b  peak  + 6.60 uV at 380 ms
    N100   trough - 7.55 uV at 288 ms

The raw EEG page prints no voltage scale at all, so those channels come out in
normalised units and say so.

    python3 video/trace.py --img build/conference/img --out build/video/series.json
"""

import argparse
import json
import os
import sys

try:
    import numpy as np
    from PIL import Image
except ImportError:
    sys.exit("needs numpy and pillow:  pip install numpy pillow")


# ---------------------------------------------------------------------------
# Evoked potentials. Boxes are the plot interior in fractions of the figure
# crop, chosen to exclude the axis furniture and the tick labels.
# ---------------------------------------------------------------------------
ERP = {
    "Cz": dict(fig="GoNoGo_ERP-P300a-Cz", uv_step=5.0,
               peak_uv=17.26, peak_ms=468.0, sign=+1,
               label="P300a  Cz  checkerboard"),
    "Pz": dict(fig="GoNoGo_ERP-P300b-Pz", uv_step=2.0,
               peak_uv=6.60, peak_ms=380.0, sign=+1,
               label="P300b  Pz  target"),
    "O2": dict(fig="GoNoGo_ERP-N100-O2", uv_step=5.0,
               peak_uv=-7.55, peak_ms=288.0, sign=-1,
               label="N100  O2  checkerboard"),
}

MS_PER_TICK = 100.0      # 13 ticks spanning -200..1000 ms
ZERO_TICK_INDEX = 2      # tick[0] is -200 ms

# The raw-EEG montage, in the printed order. Four rows are labelled (rejected)
# and carry a flat line; they are traced anyway so the montage stays honest
# about which electrodes contributed nothing.
MONTAGE = ["FP1", "FP2", "F7", "F3", "FZ", "F4", "F8", "T7", "C3", "CZ",
           "C4", "T8", "P7", "P3", "PZ", "P4", "P8", "O1", "O2"]
REJECTED = {"FZ", "T8", "P3", "P8"}

RAW = {
    "eyes_open":   dict(fig="EyesOpen_EEG-RawTrace",   plot=(0.175, 0.045, 0.995, 0.875)),
    "eyes_closed": dict(fig="EyesClosed_EEG-RawTrace", plot=(0.175, 0.045, 0.995, 0.875)),
}


# ---------------------------------------------------------------------------
def load(imgdir, stem):
    for f in sorted(os.listdir(imgdir)):
        if f.startswith(stem + "_") and f.endswith(".png"):
            return np.asarray(Image.open(os.path.join(imgdir, f)).convert("L"), dtype=np.float64)
    raise FileNotFoundError(f"{stem}_*.png not in {imgdir}")


def sub(img, box):
    h, w = img.shape
    x0, y0, x1, y1 = box
    return img[int(y0 * h):int(y1 * h), int(x0 * w):int(x1 * w)]


def trace_curve(plot, drop_wide=0.55):
    """Follow the darkest continuous stroke down each column.

    The plot contains more than the curve: a dashed vertical stimulus marker, a
    dotted zero line, a grey shaded latency window, and the frame. The curve is
    distinguished by being the darkest *and* the most compact vertical run --
    the dashed marker spans most of the column height and is rejected by
    `drop_wide`, and the grey band never gets dark enough to compete.

    Returns (y_centroid_per_column, valid_mask), y in pixel rows from the top.
    """
    H, W = plot.shape
    ink = 255.0 - plot
    thr = max(70.0, float(np.percentile(ink, 99.0)) * 0.45)

    ys = np.full(W, np.nan)
    for x in range(W):
        col = ink[:, x]
        on = col > thr
        if not on.any():
            continue
        # split the column into runs of "on" pixels
        idx = np.flatnonzero(on)
        splits = np.flatnonzero(np.diff(idx) > 1) + 1
        best, best_mass = None, 0.0
        for run in np.split(idx, splits):
            if len(run) > drop_wide * H:      # the dashed stimulus marker
                continue
            mass = float(col[run].sum())
            if mass > best_mass:
                best_mass, best = mass, run
        if best is None:
            continue
        w = col[best]
        ys[x] = float((best * w).sum() / w.sum())
    return ys, ~np.isnan(ys)


def fill_gaps(ys):
    """Linear interpolation across columns the tracer could not resolve."""
    v = ~np.isnan(ys)
    if v.sum() < 2:
        return ys
    x = np.arange(len(ys))
    out = ys.copy()
    out[~v] = np.interp(x[~v], x[v], ys[v])
    return out


def _groups(mask, gap=2):
    idx = np.flatnonzero(mask)
    if len(idx) == 0:
        return []
    return [g for g in np.split(idx, np.flatnonzero(np.diff(idx) > gap) + 1) if len(g)]


def _drop_outlier_ticks(ticks):
    """Keep the longest run of consistently-spaced ticks.

    The figure crops include a table rule a few pixels outside the axis, which
    reads as one extra 'tick' at an anomalous spacing. Dropping by spacing
    consistency removes it without hard-coding where it is.
    """
    if len(ticks) < 3:
        return ticks
    d = np.diff(ticks)
    med = float(np.median(d))
    keep = [ticks[0]] if abs(d[0] - med) <= 0.25 * med else []
    for i, dd in enumerate(d):
        if abs(dd - med) <= 0.25 * med:
            if not keep or keep[-1] != ticks[i]:
                keep.append(ticks[i])
            keep.append(ticks[i + 1])
    return keep


def find_axes(img):
    """Locate the plot frame, the tick marks, and the baseline.

    Everything downstream hangs off this, so it is done by detection rather
    than by fractions of the image: the three ERP crops differ in height by
    enough that a hard-coded box lands on the wrong row in at least one.
    """
    H, W = img.shape
    ink = 255.0 - img

    rs = ink.sum(axis=1)
    axis_row = int(np.argmax(rs[int(H * 0.55):int(H * 0.95)])) + int(H * 0.55)
    top_row = int(np.argmax(rs[: int(H * 0.15)]))

    cs = ink[:axis_row, :].sum(axis=0)
    spine = int(np.argmax(cs[int(W * 0.10):int(W * 0.30)])) + int(W * 0.10)

    band = ink[axis_row + 2:axis_row + 9, :].sum(axis=0)
    xt = _drop_outlier_ticks([int(g.mean()) for g in _groups(band > band.max() * 0.45)])

    band = ink[:axis_row, max(0, spine - 8):spine - 1].sum(axis=1)
    yt = _drop_outlier_ticks([int(g.mean()) for g in _groups(band > band.max() * 0.45)])

    # Zero volts is the y tick that the dotted baseline runs along, which is the
    # one whose row carries the most ink inside the plot.
    interior = ink[:, spine + 3:]
    zero_row = max(yt, key=lambda r: interior[r].sum()) if yt else axis_row

    return dict(axis_row=axis_row, top_row=top_row, spine=spine,
                xticks=xt, yticks=yt, zero_row=zero_row)


# ---------------------------------------------------------------------------
def trace_erp(imgdir, key, spec, report):
    img = load(imgdir, spec["fig"])
    ax = find_axes(img)
    xt, yt = ax["xticks"], ax["yticks"]
    if len(xt) < 5 or len(yt) < 3:
        raise RuntimeError(f"{key}: only {len(xt)} x ticks and {len(yt)} y ticks found")

    px_per_tick = float(np.median(np.diff(xt)))
    ms_per_px = MS_PER_TICK / px_per_tick
    stim_col = xt[ZERO_TICK_INDEX]
    uv_per_px = spec["uv_step"] / float(np.median(np.diff(yt)))
    zero_row = ax["zero_row"]

    # Clip to the tick extent on both axes. Running the crop out to the image
    # edge lets the surrounding table rules into the plot, and the tracer
    # follows the rule instead of the curve -- which is what put the P300a
    # "peak" at 997 ms against a report that says 468.
    x0, x1 = ax["spine"] + 3, xt[-1] + 2
    y0, y1 = ax["top_row"] + 3, ax["axis_row"] - 2
    plot = img[y0:y1, x0:x1]
    x_off = x0
    W = plot.shape[1]

    ys, valid = trace_curve(plot)
    ys = fill_gaps(ys)

    t_ms = (np.arange(W) + x_off - stim_col) * ms_per_px
    uv = (zero_row - (ys + y0)) * uv_per_px

    # Independent check: the extremum should land where the report says.
    lo, hi = int(W * 0.04), int(W * 0.96)
    seg = uv[lo:hi]
    ext = lo + int(np.argmax(seg) if spec["sign"] > 0 else np.argmin(seg))
    d_uv = uv[ext] - spec["peak_uv"]
    d_ms = t_ms[ext] - spec["peak_ms"]
    ok = abs(d_uv) <= 0.9 and abs(d_ms) <= 45
    report.append(
        f"  {key:3s} {spec['label']:26s} {W} px  "
        f"{ms_per_px:.2f} ms/px  {uv_per_px:.4f} uV/px  "
        f"epoch {t_ms[0]:+.0f}..{t_ms[-1]:+.0f} ms  "
        f"extremum {uv[ext]:+.2f} uV @ {t_ms[ext]:.0f} ms vs report "
        f"{spec['peak_uv']:+.2f} @ {spec['peak_ms']:.0f}  "
        f"[{'ok' if ok else 'MISMATCH'} {d_uv:+.2f} uV {d_ms:+.0f} ms]  "
        f"{valid.mean()*100:.0f}% resolved"
    )
    return dict(
        channel=key, label=spec["label"],
        t_ms=t_ms.round(3).tolist(), uv=uv.round(4).tolist(), units="uV",
        check=dict(traced_uv=round(float(uv[ext]), 3), traced_ms=round(float(t_ms[ext]), 1),
                   report_uv=spec["peak_uv"], report_ms=spec["peak_ms"], ok=bool(ok)),
        provenance=(
            f"digitised from {spec['fig']}.tiff; both axes calibrated from the "
            f"plot's own tick marks ({MS_PER_TICK:.0f} ms and "
            f"{spec['uv_step']:.0f} uV per tick), not from the report's numbers"
        ),
    )


def trace_raw(imgdir, cond, spec, report):
    img = load(imgdir, spec["fig"])
    plot = sub(img, spec["plot"])
    H, W = plot.shape
    n = len(MONTAGE)
    band = H / n

    chans = {}
    unresolved = np.zeros(W)
    for i, name in enumerate(MONTAGE):
        y0, y1 = int(i * band), int((i + 1) * band)
        strip = plot[y0:y1, :]
        ys, valid = trace_curve(strip, drop_wide=0.9)
        unresolved += ~valid
        ys = fill_gaps(ys)
        if np.isnan(ys).all():
            chans[name] = None
            continue
        v = ys - np.nanmean(ys)
        v = -v                       # pixel rows increase downward
        chans[name] = v

    # The crop runs a little past the end of the printed axis, so the last few
    # dozen columns are blank paper with a vertical rule sitting in them. Left
    # alone, fill_gaps interpolates straight across the blank and lands on the
    # rule, which manufactures a clean diagonal ramp in every channel at once
    # -- a fake synchronous discharge, and the most convincing kind of wrong.
    # So the window is cut to the longest run of columns that most channels
    # actually resolved, and the isolated run that is the rule is left outside.
    ok = unresolved <= n // 2
    best = (0, 0)
    i = 0
    while i < W:
        if ok[i]:
            j = i
            while j + 1 < W and ok[j + 1]:
                j += 1
            if j - i > best[1] - best[0]:
                best = (i, j)
            i = j
        i += 1
    c0, c1 = best[0], best[1] + 1
    if c1 - c0 < W:
        report.append(f"  {cond:11s} trimmed to columns {c0}..{c1} of {W} "
                      f"({W - (c1 - c0)} blank or ruled)")
    for name in list(chans):
        if chans[name] is not None:
            chans[name] = chans[name][c0:c1]
    W = c1 - c0

    # The raw-EEG page carries no voltage scale, so amplitude is normalised to
    # the median non-rejected channel's standard deviation. That keeps the
    # relative amplitudes between channels -- which is the thing the animation
    # is actually showing -- without inventing a microvolt figure.
    sds = [float(np.std(v)) for k, v in chans.items() if v is not None and k not in REJECTED]
    ref = float(np.median(sds)) if sds else 1.0

    out = {}
    for name, v in chans.items():
        if v is None:
            out[name] = None
            continue
        out[name] = (v / ref).round(4).tolist()

    live = [k for k, v in out.items() if v is not None and k not in REJECTED]
    report.append(
        f"  {cond:11s} {W} inked columns over 10 s ({W/10:.0f} px/s), "
        f"{len(live)}/{n} channels traced, "
        f"reference SD {ref:.2f} px, amplitude in normalised units"
    )
    return dict(
        condition=cond, montage=MONTAGE, rejected=sorted(REJECTED),
        seconds=10.0, samples=W, channels=out, units="normalised",
        provenance=(
            f"digitised from {spec['fig']}.tiff; the source figure prints no "
            f"voltage scale, so amplitudes are divided by the median "
            f"non-rejected channel SD and are relative, not microvolts"
        ),
    )


# ---------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--img", default="build/conference/img")
    ap.add_argument("--out", default="build/video/series.json")
    args = ap.parse_args()
    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)

    report = []
    print("trace: evoked potentials (the photic block)", file=sys.stderr)
    erp = {k: trace_erp(args.img, k, s, report) for k, s in ERP.items()}
    print("\n".join(report), file=sys.stderr)

    report = []
    print("trace: raw EEG (resting)", file=sys.stderr)
    raw = {k: trace_raw(args.img, k, s, report) for k, s in RAW.items()}
    print("\n".join(report), file=sys.stderr)

    with open(args.out, "w") as f:
        json.dump({
            "schema": "neuro/series/v1",
            "warning": (
                "Every sample here was recovered by tracing ink on a scanned "
                "printout. It is a faithful reading of the published figures and "
                "it is not the original recording."
            ),
            "erp": erp,
            "raw": raw,
        }, f)
    print(f"trace: wrote {args.out}", file=sys.stderr)


if __name__ == "__main__":
    main()
