# FolkBoy — folklang Metal renderer for iOS

The `render-metal-ios` target from the [folkOS capability
matrix](../../generated/capability-matrix.md): an iOS app that runs
**real Jim Tcl** (the same interpreter family folk itself uses) with a
miniature folk engine inside it, and renders the resulting display
list with **Metal** — dressed up as a Game Boy, with a keyboard where
the d-pad and A/B would be.

```
┌───────────────────────────────┐
│ ● POWER              OK 2·2   │
│ ┌────────────┬──────────────┐ │   top: left = folk code editor,
│ │ Wish $this │   ┌──────┐   │ │   right = Metal-rendered simulated
│ │ is outlined│   │ hello│   │ │   table (green outline + label)
│ │ green ...  │   └──────┘   │ │
│ └────────────┴──────────────┘ │
│  FOLK BOY · folkOS            │
│ [q][w][e][r][t][y][u][i][o][p]│
│  [a][s][d][f][g][h][j][k][l]  │   bottom: Game Boy-styled
│ [⇧][z][x][c][v][b][n][m][⌫]  │   keyboard + SELECT/START pills
│ [#$1][$][   space   ]["][⏎]  │   (CLEAR / RUN)
│   (SELECT·CLEAR) (START·RUN)  │
└───────────────────────────────┘
```

Typing (or pasting) e.g.

```tcl
Wish $this is outlined green; Wish $this is labelled "hello from iOS"
```

re-evaluates live on every keystroke and draws a green outline around
the virtual page with a centered label. Smart quotes from iOS are
normalized automatically.

## Architecture

```
App/ (SwiftUI + Metal)                      code string
  ContentView / GameBoyKeyboard  ──────────────┐
  FolkVM.swift  ── folk_eval_program(code) ────▼
CSources/folk_jim.c  ── embeds ──▶  Vendor/jimsh0.c (Jim Tcl 0.84,
  │                                 single-file bootstrap amalgamation)
  └── runs ──▶ Engine/folk-engine.tcl (mini folk engine:
               Claim/Wish/When, /var/ patterns, claimize, stdlib vocab)
  ◀── JSON display list {"display":[{"op":"outline","color":"green",…}]}
App/Renderer.swift (MTKView delegate)
  solid pipeline: page, fills, highlights, outlines, circles
  textured pipeline: CoreText-rasterized labels/titles/errors
```

- **Engine semantics** are the folklang subset declared in
  [`folklang.bnf.tcl`](../../folklang.bnf.tcl): batch evaluation to a
  fixpoint per keystroke — no `Hold!`/`On unmatch`/negation yet
  (core-syntax = partial, reactive-db = partial in the matrix).
- **Vocabulary implemented**: `is outlined /c/` (+ `thick`), `is
  labelled /t/` (+ `with color /c/`), `is titled`, `is highlighted`,
  `is filled with color`, `draws text`, `draws a circle with
  radius/x/y/color/filled`. Errors surface folk-style (`ok:false` +
  red on-screen error text).
- `exec` is removed from the interpreter at init (no subprocesses on
  iOS).

## Building the app

Needs a Mac with Xcode 15+:

```sh
brew install xcodegen
cd folkOS/renderers/metal-ios
xcodegen                     # generates FolkBoy.xcodeproj
open FolkBoy.xcodeproj       # pick a simulator or device, Run
```

## Testing the engine without a Mac

The exact C + Jim + Tcl stack the app embeds runs anywhere with a C
compiler:

```sh
./scripts/test-host.sh       # builds the host harness, runs 13 conformance checks
printf 'Wish $this is outlined green' | \
  ./build/folkboy-host Engine/folk-engine.tcl -   # prints the JSON frame
```

## Files

| Path | What |
|---|---|
| `Engine/folk-engine.tcl` | mini folk engine (pure Tcl, Jim-compatible) |
| `CSources/folk_jim.{h,c}` | embedding API: `folk_init`, `folk_eval_program` |
| `Vendor/jimsh0.c` | Jim Tcl bootstrap amalgamation (regenerate: `scripts/fetch-jimtcl.sh`) |
| `App/` | SwiftUI shell, keyboard, Metal renderer, shaders |
| `HostTest/` + `scripts/test-host.sh` | host-side conformance harness |
| `project.yml` | XcodeGen project definition |
