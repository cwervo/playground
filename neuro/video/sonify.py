#!/usr/bin/env python3
"""sonify.py — the discharge pattern as sound. G Mixolydian, pipe organ, thunder.

Nothing here is invented rhythm. Every note and every hit is a row out of
build/video/features.json, placed at the video time its data time maps to, so
the score and the picture cannot drift: they are the same event list.

    peak            -> an organ note. pitch = where the electrode sits front to
                       back, loudness = microvolts, voicing = polarity
    polarity flip   -> a chopped slice of thunder, pitch-bent by the slope of
                       the crossing, panned by how far off the midline the
                       electrode is
    principal peak  -> the full crack: chord, thunder, sub drop, everything
                       else ducked out of the way
    resting alpha   -> the tremulant. The organ's flutter rate IS the measured
                       eyes-closed dominant frequency, read out of
                       features.json rather than chosen. The alpha rhythm is
                       not represented by the tremolo; it is the tremolo.

THE SCALE
    G Mixolydian: G A B C D E F. Major triad, flat seventh. Chosen because the
    material is bimodal -- a positive-going and a negative-going family of
    deflections -- and mixolydian gives two stable colours over one root:
    positive peaks voice the major triad, negative peaks voice the quartal
    stack on the flat seventh. Polarity is audible without a key change.

THE ORGAN
    Additive, drawbar style: ranks at 1, 2, 3, 4, 6 and 8 times the fundamental
    -- 8', 4', 2 2/3', 2', 1 1/3' and 1' -- each slightly detuned from exact so
    the ranks beat against each other the way real pipes do. Speech is modelled
    as a chiff: a short filtered noise burst at note onset before the tone
    settles. A tremulant wobbles wind pressure, which moves pitch and amplitude
    together.

THE THUNDER
    Synthesised, not sampled: a crack (noise filtered bright, then enveloped so
    there is no pre-ring) with three reflections, over a brown-noise body rolled
    off below 200 Hz. Then chopped -- hard rectangular gates, resampled with a
    falling pitch envelope, so each slice is a different piece of the same
    strike.

THE MIX  (the SOPHIE part)
    hard gates          slices start and end at zero, 1.5 ms edges, no fades
    sidechain duck      every hit flattens the pad bus and lets it back up
    sub reinforcement   a mono sine under each hit, saturated, pitched to the
                        note it lands on
    bright top          a highpassed air burst on every transient
    wide stereo         chops panned by electrode laterality with a Haas offset;
                        the sub stays mono so it survives a phone speaker
    silence as an event the act boundary is a hard cut, not a crossfade

    python3 video/sonify.py --features build/video/features.json \
                            --series build/video/series.json \
                            --out build/video/track.wav \
                            --score build/video/score.json
"""

import argparse
import json
import os
import sys
import wave

try:
    import numpy as np
except ImportError:
    sys.exit("needs numpy:  pip install numpy")

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import ACTS, TAIL, TOTAL, act_start, video_time  # noqa: E402

SR = 48000
RNG = np.random.default_rng(20260818)

# G2. Low enough that the 16' pedal has somewhere to go under it.
ROOT = 98.0
MIXOLYDIAN = [0, 2, 4, 5, 7, 9, 10]


def degree_hz(d):
    """Scale degree (may be negative or > 6) -> Hz in G Mixolydian."""
    st = MIXOLYDIAN[d % 7] + 12 * (d // 7)
    return ROOT * (2.0 ** (st / 12.0))


# Posterior to anterior -> up the tonic triad. O2 is the back of the head and
# the bottom of the chord; Cz is the top of it.
CH_DEGREE = {"O2": 7, "Pz": 9, "Cz": 11}      # G3, B3, D4
CH_PAN = {"O2": 0.31, "Pz": 0.0, "Cz": 0.0}   # 10-20 x, midline is centre


# ---------------------------------------------------------------------------
# filters. Zero-phase FFT magnitude shaping. Always applied to noise BEFORE its
# envelope, never after -- filtering an existing transient zero-phase smears
# energy backwards in time and you hear the crack before it happens.
# ---------------------------------------------------------------------------
def _resp(n, fc, order, kind):
    f = np.fft.rfftfreq(n, 1.0 / SR)
    with np.errstate(divide="ignore", invalid="ignore"):
        r = np.where(f > 0, f / fc, 1e-9)
    if kind == "lp":
        return 1.0 / np.sqrt(1.0 + r ** (2 * order))
    h = r ** order / np.sqrt(1.0 + r ** (2 * order))
    h[0] = 0.0
    return h


def lp(x, fc, order=2):
    return np.fft.irfft(np.fft.rfft(x) * _resp(len(x), fc, order, "lp"), n=len(x))


def hp(x, fc, order=2):
    return np.fft.irfft(np.fft.rfft(x) * _resp(len(x), fc, order, "hp"), n=len(x))


# ---------------------------------------------------------------------------
# the organ
# ---------------------------------------------------------------------------
# rank multiplier, level, detune in cents.
#   8'  4'  2-2/3'  2'  1-1/3'  1'  and two mixture ranks on top.
# The upper ranks are drawn much further out than a church registration would
# have them, because this is going to a phone speaker: everything below about
# 200 Hz is going to be reproduced badly or not at all, so the tone has to
# survive in the mixtures.
STOPS = [(1.0, 1.00, 0.0), (2.0, 0.74, +2.5), (3.0, 0.46, -3.5),
         (4.0, 0.55, +4.0), (6.0, 0.30, -5.5), (8.0, 0.28, +6.5),
         (12.0, 0.16, -7.0), (16.0, 0.12, +8.0)]


def organ(f0, dur, gain=1.0, bright=1.0, trem_hz=5.6, trem_depth=0.05,
          chiff=1.0, attack=0.014, release=0.22, t_off=0.0, detune=0.0):
    """One rank-stack of pipes. Returns mono float32.

    `t_off` is the note's absolute start time. The tremulant is phased off it
    rather than off the note, because one tremulant serves the whole chest:
    every pipe speaking at once flutters in step. That is what makes the act-2
    flutter read as a single 9.44 Hz rhythm instead of smearing into mush.

    `detune` in cents. Real ranks are never exactly in tune with each other,
    and the small errors are most of what makes an organ sound wide.
    """
    f0 = f0 * (2.0 ** (detune / 1200.0))
    n = int((dur + release) * SR)
    if n < 8:
        return np.zeros(0, dtype=np.float32)
    t = np.arange(n) / SR
    ta = t + t_off

    # Wind. The tremulant moves pressure, so pitch and level move together, and
    # a slower wobble underneath keeps it from sounding like an LFO.
    trem = np.sin(2 * np.pi * trem_hz * ta)
    wind = 1.0 + trem_depth * trem + 0.012 * np.sin(2 * np.pi * 0.7 * ta + 1.1)
    phase = 2 * np.pi * f0 * np.cumsum(wind) / SR

    y = np.zeros(n)
    for k, lvl, cents in STOPS:
        amp = lvl * (bright ** max(0.0, np.log2(k)))
        y += amp * np.sin(phase * k * (2.0 ** (cents / 1200.0)))
    y /= sum(s[1] for s in STOPS)

    # Speech. Air before tone: a bright burst around the 4' rank that dies in
    # 30 ms, which is what makes an organ sound blown rather than switched on.
    if chiff > 0:
        cn = min(n, int(0.045 * SR))
        noise = hp(RNG.standard_normal(cn), min(0.45 * SR, 2.0 * f0), 2)
        y[:cn] += 0.16 * chiff * noise / (np.abs(noise).max() + 1e-9) * \
            np.exp(-np.arange(cn) / (0.010 * SR))

    env = np.ones(n)
    a = max(2, int(attack * SR))
    r = max(2, int(release * SR))
    env[:a] = np.linspace(0.0, 1.0, a) ** 0.6
    env[-r:] = np.linspace(1.0, 0.0, r) ** 1.8
    env *= 1.0 + 0.35 * trem_depth * trem
    return (y * env * gain).astype(np.float32)


# ---------------------------------------------------------------------------
# the thunder
# ---------------------------------------------------------------------------
def make_thunder(seconds=2.6):
    n = int(seconds * SR)
    t = np.arange(n) / SR

    # crack: filter first, envelope second
    bright = hp(RNG.standard_normal(n), 900.0, 2)
    bright /= np.abs(bright).max() + 1e-9
    crack = np.zeros(n)
    for delay, lvl, tau in ((0.000, 1.00, 0.030), (0.018, 0.55, 0.055),
                            (0.047, 0.34, 0.090), (0.105, 0.20, 0.160)):
        d = int(delay * SR)
        e = np.exp(-(t[:n - d]) / tau)
        crack[d:] += lvl * bright[d:] * e

    # body: brown noise, rolled off, long tail
    brown = np.cumsum(RNG.standard_normal(n))
    brown -= lp(brown, 6.0, 1)              # kill the DC wander
    brown = lp(brown, 190.0, 3)
    brown /= np.abs(brown).max() + 1e-9
    body = brown * (1.0 - np.exp(-t / 0.05)) * np.exp(-t / 0.85)

    # mid rumble, the part that reads as distance
    mid = lp(hp(RNG.standard_normal(n), 120.0, 2), 900.0, 2)
    mid /= np.abs(mid).max() + 1e-9
    mid *= (1.0 - np.exp(-t / 0.02)) * np.exp(-t / 0.40)

    y = 1.15 * crack + 0.52 * body + 0.60 * mid
    return (y / (np.abs(y).max() + 1e-9)).astype(np.float32)


def chop(src, start, dur, rate0, rate1=None, gate=0.0015):
    """A hard-gated slice, resampled with a pitch envelope. SOPHIE's whole bag."""
    n = int(dur * SR)
    if n < 16:
        return np.zeros(0, dtype=np.float32)
    rates = np.linspace(rate0, rate1 if rate1 is not None else rate0, n)
    idx = start * SR + np.cumsum(rates)
    idx = np.clip(idx, 0, len(src) - 1)
    y = np.interp(idx, np.arange(len(src)), src)
    g = max(2, int(gate * SR))
    y[:g] *= np.linspace(0.0, 1.0, g)
    y[-g:] *= np.linspace(1.0, 0.0, g)
    return y.astype(np.float32)


def sub(f0, dur, gain=1.0, bend=0.55):
    """Mono sine under a hit, pitch dropping, saturated. Survives a phone."""
    n = int(dur * SR)
    if n < 16:
        return np.zeros(0, dtype=np.float32)
    t = np.arange(n) / SR
    f = f0 * (bend + (1 - bend) * np.exp(-t / (0.09 * dur + 1e-6)))
    y = np.sin(2 * np.pi * np.cumsum(f) / SR)
    env = (1.0 - np.exp(-t / 0.004)) * np.exp(-t / (0.34 * dur))
    return (np.tanh(2.2 * y * env) * gain).astype(np.float32)


def air(dur, gain=1.0, fc=5200.0):
    n = int(dur * SR)
    if n < 16:
        return np.zeros(0, dtype=np.float32)
    y = hp(RNG.standard_normal(n), fc, 3)
    y /= np.abs(y).max() + 1e-9
    return (y * np.exp(-np.arange(n) / (0.055 * SR)) * gain).astype(np.float32)


# ---------------------------------------------------------------------------
# busing
# ---------------------------------------------------------------------------
class Bus:
    def __init__(self, seconds):
        self.n = int(seconds * SR)
        self.L = np.zeros(self.n, dtype=np.float32)
        self.R = np.zeros(self.n, dtype=np.float32)

    def add(self, mono, at, pan=0.0, haas=0.0):
        """Equal-power pan. `haas` delays the far side in ms for width."""
        i = int(at * SR)
        if i >= self.n or len(mono) == 0:
            return
        m = mono[:max(0, self.n - i)]
        p = (np.clip(pan, -1.0, 1.0) + 1.0) * np.pi / 4.0
        gl, gr = np.cos(p), np.sin(p)
        self.L[i:i + len(m)] += gl * m
        if haas > 0.0:
            j = i + int(haas * 0.001 * SR)
            if j < self.n:
                mm = mono[:max(0, self.n - j)]
                self.R[j:j + len(mm)] += gr * mm
                return
        self.R[i:i + len(m)] += gr * m

    def add_mono(self, mono, at, gain=1.0):
        i = int(at * SR)
        if i >= self.n or len(mono) == 0:
            return
        m = mono[:max(0, self.n - i)] * gain
        self.L[i:i + len(m)] += m
        self.R[i:i + len(m)] += m


def duck_envelope(n, hits, depth=0.78, hold=0.045, recover=0.34):
    """1.0 normally, slammed to (1-depth) on each hit, back up in `recover`."""
    env = np.ones(n, dtype=np.float32)
    for at, amt in hits:
        i = int(at * SR)
        if i >= n:
            continue
        h = int(hold * SR)
        r = int(recover * SR)
        d = depth * float(np.clip(amt, 0.0, 1.0))
        seg = np.concatenate([np.full(h, 1.0 - d),
                              1.0 - d * (1.0 - np.linspace(0, 1, r) ** 0.45)])
        seg = seg[:max(0, n - i)]
        env[i:i + len(seg)] = np.minimum(env[i:i + len(seg)], seg)
    return env


# ---------------------------------------------------------------------------
# score
# ---------------------------------------------------------------------------
def build_score(F, S):
    """Every sound event, with the data row that caused it. Written to disk so
    the renderer can flash on exactly these frames."""
    ev = []
    photic = ACTS[0]
    spans = {k: v["span_uv"] for k, v in F["erp"].items()}
    gmax = max(spans.values())

    principal = {d["channel"]: d for d in F["discharge_order"]}

    for ch, rec in F["erp"].items():
        pan = CH_PAN.get(ch, 0.0)
        base = CH_DEGREE.get(ch, 7)
        cross = sorted(c["t_ms"] for c in rec["crossings"])

        for p in rec["peaks"]:
            if p["prominence"] < 0.08 * rec["span_uv"]:
                continue
            # Anything before the flash is pre-stimulus baseline. It is real
            # trace and it stays in, but it is not a response and must not
            # sound like one, so it plays at a third of its weight.
            base = p["t_ms"] < 0.0
            vt = video_time(photic, p["t_ms"])
            nxt = next((c for c in cross if c > p["t_ms"]), photic["t1"])
            dur = np.clip(video_time(photic, nxt) - vt, 0.45, 2.6)
            amp = min(1.0, abs(p["uv"]) / gmax)
            is_principal = (principal.get(ch, {}).get("t_ms") == p["t_ms"])
            ev.append(dict(
                kind="principal" if is_principal else "peak",
                t=round(float(vt), 4), dur=round(float(dur), 4),
                channel=ch, t_ms=p["t_ms"], uv=p["uv"],
                polarity=p["polarity"],
                amp=round(float(amp * (0.35 if base else 1.0)), 4),
                baseline=base, degree=CH_DEGREE.get(ch, 7), pan=pan,
                component=next((nm for nm, q in rec["components"].items()
                                if q["t_ms"] == p["t_ms"]), None),
            ))

        for c in rec["crossings"]:
            slope = abs(c["slope_uv_per_ms"])
            base = c["t_ms"] < 0.0
            ev.append(dict(
                kind="flip", t=round(float(video_time(photic, c["t_ms"])), 4),
                channel=ch, t_ms=c["t_ms"], direction=c["direction"],
                slope=slope, pan=pan, baseline=base,
                amp=round(float(min(1.0, slope / 0.09) * (0.35 if base else 1.0)), 4),
            ))

    # The flash itself. Data zero: the instant the checkerboard reverses.
    ev.append(dict(kind="stim", t=round(float(video_time(photic, 0.0)), 4),
                   t_ms=0.0, channel=None, amp=0.7,
                   note="checkerboard reversal, t = 0"))

    rest = ACTS[1]
    t0 = act_start(rest["id"])
    hz = F["raw"][rest["cond"]]["mean_hz"]
    ev.append(dict(kind="gate", t=round(t0, 4), amp=1.0,
                   note="act boundary, hard cut"))
    ev.append(dict(kind="alpha", t=round(t0, 4), dur=rest["dur"], hz=hz,
                   channel=None, amp=0.9,
                   note=f"tremulant rate = measured eyes-closed dominant {hz} Hz"))
    ev.sort(key=lambda e: (e["t"], e["kind"]))
    return ev


# ---------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--features", default="build/video/features.json")
    ap.add_argument("--series", default="build/video/series.json")
    ap.add_argument("--out", default="build/video/track.wav")
    ap.add_argument("--score", default="build/video/score.json")
    args = ap.parse_args()
    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)

    F = json.load(open(args.features))
    S = json.load(open(args.series))
    ev = build_score(F, S)
    json.dump({"schema": "neuro/score/v1", "sr": SR, "seconds": TOTAL,
               "root_hz": ROOT, "scale": "G mixolydian",
               "events": ev}, open(args.score, "w"), indent=1)

    tail = TAIL
    pad, hit, top = Bus(TOTAL + tail), Bus(TOTAL + tail), Bus(TOTAL + tail)
    TH = make_thunder()
    hits = []

    photic, rest = ACTS[0], ACTS[1]

    # -- act 1 pedal. 16' + 8' under the whole photic block, swelling in.
    # Two ranks at slightly different tremulant rates, one to each side. Real
    # ranks never wobble in lockstep, and the difference is what opens the
    # stereo field without any width processing.
    pad.add(organ(degree_hz(0), photic["dur"] - 0.4, gain=0.30, bright=0.55,
                  trem_hz=4.80, trem_depth=0.045, attack=1.6, release=0.9,
                  t_off=0.0, detune=-3.0),
            0.0, pan=-0.35)
    pad.add(organ(degree_hz(0), photic["dur"] - 0.4, gain=0.26, bright=0.55,
                  trem_hz=5.07, trem_depth=0.050, attack=1.9, release=0.9,
                  t_off=0.0, detune=+3.0),
            0.0, pan=+0.35)
    pad.add(organ(degree_hz(7), photic["dur"] - 0.4, gain=0.16, bright=0.5,
                  trem_hz=4.65, trem_depth=0.045, attack=2.4, release=0.9,
                  t_off=0.0, detune=+1.5),
            0.0, pan=+0.15)

    n_peak = n_flip = 0
    for e in ev:
        if e["kind"] in ("peak", "principal"):
            n_peak += 1
            d, amp = e["degree"], e["amp"]
            # polarity chooses the voicing, not the key
            voice = [0, 2, 4, 7] if e["polarity"] > 0 else [0, 3, 6, 7]
            big = e["kind"] == "principal"
            for i, iv in enumerate(voice):
                lvl = (0.34 if big else 0.20) * amp * (0.85 ** i)
                pad.add(organ(degree_hz(d + iv), e["dur"],
                              gain=lvl,
                              bright=0.55 + 0.5 * amp,
                              trem_hz=5.6, trem_depth=0.05 + 0.05 * amp,
                              chiff=0.6 + 0.8 * amp,
                              attack=0.010 if big else 0.020,
                              t_off=e["t"], detune=(-4.0 + 2.7 * i)),
                        e["t"], pan=e["pan"] * 0.7)
            if big:
                # the crack itself: whole strike, sub drop, air, and the pad
                # gets out of the way
                hit.add(chop(TH, 0.0, 2.2, 1.0, 0.88, gate=0.0012),
                        e["t"], pan=e["pan"] * 0.5, haas=4.0)
                hit.add_mono(sub(degree_hz(d) * 0.5, 1.5, gain=0.55 * amp), e["t"])
                top.add(air(0.30, gain=0.30 * amp), e["t"], pan=e["pan"] * 0.9)
                hits.append((e["t"], amp))
        elif e["kind"] == "stim":
            # A flash is not a thunderclap. It is a rise and a swell: air
            # rushing into the chest a beat before the response arrives.
            top.add(air(0.55, gain=0.16, fc=3000.0), e["t"] - 0.02, pan=-0.2)
            top.add(air(0.55, gain=0.16, fc=3800.0), e["t"] - 0.02, pan=+0.2)
            pad.add(organ(degree_hz(4), 1.1, gain=0.13, bright=0.9,
                          trem_hz=6.4, trem_depth=0.08, chiff=1.4,
                          attack=0.006, release=0.5, t_off=e["t"]), e["t"])
            hit.add_mono(sub(degree_hz(0) * 0.5, 0.9, gain=0.22, bend=0.85), e["t"])
        elif e["kind"] == "flip":
            n_flip += 1
            a = e["amp"]
            # steeper reversal -> shorter, higher slice
            dur = float(np.clip(0.34 - 0.22 * a, 0.075, 0.34))
            rate = 0.72 + 1.9 * a
            hit.add(chop(TH, 0.02 + 0.55 * a, dur, rate, rate * 0.82),
                    e["t"], pan=e["pan"] * 0.85 + (0.18 if e["direction"] == "rising" else -0.18),
                    haas=2.5 + 4.0 * a)
            hit.add_mono(sub(degree_hz(CH_DEGREE.get(e["channel"], 7)) * 0.5,
                             0.28, gain=0.18 * a), e["t"])
            top.add(air(0.10, gain=0.10 + 0.16 * a),
                    e["t"], pan=-e["pan"] * 0.6)
            hits.append((e["t"], 0.45 * a))

    # -- the act boundary. Hard cut, one crack, new pedal.
    t0 = act_start(rest["id"])
    hit.add(chop(TH, 0.0, 2.4, 0.86, 0.74, gate=0.0010), t0 - 0.02, pan=0.0, haas=6.0)
    hit.add_mono(sub(degree_hz(0) * 0.5, 1.9, gain=0.60), t0 - 0.02)
    top.add(air(0.42, gain=0.34), t0 - 0.02)
    hits.append((t0 - 0.02, 1.0))

    # -- act 2: the montage as one chord, fluttering at the measured alpha rate
    alpha = F["raw"][rest["cond"]]["mean_hz"]
    st = F["raw"][rest["cond"]]["stats"]
    rejected = set(S["raw"][rest["cond"]].get("rejected", []))
    live = [(k, v) for k, v in st.items() if v and k not in rejected]
    rms_max = max(v["rms"] for _, v in live)
    POS = F["positions"]

    pad.add(organ(degree_hz(0), rest["dur"] - 0.5, gain=0.34, bright=0.5,
                  trem_hz=alpha, trem_depth=0.10, attack=0.35, release=1.0,
                  t_off=t0, detune=-2.0), t0)
    pad.add(organ(degree_hz(6), rest["dur"] - 0.5, gain=0.13, bright=0.5,
                  trem_hz=alpha, trem_depth=0.10, attack=1.2, release=1.0,
                  t_off=t0, detune=+2.0), t0)

    for vi, (name, st_) in enumerate(sorted(live)):
        x, y = POS[name]
        # posterior electrodes low, anterior high; one scale degree per step
        d = int(round((0.85 - y) / 1.70 * 7.0)) + 7
        r = st_["rms"] / rms_max
        onset = t0 + 0.10 + 0.5 * abs(x)
        pad.add(organ(degree_hz(d), rest["dur"] - 0.6,
                      gain=0.16 * r ** 0.8, bright=0.45 + 0.35 * r,
                      trem_hz=alpha, trem_depth=0.16,
                      chiff=0.4, attack=0.5 + 0.6 * abs(x), release=0.9,
                      t_off=onset, detune=(-5.0 + 10.0 * (vi % 7) / 6.0)),
                onset, pan=float(np.clip(x, -1, 1)) * 0.9)

    # alpha pulse in the last third: the flutter made percussive
    pulse_from = t0 + rest["dur"] * 0.55
    k = 0
    tt = pulse_from
    while tt < t0 + rest["dur"] - 0.35:
        a = 0.30 + 0.55 * (tt - pulse_from) / max(1e-6, rest["dur"] * 0.45)
        hit.add(chop(TH, 0.03, 0.09, 1.25 + 0.35 * (k % 3), 1.0),
                tt, pan=0.55 * (-1) ** k, haas=3.5)
        hit.add_mono(sub(degree_hz(0) * 0.5, 0.16, gain=0.22 * a), tt)
        if k % 2 == 0:
            top.add(air(0.07, gain=0.10 * a), tt, pan=-0.4 * (-1) ** k)
        hits.append((tt, 0.35 * a))
        tt += 2.0 / alpha          # every second alpha cycle
        k += 1

    # final hit on the last beat, then let it ring out
    tend = t0 + rest["dur"] - 0.30
    hit.add(chop(TH, 0.0, 1.6, 0.80, 0.70, gate=0.0010), tend, pan=0.0, haas=5.0)
    hit.add_mono(sub(degree_hz(0) * 0.5, 1.4, gain=0.55), tend)
    top.add(air(0.35, gain=0.30), tend)
    hits.append((tend, 1.0))

    # -- master ------------------------------------------------------------
    n = pad.n
    duck = duck_envelope(n, hits)
    L = pad.L * duck + hit.L + top.L
    R = pad.R * duck + hit.R + top.R

    # hard cut at the act boundary: 12 ms of real silence, then the new act.
    g0 = int((t0 - 0.075) * SR)
    g1 = int((t0 - 0.020) * SR)
    if 0 < g0 < g1 < n:
        w = np.linspace(1.0, 0.0, g1 - g0) ** 2.2
        L[g0:g1] *= w
        R[g0:g1] *= w
        L[g1:int(t0 * SR)] = 0.0
        R[g1:int(t0 * SR)] = 0.0

    # Tone. Left alone, a pipe organ plus a thunder body puts four fifths of
    # its energy under 120 Hz, which is exactly the part a phone cannot
    # reproduce -- the mix would arrive as a thin tick. So: infrasonic rumble
    # off, low shelf pulled down, air shelf pushed up.
    def shape(x):
        x = hp(x, 30.0, 3)
        x = x - 0.46 * lp(x, 115.0, 2)      # low shelf, about -5 dB
        x = x + 0.75 * hp(x, 2200.0, 2)     # air shelf, about +5 dB
        x = x + 0.22 * hp(x, 800.0, 2)      # presence, so speech-band detail lands
        return x

    L, R = shape(L), shape(R)

    # Glue. The saturator doubles as the limiter: drive into it, let it round
    # the transients off, take the level back on the way out. A reel gets
    # loudness-normalised on playback, so what matters is that the quiet parts
    # are still there when the loud parts have been pulled down.
    drive = 2.9
    L = np.tanh(drive * L) / np.tanh(drive)
    R = np.tanh(drive * R) / np.tanh(drive)
    peak = max(np.abs(L).max(), np.abs(R).max(), 1e-9)
    g = 0.891 / peak                       # -1 dBFS
    L, R = L * g, R * g

    stereo = np.stack([L, R], axis=1)
    pcm = np.clip(stereo, -1.0, 1.0)
    pcm = (pcm * 32767.0).astype("<i2")
    with wave.open(args.out, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())

    rms = float(np.sqrt((stereo ** 2).mean()))
    print(f"  score: {n_peak} organ notes, {n_flip} polarity-flip chops, "
          f"{len(hits)} ducking hits", file=sys.stderr)
    print(f"  master: peak {20*np.log10(max(np.abs(stereo).max(),1e-9)):.2f} dBFS, "
          f"rms {20*np.log10(max(rms,1e-9)):.2f} dBFS, "
          f"{n/SR:.2f} s", file=sys.stderr)
    print(f"sonify: wrote {args.out} and {args.score}", file=sys.stderr)


if __name__ == "__main__":
    main()
