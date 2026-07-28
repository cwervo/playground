# pcc4e-node (Go)

Reference implementation of the PCC4E discovery protocol (`../proto/DISCOVERY.md`) in Go, using
only the standard library (`net.ListenMulticastUDP`).

## Build

```
go build -o pcc4e-node ./cmd/pcc4e-node
```

## Run

```
./pcc4e-node -name my-node -port 9443
```

Flags:

- `-name` — advertised node name (defaults to hostname)
- `-port` — advertised data-plane port (default `9443`)
- `-caps` — comma-separated capability list (default `compute,relay`)
- `-run-for` — exit after a duration (e.g. `10s`); default runs forever

## Real output

Two Go nodes plus one Zig node (`../zig`) run for 8 seconds on the same host, discovering each
other over the `239.255.77.77:7777` multicast group:

```
$ ./pcc4e-node -name go-node-1 -port 9443 -run-for 8s
2026/07/28 13:02:23 pcc4e-node go-node-1 (fdb5071cffb2405f) up — data-plane port 9443, group 239.255.77.77:7777
2026/07/28 13:02:23 discovered peer go-node-2    id=a2c914b16e28f666 caps=[compute relay] port=9445 addr=192.0.2.2
2026/07/28 13:02:25 discovered peer zig-node-1   id=195ec07804e3826c caps=[compute relay] port=9444 addr=192.0.2.2

=== go-node-1 (fdb5071cffb2405f) final peer table ===
  go-node-2    id=a2c914b16e28f666 caps=[compute relay] port=9445
  zig-node-1   id=195ec07804e3826c caps=[compute relay] port=9444
```

See `../zig/README.md` for the matching Zig-side output from the same run.
