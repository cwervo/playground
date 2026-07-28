# PCC4E Discovery Protocol (v1, draft)

This is the wire format used by the `mDNS`-transport prototypes in `go/` and `zig/`. It is
**not** full RFC 6762/6763 (DNS-SD) — it's a minimal multicast announce protocol in the same
spirit (link-local multicast, periodic self-announcement, no central server) that's small enough
to reimplement identically in multiple languages and, later, port onto constrained transports
(IR, audio modem) that can't carry real DNS packets. A follow-up milestone is swapping this for
wire-compatible mDNS/DNS-SD so PCC4E nodes show up in normal `dns-sd`/`avahi-browse` tooling; this
prototype validates the node model and framing first.

## Transport

- IPv4 multicast group: `239.255.77.77`
- UDP port: `7777`
- TTL: 1 (link-local only, by default)

`239.255.77.0/24` is in the IPv4 Organization-Local Scope range (RFC 2365 admin-scoped), which is
the right place for a prototype like this to squat rather than the real mDNS group
(`224.0.0.251`), so these nodes never get confused with real DNS-SD traffic on a shared network.

## Message format

Newline-delimited JSON, one message per UDP datagram:

```json
{
  "v": 1,
  "type": "announce",
  "node_id": "3f9a1c...",
  "name": "laptop-a",
  "caps": ["compute", "relay"],
  "pubkey": "ab12ef...",
  "port": 9443,
  "ts": 1753700000
}
```

| Field     | Type       | Meaning                                                              |
|-----------|------------|-----------------------------------------------------------------------|
| `v`       | int        | Protocol version, `1`                                                 |
| `type`    | string     | `"announce"` (only message type in v1)                                |
| `node_id` | hex string | Random 16-byte node identifier, generated at startup                  |
| `name`    | string     | Human-readable label                                                  |
| `caps`    | string[]   | Advertised capabilities, e.g. `compute`, `relay`, `attest`            |
| `pubkey`  | hex string | Placeholder for the node's attestation/identity key (not real crypto in v1) |
| `port`    | int        | TCP port the node will eventually offer the data-plane API on         |
| `ts`      | int        | Unix timestamp the announce was sent                                  |

A node sends an announce every 2 seconds and considers a peer gone if no announce is seen for 6
seconds (3 missed beacons).

## What's deliberately NOT here yet

- No attestation — `pubkey` is a random placeholder, not verified.
- No encryption — this is discovery only, not the data plane.
- No unicast query/response (real mDNS lets you ask "who has X"); v1 is announce-only.

Both `go/` and `zig/` implement exactly this format so a Go node and a Zig node discover each
other on the same multicast group.
