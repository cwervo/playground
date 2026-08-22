# The ioa line

Six pieces of hardware, three pieces of software, one service, one kit. The
whole line exists to answer one question in as many ways as a site demands:
**how do pictures get from that camera to that screen, here, today?**

The catalog is not just prose. It is
[`lib/products.tcl`](../lib/products.tcl), and it is the same data the planner
reasons over — a device in a fabric names a SKU and inherits that SKU's
interfaces, encoder ceiling and power draw. Add a product there and the
planner can route through it immediately. `ioa products --sku IOA-EYE-S3`
prints any of them in full.

---

## Capture

### ioa Eye — `IOA-EYE-S3` — $59 — shipping

Palm-sized RF camera node. ESP32-S3, 8 MB PSRAM, OV5640 5 MP on an M12 mount,
38 x 38 x 16 mm, USB-C or 1S LiPo.

JPEG comes out of the sensor pipeline in hardware; the SoC never touches
pixels, only packets. That is what lets a $6 microcontroller sustain
1600x1200 at 25 fps — it is a packet pump with a lens on it.

Speaks Wi-Fi (TCP and UDP), ESP-NOW, BLE, IR and UART. The ESP-NOW port is the
interesting one: no association, no DHCP, no access point, 200 m of range, and
250-byte packets. The consequences of that MTU are the subject of
[PROTOCOL.md](PROTOCOL.md).

**Buy it when** you need many cameras, cheaply, and can live with 720p15.

### ioa Eye Pro — `IOA-EYE-PRO` — $329 — beta

Global-shutter head with a real encoder. RK3588S, IMX296 1.6 MP global
shutter, C-mount, PoE+ or 12 V, 92 x 62 x 40 mm.

H.265 to 1080p60 in silicon (`h264_rkmpp` for the H.264 path), so it is the
only camera in the line whose output survives a long thin link without
retreating down the ladder first. Carries Ethernet, Wi-Fi, UVC, and a
Prism-compatible optical port — it can drive a laser head directly, with no
relay in between.

**Buy it when** motion is fast, or the link is long, or both.

---

## Moving the bits

### ioa Relay — `IOA-RELAY-24` — $89 — shipping

The repeater. ESP32-S3 + nRF52840 + SX1262: Wi-Fi, ESP-NOW, BLE, LoRa, UART
and an IR control port in one 70 mm puck, PoE or USB-C PD.

Takes a stream in on one medium and puts it out on another. Store-and-forward
through a 4 MB frame ring, so it survives a 300 ms outage on its uplink
without losing a picture; when the ring does fill it drops oldest-first,
because in live video a late picture is worth less than a missing one.

**Buy it when** the camera and the screen do not share a medium.

### ioa Prism — `IOA-PRISM-L1` — $249 — beta

Photonic head. Lattice iCE40UP5K, 650 nm laser diode, APD front end, Ø60 x
110 mm tube on a tripod boss, 12 V 2 A.

Two modes. Diffuse Li-Fi at 12 Mb/s covers a room with no aiming at all.
Collimated laser does 100 Mb/s to another Prism you have pointed at it, out to
400 m. Class 3R, interlocked, and it drops to *zero* below 0.5 alignment
rather than degrading gracefully — a misaligned optical link is not a slow
link, and the planner models it that way.

**Buy it when** RF is banned, jammed, full, or crossing a property line.
Sold in pairs for the obvious reason.

### ioa Beam — `IOA-BEAM-IR` — $29 — shipping

Infrared side channel. ESP32-C3, 940 nm array, TSOP receiver, 48 x 24 x 14 mm,
USB-C or 2xAA.

2.4 kb/s. Three orders of magnitude too slow for video, which is the point:
it is the channel that still works when the video channel does not. Wake a
sleeping Eye, aim a Prism, pull telemetry off a node whose radio you have
just misconfigured.

**Buy it when** you want a way in that does not depend on the way out.

### ioa Frame — `IOA-FRAME-HD` — $199 — shipping

HDMI in one side, ioa out the other, and back again. Lattice CrossLink-NX with
a hardware H.264 encoder, 1080p60 both directions, PoE+ or USB-C PD.

Uncompressed 1080p60 is 3 Gb/s; the Frame encodes on the way in so the rest of
the fabric survives contact with it. The egress side enumerates as an ordinary
UVC webcam, so any host application sees an ioa stream as `/dev/video0` with
no driver, no plugin and no explanation.

**Buy it when** the source or the sink is something you cannot modify.

---

## Software and service

### ioa Hub — `IOA-HUB-X` — free — shipping

The orchestrator daemon, and this repository. Tcl 8.6, no compiled
dependencies, macOS 13+ or Linux 5.15+. Plans routes, emits per-node
configuration, holds sessions open across failures. Shells out to `ffmpeg`
only when a real stream is being moved; everything else is arithmetic.

### ioa Sight — `IOA-SIGHT-1` — free — beta

Viewer and recorder. Decodes IOAF directly, so it shows fragment loss and
per-hop latency *alongside* the picture instead of hiding them behind a
buffer. When a link is failing you want to see it failing.

### ioa Loom — `IOA-LOOM` — $12/node/month — concept

Fleet service: inventory, firmware, route history for installations you cannot
visit. Entirely optional — the fabric runs headless without it, and nothing in
the Hub phones home.

---

## Kit

### ioa Dev Kit — `IOA-DK-1` — $549 — shipping

Two Eyes, two Prisms, a Relay, a Beam, a Hub licence, foam case. Two of each
optical part on purpose: a one-ended optical link is not a link.

---

## Reading the line as a table

| SKU | class | platform | what it terminates |
|---|---|---|---|
| `IOA-EYE-S3` | camera | ESP32 | wifi_tcp, wifi_udp, espnow, ble, ir, uart |
| `IOA-EYE-PRO` | camera | Linux | ethernet, wifi_tcp, uvc, lifi, laser, uart |
| `IOA-RELAY-24` | relay | ESP32 | wifi_tcp, wifi_udp, espnow, ble, lora, uart, ir |
| `IOA-PRISM-L1` | optical | FPGA | lifi, laser, ethernet, uart |
| `IOA-BEAM-IR` | optical | ESP32 | ir, ble, uart |
| `IOA-FRAME-HD` | bridge | FPGA | hdmi, ethernet, wifi_tcp, uvc, uart |
| `IOA-HUB-X` | host | macOS/Linux | everything the host has |
| `IOA-SIGHT-1` | software | macOS/Linux | loopback, wifi_tcp, uvc |
| `IOA-LOOM` | service | hosted | ethernet |
| `IOA-DK-1` | kit | — | — |

The test suite enforces the parts of this table that can be enforced: every
declared interface exists in the transport registry, every product runs on a
platform the deployer knows how to drive, no product claims a medium its
platform family cannot terminate, and every camera can actually encode
something. See [`tests/products.test`](../tests/products.test).
