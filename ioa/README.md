# ioa — Image Over Air

Cameras on one side, screens on the other, and whatever will carry bits in
between: Wi-Fi, ESP-NOW, BLE, LoRa, infrared, Li-Fi, laser, HDMI, USB, UART,
Ethernet.

ioa does not move pixels. It works out what can be moved over what, tells each
box on the route how to do its part, and keeps working it out as the fabric
changes. A $59 ESP32 camera, a laser head across a courtyard and a MacBook are
all the same kind of thing to it: something with interfaces, a capacity, and a
place to stand.

```
$ ioa plan --from eye-01 --to desk --want webcam

route: eye-01 -> desk
=====================
  carrying     mj720p15 1280x720@15 mjpeg q75 (6.08 Mb/s)
  picture      49.5 KiB per frame, 7.35 ms keyframe stall worst hop
  latency      17.85 ms one way
  delivery     96.83% of pictures arrive whole
  bottleneck   wifi_tcp at 62.7 Mb/s (9.1x headroom)
  radiated     700 mW across 1 hop(s)

hop             transport  medium  dist  capacity   offered    frags  fec    loss   delivered  ms
--------------  ---------  ------  ----  ---------  ---------  -----  -----  -----  ---------  ----
eye-01 -> desk  wifi_tcp   rf      34 m  62.7 Mb/s  6.91 Mb/s  36     1.10x  4.46%  96.8%      11.3

rungs refused on the way down:
  mj720p30     beyond eye-01 encoder ceiling (mjpeg 1600 1200 25)
```

You asked for 30 fps. The sensor tops out at 25, so it offered 15 and said
why. That is most of what ioa is for.

## Try it

Needs `tclsh` 8.6 and nothing else.

```sh
./ioa.tcl demo          # the whole story in seven sections
./ioa.tcl products      # the line
./ioa.tcl transports    # every medium it can plan over
./ioa.tcl codecs        # the quality ladder
make test               # 113 tests
```

Then point it at an installation:

```sh
./ioa.tcl fabric  --fabric studio.ioa
./ioa.tcl plan    --fabric darkroom    --from eye-pro --to host --want hd --forbid rf
./ioa.tcl run     --fabric backcountry --from eye-01  --to base --want webcam --seconds 120
./ioa.tcl deploy  --fabric studio      --from eye-pro --to desk --want broadcast
./ioa.tcl session --fabric studio      --from eye-pro --to desk --want broadcast \
                  --event 'link eye-pro prism-near laser {alignment 0.3}' \
                  --event 'medium rf {interference 0.8}'
```

## What it actually does

**Plans.** Descends a sixteen-rung quality ladder until the fabric can honestly
carry a rung, running a shortest-path over the links that survive at each
level. Every refusal is kept and printed.

**Budgets.** The binding constraint on low-MTU media is not bandwidth, it is
arithmetic: a 59 KiB JPEG over 250-byte ESP-NOW packets is 276 fragments, and
losing any one loses the picture. At 1.2% packet loss that is a **3.4%**
delivery rate on a link the datasheet calls reliable. ioa computes that before
you install anything, and adds forward error correction — or refuses the link.

**Deploys.** Emits what each box must run: `ffmpeg` invocations on macOS and
Linux, `sdkconfig` values and a flash command on the ESP32, bitstream and
alignment steps on the FPGA parts. It prints them. It does not run them.

**Holds.** A session survives its route failing. Misalign the laser and it
reroutes to Wi-Fi; fill the band and it drops a rung; take away everything and
it says *dark* rather than pretending.

```
#  event                                                     carrying   path                       outcome
1  session opened                                            hd1080p60  eye-pro->prism-near->desk  hd1080p60 over laser, 95.1% delivery
2  eye-pro -> prism-near over laser changed (alignment 0.3)  hd1080p60  eye-pro->desk              rerouted; bottleneck now wifi_tcp
3  rf medium degraded (interference 0.8)                     hd1080p30  eye-pro->desk              quality hd1080p60 -> hd1080p30
```

**Argues with itself.** `ioa run` simulates the planned route with a
deterministic lossy channel and reports predicted against observed, plus real
IOAF frames round-tripped through the real encoder with deliberate corruption
to prove the CRC catches it.

## The line

Six pieces of hardware, three of software, one service, one kit — defined as
data in [`lib/products.tcl`](lib/products.tcl) so the planner reasons over real
hardware limits, not a wish list.

| SKU | | price | what |
|---|---|---|---|
| `IOA-EYE-S3` | ioa Eye | $59 | ESP32-S3 camera node. JPEGs at anything listening. |
| `IOA-EYE-PRO` | ioa Eye Pro | $329 | Global shutter, hardware H.265, optical port. |
| `IOA-RELAY-24` | ioa Relay | $89 | Takes a stream in on one medium, out on another. |
| `IOA-PRISM-L1` | ioa Prism | $249 | Li-Fi and laser. Where RF is banned, jammed or full. |
| `IOA-BEAM-IR` | ioa Beam | $29 | 2.4 kb/s infrared. The channel that still works. |
| `IOA-FRAME-HD` | ioa Frame | $199 | HDMI both ways; egress enumerates as a webcam. |
| `IOA-HUB-X` | ioa Hub | free | This repository. |
| `IOA-SIGHT-1` | ioa Sight | free | Viewer that shows the loss instead of hiding it. |
| `IOA-LOOM` | ioa Loom | $12/mo | Optional fleet service. |
| `IOA-DK-1` | ioa Dev Kit | $549 | Two of each optical part, on purpose. |

Full descriptions in [docs/PRODUCTS.md](docs/PRODUCTS.md).

## Layout

```
ioa.tcl                 CLI
lib/core.tcl            units, logging, deterministic RNG
lib/frame.tcl           IOAF/1 wire format, fragmentation, reassembly
lib/transport.tcl       medium-agnostic driver registry
lib/transports/         rf, optical, wired, virtual
lib/codec.tcl           the quality ladder
lib/budget.tcl          fragments, FEC, binomial delivery
lib/products.tcl        the line, as data
lib/device.tcl          a node: a product plus a place to stand
lib/fabric.tcl          the installation DSL, in a safe interpreter
lib/plan.tcl            ladder descent + shortest path
lib/sim.tcl             discrete-event simulation that argues with the plan
lib/deploy.tcl          per-node commands, firmware and bitstreams
lib/session.tcl         hold a route open across failures
fabric/studio.ioa       a working room: RF and a laser in parallel
fabric/darkroom.ioa     a site that bans radio; everything goes optical
fabric/backcountry.ioa  3 km of LoRa on solar, at the bottom of the ladder
tests/                  113 tests, tcltest
docs/                   PRODUCTS, ARCHITECTURE, PROTOCOL
```

## Describing your own site

A fabric file is Tcl, loaded in a safe interpreter — describing someone else's
rig can never run code on yours.

```tcl
fabric "Studio A" {}
site "third floor, and the building opposite"

device eye-01  {product IOA-EYE-S3  place "north truss"}
device relay-a {product IOA-RELAY-24 place "ceiling centre"}
device desk    {product IOA-HUB-X   platform macos}

link eye-01  relay-a espnow   {distance_m 18 channel 6}
link relay-a desk    wifi_tcp {distance_m 9 peer 10.0.0.4 interference 0.35}
```

Devices inherit interfaces, encoder ceiling and power draw from their SKU. A
device may also state its interfaces directly and skip the product entirely —
see [`tests/fixtures/bench.ioa`](tests/fixtures/bench.ioa).

## Honest limits

- **Nothing here touches hardware.** `ioa deploy` prints commands; the `ioa gw`
  gateway they invoke is specified, not implemented. The hardware in
  `ioa products` does not exist.
- **The numbers are modelled.** Every transport figure is a plausible field
  estimate and every latency is computed, not measured. Good enough to size an
  install and choose a medium; not a substitute for one afternoon with the
  actual radios.
- **IOAF/1 has no encryption and no retransmission.** Both are deliberate; see
  [docs/PROTOCOL.md](docs/PROTOCOL.md).

What *is* real: the wire format, the fragmentation and FEC arithmetic, the
route planner, the simulator, and the 113 tests that hold them to it.
