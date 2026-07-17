# Folk for iOS — a Swift VM for the Folk language

An iOS app (named **Folk**) that runs Folk programs inside a Swift-hosted
Tcl evaluator — no I/O, no processes, just the language — with a Metal
**Surface** standing in for Folk's Vulkan render context.

> The directory is `folk-ios/` (not `Folk/`) only because the repo already
> has a `folk/` directory and macOS filesystems are case-insensitive.

## Running

Open `Folk.xcodeproj` in Xcode 16+ and run on an iPhone/iPad or simulator
(iOS 16+). There are no dependencies.

## What's inside

### The Swift VM (`Folk/VM/`)

- `Tcl.swift`, `TclExpr.swift` — a small Tcl interpreter written in Swift
  (picol-style): substitution, `proc`/`fn`, `expr` with math functions,
  control flow, lists (`list`, `lindex`, `lassign`, `foreach`, …),
  `string`, `format`, `catch`. No `open`, `exec`, `socket` — no I/O at all.
- `FolkVM.swift` — the Folk layer: a statement database with **`Claim`**,
  **`Wish`**, and **`When`** (patterns use `/var/` wildcards, including the
  `/someone/ claims …` form). The whole database is rebuilt from scratch
  every tick (~30 Hz), Folk-style: programs run, `When` rules match to a
  fixpoint, then wishes are collected.
- `FolkBuiltins.swift` — built-in programs as embedded source, including a
  **metaball clock**: four gold metaballs on concentric rings encoding
  HH / MM / SS / ms — the live version of the app icon.

Base claims provided each tick: `the clock time is /t/` (uptime seconds),
`the wall clock is /hh/ /mm/ /ss/ /ms/`, and `the surface has size /w/ /h/`.

### The Surface (`Folk/Surface/`)

A Metal-backed view that plays the role of Folk's Vulkan render context.
Programs emit a small display-list **instruction set** through wishes:

```tcl
Wish the surface is cleared with color {0.06 0.06 0.08 1}
Wish to draw a line from {100 100} to {300 200} color white thickness 2
Wish to draw a circle at {200 300} radius 40 color cyan thickness 3   ;# omit thickness = filled
Wish to draw a rectangle at {50 50} size {120 80} color {0.9 0.2 0.2}
Wish to draw text "hello" at {200 120} size 20 color gold
Wish to draw metaballs at {100 100} {200 150} {160 260} {90 200} radius 60 color gold
```

`DrawInstruction.swift` parses wishes into instructions; `SurfaceRenderer.swift`
translates them into Metal draw calls (shapes are tessellated into a
flat-color pipeline; metaballs are an analytic field evaluated in a
fragment shader — see `Shaders.metal`). Text is composited over the Metal
layer as SwiftUI views. Colors are names (`gold`, `white`, `cyan`, …) or
`{r g b ?a?}` with 0–1 components.

### The input box (`Folk/UI/InputBox.swift`)

A floating card, draggable anywhere by its title bar. Type a Folk program,
press **Run**, and it joins the VM's program set live; errors show inline.

## The icon (`tools/GenerateIcon.swift`)

A single-file Swift program that renders **4 gold metaballs on white**,
where the ball positions encode the icon's creation time — hours, minutes,
seconds, and milliseconds each place one ball on its own concentric ring
(12 o'clock = zero). Every regeneration produces a visibly different icon,
so you can identify a build at a glance.

Regenerate before a build (macOS):

```sh
swift tools/GenerateIcon.swift
```

It overwrites `Folk/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`
and prints the encoded timestamp. The in-app metaball clock uses the same
layout, so the icon is literally a frozen frame of the app's idle screen.

## Known limitations (v0.1)

- No `Commit` (no cross-tick state yet); animate from `the clock time` instead.
- No compound `When … & …` patterns, and no `{*}` argument expansion.
- No I/O commands by design: no files, sockets, `exec`, or web.
- The fixpoint loop caps at 8 rounds and interpreters have a step budget,
  so runaway programs degrade gracefully instead of hanging the app.
