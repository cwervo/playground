# p2p-motion

Simulators of a **UW motion-triggered mini camera board** that wirelessly sends its
photos to a more powerful chip in the same room for storage and processing.

## The paper

**"Wireless steerable vision for live insects and insect-scale robots"**
Vikram Iyer, Ali Najafi, Johannes James, Sawyer Fuller, Shyamnath Gollakota —
University of Washington, *Science Robotics* Vol. 5, Issue 44 (July 15, 2020).
DOI: [10.1126/scirobotics.abb0839](https://www.science.org/doi/10.1126/scirobotics.abb0839) ·
[UW News](https://www.washington.edu/news/2020/07/15/robotic-camera-backpack-for-insects/) ·
[code from the authors](https://github.com/uw-x/insect-robot-cam)

Key details the memory in the prompt maps to:

- **"motion-powered"** → an onboard **accelerometer wakes the camera only when the
  beetle moves**, stretching battery life from ~1–2 h to 6+ h. (Capture is
  motion-*triggered*; the sim also adds an optional motion-*harvesting* energy model
  so you can play with a fully motion-powered node.)
- **"WiFi, Bluetooth??? IR????"** → it's **Bluetooth**: frames stream to a
  smartphone/base station up to ~120 m away. The sim lets you switch between
  BLE / WiFi / IR (IR requires line of sight) to compare.
- **"mini camera board"** → the whole steerable camera + radio payload weighs
  **248 mg** and shoots **160×120 monochrome** at 1–5 fps.
- **"more powerful chip in the same room"** → the phone/base station stores and
  processes the imagery. The related UW lineage,
  [WISPCam](https://sensor.cs.washington.edu/research/wisp_1) (Naderiparizi et al.,
  IEEE RFID 2015), is a fully **battery-free RF-powered** camera that backscatters
  images to a reader in the room — if that's the one you were thinking of, the same
  node→hub simulation applies.

## What's here

| File | What it is |
|---|---|
| `index.html` | Single-file, network-last web simulator. All CSS/JS inline; zero external requests; works from `file://`. Every received JPEG persists on-device in **localStorage** (with a quota budget + oldest-first eviction). |
| `P2PMotionSim.swiftpm/` | The same simulator as a Swift Playgrounds **app package** — open the folder in Swift Playgrounds on iPad (or Xcode) and press Run. Photos persist on-device as JPEG files in the app's Documents directory. |

## The simulation

A beetle (with the orange camera backpack) random-walks a room with obstacles;
its "accelerometer" reads gait + jerk:

1. **SLEEP** — node naps, harvesting energy (motion harvest + ambient trickle).
2. **WAKE** — accel exceeds the wake threshold.
3. **CAPTURE** — renders the beetle's 160×120 grayscale first-person view
   (with sensor noise + vignette) and JPEG-compresses it at your chosen quality.
4. **TX** — the JPEG is split into link-MTU packets (BLE 244 B / WiFi 1400 B /
   IR 64 B) and streamed to the hub; loss grows with distance, IR drops to zero
   behind obstacles; lost packets are retried and every packet costs energy.
5. **HUB** — reassembles, logs, persists the photo, and offers Sobel/CIEdges
   edge extraction in the photo viewer.

Play with: link type, JPEG quality, wake threshold, harvest rate, extra packet
loss, pausing, nudging the beetle, or tapping/clicking the room to send it
somewhere. Note the tradeoffs the paper is about: capture only on motion, keep
frames tiny, and let the big chip in the room do the heavy lifting.

*Storage choice: the web version uses localStorage (kept single-file; a web-worker
SQLite would require embedding a multi-MB sql.js wasm blob to stay network-last).*
