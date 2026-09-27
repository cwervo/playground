#!/usr/bin/env python3
"""Synthesize assets/pop.wav: a short bubble-style "pop".

A sine whose pitch drops quickly (like a bubble bursting) with a fast
exponential decay, plus a tiny burst of noise at the start for the "click".
Standard library only, so it runs anywhere: `python3 tool/make_pop.py`.
"""
import math
import random
import struct
import wave
from pathlib import Path

RATE = 44100
DURATION = 0.12
START_HZ, END_HZ = 1100.0, 180.0

random.seed(7)
n = int(RATE * DURATION)
samples = []
phase = 0.0
for i in range(n):
    t = i / RATE
    freq = END_HZ + (START_HZ - END_HZ) * math.exp(-t * 45)
    phase += 2 * math.pi * freq / RATE
    env = math.exp(-t * 38) * min(1.0, t * 2000)
    click = (random.random() * 2 - 1) * math.exp(-t * 900) * 0.35
    samples.append(0.8 * env * math.sin(phase) + click)

out = Path(__file__).resolve().parent.parent / "assets" / "pop.wav"
with wave.open(str(out), "wb") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(RATE)
    w.writeframes(b"".join(
        struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in samples))
print(f"wrote {out} ({n} samples)")
