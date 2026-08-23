# Fitbit Inspire 3 — sensors, timing, and biofeedback surface

Notes on what you can actually build against a Fitbit Inspire 3, working as close to the
metal as the platform allows. Researched August 2026.

**TL;DR** — The Inspire 3 is the worst Fitbit for bespoke apps: it has *no app platform at
all*. The Fitbit OS SDK only ever targeted the smartwatches (Ionic, Versa 1/2/3, Sense — and
Sense 2 / Versa 4 got clock faces only). The tracker line (Inspire, Charge, Luxe) has no
on-device code execution, no sideloading, no developer bridge. So "bare metal adjacent" here
means: **cloud/phone-side code reading whatever the firmware chooses to emit, with the phone's
notification channel as your only actuator.**

Treat the device as a cheap, 10-day-battery *overnight physiology logger* with a coarse
remote-buzz output — not as a computer you can program.

---

## 1. Sensors — what the hardware physically has

| Sensor | Notes | Reachable by you? |
| --- | --- | --- |
| Optical PPG (green LEDs + photodiodes) | Continuous HR, HRV, breathing rate, AFib / irregular-rhythm detection | Only as derived metrics — **raw PPG is not exposed on any Fitbit**, SDK devices included |
| Red + IR LEDs (SpO2) | Blood-oxygen estimation; firmware runs this **only during sleep** | Nightly SpO2 series only |
| 3-axis accelerometer | Steps, cadence, sleep staging, auto-exercise detection, wrist raise | Aggregated (1-min / 15-min activity), never raw g-values |
| Skin/device temperature sensor | Reports *variation from personal baseline*, computed over a multi-night baseline, sleep-only | Nightly delta value, no absolute °C |
| Ambient light sensor | Auto-brightness only | **Not exposed at all** |
| Vibration motor (haptic) | The only output actuator besides the OLED | Indirectly, via phone notifications |
| BLE 5.0 radio | Proprietary Fitbit GATT profile | See §4 |

**Not present** (rules out a lot of ideas): no gyroscope, no barometer/altimeter (so no floors),
no GPS (connected-GPS borrows the phone's radio), no EDA/cEDA, no ECG electrodes, no mic, no
speaker, no NFC, no Wi-Fi, no on-demand temperature reading.

---

## 2. Timing — the four clocks that govern you

### (a) Firmware sampling cadence — fixed, not configurable

- **HR**: continuous PPG, ~1 Hz internally; denser during a started exercise session.
- **SpO2, HRV, breathing rate, skin-temp variation**: **sleep-window only**, once per night.
- **AFib / irregular rhythm**: opportunistic during stillness, mostly overnight.
- **Steps / activity**: 1-minute buckets.
- **Stress Management Score, Sleep Score, Cardio Fitness**: computed once, available next morning.

### (b) Sync cadence — your real latency floor

The tracker buffers on-device and auto-syncs over BLE roughly every 15–30 min when the phone is
near with All-Day Sync on. A manual pull-to-sync in the app gets you to ~5–30 s. **Nothing you
write can force a sync remotely.**

### (c) API retrieval resolution

| Metric | Best resolution | Path |
| --- | --- | --- |
| Heart rate | 1 sec or 1 min (Fitbit intraday); Google Health returns ~8,700 samples/day ≈ 10 s | Fitbit Intraday / Google Health v4 |
| Steps / activity | 1 min / 15 min | intraday |
| HRV | 5-min intervals across the sleep window | HRV Intraday |
| SpO2 | ~1 min during sleep | SpO2 Intraday |
| Breathing rate | per sleep stage, nightly | summary + limited intraday |
| Skin temp variation | 1 value/night | summary only |

Gates worth knowing: intraday access for *your own* data is automatic under a "Personal" app;
other users' intraday data is approved case-by-case. Legacy Fitbit Web API also caps at
150 req/hr/user.

### (d) Platform clock — this one bites right now

The **Fitbit Web API sunsets 30 September 2026.** Google Health API
(`health.googleapis.com/v4/`) is the replacement: new OAuth, mandatory user re-consent, no token
migration, webhook subscriptions with a 7-day retry backlog. Build anything new directly
against v4.

### Realistic end-to-end loop latencies

| Loop | Latency |
| --- | --- |
| Nightly / next-morning metrics | ~6–10 h (unavoidable — those sensors only run during sleep) |
| Cloud closed loop (HR/steps in → haptic out) | ~15–60 min typical; ~2–5 min if the user manually syncs |
| Sub-10-second loop | **Impossible on this device. No exceptions.** |

---

## 3. Biofeedback — what you can actually build

The only actuator is the vibration motor, and the only way to reach it is **phone notification
forwarding**: post a local notification from your own Android/iOS app, whitelist that app in
Fitbit notification settings, and the tracker buzzes ~1–3 s later.

Caveats: no control over haptic pattern or intensity, suppressed by Do Not Disturb / sleep mode,
rate-limited, and the on-device Relax breathing exercise cannot be launched programmatically.
The Web API alarm endpoints don't help either — newer trackers like the Inspire 3 use an
on-device alarm app instead and don't support those endpoints.

### Feasible loop archetypes, tightest to loosest

1. **Notification-haptic nudge loop (~15–60 min).** Poll HR/steps, decide server-side, fire a
   phone notification → wrist buzz. Sedentary-break prompts, "your HR has been elevated for
   20 min, breathe", habit pacing. This is the closest thing to interactive biofeedback the
   device supports.
2. **Session-scoped exercise loop.** User starts an exercise on-device → denser HR sampling →
   post-session analysis and a summary buzz. Retrospective *within* the workout, not during it.
3. **Nightly recovery loop.** HRV (5-min RMSSD series) + resting HR + SpO2 + skin-temp delta +
   breathing rate → your own readiness score, delivered as a morning notification, an e-ink
   display, a Folk page, whatever. **This is where the Inspire 3 is genuinely strong** — a
   research-grade overnight autonomic panel for $100.
4. **Ambient / environmental biofeedback.** Wrist data drives something in the room (lights,
   sound, projection) rather than the wrist. Sidesteps the actuator limitation entirely;
   latency budget is the sync interval.
5. **Longitudinal / behavioral.** Multi-week HRV trend vs. sleep debt vs. skin-temp anomalies
   (illness / cycle detection). No latency constraint at all.

### What you cannot build

Paced-breathing HRV coherence training with live feedback, real-time HR-zone audio, live HR on
a screen, biofeedback games — anything that reacts to a heartbeat as it happens.

---

## 4. The "bare metal" frontier — how deep you can actually go

Ordered by depth, with honest verdicts:

- **Google Health API v4 / Fitbit Web API** — highest-fidelity *legally supported* access.
  Webhooks fire on sync. Use this.
- **Health Connect on Android** — the Fitbit app writes into Health Connect, so you can read
  on-device without a cloud round trip. Narrower data-type set (no skin-temp variation, spotty
  HRV), still sync-bound.
- **Companion Android app** — the practical "bare metal adjacent" position: read via Health
  Connect, actuate via local notifications, all on-device, no server.
- **BLE / proprietary GATT.** Fitbit trackers advertise `adabXXXX-6e7d-4601-bda2-bffaa68956ba`
  with a notify characteristic (`...fb03...`) used for live transfer. The payloads are the
  classic **microdump/megadump** frames, AES-128 encrypted with a per-device key provisioned by
  Fitbit's servers — reverse-engineered in *Breaking Fitness Records without Moving* (RAID'17)
  and follow-on firmware work. Current status for modern devices: the Gadgetbridge Fitbit effort
  gets through the DTLS/CoAP pairing bootstrap but stalls on the `/sync/response` body, which
  appears to need a server-side secret. **Local-only sync is not achievable today.** Also, the
  Inspire 3 does *not* support standard BLE Heart Rate Profile broadcast — that's Charge 6-only
  — so there is no sanctioned live-HR stream to grab.
- **Firmware / JTAG-SWD.** Signed and encrypted images; published key-extraction work targets
  the Flex/One/Charge generation, nothing public for the Inspire 3. The device is glued and
  potted — you'd destroy it before getting a shell. Not a viable project.

### If your idea needs a real-time loop, change the device

Ranked by how much control you get:

1. **Any BLE chest strap or optical armband speaking standard HRP.** A Polar H10 gives you raw
   RR intervals and even raw ECG over BLE — the correct choice for HRV coherence biofeedback.
2. **Charge 6** — if you must stay in the Fitbit ecosystem and only need live HR broadcast.
3. **Used Versa 3 / Sense** — an actual on-device app with the Fitbit SDK sensor set
   (Accelerometer, Gyroscope, Orientation, Barometer, HeartRateSensor at 1 Hz,
   BodyPresenceSensor) plus haptic patterns and a screen.
4. **Wear OS / Garmin ConnectIQ** — a genuinely programmable wrist platform.

---

## Sources

- [Fitbit Inspire 3 technical specs (Google Store)](https://store.google.com/product/fitbit_inspire_3_specs?hl=en-US)
- [Notebookcheck — Inspire 3 launch specs](https://www.notebookcheck.net/Fitbit-Inspire-3-launches-with-an-OLED-display-SpO2-and-skin-temperature-monitor-capabilities-for-US-99-95.642707.0.html)
- [DC Rainmaker — Inspire 3 in-depth review](https://www.dcrainmaker.com/2022/10/fitbit-inspire-review.html)
- [Fitbit Web API — Intraday](https://dev.fitbit.com/build/reference/web-api/intraday/)
- [Fitbit Web API — HRV Intraday by Date](https://dev.fitbit.com/build/reference/web-api/intraday/get-hrv-intraday-by-date/)
- [Fitbit Web API — Get Alarms (device support caveat)](https://dev.fitbit.com/build/reference/web-api/devices/get-alarms/)
- [Google Health API — migration overview](https://developers.google.com/health/migration)
- [Google Health API — webhook subscriptions](https://developers.google.com/health/webhooks)
- [Sahha — Fitbit Web API shutdown and migration](https://sahha.ai/blog/fitbit-api-sunset-migration/)
- [Terra — how the new Google Health API works](https://tryterra.co/blog/everything-you-need-to-know-about-google-health-new-api)
- [9to5Google — Fitbit third-party dev is watch faces, not apps](https://9to5google.com/2023/02/17/fitbit-studio/)
- [Breaking Fitness Records without Moving (RAID'17)](https://arxiv.org/pdf/1706.09165)
- [Gadgetbridge — Fitbit device support issue #504](https://codeberg.org/Freeyourgadget/Gadgetbridge/issues/504)
- [Google Health Help — share real-time heart rate with equipment](https://support.google.com/googlehealth/answer/14236705?hl=en)
