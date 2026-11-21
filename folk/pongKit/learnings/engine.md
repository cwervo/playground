# Folk Pong Engine Architecture

This document explains the architecture of our successfully implemented reactive Pong simulator in Folk.

## 1. The Reactive Loop
Unlike traditional imperative programming loops (`while true`), Folk programs are fundamentally reactive rule engines. To simulate a continuous game like Pong, we need to tie state mutations to the passage of time.

We do this by creating a `When` block that listens for **both** the system clock *and* our current state:
```tcl
When the clock time is /t/ & \
     $me has state with x /x/ y /y/ vx /vx/ vy /vy/ { ... }
```
Because `/t/` changes continuously, this rule is re-evaluated on every tick, acting as our "game loop". 

## 2. Managing State with `Hold!`
State in Folk is typically represented by assertions (Claims) in the database. Our core mechanic is to capture the current position and velocity, calculate the new position (handling wall bounces), and emit a *new* state.

The critical insight to making this work without creating an infinite loop of overlapping states is the explicit use of the `-on` parameter:
```tcl
Hold! -on $me -key pong_state \
    Claim $me has state with x $next_x y $next_y vx $vx vy $vy
```

### Why `-on $me` is Required
Folk tracks claims using a dependency graph. If a `Hold!` lacks an explicit `-on` target, it implicitly belongs to the execution context that triggered it (e.g., the specific `When` node for the clock tick).
1. If we omit `-on`, the top-level initialization and the tick-based updates belong to different parents.
2. Because they have different parents, the new state *coexists* with the old state rather than overwriting it.
3. The `When` block then matches *both* states, triggering twice on the next tick, then four times, causing an exponential explosion that crashes the system.

By explicitly passing `-on $me` (where `$me` is `$this`, the ID of our program), we guarantee that all `pong_state` claims belong to the exact same parent node. Consequently, the new `Hold!` cleanly *replaces* the old one, moving the game forward by one step.

## 3. Rendering
Rendering is entirely decoupled from the physics logic. A separate reactive rule listens for our state and the presence of a display:
```tcl
When $me has state with x /x/ y /y/ vx /vx/ vy /vy/ & \
     display /disp/ has width /w/ height /h/ { ... }
```
This rule calculates physical screen coordinates from our relative percentages (0-100) and fulfills a `Wish` to draw the paddle/ball onto `$disp`. If the projector is turned off, this rule safely stops matching, and rendering stops without pausing the physics engine!

## Output Recording
Here is a capture of the working engine:

![Pong Engine Recording](/Users/cwervo/code/playground/folk/pongKit/learnings/projector_renderer_20260707-080646.mp4)
