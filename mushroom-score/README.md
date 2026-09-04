# Mushroom Score

A visual score and a mini track made from 16.95 seconds of a white mushroom growing
at the base of a street tree in Queens, NY.

Three photographs of the same mushroom — tight, mid, wide — are the score's
**stopping points.** Each is reduced to a pair of CIELAB anchors: the white of the
cap, the green of the weeds. Every frame of the video is then matched against those
anchors with ΔE₀₀, the cap is tracked, the plants' motion is sampled as a vector
field, and the camera's own zoom becomes the melody.

The music is not scored to the video. The video *is* the score.

| output | file |
|---|---|
| video (muxed) | `out/mushroom_visual_score.mp4` — 720×1280, 16.95 s |
| image sequence | `out/score_seq/` — 40 score frames, 540×960 |
| cue + stop plates | `out/plates/` — the 5 drum cues and 3 stopping points, full res |
| mini track | `out/mushroom_track.m4a` (and `.wav` master) |
| MIDI | `out/mushroom_score.mid` — 5 tracks, 133.20 BPM |
| post artifact | `out/mushroom_score_post_4x5.png`, `out/mushroom_score_cover_9x16.png` |
| timing | [`TIMING.md`](TIMING.md) — cue table, sections, sync notes |
| caption copy | [`POST.md`](POST.md) |
| published page | `out/post_kit.html` |

## Pipeline

Each stage writes a file the next stage reads; every stage is re-runnable alone.

```
src/01_anchors.py        3 photos      -> work/anchors.json          CIELAB anchors
src/02_analyse.py        508 frames    -> work/analysis.{npz,json}   masks, track, flow, zoom
src/03_midi.py           analysis      -> out/mushroom_score.mid     THE TRANSFORM
src/04_render_audio.py   the .mid      -> out/mushroom_track.wav     synthesis
src/05_render_score.py   analysis+wav  -> out/mushroom_visual_score.mp4
src/06_poster.py         score frames  -> out/*_post_4x5.png, *_cover_9x16.png
src/07_docs.py           analysis+midi -> TIMING.md
src/08_post_kit.py       analysis+out  -> out/post_kit.html   the published page
```

```bash
pip install numpy opencv-python-headless pillow scipy imageio-ffmpeg mido
ffmpeg -i assets/source_IMG_5823.mov -vf scale=720:1280 -q:v 2 work/frames/f_%04d.jpg
for s in src/0*.py; do python3 "$s"; done
```

The MIDI file is a real intermediate, not a formality. Stage 03 makes every musical
decision and writes a standard `.mid`; stage 04 reads only that file. Open the MIDI
in a DAW, change it, re-run stage 04, and the track changes — the synth has no
private knowledge of the video.

---

## Process notes

### The photographs are the colour space, not just references

The three plates are not mood board. Each one is reduced to two anchors — the median
Lab of the cap, the median Lab of the weeds — and the consensus anchors (per-channel
median across the three) are what every video frame is measured against:

| | L\* | a\* | b\* |
|---|---:|---:|---:|
| mushroom | 95.02 | −1.22 | +4.22 |
| plant | 43.57 | −15.63 | +24.13 |

Distance is **CIEDE2000**, implemented in full including the hue-rotation term, not
Euclidean CIE76. If the premise is that perceived colour drives the piece, the metric
has to be the perceptual one.

### The hardest problem was a sidewalk slab

In the wide framings the cap is about 0.05 % of the picture. A sunlit sidewalk slab
is brighter, bigger, near-neutral, convex, and beats the mushroom on every static
cue you can think of. Three attempts failed:

1. **Largest bright, low-chroma blob** — picked the sidewalk.
2. **Cap-shaped blob** (roundness × box-fill) — still picked the sidewalk; a concrete
   slab is also a filled convex quadrilateral.
3. **Bright-against-a-dark-surround** — nearly worked, then failed for a subtle
   reason: I sized the comparison ring proportionally to the blob, so the huge
   sidewalk got a ring 68 px wide that reached out into dark road and soil and
   scored *higher* contrast than the mushroom.

What actually works is temporal. Frame-local scoring is thrown away; instead the
track is **seeded** on the frame where the cap is unambiguous — deep in a tight
framing, where it fills half the picture — and propagated outward in both directions,
each step preferring the candidate that continues the current position *and* scale.
Jumping cap → sidewalk means a large positional leap and a hundred-fold area jump,
and continuity rejects it. The cap is then held on all 508 frames.

The check that this is right: apparent cap scale and the radial divergence of the
optical-flow field are two completely independent estimates of the same zoom, and
after the fix they correlate at **r = +0.855** (before it, +0.59).

### The camera sets the tempo

The clip pushes in to maximum zoom twice, 7.207 s apart. Treating that as one
four-bar phrase gives **133.20 BPM** — measured, not chosen. It falls out neatly:
the two zoom-in cues land at bar 4.4.373 and 8.4.373, exactly four bars apart.

Finding those two peaks took a second fix. My first peak-finder measured prominence
over a fixed ±27-frame window, and the camera *holds* at maximum zoom for over a
second — so the first peak's locally-measured prominence was 0.04 and it was
discarded. Replacing that with true topographic prominence (descend from the peak
until the signal rises above it again) recovers both arches.

### The vector field had to be ego-motion compensated

Drawn from raw optical flow, the magenta field is beautiful and meaningless: during
a whip-zoom it is a full-frame starburst of camera motion, and it buries the picture.
Subtracting each frame's median flow vector — a robust estimate of global camera
motion — leaves the plants moving relative to the shot, which is what the field
claims to show, and it stops fighting the footage.

One smaller lesson: confidence was originally encoded by scaling the magenta toward
black, which is not transparency — it just produces dark purple that vanishes into
bark. Magenta now stays magenta and confidence is carried by line weight.

### Palette

Four colours, each with one job, held identically across video, plates and posters:
**navy** is the mushroom (detector frame, brackets, crosshair, zoom curve),
**magenta** is plant motion (the vector field), **amber** is a drum cue and nothing
else, and paper-white is score furniture. The navy frame carries a near-black
underlay and a one-pixel bright core so it survives against dark bark without
becoming a different colour.

### The pad lurch was the chord cut, not classifier flicker

I assumed the harmony lurched because the stop classifier flickered between MID
and TIGHT during a fast push, and added hysteresis — a challenger must be 12 %
closer and stay closer for 0.20 s before the state moves. Then I counted: **8 raw
transitions, 8 after hysteresis.** There was no flicker to remove. The classifier
was already stable, and my diagnosis had been a guess.

What actually lurched was the pad *cutting*: each chord ended hard at its section
boundary and the next began from silence. The fix is the overlap — every chord now
rings 0.45 s past its section, and because the pad has a slow attack the incoming
chord fades up through the outgoing one's tail.

The hysteresis stays as a cheap guard for re-runs on other footage, and it is not
inert: it delays each transition by up to six frames, which is visible in the
score's stop ribbon and shifts every section boundary about 0.2 s later.

### Making the beat punchier

The first cut had only the five cue hits and a flow-gated hat, so it was flat
between the arches. Two changes:

**Notes.** A backbeat on the derived grid, with density tiered by the zoom curve —
under 0.28 a spare two-and-four, above 0.62 the full sixteenth pattern with ghost
snares and an open hat. So the kit builds and releases with the camera. Grid hits
within a 1/6-note of a cue are dropped and the cues sit above the groove in
velocity, so the analysis accents stay accents rather than dissolving into the
pattern. The hats now ride the ego-compensated plant motion, which is the fix
for the hi-hat problem noted here before — the weeds thicken the kit, the camera
doesn't.

**Mix.** Punch is mostly mix, not notes. Every kick ducks pad, lead and bass
through a short sidechain dip; the kit gets its own bus compressor; the plate is
fed from the tuned voices only, so reverb never smears the transients. Net:
RMS −16.2 → **−13.8 dBFS** with a **12.8 dB** crest factor, so it got louder and
denser without being flattened.

### What I would do next

The lead still re-evaluates on every 1/8 whether or not the zoom has moved, which
gives it a slightly mechanical tick under the new kit; gating it on zoom velocity
would let it hold through the plateaus. The groove tiers are also hard-thresholded,
so a zoom hovering near 0.62 can toggle the pattern between bars — the same
hysteresis idea would apply, and this time there is a real flicker to fix.

---

Source: `IMG_5823.mov`, iPhone 16 Pro, 2026-09-04, 40.7184 N 73.9496 W.
