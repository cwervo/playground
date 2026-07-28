# Risks, feasibility, legal/regulatory notes

## Feasibility

- **Biggest unknown is the signal, not the electronics.** Contact mics on
  throat/jaw/temple pick up the acoustic vibration of subvocalized or
  whispered speech — heavily low-pass filtered by tissue and bone, low
  amplitude, and prone to picking up chewing/swallowing/head-motion noise
  as well as speech. This is a real, previously-demonstrated signal
  domain (tactical throat mics, whisper ASR research) but it is not a
  solved off-the-shelf product — expect real iteration on placement,
  gain staging, and denoising before ASR accuracy is usable. `prototype-
  plan.md` phase 0/1 exist specifically to find this out cheaply.
- **This is not an EMG/neural silent-speech interface.** Devices like
  MIT's AlterEgo read surface EMG (muscle electrical activity), a
  different sensor and signal entirely, and can pick up truly silent
  (no vibration) articulation. A contact mic cannot do that — there has
  to be some vibration to sense. Don't oversell "silent" in the product
  framing; "very quiet" is the honest claim.
- **No existing labeled dataset** for throat/mastoid contact-mic
  subvocal speech at the scale a general ASR model needs. Plan on
  self-collecting a wearer-specific corpus (phase 1) and fine-tuning a
  small existing model (whisper.cpp tiny/base) rather than training from
  scratch or expecting a stock ASR model to work unmodified.
- **Standard noise-suppression models (RNNoise etc.) assume an air-mic +
  room-noise model** and may not transfer well to the contact-mic
  transfer function. Budget time to either retrain/tune an enhancement
  stage or find it's unnecessary once the AFE bandpass is dialed in.

## Safety

- **IR "laser" link — eye safety is the actual constraint, not a
  formality.** Any free-space optical transmitter needs to stay within
  IEC 60825-1 Class 1 (safe under all conditions) or Class 1M (safe for
  bare eye, unsafe if viewed through collecting optics) limits. This is
  exactly why `pcb-plan.md` recommends a standards-based IrDA transceiver
  (already engineered to be eye-safe) over a bare high-power IR LED/laser
  diode, and why the bare-LED fallback explicitly calls for redoing the
  eye-safety math before building it. Do not substitute an actual
  laser-pointer-class diode without that analysis.
- **Batteries against skin**: source LiPo cells from a vendor that does
  UL/IEC certification (Adafruit-grade), not the cheapest AliExpress
  listing, for anything worn against the neck or behind the ear. This is
  the one BOM line item where the price premium is non-negotiable.
- **Contact mic pressure/placement**: sustained pressure against the
  throat or mastoid for long wear periods needs real ergonomic iteration
  (phase 3's "wear it for a full day" exit criteria exists for this
  reason) — not just a signal-quality question but a comfort/skin-contact
  one.

## Regulatory

- **Intentional radiators (WiFi/BLE)**: using pre-certified modules
  (ESP32-S3-MINI-1, Pi Zero 2 W's onboard radio) keeps the design under
  their existing FCC/CE certification as long as antenna design and RF
  power stay within the module's certified conditions — don't modify
  antenna matching without re-checking this.
- **IrDA/optical link**: not an RF intentional radiator, but is subject to
  the laser/LED safety standard above regardless of "it's just an LED."
- **SMS/RCS**: neither iMessage nor carrier SMS/RCS has a public
  "send-as" API for third-party hardware. The realistic phase-1 design
  (relay through the paired phone's own Messages app via Shortcuts
  automation) avoids this entirely. An independent cellular-modem path
  (own SIM, own number) needs a carrier account or an aggregator API
  (Twilio-class) and its own compliance (10DLC registration for
  application-to-person SMS in the US, etc.) — treat as a phase-2+
  stretch goal, not a phase-1 requirement.

## Privacy / consent

- The device by design only picks up the wearer's own tissue vibration,
  not ambient room audio — worth stating explicitly in any product
  framing, since "wearable mic" reads as room-surveillance-adjacent to
  most people at first mention.
- The "full notes loop" continuous-transcription mode is still recording
  the wearer's own speech continuously; treat it like any other
  always-listening wearable for data handling (local-first processing,
  clear on/off state, no silent background operation) even though it
  can't pick up other people's speech.
- If any recorded corpus (phase 1+) is ever shared, reviewed, or used
  beyond the wearer's own device, that's a different consent/privacy
  situation than a private on-device transcript — handle deliberately,
  don't default into it.
