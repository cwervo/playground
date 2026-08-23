# neuro

Five scanned clinical documents from one afternoon, turned into one bytecode
that a browser, a Tk window, a pen plotter and a 3D printer all execute without
any of them re-deriving a number.

```
make                    # engine, display file, dashboard, print, plotter, card, STL
make video              # the 9:16 reel of the photic block, with its sonification
open build/dashboard.html
```

**Not a diagnosis, not medical advice.** This is decision support for a
conversation with a clinician, and a worked example of what a multimodal
physiological battery does and does not license you to say.

---

## The dataset

One clinic visit, 2026-08-18, five instruments, 19 scanned pages with no text
layer:

- **Evoke Comprehensive Report** (13 pp) — resting qEEG both conditions, ERPs,
  HRV, neuropsychological screener, ADHD decision engine
- **Evoke Summary Report** (1 p)
- **Firefly Brain Insights Report** (3 pp) — regional EEG z-scores, PHQ-9,
  GAD-7, PCL-C
- **12-lead ECG** (1 p) — machine-read, unconfirmed
- **Allergy skin-prick panel** (1 p) — 60 sites, handwritten, faxed

61 measured metrics, 58 non-control allergen sites, and one page order that
arrived shuffled. See [`data/PROVENANCE.md`](data/PROVENANCE.md) for what was
read from where and how confident each reading is.

---

## What it found

The battery was ordered to look for ADHD and did not find it — the vendor's own
screen came back negative at 90% confidence. An independent scoring pass here,
against six well-cited ADHD relationships, lands in the same place at p = 0.17.

Four other stories score better. 200 000 permutations, seed 20260818:

| | Hypothesis | C | p |
|---|---|---|---|
| **H3** | Mood driving the complaint | **+0.740** | < 0.0001 |
| **H1** | Sympathetic over-arousal | **+0.573** | 0.0002 |
| **H4** | Allergic / inflammatory load | **+0.528** | 0.0044 |
| **H2** | Timing slowed, capacity intact | **+0.401** | 0.0063 |
| H5 | Classic ADHD electrophysiology | +0.120 | 0.1735 |

Four findings that came out of re-deriving rather than re-reading:

- **The P3b/P3a amplitude ratio is 0.382 against a floor of 0.50** that the
  report states in prose on the ERP page and never computes. Novelty grabs
  attention hard; the follow-through that consolidates it is quiet. That
  describes the presenting complaint better than the theta:beta ratio which got
  flagged instead.
- **Three of the vendor's flags are hairline.** Theta:beta is 4% over its
  threshold, peak alpha frequency 0.9% over, P3a latency 4% over — against
  anxiety at +225%, depression at +200% and allergen burden at +199%. And the
  theta:beta threshold comes from normative tables the report itself says do not
  extend past age 31, on a subject aged 31 years 2 months.
- **The three evoked components arrive in the wrong order.** Digitising the
  printed curves back into numbers puts the principal deflections at O2 287 ms,
  Pz 387 ms, Cz 464 ms — N100, then the parietal P3b, then the frontocentral
  P3a. Textbook order puts P3a first. It is the same dissociation the 0.382
  ratio describes, arriving by an independent route, and it is visible in the
  figures and stated nowhere in the text.
- **The heart-rate variability total is fine and its distribution is not.**
  SDNN 82 ms and total power 2324 ms² both score normal, while VLF/LF is 1.173
  against a 0.5 threshold and HF is 11.1% of total power against a 15% floor. No
  single-number HRV summary can see that.

Full reasoning in two registers: [plain language](docs/01-plain-language.md) and
[full fat](docs/02-full-fat.md), section for section.

---

## How it is built

```
data/session-2026-08-18.json   transcribed source of truth, with per-value confidence
data/prior-graph.json          32 literature edges from the reports' own citations

src/analyze.cpp                the entire numeric pass, run exactly once
src/stats.hpp                  normalisation, concordance, permutation null, dissonance
src/nvm.hpp                    the bytecode: ISA, container, emitter
src/json.hpp                   dependency-free JSON reader

tcl/nvm.tcl                    reference interpreter and disassembler
tcl/explore.tcl                Tk host with Sketchpad-style constraint drag
tcl/nvmdump.tcl                read the display file, or its assembly

web/host.html                  immediate-mode canvas host
web/bundle.tcl                 inlines the bytecode into one self-contained file

physical/plot.tcl              SVG for print, or stroked for a pen plotter
physical/solid.tcl             STL and OpenSCAD: the margin comb
physical/card.tcl              two-sided pocket card

video/trace.py                 digitise the printed curves back into numbers
video/analyse.py               peaks, polarity reversals, discharge order
video/common.py                the timeline and the colour system, shared
video/sonify.py                organ, thunder, and the mix
video/render.py                the 9:16 reel
```

`src/analyze.cpp` reads the JSON, derives everything, and writes a `.nvm` file.
Nothing downstream reads the session data again. That is the guarantee that the
browser, the plotter, the card and the printed object cannot disagree with each
other — and `make check` rebuilds from the seed and byte-compares to prove the
pipeline is deterministic.

### The bytecode

A `.nvm` file is simultaneously the derived data (symbol table), the drawing
program (immediate-mode opcodes) and the argument (`PANEL`, `ANCHOR`, `NOTE`,
`EDGE`, `FLAG`, `CITE`). Sutherland's Sketchpad kept a display file that was
re-executed on every refresh so the drawing and the model were one object; Kay's
version is that you ship the interpreter rather than the image; Engelbart's is
that the analyst must be able to restructure the view without leaving it.

The practical version is narrower and checkable: four hosts, 18 kB, no host with
an opinion.

```
make disasm | head -40
```

Full spec: [`docs/03-bytecode-spec.md`](docs/03-bytecode-spec.md).

### The statistics

With n = 1 session there is no sample to estimate a correlation from, so there
is no correlation coefficient anywhere in this project. What *is* answerable is
whether this person's pattern of deviations agrees with published effect
directions more than a reshuffling of the same deviations would — a permutation
test on a concordance statistic over a prior graph, with a null, a statistic and
a p-value, none of which pretend to be an `r`.

The null is weak and is labelled as one everywhere it appears. Details and
limitations in [`docs/02-full-fat.md` §3](docs/02-full-fat.md).

---

## Things you can do with it

```sh
make dash                      # self-contained HTML, no server, no network
make explore                   # Tk host, needs a display
make disasm                    # read the drawing program
make dump                      # symbol table, ranked by margin past threshold
make physical                  # SVG print + plotter, card, STL + SCAD
make check                     # every host over the same bytes, plus a determinism check
make whatif M=beh.rt V=430     # Sketchpad's constraint drag, from the shell
```

`whatif` overrides one measured value and re-derives everything downstream —
composites, severities, all five concordances, all five permutation nulls.
Setting reaction time to a normal 430 ms drops H2 from C = 0.401 / p = 0.006 to
C = 0.233 / p = 0.047. The Tk explorer binds the same thing to the arrow keys,
so you can pull on a value and watch the argument move.

### In the dashboard

`1`–`5` toggle hypothesis lenses and compose; non-matching metrics dim to 45%
rather than disappearing, because removing the denominator would change what the
page claims. `p` / `f` / `b` switch the explanation register between plain
language, full fat and both. `/` finds a metric, `0` fits to width, `i`
collapses the info view, `Esc` clears. Scroll to move, ctrl-scroll to zoom, click
to pin — and pinning lights every prior-graph edge touching that metric, in
every panel it appears in.

### The original figures, as TIFFs

```sh
make figures        # -> build/figures/ and build/figures.zip
```

15 figures cut out of the source scans — EEG head maps and raw traces for both
conditions, the three ERP waveforms, the cardiac waveform, HRV tachogram and
power spectrum, the screener chart, the result gauges, the 12-lead trace and the
skin-prick grid — named
`$Condition_$Test_$Company_$Date_$timestampoftest.tiff`.

Each is a crop out of the page's **native embedded bitmap**, not a re-render, so
there is no resampling and no invented detail: 300 ppi for the 12-lead, 203 ppi
for the Evoke pages, 204 × 196 for the faxed skin test. Provenance, caption and
resolution ride along in each file's `ImageDescription` tag and in
`MANIFEST.csv`.

One caveat travels with them: only the 12-lead prints a real acquisition time
(`14:51:16`). The Evoke figures carry `152200` from the cover page's "3:22 PM",
accurate to the minute. The skin test prints no time at all, so its `165100` is
the **fax transmission** stamp — an upper bound, not a test time. The manifest's
`timestamp_source` column says which is which for every file.

### The simulated conference

```sh
make conference     # -> build/conference/proceedings.pdf, 32 pages, landscape
```

Five invented readers argue about this record for five days: a 912 Columbus
internist, a Columbia neurophysiologist, a European standards chair, a Tokyo
evoked-potential specialist, and a California vision scientist who keeps asking
what the checkerboard actually was. **They are fictional and the document says so
on its cover** — no clinician has reviewed this record.

Front matter catalogues the twentieth-century origin of every instrument
(Berger 1929, Sutton 1965, Squires 1975, Einthoven 1903, Akselrod 1981,
Blackley 1873, Halliday 1972, Rosvold 1956) against what PubMed and the journals
say now, including the January 2026 multiverse analysis that reruns the
theta/beta ratio across 576 analysis pipelines.

Every claim that rests on something visible in the source scans is highlighted
in yellow, carries a link id, and has a drawn ley line to a margin stub. The
back matter is seven annotated plates built from the extracted TIFFs, where the
line runs the other way — from a stub into a boxed region on the figure. A page
break cannot carry a line, so a link is two half-lines meeting at the page edge
under the same id and colour, both ends live in the PDF, plus one final spread
that draws all 36 links at once. Numerals are set in IBM Plex Mono throughout.

### The reel, and the sound of it

```sh
make video          # -> build/video/photic.mp4, 2160x3840, 30 s, with audio
make video SCALE=1  # 1080x1920, about a minute, for looking at
```

Thirty seconds, 9:16, in two acts: the photic block, then ten seconds of the
resting montage. The chart is the point — a montage already **is** a map, with
fixed named places, fixed routes between them and a grid you read positions off,
so the head is drawn in orthographic projection with its own graticule, the five
anterior-posterior bipolar chains are drawn as the routes a reader traverses,
and the trace panel gets meridians at the component latencies with a
cartographer's scale bar underneath, in milliseconds instead of miles.

**There is no continuous photic EEG in this record.** The checkerboard block
survives only as three averaged single-channel curves printed on one page, so
`video/trace.py` reads the ink back off the scan: it finds the axis, the tick
marks and the zero line, calibrates from the ticks alone, and never looks at the
peak values the report prints. Which makes those printed peaks a test rather
than an input, and all three pass:

| | traced | report | error |
|---|---|---|---|
| Cz | +17.92 µV @ 464 ms | +17.26 @ 468 | +0.66 µV, −4 ms |
| Pz | +6.78 µV @ 387 ms | +6.60 @ 380 | +0.18 µV, +7 ms |
| O2 | −7.73 µV @ 287 ms | −7.55 @ 288 | −0.18 µV, −1 ms |

The resting act has a real scalp field — 15 usable electrodes — so it gets an
interpolated topography. The photic act does not, and does not get one: three
points is not a field, and drawing one would be drawing data that was never
recorded.

`video/analyse.py` then extracts what the animation is actually about — every
peak with its latency, amplitude, polarity and prominence, every zero crossing,
and the order the channels discharge in. That order is the finding:

```
O2 287 ms  ->  Pz 387 ms  ->  Cz 464 ms
```

N100, then the parietal P3b, then the frontocentral P3a. Textbook order puts
P3a first. Here the orienting response arrives **last** — which is the same
story the 0.382 amplitude ratio tells, arriving by a different route, and it is
in the printed curves and in none of the printed text.

**On the colour.** The brief asked for green to red. That is the one ramp to
avoid: red-green is exactly the axis protanopia and deuteranopia collapse, and
a green-to-red amplitude scale is unreadable to roughly 8% of men at any
brightness. So the OKLab machinery stayed and what carries meaning changed —
**magnitude is lightness**, monotonic, and **polarity is hue**, azure against
gold. Lightness survives everything: full achromatopsia, a bad projector, a
phone in sunlight, a greyscale print. The positive hue is 92°, gold rather than
amber, because amber at middling lightness is in sRGB simply brown — there is no
chroma available there to make it anything else — and brown was the specific
failure the brief called out.

**On the sound.** `video/sonify.py` plays the same event list the picture is
drawn from, so a flash and a note are the same row of the same file:

- a **peak** is an organ note — pitch from where the electrode sits front to
  back, loudness from microvolts, and the voicing from polarity: positive
  deflections take the major triad, negative ones the quartal stack on the flat
  seventh. G Mixolydian gives both colours over one root, so polarity is
  audible without a key change.
- a **polarity reversal** is a chopped slice of thunder, pitch-bent by the slope
  of the crossing and panned by how far off the midline the electrode is.
- a **principal peak** is the whole crack: chord, thunder, sub drop, and
  everything else ducked out of its way.
- the **resting alpha** is the tremulant. The organ's flutter rate is not
  chosen; it is read out of `features.json` — 9.33 Hz, the measured eyes-closed
  dominant frequency. The alpha rhythm is not represented by the tremolo, it
  **is** the tremolo.

The organ is additive and drawbar-style — ranks at 1, 2, 3, 4, 6, 8, 12 and 16
times the fundamental, each detuned a few cents so they beat against each other,
with a chiff of filtered noise at onset for the sound of air arriving before
tone. The thunder is synthesised rather than sampled: a crack filtered bright
*before* it is enveloped, three reflections, over a brown-noise body rolled off
below 200 Hz. The mixing is the SOPHIE part — hard gates with 1.5 ms edges,
sidechain ducking on every hit, a mono saturated sub under each one, an air
burst on every transient, chops panned by electrode laterality with a Haas
offset, and the act boundary as twelve milliseconds of actual silence.

### On paper and in your hand

- `build/card.svg` — two 88 × 55 mm sides. The findings that clear threshold,
  the five scores, and the four things one session cannot settle. Print at 100%.
- `build/comb.stl` — a 151 mm bar with 30 pins, one per metric, height above a
  tactile rail encoding distance past threshold. Run a thumb along it and the
  shape under your hand is the decay curve. It is also the only rendering here
  that works if you cannot see.
- `build/plot.svg` — every fill converted to 45° hatching, one pen width, for an
  AxiDraw or a laser's vector pass.

---

## Design

The UI is evaluated against Apple HIG, Material Design 3, Ableton Live, Cycling
'74 Max/MSP and Teenage Engineering in
[`docs/04-ui-evaluation.md`](docs/04-ui-evaluation.md) — including where those
five conflict, which one won, and the failures still in the code.

Three defects that document surfaced and that are now fixed: three colour tokens
failing WCAG AA (one amber at 2.8:1 used as body text), anchor bounding boxes
merging across panels into one hit region that swallowed every click inside it,
and a modifier-only pan that made a 3 000 px document appear not to scroll.

---

## Privacy

`data/session-2026-08-18.json` contains real clinical measurements. Direct
identifiers — name, date of birth, medical-record number — are **not** carried
into this repository; `subject_ref` is `SUBJ-001`. `analyze --deidentify` also
suppresses the vendor report code in the emitted display file.

The measurements themselves are still health data. Treat the repository
accordingly.

---

## Requirements

`g++` with C++17, `tclsh` 8.6, and `wish` 8.6 only for the Tk explorer. No
libraries, no package manager, no network.

Two targets step outside that. `make conference` needs `node` and a Chromium to
paginate and print; `make video` needs Python with `numpy`, `pillow` and
`imageio-ffmpeg`. Everything the reel needs beyond that — the timeline, the
colour space, the organ, the thunder and the mix — is in the four files under
`video/`, and IBM Plex ships in `assets/fonts/` under the OFL so the build does
not reach for a font it might not find.
