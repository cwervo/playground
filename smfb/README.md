# smfb — Shannon Mouse Fly Brain

A fly's brain, in a mouse, on your wrist.

**smfb** is a CoreGraphics app for iOS, macOS, watchOS and tvOS in which a
little mouse scurries around the screen. What steers it is a simulated
*Drosophila* connectome: a scaled, procedurally generated fly brain with the
real cell classes and wiring logic — olfactory receptors, antennal lobe,
Kenyon cells with APL feedback, mushroom body output neurons, lateral horn,
central complex, descending neurons — running as leaky integrate-and-fire
neurons in hand-written arm64 **NEON assembly**. Tap the screen to put a crumb
down; the mouse smells it with its two antennae, the fly circuitry compares
left and right, and the descending neurons turn it toward the food.

The mouse is Theseus, after Claude Shannon's 1950 maze-solving mouse. The fly
brain is the part Shannon didn't have.

```
      tap / click / remote            SwiftUI Canvas ── withCGContext ──▶ CoreGraphics
             │                                ▲                            (mouse, crumbs,
             ▼                                │ snapshot                    brain schematic)
   smfb_world_drop_food ──▶  smfb_world_step ─┴─▶ smfb_brain_step ──▶ NEON kernels
   (C, world.c)              odor → ORNs               │               lif_neon.S
                             whiskers → MECH           │               ─────────────
                             DN rates → turn/speed     └── CSR connectome (connectome.c)
```

## Layout

```
smfb/
├── SMFBKit/                     Swift package used by all four apps
│   ├── Package.swift
│   ├── Sources/SMFBCore/        plain C + NEON: the whole simulation
│   │   ├── include/smfb_core.h  the API (regions, kernels, brain, world)
│   │   ├── lif_neon.S           arm64 NEON kernels (empty object elsewhere)
│   │   ├── lif_portable.c       lane-for-lane identical C fallback
│   │   ├── dispatch.c           picks neon/portable; pins the asm ABI
│   │   ├── connectome.c         FlyWire-shaped procedural connectome (CSR)
│   │   ├── brain.c              neuron state, stepping, reward plasticity
│   │   └── world.c              arena, mouse, crumbs, sensory-motor loop
│   ├── Sources/SMFBKit/         Swift wrapper, CoreGraphics renderer, SwiftUI
│   └── Tests/SMFBKitTests/      XCTest (runs headless, also on Linux)
├── Apps/Shared/SMFBApp.swift    the one @main, shared by every target
├── project.yml                  XcodeGen spec: SMFB-iOS/-macOS/-watchOS/-tvOS
├── tools/smfb_cli.c             headless run with an ASCII arena
├── tools/kernel_test.c          NEON vs portable, bit-exact; behaviour test
├── Makefile                     builds the core + CLI + tests with any cc
└── flake.nix                    Nix: packages, checks (incl. NEON under qemu), dev shell
```

## Building the apps

The Xcode project is generated, not checked in:

```sh
cd smfb
xcodegen generate            # brew install xcodegen, or `nix run .#xcodeproj`
open SMFB.xcodeproj
```

Pick a scheme — `SMFB-iOS`, `SMFB-macOS`, `SMFB-watchOS` or `SMFB-tvOS` — and
run. There are no dependencies beyond the local `SMFBKit` package. Minimum
targets: iOS 16, macOS 13, watchOS 9, tvOS 16.

On Apple silicon and on every iPhone, iPad, Watch and Apple TV the NEON
kernels are used; on an Intel Mac or an x86 simulator the `.S` file compiles
to nothing and the portable C kernels take over, with identical results.

### Controls

| Platform | Drop a crumb | Other |
| --- | --- | --- |
| iOS / iPadOS | tap | |
| watchOS | tap | Digital Crown scrubs simulation speed |
| tvOS | swipe the remote to move the crosshair, click or play/pause to drop | menu clears crumbs |
| macOS | click | toolbar: pause (space), clear crumbs, new brain, speed |

The panel in the corner is the fly brain: antennae at the bottom, neck
connective at the top. Nodes glow with activity; the blue ones (APL) are
inhibitory. Under it, bars for odor at each antenna and the three descending
populations (turn left, turn right, forward).

## The simulation

**Neurons.** Leaky integrate-and-fire, 1 ms steps: `τ dv/dt = −(v − v_rest) +
I_syn + I_ext + noise`, threshold −50 mV, reset −65 mV, 2 ms refractory,
exponentially decaying synaptic current (τ_syn = 5 ms). Every neuron carries
its own xorshift32 noise stream so the network is deterministic per seed.

**Connectome.** `connectome.c` lays out 21 populations in the proportions of
the fly brain and wires them by expected fan-in per postsynaptic neuron, so
synapse counts scale linearly with the `scale` parameter:

| scale | neurons | synapses | used on |
| --- | --- | --- | --- |
| 1 | 1,776 | ~27k | tests, CLI |
| 2 | 3,536 | ~57k | Apple Watch |
| 8 | 14,144 | ~236k | iPhone, iPad, Apple TV |
| 16 | 28,288 | ~470k | Mac |

The wiring is the textbook fly olfactory-to-motor path: ORN → AL (ipsilateral
excitation, contralateral inhibition) → Kenyon cells (sparse, kept sparse by
APL feedback) → MBONs of approach and avoidance valence; AL → lateral horn
(innate attraction) → descending neurons, with the LH also crossing to inhibit
the opposite side; a recurrent central complex idling near threshold drives
the forward DNs so the mouse wanders when there is nothing to smell;
mechanosensory whiskers turn it away from walls; and PAM-like dopamine neurons
fire while it chews. Eating triggers the fly's actual appetitive learning
rule: a three-factor depression of KC → MBON-avoid synapses for recently
active Kenyon cells (`smfb_brain_apply_plasticity`), so a crumb's odor becomes
more attractive the more the mouse eats.

This is a **procedural connectome shaped like FlyWire**, not the FlyWire
dataset itself: the real thing is ~140k neurons and ~50M synapses, which no
watch will step in real time. The CSR layout (`row_ptr`, `col_idx`, `weight`)
is exactly what a real export would fill; swapping the generator for a loader
is the obvious next step.

**NEON.** Four kernels in `lif_neon.S`, all using only caller-saved registers:

- `smfb_lif_step_neon` — four neurons per iteration: vector xorshift noise,
  leak, synaptic and external input, refractory hold (`cmtst`/`bit`/`uqsub`),
  threshold (`fcmge`), reset, and compaction of the firing indices into a list
  (`umaxv` to skip silent groups).
- `smfb_propagate_neon` — event-driven scatter of each spiking neuron's CSR
  row into the postsynaptic currents, unrolled four synapses at a time. This
  one is scalar A64 on purpose: NEON has no scatter, and only the ~1% of
  neurons that fired each step are touched.
- `smfb_scale_neon` / `smfb_sum_neon` — activity-trace decay and per-region
  rate readout, 16 and 4 lanes per iteration.

`lif_portable.c` is written to do the same operations in the same order
(`fmaf` where the assembly uses `fmla`, four independent noise lanes, pairwise
sum reduction), and `tools/kernel_test.c` insists the two paths agree **bit
for bit** — including a 30-second behaviour run that must eat a crumb at the
same instant on both. That test caught two real bugs while this was written:
an `orr` immediate that can only set one byte (0x3f000000 ≠ 0x3f800000, which
silenced the brain) and a clobbered callee-saved `v8`–`v10` that corrupted the
caller's floats.

## Headless: CLI, tests, Nix

No Apple hardware needed for the core:

```sh
cd smfb
make test                     # portable kernels on this machine
make run                      # 20 s of ASCII mouse
./build/smfb-cli 8 30 42      # scale 8, 30 s, seed 42

# arm64 + NEON from an x86 box (apt install qemu-user gcc-aarch64-linux-gnu):
make BUILD=build-arm64 CC=aarch64-linux-gnu-gcc \
     RUN="qemu-aarch64 -L /usr/aarch64-linux-gnu" test
```

With Nix:

```sh
nix build            # smfb-core: CLI + kernel tests, tests run as the check phase
nix run              # the CLI
nix flake check      # kernels natively, plus NEON under qemu on x86_64-linux
nix develop          # make, clang, qemu; xcodegen on macOS
nix run .#xcodeproj  # macOS: generate SMFB.xcodeproj
```

The Swift package itself also builds on Linux (`swift build`, `swift test` in
`SMFBKit/`): the SwiftUI and CoreGraphics files are behind `#if canImport`,
so what remains is the wrapper, the simulation runner and its tests.

## Numbers

Portable kernels, one x86-64 core, `-O2` (the NEON path on an A-series or
M-series chip is comfortably faster):

| scale | neurons | synapses | speed vs real time |
| --- | --- | --- | --- |
| 2 | 3,536 | 57k | 27× |
| 8 | 14,144 | 236k | 6.5× |
| 32 | 56,576 | 952k | 1.4× |

The simulation runs on its own thread at 120 Hz (60 Hz on the watch) and the
`Canvas` just draws the latest snapshot, so a slow frame never stalls the
brain and a slow brain never stalls the frame.
