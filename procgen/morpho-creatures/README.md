# Soft Morphs

A single-file, mobile-first toy inspired by Alex Mordvintsev's
[MorphoHDL](https://paradigms-of-intelligence.github.io/morpho/): grow a soft
robot from a few strokes by recursion and cell division, then watch it walk a
maze or a mountain/gravel course.

Open `index.html` in a browser (no build, no dependencies).

- **Draw** – the first stroke is the spine (start at the head); later strokes
  attach as limbs. Sliders set cell divisions, bus width (muscle wires per
  edge), branch recursion and thickness. A spine with no legs grows prolegs.
- **Simulate** – autopilot follows the gates; hold ◀ ▶ (or arrow keys) to
  steer, drag to orbit, pinch to zoom.

This borrows MorphoHDL's ideas (edges as buses, growth by division and
recursion), not its syntax or code.
