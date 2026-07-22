# Broiderspiel

A tiny falling-sand simulation ([Sandspiel](https://sandspiel.club)) stitched
inside a symmetric, self-mirroring embroidery ([Broider](https://broider.website)) —
both by [Max Bittker](https://maxbittker.com). The outer **4%** of the viewport
is the broider frame; the central **84%** box is the sand simulation
(sand, water, wood, plant, fire, smoke, stone).

It exists in **three ports** that share one Model (the cell grid) and differ
only in how they draw it, plus a **coffee-table PDF book** that reads the whole
thing as a short history of graphics programming.

```
broiderspiel/
├── index.html              WebGL port — one <canvas>, one <script>
├── tk/broiderspiel.tcl     Tcl/Tk port — immediate-mode into a Tk photo
├── sdl/broiderspiel.c      SDL2 + OpenGL/GLSL port (+ Makefile)
├── book/broiderspiel.pdf   the coffee-table book (11×8.5 landscape, 13pp)
├── book/broiderspiel.html  … its source
├── book/figures/           screenshots of the three ports (clean + debug)
└── tools/ppm2png.py        stdlib PPM→PNG (for the SDL port's dumps)
```

## The three ports

| | Render path | GUI | "Share" |
|---|---|---|---|
| **WebGL** (`index.html`) | CPU CA → RGBA grid → texture, one fullscreen triangle | immediate (redraw/frame) | Web Share API (PNG), falls back to download |
| **Tcl/Tk** (`tk/`) | CPU CA → hex rows → one `photo` blit (Tk has **no** shader path) | retained toolkit, driven immediate-mode | writes a PNG |
| **SDL/OpenGL** (`sdl/`) | CPU CA ships a tiny `type/life` texture; a **GLSL fragment shader** colours every pixel | hand-built immediate-mode UI | writes a snapshot |

All three share the same eleven-step frame and a **debug FPS sparkline**: press
`d` (or `?debug` in the browser) and the program's entire frames-per-second
history — streaming-downsampled so memory stays bounded — is compressed into a
transparent overlay across the bottom **10%** of the viewport.

### Controls (all ports)

- **drag** — paint the current element
- **1…6** — choose element (sand · water · wood · plant · fire · stone)
- **space** — pause / resume
- **d** — toggle the debug sparkline
- **double-tap / double-click** — pause + share/save a snapshot

## Running

**WebGL** — open `index.html` in any modern browser. No build.

**Tcl/Tk** — needs `tcl`/`tk` (`wish`):
```sh
wish tk/broiderspiel.tcl
# headless figure:  xvfb-run -a wish tk/broiderspiel.tcl --frames 600 --debug --out shot.png
```

**SDL/OpenGL** — needs SDL2, GLEW, an OpenGL 3.3 driver:
```sh
cd sdl && make && ./broiderspiel
# headless figure (offscreen):  ./broiderspiel --frames 600 --debug --out shot.ppm
#   ../tools/ppm2png.py shot.ppm shot.png
```
On Debian/Ubuntu: `sudo apt install tk libsdl2-dev libglew-dev libgl1-mesa-dev`.
The ports were built and verified headlessly under Xvfb; the SDL port renders on
Mesa `llvmpipe` when no GPU is present.

## The book

`book/broiderspiel.pdf` is a 13-page landscape coffee-table book that walks the
UI in **View / Simulations** steps and reads Broiderspiel against Smalltalk (MVC,
message-passing), HyperCard (the painted card, live gauges), and Simula
(simulation, objects, coroutines). It has hand-drawn SVG diagrams, screenshots of
all three ports, a lineage timeline (Sketchpad 1963 → Broiderspiel), and a
verified bibliography with an archival *Plates & Sources* apparatus (Internet
Archive, Computer History Museum, the Met's Watson Library, Library of Congress).

> Note: the archival image *files* are cited, not reproduced — the build
> environment's outbound network to those hosts was blocked by policy, so each
> plate is referenced to its catalogue rather than faked. See the book's
> frontispiece and *Plates & Sources* page. To rebuild the PDF, open
> `book/broiderspiel.html` and print to PDF (landscape, 11×8.5, backgrounds on).
