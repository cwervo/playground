# pcc4e-node (Zig)

Zig port of the PCC4E discovery protocol reference implementation (`../proto/DISCOVERY.md`),
wire-compatible with `../go`. Uses raw POSIX sockets (`std.posix`) for multicast join/send/recv
and a small hand-rolled JSON scanner instead of `std.json`, since we only ever need to read a
fixed set of keys out of announces whose shape we control.

Built and run with **Zig 0.14.1** (via the `ziglang` PyPI package, since this sandbox's egress
policy blocks `ziglang.org` directly but allows PyPI):

```
pip install ziglang==0.14.1
```

## Build

```
python3 -m ziglang build
```

Produces `zig-out/bin/pcc4e-node`.

## Run

Configuration is via environment variables (Zig's process-args API is unstable across recent
versions, env vars aren't):

```
PCC4E_NAME=my-node PCC4E_PORT=9444 ./zig-out/bin/pcc4e-node
```

- `PCC4E_NAME` — advertised node name (default `zig-node`)
- `PCC4E_PORT` — advertised data-plane port (default `9444`)
- `PCC4E_RUN_FOR_SECONDS` — exit after N seconds; default runs forever

## Real output

Same 8-second, 3-node run as `../go/README.md`, this time from the Zig node's perspective —
discovering both Go peers over the same multicast group:

```
$ PCC4E_NAME=zig-node-1 PCC4E_PORT=9444 PCC4E_RUN_FOR_SECONDS=8 ./zig-out/bin/pcc4e-node
pcc4e-node zig-node-1 (195ec07804e3826c) up — data-plane port 9444, group 239.255.77.77:7777
discovered peer go-node-2    id=a2c914b16e28f666 caps=["compute","relay"] port=9445
discovered peer go-node-1    id=fdb5071cffb2405f caps=["compute","relay"] port=9443

=== zig-node-1 (195ec07804e3826c) final peer table ===
  go-node-1    id=fdb5071cffb2405f caps=["compute","relay"] port=9443
  go-node-2    id=a2c914b16e28f666 caps=["compute","relay"] port=9445
```

Note the `node_id`s match across both READMEs (`fdb5071cffb2405f`, `a2c914b16e28f666`,
`195ec07804e3826c`) — same run, three processes, two languages, one wire format.
