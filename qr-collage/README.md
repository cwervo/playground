# QR Collage

A tiny static web app: pick N photos from your camera roll, optionally type a
link or some text, drag a QR code around on top, and download a 9:16 PNG
(1080 × 1920, or 2160 × 3840) ready for stories / reels / vertical screens.

Everything happens in the browser. No uploads, no build step, no dependencies
beyond the vendored `qrcode.js` (MIT, by Kazuhiko Arase).

## Run it

Open `index.html` directly, or serve the folder:

```sh
cd qr-collage && python3 -m http.server 8000
```

then visit http://localhost:8000 (on a phone, use your computer's LAN IP).

## How it works

- **Photos** are decoded with `createImageBitmap` (EXIF orientation respected),
  downscaled to at most 2400 px, laid out cover-cropped in a grid that
  auto-picks a column count for the 9:16 frame. You can force 1–4 columns,
  reorder, remove, and tweak gap / margin / background.
- **QR** is generated locally from the text field. Empty text means no QR.
  Drag it to move, drag its corner or pinch to resize, or use the snap buttons.
  Error-correction level and the white frame are configurable.
- **Export** draws the collage and QR at full resolution with pixel-snapped
  modules so the code stays scannable, then downloads a PNG. On phones that
  support file sharing, a "Share / Save to Photos" button is shown too.
