# Folk State Management Report: Pong Simulator

## Introduction
We explored two methods of implementing a reactive "Pong Simulator" in Folk, attempting to store and mutate the bouncing ball's state (x, y, vx, vy) continuously without being attached to a physical tag. 

We deployed both versions to `folk-cwe` and captured the projector display to compare them.

## Option A: Global Tcl Variables (`set ::pong_x ...`)
The first approach attempted to store the state in global Tcl variables and mutate them on each clock tick. 
- **Code:** We initialized `::pong_x`, `::pong_y`, etc., at the top level, and accessed them inside `When the clock time is /t/`.
- **Result:** **Failed.** The projector display correctly rendered our "fallback" error circle, proving that `[info exists ::pong_x]` evaluated to `false` inside the `When` clause.
- **Why?** Folk's reactive system isolates the execution environment of `When` clauses. Variables initialized at the top level of a program file do not automatically bridge into the lambda execution scopes of `When` matches. Global variable mutations are fundamentally incompatible with Folk's graph-based, declarative evaluation loop.

## Option B: Reactive State Claims (`Hold!`)
The second approach used Folk's native declarative system to assert and update the state using `Hold!`.
- **Code:** We claimed the initial state using `Hold! -key pong_state ...`, and then updated it inside `When the clock time is /t/ & $me has state ...` by issuing a new `Hold! -key pong_state`.
- **Result:** **Explosion / Out of Memory.** While this approach is architecturally correct, implementing state machines requires precise handling of statement ownership. The top-level `Hold!` and the `When` block's `Hold!` evaluate under different dependency nodes. Because they have different parent nodes, the new claims *coexist* with the old claims rather than overwriting them. This caused the `When` block to match exponentially, triggering a `status=2/INVALIDARGUMENT` crash in `make` and restarting the entire Folk system.

## Key Learnings
1. **Never use standard Tcl state mutation (`set`) for cross-tick data.** It either throws "no such variable" errors or silently fails to resolve inside isolated `When` scopes.
2. **`Hold!` keys are parent-scoped.** A key is only unique relative to the node that asserts it. Asserting `-key pong_state` from two different execution blocks creates two separate claims in the database.
3. **State loops require consuming the previous state or sharing a single `-on` node.** To properly implement a state machine that ticks forward without creating an infinite loop of coexisting states, we must either retract the previous state (which Folk usually handles via `-key` replacement) by ensuring all state transitions are asserted on the same node (e.g. `Hold! -on $stateNode -key pong_state`), or use specialized state primitives.

## Next Steps
To build a fully working Pong implementation, we must refine Option B by explicitly binding the `Hold!` claims to a common parent node (using `-on`) or finding Folk's canonical pattern for single-instance ticking state machines (like `Hold! -keep 12ms` or separating the initialization completely).
