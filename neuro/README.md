# neuro

Five scanned clinical documents from one afternoon, turned into one bytecode
that a browser, a Tk window, a pen plotter and a 3D printer all execute without
any of them re-deriving a number.

```
make                    # engine, display file, dashboard, print, plotter, card, STL
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

Three findings that came out of re-deriving rather than re-reading:

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
