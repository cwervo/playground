# folklang renderer capability matrix

Generated from `folklang.bnf.tcl` (source of truth) —
upstream https://github.com/folkcomputer/folk @ `33e89446f683`.

Legend: ✅ yes · 🟡 partial · 🔜 planned · ❌ not supported · ❔ undecided

| Feature | Folk native (Vulkan) | folkOS Vulkan clone | JS simulator (headless CLI) | WASM simulator | C++ simulator (CLI) | CLI ASCII emulation | Linux SDL renderer | JS <canvas> 2D | JS+WASM <canvas> | JS WebGPU <canvas> | Metal renderer (macOS) | Metal renderer (iOS) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Core syntax (`core-syntax`) | ✅ | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🟡 |
| Reactive DB (`reactive-db`) | ✅ | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🟡 |
| Decorations (`decorations`) | ✅ | 🔜 | 🔜 | 🔜 | 🔜 | 🟡 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | ✅ |
| Canvas (`canvas`) | ✅ | 🔜 | ❌ | 🔜 | 🔜 | 🟡 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 |
| 2D drawing (`draw2d`) | ✅ | 🔜 | ❌ | 🔜 | 🔜 | 🟡 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🟡 |
| Image display (`image`) | ✅ | 🔜 | ❌ | 🔜 | 🔜 | 🟡 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 |
| JPEG codec (`image-jpeg`) | ✅ | 🔜 | 🔜 | 🔜 | 🔜 | 🟡 | 🔜 | ✅ | ✅ | ✅ | ✅ | ✅ |
| PNG codec (`image-png`) | ✅ | 🔜 | 🔜 | 🔜 | 🔜 | 🟡 | 🔜 | ✅ | ✅ | ✅ | ✅ | ✅ |
| GIF playback (`image-gif`) | ✅ | 🔜 | 🔜 | 🔜 | 🔜 | 🟡 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 |
| Sprite sheets (`sprite`) | ✅ | 🔜 | ❌ | 🔜 | 🔜 | 🟡 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 |
| Video (`video`) | ❌ | 🔜 | ❌ | ❌ | 🔜 | ❌ | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 |
| Camera input (`camera`) | ✅ | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 |
| Camera slices (`camera-slice`) | ✅ | 🔜 | 🔜 | 🔜 | 🔜 | 🟡 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 |
| AprilTags (`apriltags`) | ✅ | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 |
| Page geometry (`geometry`) | ✅ | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 |
| Calibration (`calibration`) | ✅ | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 |
| Connections (`connections`) | ✅ | 🔜 | ❌ | 🔜 | 🔜 | 🟡 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 |
| Recognition (`recognition`) | ✅ | ❔ | ❌ | ❌ | ❔ | ❌ | ❔ | ❌ | ❔ | ❔ | ❔ | ❔ |
| Keyboard (`keyboard`) | ✅ | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🟡 |
| Clock/animation (`clock`) | ✅ | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 |
| Collect (`collect`) | ✅ | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 |
| Unix processes (`unix`) | ✅ | 🔜 | 🔜 | ❌ | 🔜 | 🔜 | 🔜 | ❌ | ❌ | ❌ | 🔜 | ❌ |
| Error surfacing (`errors`) | ✅ | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | ✅ |
| Program mgmt (`programs`) | ✅ | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 |
| Editor (`editor`) | ✅ | 🔜 | ❌ | ❔ | ❔ | 🟡 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🟡 |
| Printing (`print`) | ✅ | ❔ | ❌ | ❌ | ❔ | ❌ | ❔ | ❌ | ❌ | ❌ | ❔ | ❌ |
| Custom shaders (`gpu-shader`) | ✅ | 🔜 | ❌ | ❔ | ❔ | ❌ | 🟡 | ❌ | ❌ | 🔜 | 🔜 | 🔜 |
| Terminal pages (`terminal`) | ✅ | ❔ | ❌ | ❌ | 🔜 | 🔜 | 🔜 | ❌ | ❌ | ❌ | ❔ | ❌ |
| Audio (`audio`) | ✅ | ❔ | ❌ | ❔ | ❔ | ❌ | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 |
| Web dashboard (`web`) | ✅ | 🔜 | 🔜 | 🔜 | ❔ | ❌ | ❔ | 🔜 | 🔜 | 🔜 | ❔ | ❔ |

## Renderers

- **Folk native (Vulkan)** (`folk-vulkan`, C + Jim Tcl + Vulkan, reference): Upstream reference implementation; baseline for conformance. Video not built in.
- **folkOS Vulkan clone** (`folkos-vulkan`, C++ + Vulkan, planned): Clone + refine of upstream pipeline; parity target.
- **JS simulator (headless CLI)** (`sim-js-cli`, Node.js, planned): Engine-first target: reader + reactive db + synthetic claims; renders nothing, asserts everything.
- **WASM simulator** (`sim-wasm`, engine compiled to WASM, planned): Shared core for browser targets; no subprocess spawning in-sandbox.
- **C++ simulator (CLI)** (`sim-cpp-cli`, C++20, planned): Native engine; substrate for SDL/Metal/Vulkan frontends.
- **CLI ASCII emulation** (`render-ascii`, terminal cells, planned): Everything visual degrades to cells: outlines are box-drawing, images are half-block mosaics.
- **Linux SDL renderer** (`render-sdl`, C++ + SDL2/SDL3, planned): Software/GL 2D path; gpu-shader partial (translate toy shaders to GLSL).
- **JS <canvas> 2D** (`render-js-canvas`, TS + Canvas2D, planned): Browser codecs are free (jpeg/png via Image, video via <video>); shaders unsupported.
- **JS+WASM <canvas>** (`render-js-wasm-canvas`, WASM engine + Canvas2D, planned): Same surface as render-js-canvas with the WASM engine core.
- **JS WebGPU <canvas>** (`render-webgpu`, WASM/TS + WebGPU, planned): Closest browser analog to upstream's Vulkan path; toy shaders retargeted to WGSL.
- **Metal renderer (macOS)** (`render-metal-macos`, Swift/ObjC++ + Metal, planned): MSL retarget of shader surface; AVFoundation for camera/video.
- **Metal renderer (iOS)** (`render-metal-ios`, Swift + Metal + Jim Tcl, prototype): First slice shipped as FolkBoy (renderers/metal-ios): embedded Jim Tcl batch engine, decorations vocab, circles/text; touch-first, no subprocesses.

