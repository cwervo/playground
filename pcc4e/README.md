# PCC4E

## 🍏 Private Cloud Compute 4 Everyone

Apple's [Private Cloud Compute](https://security.apple.com/blog/private-cloud-compute/) is a genuinely
interesting architecture — attested, stateless, auditable compute nodes that a device can offload
sensitive work to without the cloud provider (or Apple itself) being able to inspect it. There's a
surprising amount published about it: the
[security guide](https://security.apple.com/documentation/private-cloud-compute/),
the [research blog](https://security.apple.com/blog/private-cloud-compute/), and
[independent](https://blog.trailofbits.com/) [security](https://www.nccgroup.com/)
[analyses](https://www.zerodayinitiative.com/) from third parties who've picked the design apart.
It's a real, working example of "trust but verify" applied to cloud compute — and it's exclusive
to devices inside Apple's walled garden.

There are a lot of sad, little (and big!) devices that don't get to live in that garden: old
Android phones, Linux boxes, Windows laptops, microcontrollers, routers, whatever's lying around.
PCC4E is an attempt to bring the *spirit* of that architecture — attestable, ephemeral, encrypted
offload of compute to trusted peers — to everything else, over whatever transport happens to be
available: mDNS on a LAN, WLAN direct, infrared, audio (audible chirps or ultrasonic/near-ultrasonic
tones your phone's mic can still pick up), and even SMS/MMS/RCS via `pcc4e://` URIs embedded in QR
codes for fully out-of-band bootstrapping.

This repo is the starting point: a spec, a reference implementation, and a build pipeline that
targets a wide range of platforms and architectures from a shared core.

## Goals

- **Attestable nodes.** Any device offering compute proves what it's running before a peer trusts it.
- **Ephemeral by default.** No durable state left behind after a job completes.
- **Transport-agnostic.** The same protocol runs over IP, mDNS discovery, IR, audio, or SMS/MMS.
- **Small footprint.** Runs on embedded targets, not just desktops and phones.
- **No walled garden.** Open spec, open source, portable binaries.

## Support Table

| Platform | Architecture(s)         | Status         | Notes                                      |
|----------|--------------------------|----------------|---------------------------------------------|
| Linux    | x86_64, aarch64, armv7   | 🚧 In progress | Primary development target                 |
| Windows  | x86_64, aarch64          | 🚧 In progress | via MSVC / MinGW build                      |
| Darwin   | x86_64, arm64            | 🚧 In progress | macOS only — no iOS/iPadOS build yet        |
| Android  | aarch64, armv7           | 🗺️ Roadmapped  | Termux/NDK build                            |
| FreeBSD  | x86_64                   | 🗺️ Roadmapped  | Best-effort                                 |
| ESP32    | Xtensa, RISC-V           | 🗺️ Roadmapped  | Discovery/relay role only, not a compute node |
| RISC-V (Linux) | riscv64            | 🗺️ Roadmapped  | Tracks upstream Linux port                  |
| WASM/WASI | wasm32                  | 🗺️ Roadmapped  | Sandboxed compute node for browsers/edge    |

Legend: ✅ supported · 🚧 in progress · 🗺️ roadmapped / not started

## Transports

| Transport             | Role                          | Status         |
|------------------------|-------------------------------|----------------|
| mDNS / LAN             | Local discovery + data plane  | 🚧 In progress |
| WLAN (direct/AP)       | Data plane                    | 🚧 In progress |
| Infrared (IR)          | Bootstrap / low-bandwidth link| 🗺️ Roadmapped  |
| Audio modem (audible)  | Bootstrap / low-bandwidth link| 🗺️ Roadmapped  |
| Audio modem (near-ultrasonic) | Bootstrap / low-bandwidth link | 🗺️ Roadmapped |
| SMS / MMS / RCS (`pcc4e://` QR)| Out-of-band bootstrap  | 🗺️ Roadmapped  |

## Prototypes

- [`proto/DISCOVERY.md`](proto/DISCOVERY.md) — the discovery wire format both prototypes speak
- [`go/`](go/) — reference discovery-node implementation in Go
- [`zig/`](zig/) — wire-compatible discovery-node implementation in Zig

Both are real, buildable, runnable multicast-UDP discovery nodes — not the full mDNS/DNS-SD
spec, but the same shape (link-local multicast, periodic self-announce, no central server) that
the transports section above calls out. A Go node and a Zig node running side by side discover
each other on the `239.255.77.77:7777` group; see each subdirectory's README for real captured
output from a 3-node (2× Go, 1× Zig) run.

## Status

This is an early-stage project. Nothing here is production-ready or audited. Treat it as a spec
and prototype, not a security guarantee.

## License

TBD.
