# paperwindow

Turn any macOS window into a sheet of paper. Grab a corner, pull, stretch, flick
it and watch it wobble. Press <kbd>esc</kbd> and the window goes back to normal.

```
swift build -c release
.build/release/PaperWindow
```

Move the cursor over a window, click, and it becomes paper.

## What it actually does

macOS will not let you deform another application's window — a window is a
rectangle and it stays a rectangle. So `paperwindow` builds a convincing double
instead:

1. **Photograph the window.** `ScreenCaptureKit` on macOS 14+, falling back to
   `CGWindowListCreateImage` below that. Both give a `CGImage` of exactly the
   window's bounds, at native retina resolution.
2. **Get the real window out of the way.** The Accessibility API slides it far
   off screen so it cannot peek out from under a stretched sheet. Its original
   position is remembered and restored on exit — including on <kbd>ctrl-C</kbd>,
   `SIGTERM` and `SIGHUP`. Without the Accessibility permission this step is
   skipped and everything else still works (pass `--keep-original` to make that
   the deliberate choice).
3. **Hang the photograph on a lattice.** A borderless transparent window spanning
   every display holds a Metal view. The captured image is the texture on a grid
   of triangles whose vertices are simulated particles.
4. **Simulate paper.** Position based dynamics: integrate with Verlet velocities,
   then relax structural, shear and bend distance constraints, plus a soft pull
   back to the rest shape. That last one is what makes it *elastic* rather than
   cloth — let go and it springs back, overshoots, and jiggles itself flat.
5. **Light it.** Each frame the renderer computes the deformation Jacobian at
   every vertex. `|det J|` is the local area ratio — stretched paper thins and
   brightens, squashed paper darkens — and the dot product of the normalised
   Jacobian columns measures shear, which shades the folds. A second offset pass
   in black gives the sheet a drop shadow so it reads as lifted off the screen.

## Controls

| | |
|---|---|
| drag a corner | pull and stretch the sheet from that corner |
| drag anywhere else | grab the sheet at that point |
| release mid-flick | the sheet keeps the hand's momentum and wobbles |
| <kbd>space</kbd> | random impulse — a flap |
| <kbd>g</kbd> | toggle gravity (the sheet sags and swings) |
| <kbd>r</kbd> | snap flat again |
| <kbd>esc</kbd> | put the window back and quit |

While the sheet is on screen the overlay covers the whole display, so clicks go
to the paper rather than to the apps underneath. <kbd>esc</kbd> gives everything
back.

## Options

```
paperwindow --list                  # window ids you can target
paperwindow --window 4823           # skip the picker
paperwindow --app Safari            # frontmost window of an app
paperwindow --live 20               # keep re-capturing, so the paper stays live
paperwindow --gravity               # start with gravity on
paperwindow --grid 12               # finer mesh, smoother deformation
paperwindow --stiffness 0.4         # floppier
paperwindow --spring-back 0         # stays wherever you crumple it
paperwindow --keep-original         # leave the real window where it is
paperwindow --no-shadow
```

## Permissions

- **Screen Recording** is required — without it there is nothing to photograph.
  You are prompted on first run.
- **Accessibility** is optional, and only used to move the real window aside
  while its paper double is on stage.

Permissions are granted per application, and a bare CLI binary inherits whatever
your terminal was granted, which gets confusing fast. `make app` wraps the binary
in a proper `PaperWindow.app` with a stable bundle identifier so it gets its own
entry in System Settings:

```
make app
open build/PaperWindow.app
```

The bundle is ad-hoc signed, so its signature changes on every rebuild and macOS
may ask for the permissions again after one. Sign with a real identity if that
becomes annoying.

## Notes

- Needs macOS 13 or later and any Metal-capable Mac (so, all of them).
- The sheet is a still photograph by default. `--live` re-captures at a few
  frames a second so a playing video or a scrolling page keeps moving on the
  paper — it works while the real window is parked off screen, because the
  window server still keeps its backing store.
- Multi-display setups work; the overlay spans the union of every screen, so you
  can stretch a corner from one monitor onto another.
