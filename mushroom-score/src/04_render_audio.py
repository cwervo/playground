#!/usr/bin/env python3
"""
Stage 04 - MIDI -> audio.

Reads out/mushroom_score.mid and nothing else. The MIDI file is the source of
truth for the music: if you edit it in a DAW and re-run this stage, the track
changes accordingly.

The synth is written out in numpy rather than pulled from a soundfont so the
timbres can be tied to the piece - oscillators are additive and band-limited,
the lead filter tracks CC74 (which stage 03 mapped from frame lightness L*),
and CC1 (plant mask share) opens a chorus depth, so the green in the frame is
audible as widening.
"""

import pathlib

import numpy as np
from mido import MidiFile
from scipy.signal import butter, lfilter, lfilter_zi, fftconvolve

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "out"
SR = 48000
BLOCK = 512


# ------------------------------------------------------------- oscillators --

def band_limited(freq, t, kind):
    """
    Additive oscillator, harmonics summed only up to Nyquist so nothing folds
    back as aliasing.
    """
    nyq = SR / 2.0
    kmax = int(max(1, min(64, nyq / max(freq, 1e-6) - 1)))
    out = np.zeros_like(t)
    if kind == "saw":
        for k in range(1, kmax + 1):
            out += np.sin(2 * np.pi * freq * k * t) / k
        out *= 2.0 / np.pi
    elif kind == "square":
        for k in range(1, kmax + 1, 2):
            out += np.sin(2 * np.pi * freq * k * t) / k
        out *= 4.0 / np.pi
    elif kind == "tri":
        for j, k in enumerate(range(1, kmax + 1, 2)):
            out += ((-1) ** j) * np.sin(2 * np.pi * freq * k * t) / (k * k)
        out *= 8.0 / (np.pi ** 2)
    else:  # sine
        out = np.sin(2 * np.pi * freq * t)
    return out


def adsr(n, a, d, s, r):
    """Sample-accurate ADSR over n samples; release happens inside n."""
    a_n = max(1, int(a * SR))
    d_n = max(1, int(d * SR))
    r_n = max(1, int(r * SR))
    sus_n = max(0, n - a_n - d_n - r_n)
    env = np.concatenate([
        np.linspace(0, 1, a_n, endpoint=False),
        np.linspace(1, s, d_n, endpoint=False),
        np.full(sus_n, s),
        np.linspace(s, 0, r_n),
    ])
    if len(env) < n:
        env = np.pad(env, (0, n - len(env)))
    return env[:n]


def m2f(note):
    return 440.0 * 2 ** ((note - 69) / 12.0)


def time_varying_lp(x, cutoff_curve, q_order=2):
    """
    Block-wise Butterworth lowpass whose cutoff follows `cutoff_curve` (one
    value per sample, Hz). Filter state carries across blocks so there are no
    clicks at block boundaries.
    """
    y = np.zeros_like(x)
    zi = None
    for s in range(0, len(x), BLOCK):
        e = min(len(x), s + BLOCK)
        fc = float(np.clip(np.mean(cutoff_curve[s:e]), 80.0, SR * 0.45))
        b, a = butter(q_order, fc / (SR / 2.0), btype="low")
        if zi is None:
            zi = lfilter_zi(b, a) * x[s]
        y[s:e], zi = lfilter(b, a, x[s:e], zi=zi)
    return y


# ------------------------------------------------------------------ drums ---

def drum(kind, dur=1.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    rng = np.random.default_rng({"kick": 1, "snare": 2, "hat": 3,
                                 "crash": 4, "tom": 5}[kind])
    if kind == "kick":
        f = 105 * np.exp(-t * 34) + 44
        env = np.exp(-t * 9.5)
        x = np.sin(2 * np.pi * np.cumsum(f) / SR) * env
        x += rng.normal(0, 1, n) * np.exp(-t * 190) * 0.35   # beater click
    elif kind == "tom":
        f = 180 * np.exp(-t * 16) + 92
        x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 7.5)
    elif kind == "snare":
        noise = rng.normal(0, 1, n)
        b, a = butter(2, [900 / (SR / 2), 7200 / (SR / 2)], btype="band")
        x = lfilter(b, a, noise) * np.exp(-t * 16)
        x += np.sin(2 * np.pi * 190 * t) * np.exp(-t * 24) * 0.5
    elif kind == "hat":
        noise = rng.normal(0, 1, n)
        b, a = butter(4, 7000 / (SR / 2), btype="high")
        x = lfilter(b, a, noise) * np.exp(-t * 62)
    else:  # crash
        noise = rng.normal(0, 1, n)
        b, a = butter(2, 2600 / (SR / 2), btype="high")
        x = lfilter(b, a, noise) * (np.exp(-t * 2.4) * 0.85 + np.exp(-t * 0.7) * 0.15)
    return x / (np.max(np.abs(x)) + 1e-9)


DRUM_MAP = {36: ("kick", 0.9, 1.0), 41: ("tom", 0.8, 0.72),
            38: ("snare", 0.5, 0.72), 42: ("hat", 0.14, 0.34),
            49: ("crash", 2.2, 0.62)}


# ---------------------------------------------------------------- reverb ----

def reverb_ir(tau=1.05, length=1.6, seed=7):
    n = int(length * SR)
    t = np.arange(n) / SR
    rng = np.random.default_rng(seed)
    ir = rng.normal(0, 1, n) * np.exp(-t / tau)
    b, a = butter(2, 5200 / (SR / 2), btype="low")
    ir = lfilter(b, a, ir)
    ir[: int(0.006 * SR)] = 0.0            # small pre-delay
    return ir / (np.sqrt(np.sum(ir ** 2)) + 1e-9)


# ------------------------------------------------------------------ main ----

def main():
    mid = MidiFile(str(OUT / "mushroom_score.mid"))

    # Flatten to absolute-time events. mido yields real-time deltas already
    # tempo-scaled, so this respects the tempo written in stage 03.
    notes = []       # (ch, note, vel, t_on, t_off)
    ccs = {1: [], 74: []}
    pending = {}
    t = 0.0
    for msg in mid:
        t += msg.time
        if msg.type == "note_on" and msg.velocity > 0:
            pending.setdefault((msg.channel, msg.note), []).append((t, msg.velocity))
        elif msg.type in ("note_off",) or (msg.type == "note_on" and msg.velocity == 0):
            key = (msg.channel, msg.note)
            if pending.get(key):
                t0, v = pending[key].pop(0)
                notes.append((msg.channel, msg.note, v, t0, t))
        elif msg.type == "control_change" and msg.control in ccs:
            ccs[msg.control].append((t, msg.value))
    total = max([e[4] for e in notes] + [t]) + 2.0
    n_tot = int(total * SR) + 1
    print(f"midi: {len(notes)} notes, {total:.2f}s -> {n_tot} samples")

    # CC curves resampled to audio rate.
    tt = np.arange(n_tot) / SR
    def cc_curve(num, default):
        pts = ccs.get(num) or []
        if not pts:
            return np.full(n_tot, default, dtype=np.float64)
        xs = np.array([p[0] for p in pts])
        ys = np.array([p[1] for p in pts], dtype=np.float64)
        return np.interp(tt, xs, ys)

    cc74 = cc_curve(74, 64.0)      # frame lightness -> lead cutoff
    cc1 = cc_curve(1, 0.0)         # plant share    -> chorus depth

    lead = np.zeros(n_tot)
    pad = np.zeros(n_tot)
    bass = np.zeros(n_tot)
    drums = np.zeros(n_tot)

    for ch, note, vel, t0, t1 in notes:
        s = int(t0 * SR)
        dur = max(0.02, t1 - t0)
        amp = (vel / 127.0) ** 1.4

        if ch == 9:
            if note not in DRUM_MAP:
                continue
            kind, dlen, gain = DRUM_MAP[note]
            x = drum(kind, dlen) * amp * gain
            e = min(n_tot, s + len(x))
            drums[s:e] += x[: e - s]
            continue

        n = int(dur * SR)
        if n < 8:
            continue
        tl = np.arange(n) / SR
        f = m2f(note)

        if ch == 0:      # LEAD - detuned saw pair
            x = (band_limited(f * 0.997, tl, "saw")
                 + band_limited(f * 1.003, tl, "saw")) * 0.5
            x *= adsr(n, 0.012, 0.09, 0.78, min(0.18, dur * 0.4))
            lead[s:min(n_tot, s + n)] += (x * amp * 0.55)[: max(0, min(n_tot, s + n) - s)]
        elif ch == 1:    # PAD - soft triangle stack, slow attack
            x = (band_limited(f, tl, "tri")
                 + 0.5 * band_limited(f * 2.0, tl, "sine")
                 + 0.34 * band_limited(f * 0.5, tl, "tri"))
            x *= adsr(n, min(0.55, dur * 0.35), 0.3, 0.72, min(0.7, dur * 0.35))
            pad[s:min(n_tot, s + n)] += (x * amp * 0.20)[: max(0, min(n_tot, s + n) - s)]
        elif ch == 2:    # BASS - sine plus a touch of square, saturated
            x = band_limited(f, tl, "sine") + 0.22 * band_limited(f, tl, "square")
            x = np.tanh(x * 1.5)
            x *= adsr(n, 0.008, 0.16, 0.6, min(0.3, dur * 0.4))
            bass[s:min(n_tot, s + n)] += (x * amp * 0.42)[: max(0, min(n_tot, s + n) - s)]

    # Lead filter follows CC74; the mapping is L* -> brightness, literally.
    cutoff = 420.0 + (cc74 / 127.0) ** 1.5 * 6200.0
    lead = time_varying_lp(lead, cutoff)

    # Chorus on the lead, depth from CC1 (how much green is in frame).
    depth = np.clip(cc1 / 127.0, 0, 1)
    lfo = np.sin(2 * np.pi * 0.27 * tt)
    delay = (0.004 + 0.0035 * depth * (0.5 + 0.5 * lfo)) * SR
    idx = np.clip(np.arange(n_tot) - delay, 0, n_tot - 1)
    i0 = idx.astype(int)
    frac = idx - i0
    i1 = np.clip(i0 + 1, 0, n_tot - 1)
    lead_ch = lead[i0] * (1 - frac) + lead[i1] * frac

    # Stereo placement, then a shared plate.
    ir = reverb_ir()
    left = 0.62 * lead + 0.38 * lead_ch + pad * 0.9 + bass + drums * 0.95
    right = 0.38 * lead + 0.62 * lead_ch + pad * 1.0 + bass + drums * 0.95

    wetL = fftconvolve(left, ir)[:n_tot]
    wetR = fftconvolve(right, ir)[:n_tot]
    left = left * 0.82 + wetL * 0.30
    right = right * 0.82 + wetR * 0.30

    # Master: DC-blocking high-pass, soft clip, normalise to -1 dBFS.
    b, a = butter(2, 28 / (SR / 2), btype="high")
    left, right = lfilter(b, a, left), lfilter(b, a, right)
    peak = max(np.max(np.abs(left)), np.max(np.abs(right)), 1e-9)
    left, right = left / peak * 1.15, right / peak * 1.15
    left, right = np.tanh(left), np.tanh(right)
    peak = max(np.max(np.abs(left)), np.max(np.abs(right)), 1e-9)
    g = 10 ** (-1.0 / 20.0) / peak
    stereo = np.stack([left * g, right * g], axis=1)

    pcm = (np.clip(stereo, -1, 1) * 32767).astype("<i2")
    wav = OUT / "mushroom_track.wav"
    write_wav(wav, pcm, SR)
    rms = float(np.sqrt(np.mean(stereo ** 2)))
    print(f"wrote {wav}  ({stereo.shape[0] / SR:.2f}s, peak "
          f"{20 * np.log10(np.max(np.abs(stereo))):.2f} dBFS, "
          f"rms {20 * np.log10(rms):.2f} dBFS)")


def write_wav(path, pcm_i16, sr):
    import struct
    n_frames, n_ch = pcm_i16.shape
    data = pcm_i16.tobytes()
    byte_rate = sr * n_ch * 2
    hdr = b"RIFF" + struct.pack("<I", 36 + len(data)) + b"WAVEfmt "
    hdr += struct.pack("<IHHIIHH", 16, 1, n_ch, sr, byte_rate, n_ch * 2, 16)
    hdr += b"data" + struct.pack("<I", len(data))
    path.write_bytes(hdr + data)


if __name__ == "__main__":
    main()
