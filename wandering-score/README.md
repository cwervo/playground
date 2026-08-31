# Wandering Score

A p5.js recreation of an Instagram reel: coloured pens wander across a sheet of
ruled paper while a playhead sweeps left to right, dropping a black dot wherever
it crosses a line. Strokes are born one at a time, grow, hold, then erode into
fragments and vanish — and the sheet starts over with a fresh score.

Source reel: <https://www.instagram.com/reel/DcEq4RxzYQ3/> (reference only; no
material from it is included here). All the code is original — it reproduces the
*system*, not the recording, so every run draws a different score.

## Running it

Open `index.html`. p5 1.11.3 is vendored in `vendor/`, so it works offline with
no build step and no network.

| Input           | Effect                     |
| --------------- | -------------------------- |
| click, or `R`   | start a new score          |
| `space`         | pause / resume             |
| `S`             | save a PNG                 |

## How it was matched

The reel was sampled frame by frame and measured, rather than eyeballed. Numbers
below are in the source's native 720×1280.

**Stage.** The paper is 633×844 (3:4), centred, with a 12px corner radius: 88%
of frame width, 66% of frame height. Page `#f7f5f3`, paper `#fcfaf8`, plus four
ruled lines at 19.1 / 39.7 / 60.3 / 80.9% of paper height. The camera never
moves and the paper clips the strokes — which is why one continuous line reads
as several disconnected pieces.

**Playhead.** A 2px `#3a3a38` line crossing the paper in exactly 4.0s and
wrapping — measured off 145 frames, dead periodic. Dots are 15px across.

**Palette**, from hue-clustering the saturated pixels:

| voice     | colour    |                                        |
| --------- | --------- | -------------------------------------- |
| indigo    | `#7c72de` | long meander with big open loops       |
| green     | `#229c77` | wide sweeping arcs                     |
| amber     | `#e7a641` | straight runs with abrupt corners      |
| vermilion | `#d3623d` | small tight leaf-shaped scribbles      |
| rose      | `#d97aa7` | shallow, quick wave                    |

**Timing.** Counting each colour's pixels per frame gives every stroke's birth,
plateau and decay: indigo enters at 0.5s, green 5s, amber 12s, a flurry of
vermilion scribbles from 21s, rose at 38s. Erosion begins around 43s and the
sheet is blank by 71s. `SCORE` in `sketch.js` follows that schedule.

## How it works

Geometry is in *card-width units*: the paper is exactly 1.0 wide, so nothing
depends on resolution. Each pen takes fixed-length steps and only ever changes
its heading, which is what gives the lines their even, unhurried quality.

Voices differ only in how they steer:

- **`turn`** — heading change per step. The radius of the resulting curve is
  `SEG / turn`, so the loop and arc sizes were set straight from radii measured
  off the reel (~60px indigo loops, ~180px green sweeps).
- **`freq`** — how often the pen changes its mind, in cycles per unit length.
- **`sharp`** — an exponent on the steering signal. At 1 the line curves evenly;
  higher values flatten small deflections to nothing and keep the large ones,
  giving amber its long straight runs and sudden corners.
- **`spin`** — the leaf. Curving one way only, hard at two points per lap and
  barely at all between, traces a flattened oval; the lap is normalised to close
  on itself so successive passes stack into a lens instead of fanning out into a
  rosette. Getting this wrong is very visible: too much drift per lap and the
  scribbles come out as flowers, constant curvature and they come out as coils.

p5's Perlin noise barely leaves the middle of its range, so raw it makes every
voice a gentle arc. `NOISE_GAIN` stretches it until the steering genuinely
saturates, which is what lets the pens close a loop.

Pens roam inside an ellipse a little larger than the paper, shaped like the
paper, and are steered back when they leave. A circular bound instead lets a pen
park off to one side and disappear for seconds at a time.

Erosion gives each point a threshold from 1-D noise along the path; as a
stroke's erosion rises, points below it drop out. Lines break into fragments
that shrink from both ends and wink out — the reel's dissolve, which is not an
alpha fade.

Growth is a function of a stroke's *age*, not a per-frame delta, so the drawing
is identical at any frame rate and catches up in one step after the tab has been
in the background.

## Checks

Rendered in headless Chromium and compared against the source:

- Ink coverage at the 41s peak: **40.4k px** averaged over six seeds, against
  **42.1k px** in the reel — within 4%, with the reel inside the spread.
- Lines stay whole through the build, erode into shrinking fragments, and the
  sheet is empty before the cycle restarts.
- Cycle rollover, pause/resume, resize, and a forced 25s time jump all behave.

The reel also carries a continuous music bed. It is not event-driven — the
envelope is flat, with no onsets on the playhead crossings — so there is no
audio here.
