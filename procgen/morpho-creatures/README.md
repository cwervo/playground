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

- **Evolve minimal** – a genetic algorithm (run in a worker) searches for the
  smallest version of your drawing that walks both forward and backward on
  **one input signal**: the phase of a single motor, with every muscle slaved
  to it by a fixed gain and offset. It may drop limbs, coarsen the lattice,
  narrow the bus and remove actuators; fitness is distance covered in both
  directions (the worse of the two) times the saving in material and parts.
  Evolved bodies cannot steer: ◀ runs the signal in reverse, ▶ forward.

This borrows MorphoHDL's ideas (edges as buses, growth by division and
recursion), not its syntax or code.
