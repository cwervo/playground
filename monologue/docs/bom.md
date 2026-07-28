# Sourcing / BOM

Split by what you actually need fast-turnaround NYC-reachable retail for
(Micro Center, B&H, Adafruit's NYC-adjacent shipping, RadioShack.com) vs.
what's fine coming from a warehouse supplier (AliExpress/Alibaba/Seeed)
because you're ordering 10+ of it anyway. Prices are ballpark USD, single-
unit, July 2026 — re-check before ordering, these move.

## Compute / MCU

| part | qty | source | notes |
|---|---|---|---|
| ESP32-S3-MINI-1 module (or DevKitC-1 for phase 1-2 breadboarding) | 3-4 | Adafruit (DevKit) / AliExpress or Digi-Key-via-Seeed (bare module for PCB) | breadboard on the DevKit first, don't design Board A around the bare module until phase 1 signal validation passes |
| Raspberry Pi Zero 2 W | 1-2 | Micro Center (in-stock pickup, avoids Pi-shortage shipping delays) / Adafruit | get 2 — one stays a known-good dev unit |

## Analog front end

| part | qty | source | notes |
|---|---|---|---|
| Piezo contact mic capsule (disc-style, ~20-27mm) | 5-10 | AliExpress (cheap, bulk, for iteration) | this is the actual "throat mic" sensing element — buy several, placement matters more than the specific part |
| Electret bone-conduction contact mic (alternative to piezo) | 3-5 | Adafruit / AliExpress | electret needs bias voltage + different front-end gain than piezo — pick one family early, don't design for both |
| OPA2333 low-noise low-bias op-amp | 10 | Digi-Key/Mouser (via Adafruit or direct) | charge-amp/buffer stage; TL072 as a cheaper stand-in for early breadboard work |
| ADS1115 4-channel 16-bit ADC breakout | 2 | Adafruit | phase-1/2 external ADC option, before committing to onboard ESP32 ADC or an I2S ADC |
| PCM1808 I2S ADC breakout | 1-2 | AliExpress / Sparkfun-equivalent | if audio-rate/low-noise sampling is needed after phase 1 testing |
| Passives (resistors, film caps, ferrites) | assorted | RadioShack.com (still operates as an online parts retailer) or Micro Center | grab an assortment kit rather than ordering piecemeal |

## Power

| part | qty | source | notes |
|---|---|---|---|
| LiPo 3.7V 100-300mAh (choker/ear-piece scale) | 4-6 | Adafruit (UL-tested cells, worth the premium for anything worn against skin) | do not source wearable batteries from AliExpress — get certified cells for anything against the body |
| MCP73831 LiPo charger breakout | 4 | Adafruit | |
| AP2112K-3.3 LDO breakout | 4 | Adafruit / AliExpress | |
| MAX17048 fuel gauge (optional) | 2 | Adafruit | nice-to-have for battery-life tuning later, not phase 1 |

## Hub (Pi Zero) add-ons

| part | qty | source | notes |
|---|---|---|---|
| Vishay TFDU4101 IrDA transceiver (or equivalent) | 2-3 | AliExpress / Digi-Key via Mouser | preferred over a bare IR LED — already eye-safe, already does modulation |
| High-power 940nm IR LED + lens, photodiode + OPA380 TIA (fallback if IrDA range is insufficient) | 1 set | AliExpress (LED/photodiode) + Digi-Key (OPA380) | only if IrDA-class range proves too short; do the eye-safety math in `risks.md` before building this variant |
| SIM7600-class cellular modem HAT | 1 | Seeed Studio | only if phase-2+ phone-independent SMS/RCS becomes a hard requirement |
| USB-C power/charging breakouts, boost converters | assorted | Adafruit | |

## Mechanical / wearable

| part | qty | source | notes |
|---|---|---|---|
| Flexible polyimide PCB prototyping (for Board A rev2) | per design | Seeed Studio Fusion (flex-PCB service) or PCBWay (also fast to NYC) | order after rev1 rigid board proves the schematic |
| Rigid PCB fab, 2-layer, phase-4 rev1 | per design | JLCPCB or PCBWay | either has ~1 week to NYC options |
| JST-SH 1.0mm connector kit | 1 | AliExpress | mic-pad and battery connectors |
| Choker strap materials (fabric, snap fasteners) | — | any craft/fabric supplier, or B&H if going with an off-the-shelf camera-strap-style base | not really an "electronics retailer" item, but relevant to the wearable build |
| Small enclosure stock / heat-shrink / Sugru-equivalent | — | Micro Center / B&H | for phase 3 perfboard prototype housing |

## Bench/tools (if not already on hand)

| part | source | notes |
|---|---|---|
| USB oscilloscope or entry bench scope | Micro Center / B&H | phase 0 signal validation is scope-first, don't skip this |
| Hot air rework + fine-tip iron | Micro Center | for the rigid-flex ear-piece assembly later |
| JLCPCB/PCBWay stencil + reflow (or hand-solder for low pin-count rev1) | — | ESP32-S3-MINI-1 is a castellated-edge module, hand-solderable on a rev1 board if pads are laid out generously |
