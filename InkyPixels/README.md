# InkyPixels

A single-file Tcl authoring library (`inkypixels.tcl`, namespace `::inkypixels`,
alias `::ip`) for building "inky pixel" websites whose visuals are produced by
**one progressively-enhanced render loop that runs off the main thread**.

```
WebGPU  →  WebGL2  →  Canvas2D
   (best)   (typical)   (fallback)
```

The background `<canvas>` is handed to a **Web Worker** via `OffscreenCanvas`
(the worker is built from an inline **Blob URL**, so there is no network
dependency). The worker owns the heavy per-pixel **CMYK halftone ink
simulation**; the main thread stays awake and responsive, only nudging small DOM
widgets — the four **CMYK data wells** and the engine/FPS badge — once per frame.
If `OffscreenCanvas` (or a GPU tier) is unavailable it degrades cleanly to a
main-thread `Canvas2D` loop. Every generated page is **self-contained and makes
zero network requests**.

## Build

```sh
tclsh build.tcl        # writes history-of-color/index.html and ui-kit/index.html
```

## Library API

```tcl
source inkypixels.tcl
namespace import ::inkypixels::*

set html [doc "Title" $bodyHtml {wells 1 badge 1 startEra 4 eraNames {...}}]
write path/index.html $html
```

Component helpers (each returns an HTML fragment): `btn slider toggle seg
radio3 tabs card field input progress badge chip note kbd modal inkwells`.
The engine, worker glue, UI behaviours (tabs, toggles, radios, modal, toasts)
and all CSS are inlined by `doc` automatically.

## Demos

### `history-of-color/`
**A History of Photographic Color** — cyanotypes, daguerreotypes, tin etching,
painted B/W, the invention of colored-crystal photochemistry (autochrome), and
the story of film grain and film-stock size (16mm → 70mm). Scrub the timeline and
the page re-inks itself; the **four data wells** in the bottom-left rise and fall
with the simulated **C M Y K** each era lays down (mean CMYK per era × the
coverage budget).

### `ui-kit/`
A full page of modern, accessible components — buttons, switches, ranges,
segmented controls, a three-way ink-budget radio, tabs, cards, progress, badges,
dialogs and toasts — every one of them floating over the **same** off-thread CMYK
render loop, which you can drive live (era + coverage budget).

## How the render tiers are chosen

`createRenderer()` tries `webgpu` → `webgl2` → `canvas2d`, returning the first
that initializes. The same tiered renderer runs inside the worker (preferred)
and, if `OffscreenCanvas`/`Worker` is missing, directly on the main thread. The
engine badge (top-right) reports the resolved tier and whether it is on a
`worker` or `main` thread, next to a live main-thread FPS counter — proof the
heavy pixels never block the UI.
