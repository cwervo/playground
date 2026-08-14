# Necker cube device chart

A 3-axis Cartesian chart drawn as a Necker cube in true one-point perspective,
with Matplotlib in plain 2D — the pinhole projection is hand-rolled. The data
is normalized onto a unit cube; the camera sits just outside the origin corner
(nudged off the exact diagonal so correlated points don't collapse onto the
vanishing point) and is aimed at (1, 1, 1), which projects the far corner to
the exact center of the frame. All 12 cube edges are drawn — the classic
overlapping-squares Necker ambiguity — and depth is carried by
perspective-scaled dot sizes plus each point's dashed drop to the z=0 floor.

Axes use the classic R/G/B convention:

- **X (red)** — price, USD
- **Y (green)** — feature count
- **Z (blue)** — power needs, estimated typical active draw (mA, WiFi on,
  backlight on where present)

Dots are color- and shape-coded by kind of device.

```sh
python3 chart.py   # writes esp32-necker-light.png and esp32-necker-dark.png
```

![light mode chart](esp32-necker-light.png)

## Data

Street prices and current draw are approximate (August 2026); feature count is
the length of the feature list.

| Device | Kind | Price (USD) | Features (count) | Est. active draw (mA) |
|---|---|---:|---:|---:|
| LILYGO T-Display | Screen dev board | 18 | 1.14″ LCD, WiFi, BT, LiPo charge (4) | 180 |
| LILYGO T-Display-S3 | Screen dev board | 23 | 1.9″ LCD, touch, WiFi, BLE 5, LiPo charge (5) | 210 |
| LILYGO T-Display S3 Long | Screen dev board | 32 | 3.4″ LCD, touch, WiFi, BLE 5, LiPo charge (5) | 260 |
| LILYGO T-Display-Bar | Screen dev board | 30 | 2.25″ LCD, touch, WiFi, BT, TF slot, LiPo charge (6) | 260 |
| LILYGO T-Dongle-S3 | Screen dev board | 19 | 0.96″ LCD, WiFi, BT, TF slot, RGB LED (5) | 170 |
| LILYGO T-RGB | Smart display panel | 37 | 2.1″ round IPS, touch, WiFi, BT, TF slot, LiPo charge (6) | 300 |
| LILYGO T-Panel S3 | Smart display panel | 50 | 3.95″ IPS, touch, WiFi, BT, TF slot, RS-485 (6) | 450 |
| Adafruit Feather ESP32-C6 | Headless dev board | 15 | WiFi 6, BLE 5, Zigbee/Thread, LiPo charge, STEMMA QT, NeoPixel (6) | 100 |
| Adafruit Metro ESP32-S2 | Headless dev board | 20 | WiFi, 30+ GPIO, STEMMA QT, LiPo charge, NeoPixel (5) | 140 |

Edit the `DEVICES` list in `chart.py` to add boards or correct numbers, or
`CAM` to move the camera — the renders update from it. An earlier 45°
axonometric version of this chart lives in the git history.
