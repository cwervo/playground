# How the Amazon / Whole Foods "In-Store Code" QR is generated

Findings from decoding the In-Store Code QR shown by the Amazon app on the
Whole Foods Market tab: two screenshots (14:38:47 and 14:39:02 EDT) and a
28.5 s screen recording (starting 14:39:10 EDT), all from 2026‑09‑11.
Eleven distinct codes were recovered in total.

The source screenshots and recording are **not** committed: they show the
account holder's name, card details, and live payment codes. Identity and
signature bytes below are partially redacted for the same reason.
`decode_instore_code.py` reproduces every field from an image or a base64
string.

## 1. The symbol

| Property | Value |
|---|---|
| Barcode | QR Code, symbology identifier `]Q1` |
| Version | 7 (45 × 45 modules; measured 7‑module finder patterns at ≈11.3 px/module over a 510 px side) |
| Error correction | M |
| Encoding mode | Byte mode: the payload is standard base64 text (`+`, `/`, `=` present, so not URL‑safe) |
| Text length | 120 characters, decoding to 89 bytes |
| Presentation | Drawn rotated 45° (a diamond). Readers report orientation 45°; the rotation is cosmetic and decodes normally |

Version 7 is the smallest version that holds 120 bytes at level M
(capacity 122), so the generator is simply letting the QR library pick the
minimum size.

## 2. Payload layout (89 bytes)

```
offset  len  field                                     observed
------  ---  ----------------------------------------  ------------------------------
  0      3   magic                                     "AMZ"  (41 4D 5A)
  3      1   format version                            0x01
  4      4   issued‑at, Unix seconds, big‑endian       0x6AA44AC6 = 1789151942 = 2026‑09‑11 18:39:02Z
  8     16   RFC 4122 v4 UUID                          e9ba…8ced (identical in all 11 codes)
 24      1   unknown, constant                         0x00
 25     64   authenticator (randomised)                different in every code
```

Evidence for each field:

- **Timestamp.** The two screenshots carry `…4AC6` and `…4AB7`, 15 s apart,
  and each decodes to the exact minute:second shown on the phone's status bar
  once converted to EDT (UTC‑4). In the recording the field tracks the wall
  clock to the second while codes are regenerated (see §4), so it is an
  *issued‑at* time, not an expiry.
- **UUID.** The 16 bytes have the version nibble `4` and an RFC 4122 variant.
  It did not change between the "Payment method cannot be verified" state, the
  re‑selection of a card, and the later codes, so it identifies the account,
  device or registered key rather than a payment method or a session.
- **Byte 24.** Always `0x00`. Possibly a flags/type byte or an
  algorithm identifier; there is not enough variation in this sample to say.
- **Tail.** 64 bytes, byte‑entropy 7.74 bits over 704 bytes, no structure.

## 3. What the 64‑byte tail is (and is not)

The tail changes even when the 25 bytes before it do not: at 18:39:33Z the app
produced **three different codes with byte‑identical headers** and three
different tails (same again at :36 and :37). Therefore the tail is not a
deterministic function of the visible header. That rules out:

- HMAC of the header (SHA‑512 output is also 64 bytes, but it would repeat).
- Ed25519 (deterministic; additionally 7 of the 11 tails have a
  non‑canonical `s` half, which Ed25519 verifiers reject).
- Deterministic ECDSA (RFC 6979).

What remains consistent with 64 random‑looking bytes that differ per
signing operation:

1. **Randomised ECDSA over a 256‑bit curve, raw `r‖s`.** This is the most
   conventional fit: hardware‑backed keys on iOS (Secure Enclave) and Android
   (Keystore) are P‑256 ECDSA and produce a fresh `k` per signature. All 11
   tails satisfy `r, s < n` for P‑256, though that check is weak. The app would
   convert the platform's DER signature to fixed 64‑byte form before encoding.
2. A random nonce concatenated with a MAC (e.g. 16 + 48 or 32 + 32 bytes).
3. An encrypted blob with a random IV (e.g. AES‑GCM/CBC) carrying data the
   scanner cannot read.

Without a public key or secret none of these can be confirmed from the
payload alone; option 1 is the working assumption in the rest of this
document.

## 4. When and where codes are generated

Timeline reconstructed from the recording (wall clock = 14:39:10 + video
time; the recording's start is only known to the second):

| Video time | Wall clock (EDT) | Observation |
|---|---|---|
| 0.0 – 16.25 s | 14:39:10 – :26 | Same code as screenshot 2 (issued 14:39:02). No rotation for ≥ 24 s. |
| 16.5 – 20.5 s | :26 – :30 | User opens "Select a payment method", re‑selects the ****9180 card, taps Continue. |
| 21.0 s | :31 | "Generating code" spinner, under 250 ms. |
| 21.27, 22.13, 22.47, 22.77, 23.13 s | :31 – :33 | Five fresh codes, ≈0.3–0.9 s apart, timestamps :31, :32, :33, :33, :33. |
| 23.13 – 24.87 s | :33 – :35 | Code held; then a horizontal page transition hides it. |
| 25.70, 26.27, 26.67, 27.00 s | :36 – :37 | Four fresh codes ≈0.3–0.6 s apart. |
| 27.0 – 28.5 s | :37 – :38 | Code held to end of recording. |

Conclusions:

- **Generation is on‑device at display time.** The issued‑at field follows the
  phone's clock to sub‑second precision and up to three codes were produced
  within one second. A batch of pre‑signed codes fetched from a server would
  carry fetch‑time timestamps, not display‑time ones, and a network round trip
  per code at 3 Hz is implausible. This also matches a device‑held signing key
  (§3, option 1) whose public key Amazon registered at enrolment under the
  UUID.
- **There is no fixed rotation timer.** A code sat unchanged for at least
  24 s, yet during and after the payment‑method flow codes were re‑issued in
  bursts every 0.3–0.4 s. The bursts line up with view re‑renders (sheet
  dismissal, the "Generating code" state, a page transition), which suggests
  the code view calls the generator on every render rather than on a
  schedule. This is an inference from behaviour, not from code.
- **The payment method is not in the code.** Structure, UUID and length were
  identical before and after the card was fixed; the card shown under the
  code is UI state. The point‑of‑sale must resolve the account and its chosen
  in‑store payment method server‑side after verifying the code.

## 5. Inferred verification model

1. The register scans the QR and forwards the 89‑byte payload to Amazon.
2. Amazon looks up the UUID → registered public key (or shared secret).
3. It verifies the 64‑byte authenticator over the 25‑byte header.
4. It checks the issued‑at timestamp against an acceptance window and,
   presumably, rejects replays of an already‑used code.
5. It maps the UUID to the customer account and charges the default in‑store
   payment method (or opens a Dash Cart session).

Practical consequence: within its acceptance window the QR is a bearer
credential for the account's payment method. Screenshots of it should be
treated like a photo of a payment card and the acceptance window is unknown,
so they should not be shared.

## 6. Open questions

- Meaning of byte 24 (`0x00`).
- The exact signature scheme (§3) and the curve/hash used.
- The server‑side freshness window for the timestamp.
- Whether the UUID is per account, per device, or per enrolled key
  (a second device on the same account would settle this).

## 7. Method

- QR decoding: `zxing-cpp` via OpenCV, on the two PNG screenshots and on
  frames extracted from the HEVC recording at 4 fps (whole clip) and 30 fps
  (the 20.5–28.6 s burst).
- Symbol version: minimal‑version capacity table cross‑checked by measuring
  the finder‑pattern run lengths (1‑1‑3‑1‑1 modules) in the rotated image.
- Field analysis: byte‑wise diff across the 11 payloads, UUID version/variant
  check, timestamp cross‑check against the on‑screen clock, Ed25519
  canonical‑`s` and ECDSA range checks on the tails, byte entropy.
