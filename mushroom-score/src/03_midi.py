#!/usr/bin/env python3
"""
Stage 03 - video analysis -> MIDI.

This is a dedicated, self-contained transform: it reads only work/analysis.npz
and writes a standard MIDI file. No audio is synthesised here. Everything the
music does is decided at this stage, so the score can be opened in any DAW and
the mapping can be argued with.

Mapping
-------
tempo      derived from the footage: the interval between the two maximum
           zoom-ins is treated as one 4-bar phrase, so the camera sets the BPM.

ch 0 LEAD    pitch  = zoom curve quantised to D minor pentatonic (closer = higher)
             vel    = optical-flow magnitude
             CC1    = plant mask share  (how much green is in frame)
             CC74   = mean L* of the frame
ch 1 PAD     one sustained chord per stopping-point segment
             WIDE = Dm (low, open)   MID = Bb (bVI)   TIGHT = Dm (high, arrival)
ch 2 BASS    root of the current stopping point, on bar downbeats
ch 9 DRUMS   cues:   kick + low tom at each maximum zoom-IN
                     crash + snare   at each maximum zoom-OUT
             groove: backbeat on the derived grid, its density tiered by the
                     zoom curve - wide framings get a spare two-and-four, the
                     pushes in get a full sixteenth pattern - with the hats
                     gated by ego-compensated plant motion so the kit thickens
                     with the weeds moving, not with the camera moving.
                     Grid hits within a 1/6-note of a cue are dropped, and the
                     cues sit above the groove in velocity, so the analysis
                     accents stay audible as accents.
"""

import json
import pathlib

import numpy as np
from mido import Message, MetaMessage, MidiFile, MidiTrack, bpm2tempo

ROOT = pathlib.Path(__file__).resolve().parent.parent
WORK = ROOT / "work"
OUT = ROOT / "out"

PPQ = 480

# D minor pentatonic: D F G A C
SCALE = [0, 3, 5, 7, 10]
ROOT_PC = 2                      # D
LEAD_LO, LEAD_HI = 50, 86        # D3 .. D6

# Chord voicings per stopping point (MIDI note numbers).
CHORDS = {
    "WIDE":  [38, 45, 50, 53],   # D2 A2 D3 F3   - Dm, open and low
    "MID":   [46, 53, 58, 62],   # Bb2 F3 Bb3 D4 - bVI, the approach
    "TIGHT": [50, 57, 62, 65],   # D3 A3 D4 F4   - Dm an octave up, arrival
}
BASS_ROOT = {"WIDE": 26, "MID": 34, "TIGHT": 38}   # D1, Bb1, D2

KICK, SNARE, HAT, OPENHAT, CRASH, LOWTOM = 36, 38, 42, 46, 49, 41


def scale_pitches(lo, hi):
    """All pitches of the scale between lo and hi inclusive."""
    return [p for p in range(lo, hi + 1) if (p - ROOT_PC) % 12 in SCALE]


def norm(x):
    lo, hi = np.percentile(x, 2), np.percentile(x, 98)
    return np.clip((x - lo) / max(1e-9, hi - lo), 0.0, 1.0)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    d = np.load(WORK / "analysis.npz")
    meta = json.loads((WORK / "analysis.json").read_text())

    zoom = d["zoom"]
    flow = norm(d["flow_mag"])
    plant_motion = d["plant_motion"]
    plant = d["plant_share"]
    meanL = d["mean_L"]
    stop_idx = d["stop_idx"]
    stop_names = ["TIGHT", "MID", "WIDE"]

    fps = meta["fps"]
    n = len(zoom)
    dur = n / fps

    ins = [e["frame"] for e in meta["zoom_in_extrema"]]
    outs = [e["frame"] for e in meta["zoom_out_extrema"]]

    # --- tempo from the footage ------------------------------------------
    # The camera pushes in twice; the gap between those two arrivals is one
    # 4-bar phrase, which makes the BPM a measurement rather than a taste call.
    if len(ins) >= 2:
        phrase_s = (ins[-1] - ins[0]) / fps / (len(ins) - 1)
        bpm = 60.0 * 16.0 / phrase_s          # 16 beats per phrase
        while bpm > 168:
            bpm /= 2.0
        while bpm < 84:
            bpm *= 2.0
    else:
        bpm = 120.0
    spb = 60.0 / bpm                            # seconds per beat
    print(f"derived tempo: {bpm:.2f} BPM  (phrase = {phrase_s:.3f} s)"
          if len(ins) >= 2 else f"tempo {bpm}")

    def t2tick(t):
        return int(round(t / spb * PPQ))

    def f2tick(fr):
        return t2tick(fr / fps)

    def at(fr_float):
        """Sample the analysis arrays at a (possibly fractional) frame index."""
        i = int(np.clip(round(fr_float), 0, n - 1))
        return i

    events = []          # (tick, track, Message) collected then sorted per track
    log = []             # human-readable event list

    # --- ch 9 drums: the zoom extrema -------------------------------------
    for fr in ins:
        tk = f2tick(fr)
        events.append((tk, "drums", Message("note_on", channel=9, note=KICK, velocity=127)))
        events.append((tk + PPQ // 4, "drums", Message("note_off", channel=9, note=KICK, velocity=0)))
        events.append((tk, "drums", Message("note_on", channel=9, note=LOWTOM, velocity=104)))
        events.append((tk + PPQ // 2, "drums", Message("note_off", channel=9, note=LOWTOM, velocity=0)))
        log.append({"t": round(fr / fps, 3), "frame": int(fr), "event": "DRUM max-zoom-IN",
                    "detail": "kick 36 + low tom 41"})
    for fr in outs:
        tk = f2tick(fr)
        events.append((tk, "drums", Message("note_on", channel=9, note=CRASH, velocity=118)))
        events.append((tk + PPQ, "drums", Message("note_off", channel=9, note=CRASH, velocity=0)))
        events.append((tk, "drums", Message("note_on", channel=9, note=SNARE, velocity=112)))
        events.append((tk + PPQ // 4, "drums", Message("note_off", channel=9, note=SNARE, velocity=0)))
        log.append({"t": round(fr / fps, 3), "frame": int(fr), "event": "DRUM max-zoom-OUT",
                    "detail": "crash 49 + snare 38"})

    # --- ch 9 drums: the groove -------------------------------------------
    # A backbeat on the derived grid, with its density driven by the zoom curve:
    # wide framings get a spare two-and-four, the pushes in get a full sixteenth
    # pattern. The kit therefore builds and releases with the camera's arches
    # rather than running flat underneath them.
    KICK_BY_TIER = {0: [0, 8], 1: [0, 8, 11], 2: [0, 6, 8, 11, 14]}
    SNARE_STEPS = [4, 12]
    GHOST_BY_TIER = {0: [], 1: [15], 2: [7, 15]}
    OPENHAT_BY_TIER = {0: [], 1: [], 2: [14]}
    ACCENT_STEPS = {0, 4, 8, 12}

    sixteenth = spb / 4.0
    guard = PPQ // 6            # keep the grid off the top of a cue hit
    cue_kick_ticks = [f2tick(fr) for fr in ins]
    cue_snare_ticks = [f2tick(fr) for fr in outs]
    pm = norm(plant_motion)

    def clashes(tk, ticks):
        return any(abs(tk - c) < guard for c in ticks)

    def hit(tk, note, vel, length=PPQ // 8):
        events.append((tk, "drums", Message("note_on", channel=9, note=note,
                                            velocity=int(np.clip(vel, 1, 127)))))
        events.append((tk + length, "drums",
                       Message("note_off", channel=9, note=note, velocity=0)))

    n_steps = int(np.ceil(dur / sixteenth))
    groove_counts = {"kick": 0, "snare": 0, "ghost": 0, "hat": 0, "open": 0}
    for s in range(n_steps):
        t = s * sixteenth
        if t >= dur:
            break
        i = at(t * fps)
        z = float(zoom[i])
        tier = 2 if z > 0.62 else (1 if z > 0.28 else 0)
        st = s % 16
        tk = t2tick(t)

        if st in KICK_BY_TIER[tier] and not clashes(tk, cue_kick_ticks):
            hit(tk, KICK, 106 + 16 * z, PPQ // 4)
            groove_counts["kick"] += 1
        if st in SNARE_STEPS and not clashes(tk, cue_snare_ticks):
            hit(tk, SNARE, 98 + 16 * z, PPQ // 5)
            groove_counts["snare"] += 1
        if st in GHOST_BY_TIER[tier]:
            hit(tk, SNARE, 34 + 14 * z, PPQ // 12)
            groove_counts["ghost"] += 1

        # Hats ride the plant motion, not the global flow: the weeds moving is
        # what should thicken the kit, and camera motion already has the cues.
        hat_here = (st % 2 == 0) if tier == 0 else True
        if hat_here:
            if st in OPENHAT_BY_TIER[tier]:
                hit(tk, OPENHAT, 76 + 34 * pm[i], PPQ // 4)
                groove_counts["open"] += 1
            else:
                v = 42 + 44 * pm[i] + (20 if st in ACCENT_STEPS else 0)
                hit(tk, HAT, v, PPQ // 12)
                groove_counts["hat"] += 1

    # --- ch 0 lead: the zoom curve as pitch --------------------------------
    pitches = scale_pitches(LEAD_LO, LEAD_HI)
    step = spb / 2.0                 # the lead re-evaluates on the 1/8 grid
    cur_pitch, cur_start = None, 0.0
    t = 0.0
    lead_notes = 0
    while t < dur:
        i = at(t * fps)
        # Closer = higher. The curve is already normalised 0..1 over the clip.
        p = pitches[int(np.clip(round(zoom[i] * (len(pitches) - 1)), 0, len(pitches) - 1))]
        if p != cur_pitch:
            if cur_pitch is not None:
                events.append((t2tick(cur_start), "lead",
                               Message("note_on", channel=0, note=cur_pitch,
                                       velocity=int(np.clip(52 + 62 * flow[at(cur_start * fps)], 40, 118)))))
                events.append((t2tick(t), "lead",
                               Message("note_off", channel=0, note=cur_pitch, velocity=0)))
                lead_notes += 1
            cur_pitch, cur_start = p, t
        t += step
    if cur_pitch is not None:
        events.append((t2tick(cur_start), "lead",
                       Message("note_on", channel=0, note=cur_pitch,
                               velocity=int(np.clip(52 + 62 * flow[at(cur_start * fps)], 40, 118)))))
        events.append((t2tick(dur), "lead",
                       Message("note_off", channel=0, note=cur_pitch, velocity=0)))
        lead_notes += 1

    # Continuous controllers, at 1/16 resolution.
    t = 0.0
    while t < dur:
        i = at(t * fps)
        tk = t2tick(t)
        events.append((tk, "lead", Message("control_change", channel=0, control=1,
                                           value=int(np.clip(plant[i] / 0.25 * 127, 0, 127)))))
        events.append((tk, "lead", Message("control_change", channel=0, control=74,
                                           value=int(np.clip((meanL[i] - 30) / 45 * 127, 0, 127)))))
        t += spb / 4.0

    # --- ch 1 pad + ch 2 bass: one gesture per stopping-point segment -------
    segs = []
    run = 0
    for i in range(1, n + 1):
        if i == n or stop_idx[i] != stop_idx[run]:
            if i - run >= int(0.4 * fps):
                segs.append((stop_names[stop_idx[run]], run, i - 1))
            run = i

    # Each chord rings PAD_TAIL past the end of its section, so consecutive
    # chords overlap and the pad crossfades instead of cutting. Stage 04 gives
    # the pad a slow attack, so the incoming chord fades up through the tail of
    # the outgoing one.
    PAD_TAIL = 0.45
    for name, a, b in segs:
        t0, t1 = a / fps, (b + 1) / fps
        tk0, tk1 = t2tick(t0), t2tick(t1 + PAD_TAIL)
        for note in CHORDS[name]:
            events.append((tk0, "pad", Message("note_on", channel=1, note=note, velocity=62)))
            events.append((tk1, "pad", Message("note_off", channel=1, note=note, velocity=0)))
        # Bass on each bar downbeat inside the segment.
        bar = spb * 4.0
        bt = np.ceil(t0 / bar) * bar
        if bt >= t1:
            bt = t0
        while bt < t1:
            events.append((t2tick(bt), "bass",
                           Message("note_on", channel=2, note=BASS_ROOT[name], velocity=92)))
            events.append((t2tick(min(bt + bar * 0.92, t1)), "bass",
                           Message("note_off", channel=2, note=BASS_ROOT[name], velocity=0)))
            bt += bar
        log.append({"t": round(t0, 3), "frame": int(a), "event": f"SECTION {name}",
                    "detail": f"pad {CHORDS[name]}, bass {BASS_ROOT[name]}, "
                              f"through {round(t1, 3)}s"})

    # --- assemble the file -------------------------------------------------
    mid = MidiFile(ticks_per_beat=PPQ)
    conductor = MidiTrack()
    conductor.append(MetaMessage("track_name", name="mushroom score / conductor", time=0))
    conductor.append(MetaMessage("set_tempo", tempo=bpm2tempo(bpm), time=0))
    conductor.append(MetaMessage("time_signature", numerator=4, denominator=4, time=0))
    mid.tracks.append(conductor)

    voices = [
        ("lead", "LEAD zoom->pitch", 0, 81),    # saw lead
        ("pad", "PAD stop-point chords", 1, 89),  # warm pad
        ("bass", "BASS stop-point root", 2, 39),  # synth bass
        ("drums", "DRUMS zoom extrema", 9, None),
    ]
    for key, tname, ch, prog in voices:
        tr = MidiTrack()
        tr.append(MetaMessage("track_name", name=tname, time=0))
        if prog is not None:
            tr.append(Message("program_change", channel=ch, program=prog, time=0))
        evs = sorted([e for e in events if e[1] == key], key=lambda e: e[0])
        last = 0
        for tk, _, msg in evs:
            msg = msg.copy(time=max(0, tk - last))
            tr.append(msg)
            last = tk
        mid.tracks.append(tr)

    mid_path = OUT / "mushroom_score.mid"
    mid.save(str(mid_path))

    log.sort(key=lambda e: e["t"])
    (WORK / "midi_events.json").write_text(json.dumps({
        "bpm": round(bpm, 3),
        "ticks_per_beat": PPQ,
        "seconds_per_beat": round(spb, 5),
        "bar_seconds": round(spb * 4, 5),
        "duration_s": round(dur, 3),
        "lead_notes": lead_notes,
        "scale": "D minor pentatonic (D F G A C)",
        "chords": CHORDS,
        "cues": log,
    }, indent=2) + "\n")

    print(f"tracks: {len(mid.tracks)}  lead notes: {lead_notes}  "
          f"sections: {len(segs)}  drum cues: {len(ins) + len(outs)}")
    print("  groove: " + "  ".join(f"{k}={v}" for k, v in groove_counts.items()))
    print("wrote", mid_path)
    print("wrote", WORK / "midi_events.json")


if __name__ == "__main__":
    main()
