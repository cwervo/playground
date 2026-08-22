# How ioa is put together

ioa is an orchestrator, not a video pipeline. It does not capture, encode,
decode or display anything. It decides **what can be moved over what**, tells
each box on the route how to do its part, and keeps deciding as the fabric
changes underneath it.

That division is deliberate. Every platform already has something excellent at
moving pixels — AVFoundation and VideoToolbox on macOS, V4L2 and VA-API on
Linux, `esp32-camera` on the ESP32, a hardware encoder on the FPGA parts. What
none of them has is an answer to "this camera, that screen, over a laser and
two radios, at what quality?"

## The stack

```
              ioa.tcl                    CLI: products, plan, run, deploy, session
                 |
    +------------+------------+
    |                         |
 session.tcl               deploy.tcl    hold a route open  /  emit real commands
    |                         |
 plan.tcl -------------------+            ladder descent + shortest path
    |          |
 budget.tcl  codec.tcl                    fragments, FEC, binomial delivery / bitrates
    |          |
 fabric.tcl  device.tcl  products.tcl     the installation, as data
    |
 transport.tcl                            one vtable per medium
    |
 transports/{rf,optical,wired,virtual}.tcl
    |
 frame.tcl                                IOAF/1 on the wire
    |
 core.tcl                                 units, logging, deterministic RNG
```

Each file depends only on the ones below it. `sim.tcl` hangs off the side of
`plan.tcl`: it consumes a plan and disagrees with it.

## The five ideas

### 1. Every medium answers the same four questions

A transport registers with `ioa::transport::define` and must state its
goodput, MTU, latency and loss. The planner never asks "is this a radio?" —
it asks those four numbers, which is why a laser and an HDMI cable can be
consecutive hops on one route. Geometry is applied by a per-medium `derate`
proc: RF rolls off with distance and interference, optical cares about
alignment and ambient light, wired media are flat.

### 2. Fragmentation is the real constraint

Bandwidth is the obvious limit and rarely the binding one. The binding one is
that a 59 KiB picture becomes 276 packets on a 250-byte medium, and losing any
one of them loses all of it. `lib/budget.tcl` computes delivery as a binomial
tail over the fragment count, which is what lets the planner reject a link the
datasheet says is fine. See [PROTOCOL.md](PROTOCOL.md).

### 3. Quality is a ladder you walk down

`lib/codec.tcl` holds sixteen rungs from 4K60 H.265 down to 80x60 at one frame
every five seconds. The planner starts at what you asked for and descends
until the fabric agrees, keeping every refusal and its reason. `ioa plan`
prints them, because "why is my camera at 320x240" is the question operators
actually ask.

The curated order is by *usefulness*, which is not the same as by cost — MJPEG
1080p30 is a better picture than H.264 1080p30 and five times the bitrate. So
the descent skips any rung costing more than the one just refused: retreating
must always be cheaper, or the planner is guessing. (`ioa::codec::descent`,
and the invariant is enforced in `tests/codec.test`.)

### 4. Planning is shortest-path over the rungs that survive

For each rung: ask every edge whether it can carry it — with FEC if the
fragment count demands it, refusing if even 2.0x redundancy will not save it —
then Dijkstra over the survivors, minimising predicted one-way latency. The
first rung with a viable path wins.

Capacity is checked against a utilisation ceiling (80% by default) rather than
the raw goodput, and the keyframe burst is checked separately from the average
bitrate. A fabric that carries the average but not the keyframe stutters once
per GOP, which is exactly the kind of thing that survives a bench test and
fails on site.

### 5. The plan is a claim, and the simulator argues with it

`ioa run` pushes pictures through the planned route with a deterministic
channel: per-fragment loss draws, serialisation, and a store-and-forward queue
at every relay that can and does overflow. Then it prints predicted against
observed and says which way the plan was wrong.

A sample of pictures also goes through the *real* IOAF encoder and
reassembler, and one frame per picture is deliberately corrupted to confirm
the CRC rejects it. The model can be wrong; the wire format is exercised
rather than assumed.

## Why Tcl

- **It is the language of the room.** This lives in a Folk playground, and
  Folk is Tcl. A fabric file is Tcl, evaluated in a safe interpreter.
- **`binary format` / `binary scan`** are a wire-format DSL that happens to
  ship in the standard library. IOAF pack and unpack are one line each.
- **No dependencies and no build.** `tclsh ioa.tcl` on a stock macOS or Linux
  box, including the test suite. The thing that plans the fabric should not
  need a toolchain the fabric does not.
- **Dicts are the whole data model.** Products, devices, links, plans and
  manifests are plain dicts; there is no object system to learn and nothing
  to serialise.

## Adding a medium

Four steps, no core changes:

1. `ioa::transport::define yourmedium { ... }` in `lib/transports/`, stating
   the four numbers plus `medium`, `duplex`, `mtu`, `range_m`, `los`,
   `power_mw` and which `platforms` can terminate it.
2. Point `derate` at `derateFlat`, `derateRf`, `derateOptical`, or write your
   own `{caps params} -> {goodput_bps loss}`.
3. Point `realize` at a proc returning what to actually run — `exec` with a
   command, `firmware` with a config dict, `bitstream` with a bitfile.
4. Add it to a product's `transports` list.

The planner, budget model, simulator and deployer pick it up with no further
work. `lib/transports/virtual.tcl` is the shortest example.

## Adding a product

One stanza in `lib/products.tcl`, naming its `platform`, `transports`,
`encode` ceiling and `power_mw`. `tests/products.test` will then hold you to
it: interfaces must exist, the platform must be one the deployer can drive,
and no product may claim a medium its platform family cannot terminate.

## What this is not

- Not a video pipeline. It generates `ffmpeg` invocations; it does not link
  against libav.
- Not a running daemon. `ioa deploy` prints commands and nothing executes
  them. The `ioa gw` gateway those commands invoke is not implemented here.
- Not measured. Every transport number is a plausible field estimate, and
  every latency figure is modelled. Treat them as a well-argued starting point
  for an install, not as test results.
