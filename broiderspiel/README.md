# Broiderspiel

A fullscreen WebGL toy mashing up two [Max Bittker](https://maxbittker.com)
projects in a single `<canvas>` driven by a single `<script>`:

- **[Broider](https://broider.website)** — a symmetric, self-mirroring
  "embroidery" that stitches the **outer 4%** frame of the viewport.
- **[Sandspiel](https://sandspiel.club)** — a falling-sand cellular automaton
  (sand, water, wood, plant, fire, smoke, stone) running inside the central
  **84%** box.

Everything simulates on the CPU into a low-resolution RGBA grid that is uploaded
once per frame to a texture and drawn as one fullscreen triangle with
nearest-neighbour sampling, so the whole thing is a single self-contained HTML
file with no dependencies.

## Run

Open `index.html` in any modern browser (desktop or mobile). No build step.

## Controls

| Gesture | Action |
| --- | --- |
| drag / paint | draw the current element into the sand box |
| single tap | cycle the current element (sand → water → wood → plant → fire → stone) |
| double tap | **pause** the simulation and open the native **Share** sheet |

Double-tapping captures the canvas as a PNG and hands it to the Web Share API
(`navigator.share`) so you can save or share your creation; where Web Share
isn't available it falls back to a direct PNG download. Double-tap again to
resume.
