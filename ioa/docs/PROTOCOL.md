# IOAF/1 — the wire frame

One frame format crosses every medium in the line. Wi-Fi, ESP-NOW, BLE, LoRa,
infrared, Li-Fi, laser, HDMI, USB, UART and Ethernet all carry the same
28-byte header; only the MTU changes, and fragmentation absorbs that
difference. This is the entire reason a 250-byte ESP-NOW packet and a
1472-byte Wi-Fi datagram can appear on the same route.

Implementation: [`lib/frame.tcl`](../lib/frame.tcl). Tests:
[`tests/frame.test`](../tests/frame.test).

## Header

28 bytes, big-endian, no alignment padding.

| offset | size | field | notes |
|---|---|---|---|
| 0 | 4 | `magic` | `IOAF` |
| 4 | 1 | `version` | 1 |
| 5 | 1 | `type` | 0 hello, 1 media, 2 ctrl, 3 ack, 4 telemetry, 5 bye, 6 fec |
| 6 | 1 | `flags` | see below |
| 7 | 1 | `codec` | 0 raw, 1 mjpeg, 2 h264, 3 h265, 4 av1, 5 rgb565, 6 gray8, 7 jpegxl |
| 8 | 2 | `stream` | many streams may share one link |
| 10 | 4 | `seq` | picture number, not fragment number |
| 14 | 2 | `frag` | index of this fragment within the picture |
| 16 | 2 | `nfrag` | fragments in this picture |
| 18 | 4 | `ts` | source milliseconds, wrapping |
| 22 | 2 | `len` | payload bytes in this frame |
| 24 | 4 | `crc32` | over the payload only |

Flags: `0x01` keyframe, `0x02` fragment of a larger picture, `0x04` final
fragment, `0x08` FEC-protected, `0x10` encrypted.

The payload is opaque. ioa never parses a JPEG or an H.264 NAL — the `codec`
field exists so the sink knows which decoder to hand the bytes to, and that is
the extent of its interest.

## Fragmentation

The header comes out of the MTU, not on top of it:

```
room   = mtu - 28
nfrag  = ceil(picture_bytes / room)
```

For a 720p30 MJPEG picture — 59.6 KiB — that is 43 fragments over Wi-Fi and
**276 over ESP-NOW**. The second number is the one that matters.

## Why a low MTU is a delivery problem, not a bandwidth problem

Lose any one fragment and the whole picture is gone. With independent
per-packet loss `p`, a picture of `n` fragments arrives with probability
`(1-p)^n`:

| link | picture | fragments | packet loss | picture delivery |
|---|---|---|---|---|
| Wi-Fi, 1472 B MTU | 720p30, 59.6 KiB | 43 | 0.05% | 97.8% |
| ESP-NOW, 250 B MTU | 720p30, 59.6 KiB | 276 | 1.22% | **3.4%** |
| ESP-NOW, 250 B MTU | QVGA5, 2.25 KiB | 11 | 1.22% | 87.4% |

(Reproduce with `tclsh` over `lib/`, or read them off `ioa plan`'s hop table.)

A datasheet calls 1.2% packet loss reliable. At 276 fragments per picture it
delivers one frame in thirty. The planner computes this before you install
anything — [`lib/budget.tcl`](../lib/budget.tcl), `ioa::budget::hop`.

## Forward error correction

The fix is redundancy, not retransmission: at 30 fps a NAK round trip has
already missed its deadline. A FEC ratio of `r` sends `ceil(n*r)` packets, of
which `ceil(n*r) - n` are repair symbols, and the picture survives if no more
than that many packets are lost. Delivery is then the binomial tail

```
P(X <= repair),  X ~ Binomial(sent, p)
```

computed exactly in `ioa::budget::binomCdf`. The planner tries
`1.0, 1.1, 1.25, 1.5, 2.0` and takes the cheapest ratio that clears the
delivery target, or refuses the link if none does. That refusal is deliberate:
a 900-fragment picture at 15% loss is unrecoverable at any redundancy worth
sending, and saying so is more useful than shipping something that stutters.

Wire cost is accounted honestly — data fragments pay the payload plus a
28-byte header each, repair symbols are always full-width:

```
wire_bytes = picture_bytes + nfrag * 28 + repair * mtu
```

## Reassembly

The reassembler holds partial pictures keyed by `seq`, emits one the moment
its last fragment lands, and evicts anything still incomplete once newer
sequence numbers have moved past it by more than the window (default 4
pictures). Stalled pictures are dropped rather than kept: for live video, a
frame that arrives late is worse than a frame that never arrives, because it
costs the buffer that the next one needed.

Duplicates are counted and discarded — half-duplex media with retries deliver
them routinely.

## Failure modes, and what each one raises

Every rejection carries a Tcl `-errorcode` so a transport can tell "corrupt,
drop it" from "not one of ours":

| errorcode | meaning |
|---|---|
| `IOA FRAME RUNT` | fewer bytes than a header |
| `IOA FRAME MAGIC` | not an IOAF frame; some other protocol on this port |
| `IOA FRAME VERSION` | IOAF from a newer implementation |
| `IOA FRAME TRUNC` | declared length exceeds what arrived |
| `IOA FRAME CRC` | payload corrupted in flight — drop, do not hand it up |
| `IOA FRAME MTU` | this medium cannot carry a header plus useful payload |
| `IOA FRAME TOOBIG` | payload over 65535; fragment before packing |

A torn picture must never reach a decoder. `ioa run` deliberately corrupts one
frame per verified picture and asserts the CRC catches it.

## Control plane

Types `hello`, `ctrl`, `telemetry` and `bye` share the same header and travel
the same links, but the planner will route them over interfaces marked
`control` — the IR port on a camera, the UART on a Prism — which it refuses to
use for video. That separation is why the Beam exists: the channel you use to
fix a node should not be the channel you just broke.

## What IOAF/1 does not do

- **No encryption.** The flag is reserved; nothing implements it. Treat an ioa
  fabric as you would an unencrypted video feed on a LAN.
- **No retransmission.** FEC or nothing, on purpose.
- **No congestion control.** The planner sizes the stream to fit the link in
  advance and relays drop oldest-first when it does not. There is no feedback
  loop that reacts to queue growth.
- **No clock synchronisation.** `ts` is the source's own millisecond counter.
  Cross-node latency figures from `ioa run` are modelled, not measured.
