# folkWallet — NFC / BLE Device Identity (UI mockup)

A self-contained UI mockup for an **iOS / iPadOS** app that broadcasts a
unique `folkDevice` hardware identifier over **NFC** and **Bluetooth LE**, and
can also present that identifier as a **QR code rendered through a Metal-style
GPU shader** so the code blends into whatever surface the device is laid on.

Open `index.html` in any browser — no build step, no dependencies.

## What's in the mockup

- **Identity tab** — the folkDevice hero card (Secure Enclave-signed ID),
  live NFC / BLE broadcast toggles with pulsing radio indicators, and a
  nearby-peers list (RSSI, GATT/NFC handshake state).
- **Blend QR tab** — a WebGL shader that renders the folkDevice ID as a
  QR-like code and melts/refracts it over a sampled backdrop. Three blend
  modes (Chroma Melt, Liquid Glass, Ink Bloom), blend/flow sliders, and
  backdrop swatches. This is the browser stand-in for the on-device Metal
  shader that would sample the camera/surface under the iPad or iPhone.
- **Device tab** — hardware info, security policy (token rotation, Face ID to
  share), and radio policy settings.

Framed as an iPhone-class device with a Dynamic Island, status bar, and tab
bar; it also fills the viewport on a real phone screen.

## Notes for the eventual native app

- The QR here is a deterministic *visual* stand-in (finder patterns + hashed
  modules), not a spec-valid QR — swap in a real generator for production.
- The "backdrop" is procedural noise; on-device this would be the live camera
  feed / surface sample driving the Metal fragment shader.
- Identifier, token rotation, and Face ID gating are mocked in the UI only.
