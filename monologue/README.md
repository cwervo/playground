# Monologue

**Your voice, alone. Your voices, together.**

A wearable (choker + behind-ear piece) that picks up contact-mic vibration
from the throat, jaw, or mastoid/temple during subvocalization or whisper-quiet
speech, and turns it into text/audio on an iPhone, iPad, or Mac — over
whichever transport actually works in the room: a private WLAN, a relay
through iMessage/SMS/RCS, or a line-of-sight IR optical link to a nearby
Linux box.

This directory is a from-scratch hardware + firmware + software plan, not
a finished build. Read [`docs/risks.md`](docs/risks.md) first — the
biggest open question isn't the PCB, it's whether the signal is usable at
all, and the plan is sequenced to answer that before spending money on
boards.

## What this actually is (read before the block diagrams)

A piezo/electret **contact mic** pressed against skin does not read nerve
or muscle signals — it reads the same acoustic vibration a throat mic or
bone-conduction headset reads, just filtered through tissue and bone. That
means:

- It **will** pick up whispered or subvocalized speech as a very
  low-bandwidth, low-frequency, high-noise version of normal speech audio.
  This is a solved-adjacent problem (tactical throat mics, whisper ASR).
- It will **not** do silent-speech-from-EMG the way research rigs like
  MIT's AlterEgo do (those use surface EMG electrodes on the jaw, a
  different sensor and a different signal). Don't scope the ASR plan
  around EMG-only techniques — scope it around whisper/throat-mic ASR
  fine-tuning instead.
- The device only hears the wearer's own tissue vibration, not room audio
  — that's a real privacy *feature* worth calling out, not just a
  limitation.

## Contents

| doc | covers |
|---|---|
| [`docs/architecture.md`](docs/architecture.md) | system diagram, data flow, the four transport modes |
| [`docs/pcb-plan.md`](docs/pcb-plan.md) | wearable node PCB + Pi Zero hub HAT, block-level schematic plan |
| [`docs/bom.md`](docs/bom.md) | sourcing tables — AliExpress/Alibaba/Micro Center/B&H/Seeed/Adafruit/RadioShack |
| [`docs/prototype-plan.md`](docs/prototype-plan.md) | phased build plan, signal-first |
| [`docs/risks.md`](docs/risks.md) | feasibility, legal, regulatory, safety notes |
| [`firmware/esp32/monologue_node/`](firmware/esp32/monologue_node/) | ESP32 sensor-node firmware skeleton |
| [`gateway/pi_zero/`](gateway/pi_zero/) | Pi Zero hub/gateway skeleton (Python) |
| [`apps/macos-daemon/`](apps/macos-daemon/) | macOS receiver daemon skeleton (Swift) |
| [`apps/ios-keyboard/`](apps/ios-keyboard/) | iOS custom keyboard + notes-loop app architecture |

## One-paragraph architecture

Two or three contact-mic pads (choker: throat, both sides of larynx;
ear piece: mastoid/temple) feed an analog front end into an **ESP32-S3**
sensor node, which does on-device VAD and streams lightly compressed audio
over BLE and/or WiFi to a **Raspberry Pi Zero 2 W** hub (worn or pocketed).
The hub buffers, denoises, and routes: over a private mTLS WLAN socket to
a paired iPhone/iPad/Mac (primary path), relayed as iMessage/SMS/RCS text
through the paired phone when there's no shared network, or — for a
specific "hand this transcript to the Linux box across the room without
touching RF" case — out an IR optical link to a photodiode receiver
plugged into that box. On the Apple side, a macOS daemon and an iOS custom
keyboard + notes app take transcript text/audio and either type it into
the focused field or append it to a running transcript log.
