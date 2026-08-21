# UI evaluation

The dashboard was reviewed against five design traditions. They do not agree
with each other, and the interesting part of this document is where they
conflict and which one won.

Scoring is deliberately blunt: **pass**, **partial**, **fail**. Every "fail" is
a real defect that is still in the code.

---

## Summary

| Tradition | Pass | Partial | Fail |
|---|---|---|---|
| Apple HIG | 8 | 2 | 2 |
| Material Design 3 | 6 | 3 | 2 |
| Ableton Live | 5 | 1 | 1 |
| Cycling '74 Max/MSP | 3 | 2 | 2 |
| Teenage Engineering | 4 | 2 | 1 |

A `<canvas>` has no accessible object model, so the data is also emitted as a
tab-reachable, visually-hidden `<table>`. That closes the worst of the gap and
does not close all of it; the accessibility section at the end says exactly what
is covered and what is not.

---

## Apple — Human Interface Guidelines

HIG's three stated principles are clarity, deference and depth.

**Clarity — pass.** The type scale is a small closed set (17 / 15 / 13 / 12.5 /
11 px chrome, 15 / 13 / 12 / 11 / 9.5 px canvas) rather than an arbitrary one.
Numerics use `font-variant-numeric: tabular-nums`, so a column of margins does
not jitter. Every metric carries its unit.

**Deference — pass.** The chrome is one 50 px bar and one 32 px status line. No
gradients, no shadows except the modal, no decorative illustration. The content
occupies everything else.

**Depth — partial.** HIG means depth as layered navigation. There is exactly one
layer here plus one modal (find). Selection expands into the info view rather
than pushing a screen. Defensible for a single-document tool, but it is not what
HIG describes.

**Hit targets — partial.** HIG asks for 44×44 pt. The lens toggles and segmented
buttons are 34 px tall — comfortable for a pointer, undersized for touch. Fixed
for touch would mean a 60 px header bar that costs canvas height on exactly the
devices with the least of it. **Chosen: 34 px, and the tool is honest that it is
pointer-first.** That is a real trade, not an oversight.

**Contrast — pass, after a fix.** Every text token was measured, not eyeballed:

| token | light on `--bg` | dark on `--bg` |
|---|---|---|
| `--ink` | 16.4 | 15.7 |
| `--ink-2` | 8.0 | 9.9 |
| `--muted` | 5.2 | 5.4 |
| `--accent` | 5.5 | 7.6 |
| `--ok` | 5.5 | 8.7 |
| `--border` | 5.1 | 8.8 |
| `--deviant` | 5.4 | 6.9 |

Three of these originally failed AA. `--muted` was 3.9:1, `--deviant` was 4.45:1
on `--surface-1`, and the amber `--border` was **2.8:1** — badly failing as text.
The amber is the interesting case: it is used both as a *fill* for borderline
bars, where WCAG 1.4.11 asks 3:1 for non-text objects, and as *type* for the
margin figure, where AA asks 4.5:1. One colour cannot do both. The emitter now
carries `kBorder` (fill) and `kBorderTxt` (type) as separate constants, and the
comment in `src/analyze.cpp` says why so the next person does not "simplify"
them back together.

**Colour is never the only channel — pass.** Severity is carried by colour, by
the signed percentage, by the raw value, by the word in the info view
(`within reference` / `borderline` / `deviant`), and by position in the ranking.
A red-green colour-blind reader loses one of five channels.

**Reduced motion — pass.** `prefers-reduced-motion` collapses every transition.
The canvas has no animation to suppress: it redraws each frame but the picture
does not move unless the reader moves it.

**Dark mode — pass.** Light is defined on bare `:root`; dark overrides under
both `prefers-color-scheme` and `[data-theme="dark"]`, so the explicit toggle
wins in both directions and a page with no colour-scheme signal still has a
complete palette.

**Focus — pass.** `:focus-visible` rings exist on every chrome control, and the
accessible data table behind the canvas is tab-reachable and reveals itself on
focus. See the accessibility section.

**Fail — no undo.** Nudging a value in the Tk explorer re-derives everything and
the only way back is `R`, which drops *all* overrides. HIG is clear that a
destructive-feeling action wants a graceful reverse. An override stack would be
maybe thirty lines and is not written.

**Fail — no persistence.** Theme, lens set and register reset on reload. HIG
expects a document tool to remember where you were.

---

## Google — Material Design 3

**State layers — pass.** Interactive elements use a `::after` overlay at
`--state-hover` / `--state-press` opacity rather than swapping background
colours, so hover, focus and press compose. Opacities are raised in dark mode
(0.06 → 0.09) because a fixed overlay reads weaker against a dark ground, which
is M3's own guidance.

**Tonal surfaces — pass.** `--surface`, `--surface-1`, `--surface-2` form an
elevation ladder used consistently: page ground, panel, control chip.

**Shape scale — pass.** Three radii (4 / 8 / 14 px), applied by role — small for
chips inside controls, medium for controls, large for the modal.

**Typography roles — partial.** M3 wants a named role set (display / headline /
title / body / label). This has an implicit one — `.wordmark`, `aside h2`,
`.reg-label`, `.reg-body`, `.grouplabel` — but the roles are not named as tokens
and a sixth would probably get invented ad hoc.

**Segmented button — pass.** The Plain / Full fat / Both control is exactly M3's
single-select segmented button, with `aria-pressed` maintained.

**Colour roles — partial.** There is a primary (`--accent`) and an error
(`--deviant`), but no secondary or tertiary, and no container/on-container
pairs. The palette is deliberately smaller than M3's because a five-colour
semantic scale (ok / borderline / deviant / no-data / accent) is already
carrying meaning, and adding decorative roles on top would compete with it.
**Chosen: fewer roles, all semantic.**

**Fail — no motion system.** M3 specifies easing and duration tokens per
transition class. This uses `.12s ease` everywhere.

**Fail — no elevation on the modal beyond a shadow.** M3 dialogs have a defined
scrim and elevation token; here it is one hand-picked `box-shadow`.

---

## Ableton Live

Live is the strongest influence on this design and the one it follows most
closely.

**One window, no modal dialogs — pass.** Everything except Find is in one view.
There is no settings panel, no wizard, no confirmation step.

**The Info View — pass, and this is the borrowed idea.** Live keeps a permanent
box in the bottom-left that describes whatever the pointer is over. It is the
single highest-value affordance in that program for anyone learning it, and it
costs one panel. The right-hand info view here is that, with the addition of two
registers: the plain sentence is the "what is this control" line, the full-fat
paragraph is the manual entry, and you can have either or both without leaving
the page.

**State is visible, not hidden — pass.** The five lenses are always on screen
with their on/off state legible. Nothing is behind a disclosure triangle.

**Direct manipulation with immediate feedback — pass.** Click to pin. No OK
button anywhere in the tool.

**Monochrome plus one accent — pass.** The chrome is grey plus `--accent`. The
only other colours in the interface are the three severity hues, which are data,
not decoration.

**Fail — no keyboard-first workflow for the canvas.** In Live you can drive
almost everything without the mouse. Here `1`–`5`, `p`/`f`/`b`, `/`, `0`, `i`
and the arrow keys work, and the hidden data table gives linear traversal, but
there is no spatial "next metric in this panel" movement, so the canvas itself
is still pointer-led.

---

## Cycling '74 — Max/MSP

Max is where this design borrows least comfortably, and the honest answer is
that two of its central ideas do not fit.

**Patch cords as first-class objects — pass.** With a lens active, prior-graph
edges are drawn as Bézier cords between the metrics they relate, coloured by
whether this record agrees with the published direction. The connections are the
argument, so they are drawn rather than implied by adjacency. Selecting any
metric lights every cord touching it, whether or not its lens is on — selection
is a question, and the answer should not depend on remembering to enable
something first.

**Objects report their own state — pass.** Every anchored element carries its
value, its deviation, its margin and its severity, and shows all four on
inspection. Nothing is a bare glyph.

**Signal flow is legible — partial.** You can see *that* `beh.rt` relates to
five other metrics across three hypotheses. You cannot see the derivation chain
— that `ans.vlf_ratio` is `ans.vlf / ans.lf` — anywhere in the UI. It is in
`data/prior-graph.json` and in the docs. A patcher would show it as boxes and
cords. **This is the most Max-shaped thing the tool is missing.**

**Fail — no edit mode.** Max's defining move is the runtime/edit toggle: the
same window either runs the patch or lets you rewire it. Here the graph is
authored in a JSON file and compiled in. You can change a *value* at run time
(the Tk explorer's constraint drag re-derives everything from the engine) but
you cannot add or delete an *edge* without editing a file and rebuilding.

**Fail — no console.** Max keeps a message window where objects print. The
status line is one ephemeral line with no history, so a sequence of actions
leaves no trace you can scroll back through.

---

## Teenage Engineering

**Reduction — pass.** No icons that need learning, no chrome that is not a
control, no illustration. Every pixel of the header does something.

**Numbered affordances — pass.** The lenses are `1`–`5` with the number set in a
mono chip, and the number is also the key that toggles them. TE's OP-1 does
exactly this: the label on the hardware *is* the input. There is no separate
shortcut list to memorise because the shortcut is printed on the control.

**Functional micro-labels — pass.** `LENS` and `EXPLAIN` are set at 9.5 px, mono,
0.16 em tracking, in `--muted`. That is TE's panel-legend idiom, and it names a
group without competing with it.

**Monospace for anything numeric — pass.** Values, margins, ids and the status
line are all mono; prose is not. A number and a sentence should not look like
the same kind of thing.

**Strict grid — partial.** The header is on a consistent rhythm. The canvas
panels are on a 40 px margin with 30 px gutters, but panel heights are data-
driven — the ladder is as tall as there are metrics — so vertical rhythm is not
strict.

**One accent — partial.** There is one interface accent, but the data uses three
semantic hues. TE would likely reduce that to one accent plus value, and it
would be wrong to here: the difference between "borderline" and "deviant" is the
whole point of the ladder panel.

**Fail — hardware honesty.** TE designs objects whose affordances are physically
true: a knob turns because it is a knob. The lens toggles look like buttons and
behave like buttons, but nothing else on the page is tactile. The 3D-printed
comb in `physical/` is the one artefact in this project that actually meets that
standard, and it is not the dashboard.

---

## Where the traditions actually conflict

**Density.** HIG's 44 pt targets and M3's 48 dp minimums both push toward a
taller, roomier header. Ableton and TE both push the other way — Live's mixer
strip is deliberately dense because a producer needs to see everything at once.
This tool sides with density: **34 px controls**, and it says so rather than
claiming to meet the touch guidance.

**Colour count.** M3 wants primary / secondary / tertiary / error plus
containers. TE wants one accent. Ableton wants monochrome plus one. The data
already needs four semantic colours. Adding M3's decorative roles on top would
put decorative colour in competition with meaningful colour, on a page whose
central claim is that a red dot has to be quantified. **Fewer roles, all
semantic.**

**Where explanation lives.** HIG would use a popover or a detail view. M3 would
use a bottom sheet on small screens. Ableton uses a permanent info box that
never moves. The permanent box wins because the reader is comparing many things
in one sitting, and a popover that opens and closes forty times is worse than a
panel that quietly updates.

**Hiding versus dimming.** Filtering usually means hiding. Here, activating a
lens **dims non-matching metrics to 45% rather than removing them**, because the
whole claim of the ladder panel is "here is how far past the line each finding
sits, out of everything measured". Remove the denominator and the panel is
making a different, weaker claim. Engelbart's principle — restructure the view
without leaving it — decided this one.

---

## Accessibility

A `<canvas>` has no accessible object model. Drawn as-is, a screen-reader user
would get the header, the info view and the status line, and nothing at all from
the 62 metrics — which would make the central claim of the page unreachable to
them.

**What is implemented.** The canvas is `aria-hidden`, and the same data is also
emitted as a real `<table>`: one row per measured metric, sorted furthest-past-
threshold first so a screen-reader user meets the findings in the same order a
sighted one does, with label, domain, value, signed margin, status word and the
plain-language sentence. It is `.sr-only` — clipped, not `display:none`, because
`display:none` would remove it from the accessibility tree and defeat the
purpose — and it is in the tab order. Each row's label is a button that pins
that metric, so keyboard traversal and canvas selection drive the same state.
`.sr-only:focus-within` un-hides the table when anything inside it takes focus,
so a sighted keyboard user can see where they are rather than tabbing into an
invisible region. The info view is an `aria-live="polite"` region, so pinning
announces.

**What is still missing.** The individual marks on the canvas are not
independently focusable, so there is no spatial traversal — you get the table's
linear order or nothing. The chord panel's structure, specifically, has no
non-visual equivalent beyond the per-metric edge list in the info view.

Two further artefacts mitigate rather than substitute. The
**pocket card** (`build/card.svg`) is real text at print sizes and carries the
findings, the scores and the caveats. The **3D-printed comb**
(`build/comb.stl`) encodes every margin as a physical profile you read with a
thumb, and is the only rendering in this project that works if you cannot see it
at all. That was not a happy accident — it is why the object was made — but a
web dashboard should not be outsourcing its accessibility story to a 3D printer.

---

## What was measured, not asserted

- Contrast ratios: computed for every token pair against all three surfaces, in
  both themes. Three failures found and fixed.
- Frame cost: ~4 470 instructions per frame, 45–50 fps in headless Chromium at
  1500×950 with a 2× device pixel ratio. The first version ran at 19 fps because
  `getComputedStyle` was being called inside the interpreter loop on every
  `FONT` opcode; tokens are now cached per theme change.
- Interaction: driven under Playwright — hover, pin, lens toggle, register
  switch, scroll, keyboard. Two real bugs surfaced that way and are fixed: merged
  anchor bounding boxes across panels (one giant hit region that swallowed every
  click inside it), and a modifier-only pan that made a 3 000 px document appear
  not to scroll.
- Dark mode: verified visually, and the lightness-only inversion was written
  after the naive `255−x` version turned every deviant red into cyan.
