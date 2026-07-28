# PCB plan

Two boards. Neither is designed in this pass (no EDA tool run here) — this
is the block-level plan an actual KiCad schematic should follow, written
so phase 4 (`prototype-plan.md`) can go straight to layout.

## Board A — wearable sensor node (choker / ear piece)

One design, two enclosures. Same schematic, different flex outline and
mic-pad placement.

### Blocks

```
[contact mic ×1-3] -> [DC block + charge/instrumentation amp] -> [2nd-stage gain]
   -> [anti-alias LPF ~4kHz] -> [ESP32-S3 ADC or external I2S ADC] -> [ESP32-S3]
                                                                          |
                              [LiPo 3.7V] -> [MCP73831 charger] -> [AP2112-3.3 LDO]
                                                     |
                                            [status LED, on/off switch]
```

- **MCU**: ESP32-S3-MINI-1 (castellated module — WiFi + BLE5, native USB,
  enough GPIO/ADC for 2-3 mic channels, small enough for an ear piece).
  Avoid the plain ESP32 ADC's known noise/nonlinearity for anything beyond
  breadboard testing.
- **Analog front end (per channel)**: piezo/electret contact mic pads are
  high-impedance sources — buffer with a low-noise, low-bias-current
  op-amp (TI OPA2333 or a TL072 for the cheap/breadboard rev) configured
  as a charge amp for piezo elements or a simple non-inverting gain stage
  for electret contact mics, second gain stage to hit the ADC's full
  scale, then a 2nd-order anti-alias low-pass around 4 kHz (tissue/bone
  conduction rolls off well below normal 8 kHz speech bandwidth, so don't
  over-spec the ADC rate here).
- **Better-than-onboard-ADC option**: if the ESP32's ADC noise floor is a
  problem (very likely once you're past breadboard), add an external
  ADC — either a simple SPI/I2C one (ADS1115, 4 channels, slow but easy)
  or an I2S audio ADC (PCM1808) if you want proper audio-rate sampling
  with low noise. Decide after phase 0/1 signal validation, not before.
- **Power**: single-cell LiPo (~100-300 mAh depending on enclosure),
  MCP73831 linear charger (USB-C input), AP2112K-3.3 LDO for the analog
  and digital 3.3V rail (keep analog and digital 3.3V rails separately
  filtered/ferrite-isolated on the PCB — this is a low-level analog signal
  board, layout discipline matters more than component choice).
- **Connectors**: JST-SH 1.0mm for mic pads (so pads can be replaced/
  repositioned without resoldering the board) and for the battery; pogo
  pads or a small magnetic pogo connector for charging without a port on
  the choker itself.
- **Form factor**:
  - *Choker*: flexible polyimide PCB strip, 2-3 mic pads distributed
    around the throat/larynx, main rigid island (MCU + AFE + battery) at
    the back of the neck or on a small pendant.
  - *Ear piece*: small rigid-flex board behind the ear (hearing-aid-scale),
    single mic pad against the mastoid/temple, battery in the ear-hook
    body. This is the harder mechanical build — plan it after the choker
    proves the signal chain works.

## Board B — Pi Zero 2 W hub HAT

A 40-pin HAT, not a full custom carrier — the Pi already has WiFi/BLE, the
HAT only needs to add what the Pi doesn't have.

### Blocks

```
[Pi Zero 2 W 40-pin header]
   -> [IR transceiver: TFDU4101-class SIR/FIR, or IR LED + photodiode TIA]
   -> [power path: USB-C in / LiPo + boost-to-5V, load-share]
   -> [optional cellular modem (SIM7600-class) for phone-independent SMS/RCS — phase 2+ stretch]
   -> [status LED, user button (push-to-talk / mode select)]
```

- **IR transceiver**: prefer a standards-based IrDA transceiver module
  (Vishay TFDU4101 or similar) over a bare laser diode — it's already
  eye-safe by design, already does the modulation/demodulation, and talks
  UART to the Pi directly. Only drop to a bare high-power 940nm IR LED +
  photodiode/TIA (OPA380-class transimpedance amp on the receive side) if
  you need more range than IrDA gives you, and if so budget real time for
  the eye-safety analysis in `risks.md` before building it.
- **Power**: USB-C primary input; if the hub needs to be untethered from
  wall power, a small LiPo + boost converter feeding the Pi's 5V rail,
  sized against the Pi Zero 2 W's ~250-450 mA typical draw plus whatever
  the IR/cellular add-ons pull.
- **Cellular modem**: only needed if "hub sends SMS/RCS without a nearby
  paired phone" is a hard requirement — see `architecture.md`'s transport
  table. Treat as a separate HAT revision, not board-B-v1.

## What phase 1 (`prototype-plan.md`) should validate before either board
is laid out

1. Contact mic + AFE actually produces a usable, intelligible-when-played-
   back signal from throat and from mastoid/temple placement, on a scope
   and by ear, before any MCU is involved.
2. ESP32 ADC noise floor vs. external ADC — decide which analog front end
   ships on Board A rev1.
3. BLE vs. WiFi power/bandwidth tradeoff for the always-on link, measured,
   not assumed.
