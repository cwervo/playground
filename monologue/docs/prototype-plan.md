# Prototype plan

Sequenced so the highest-uncertainty question — is the sensed signal
usable at all — gets answered before any PCB spend, and so every later
phase only adds one new unknown at a time.

## Phase 0 — Signal validation (breadboard, no MCU)

Contact mic → op-amp charge amp/buffer → bandpass filter, straight into a
scope and into a normal audio interface for recording. Try throat, larynx
side, and mastoid/temple placement. Listen to the recordings. This phase
answers the only question that actually matters before committing to
anything else: does subvocalized/whispered speech through this sensor at
this placement come out intelligible (even quietly/muffled) once amplified
and filtered? If no placement gives a usable signal, stop and rethink the
sensor before writing a line of firmware.

**Exit criteria**: recorded clips a second person can partially transcribe
by ear, or that a stock Whisper model gets partial credit on without any
fine-tuning.

## Phase 1 — Wired MCU prototype

Same AFE, now digitized by an ESP32 DevKitC-1 and streamed over USB-serial
to a laptop for recording. This is where the real dataset-building starts
— record a wearer-specific corpus (read sentences, both throat and
mastoid placement) for later ASR fine-tuning. Also A/B the onboard ESP32
ADC against an ADS1115/PCM1808 external ADC here — decide the Board A
analog front end from measured noise floor, not from the datasheet.

**Exit criteria**: a fine-tuned whisper.cpp (tiny/base) run against the
recorded corpus gets a word error rate you're willing to build a wearable
around. This number gates everything after it.

## Phase 2 — Wireless breadboard

Add BLE/WiFi streaming from the ESP32 DevKit to a Pi Zero 2 W dev board.
Stand up the private-WLAN mTLS socket and get transcript text flowing to
a Mac. This phase is almost entirely de-risking the software path
(`architecture.md` data flow steps 3-6) before anything is wearable.

**Exit criteria**: end-to-end latency (mouth movement → text on Mac
screen) measured and acceptable; BLE/WiFi power draw measured against a
target battery life.

## Phase 3 — Hand-wired wearable

First thing actually worn: contact mics hot-glued/fabric-mounted on a
choker strap, perfboard AFE + ESP32 DevKit riding in a small pouch. Ugly
on purpose — the goal is wearing it through a real day and finding out
what placement/strain/sweat/motion problems phase 0-2 couldn't surface on
a bench.

**Exit criteria**: a full worn day without the signal degrading past
usability, and a placement/strain-relief design that survives it.

## Phase 4 — Custom PCB rev1 (rigid)

Board A from `pcb-plan.md`, fabbed as a 2-layer rigid board (JLCPCB/
PCBWay), still in a chest-worn-puck form factor rather than a true choker.
First board where the ESP32-S3-MINI-1 module and the chosen ADC path are
soldered rather than dev-kitted.

**Exit criteria**: bench-verified signal chain matches or beats the
perfboard version; firmware ported cleanly to the module.

## Phase 5 — Custom PCB rev2 (flex/rigid-flex)

True choker and ear-piece form factors — flexible polyimide strip for the
choker, small rigid-flex board for the ear piece. This is the mechanically
hard phase; budget real iteration time (enclosure, strain relief at the
flex-to-rigid boundary, sweat/moisture sealing).

## Phase 6 — Hub HAT

Board B from `pcb-plan.md` — IR transceiver + power path on a Pi Zero 2 W
HAT. Independently testable from the wearable side; can happen in parallel
with phase 5.

## Phase 7 — Apple-side software + closed alpha

macOS daemon and iOS custom keyboard/notes app (see `apps/`) come online
against the phase-2 protocol, which shouldn't have changed shape since.
Fine-tune ASR on wearer-specific data collected through phases 1-3. Closed
alpha with the full rev2 hardware once phases 4-6 land.

## What not to parallelize

Don't start PCB layout (phase 4+) before phase 1's exit criteria — if the
WER off a wired prototype isn't good enough to be useful, the PCB spend
and the ear-piece mechanical design are wasted regardless of how good the
board is.
