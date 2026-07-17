# lilguys

Tiny critters that live on your macOS desktop, rendered by a single Metal
shader into a transparent, click-through overlay.

## The herd

- **fuzzball** — a small fuzzy white metaball with two blinking eyes. It's
  sticky: it rolls along the bottom of the screen, up screen edges, and along
  window borders, A*-pathfinding its way to the frontmost window's
  close/minimize/maximize "stoplight" cluster, where it nuzzles up and bobs.
- **grass** (×3 by default) — blades of grass with beady eyes that crouch and
  bounce left/right along the bottom of the screen. If the Dock is in the way,
  they wind up a bigger jump to clear it. Blades that end up near each other
  form groups and dance together in the wind.
- **dandelion** — sways gently, then occasionally keels over and dies,
  releasing three seeds: one grows into a new baby dandelion over 10 minutes,
  the other two land and become wandering blades of grass.

## Run it

```sh
./run.sh              # symlinks ~/Desktop/playground/lilguys, builds, runs
./run.sh my-herd.lg   # bring your own herd
```

Or by hand:

```sh
swiftc -O Lilguys.swift -o lilguysd
./lilguysd lilguys.lg
```

Ctrl-C to shoo them all away.

## Why no .app / no permission prompts

The prototype is a plain compiled Swift binary — a "daemon", not an app
bundle. It reads every on-screen window's position and size (front-to-back
order included) from `CGWindowListCopyWindowInfo`, which needs **no**
Accessibility or Screen Recording permission — those are only required for
window *titles/contents* or for moving other apps' windows, neither of which
we do. Rendering happens in our own borderless `NSWindow` at screen-saver
level with `ignoresMouseEvents = true`, so clicks pass straight through the
lilguys to whatever's underneath.

## The `.lg` file

One lilguy per line; `#` starts a comment.

```
fuzzball
grass x=0.25          # x is a fraction of screen width
dandelion x=0.6 size=120
```

The eventual plan: register the daemon as the handler for `.lg` files so
double-clicking one releases that herd. For now, pass the file as the first
argument (defaults to `./lilguys.lg`).

## Prototype limitations

- Main display only (multi-monitor herds later).
- The fuzzball pathfinds on a coarse 36pt grid of "sticky" cells hugging
  window borders and screen edges; it re-plans every ~1.2s, so it lags a bit
  when you drag windows around.
- Dock detection assumes a bottom Dock for the jump-over behavior.
