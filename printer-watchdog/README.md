# printer-watchdog

A nightly cron job for `folk-SVA` that keeps its printer reachable on a network
with **no mDNS**.

## The problem

The SVA IT WiFi doesn't pass multicast DNS, and it hands out DHCP leases that
move the printer around. Both halves of that hurt:

- `folk-printer.local` never resolves, so any queue set up as `dnssd://…` (which
  is what CUPS picks by default when you add a printer at home) is dead on
  arrival, and any Folk program that hard-codes a `.local` name fails too.
- Even a queue pinned to a numeric IP goes stale the next time the printer's
  lease changes, and CUPS quietly *pauses* the queue after it fails to connect.
  Jobs then pile up with no error anywhere the room can see.

So every morning the printer looks broken, and the fix is someone finding the
new IP by hand.

## The fix

`folk-printer-watchdog` re-derives the printer's address from the one thing DHCP
cannot change — its **MAC address** — and repairs CUPS to match. Each run:

1. makes sure `cupsd` is up (starts it if not);
2. finds the printer's current IP, trying in order: last known good IP, the
   configured fallback, the MAC in the kernel's ARP/neighbour table, and finally
   an `arp-scan` or parallel ping sweep of the local subnet to refresh it;
3. verifies the candidate really is the printer — the printer port has to answer
   *and* the MAC at that address has to match, so a laptop that inherited the
   printer's old lease never gets promoted into the queue;
4. rewrites the queue's `device-uri` with `lpadmin` if the address moved;
5. `cupsenable`/`cupsaccept`s a queue that CUPS paused when the old address
   stopped answering;
6. pins `folk-printer.local` to the current IP in `/etc/hosts`, so programs that
   still ask for the `.local` name keep working without mDNS.

It changes nothing when nothing is wrong, and it's safe to run by hand any time
the printer stops answering.

## Install (on folk-SVA)

```sh
git clone https://github.com/cwervo/playground.git
cd playground/printer-watchdog
sudo ./install.sh            # add --at-boot to also run one minute after boot
```

That installs `/usr/local/bin/folk-printer-watchdog`, seeds
`/etc/folk-printer-watchdog.conf`, and adds this to root's crontab:

```
0 0 * * * /usr/local/bin/folk-printer-watchdog --quiet # folk-printer-watchdog
```

It runs as root because `lpadmin` and `/etc/hosts` need it, and because a ping
sweep is a lot faster from `arp-scan`.

## Configure

Edit `/etc/folk-printer-watchdog.conf`. One row per printer:

```
# QUEUE        MAC                  PORT  NAME                 FALLBACK_IP
folk-printer   3c:2a:f4:00:00:00    9100  folk-printer.local   192.168.1.50
```

To get the two values that matter:

```sh
lpstat -v                             # queue names and their current device-uri
ping -c1 <printer-ip>; ip neigh show <printer-ip>   # the MAC, while it's reachable
```

The MAC is also on the printer's own network-config printout. Use `-` for any
optional field. `PORT` picks the URI style: `9100` → `socket://IP:9100`,
`631` → `ipp://IP/ipp/print`, `443` → `ipps://IP/ipp/print`.

Settings can go at the top of the same file as `KEY=value`:
`SCAN_INTERFACE`, `MAX_SWEEP_HOSTS`, `PIN_HOSTS`, `FLUSH_STUCK_JOBS`.

## Testing: an emulated SVA network

`test/emulate.sh` runs the watchdog against a real, if miniature, version of the
problem — no mocks anywhere in the path under test:

```sh
sudo ./test/emulate.sh          # build the lab, run every scenario, tear down
sudo ./test/emulate.sh up       # leave it running
sudo ./test/emulate.sh shell    # a shell on the emulated folk-SVA machine
```

It builds three machines out of Linux network namespaces, joined by a bridge
that plays the part of the AP:

```
  folk-SVA  ----+                        +----  the printer
  cupsd         |                        |      cupsd :631  (real IPP)
  avahi         +---  bridge (the AP) ---+      jetdirect :9100
  watchdog      |     drops mDNS         |      avahi (real Bonjour)
                |                        |      MAC 3c:2a:f4:ab:cd:01
                +---  a laptop that grabs the printer's old DHCP lease
```

Everything the watchdog touches is real: real `cupsd` on both ends, real
`lpadmin`/`lpstat`/`cupsenable`, real ARP tables, real ping sweeps, real Avahi
daemons, real IPP transactions, and real job bytes captured at the device. Each
machine gets its own mount and UTS namespace, so "no mDNS on folk-SVA" is
genuinely no mDNS and not a shared socket in disguise. SVA mode is the bridge
refusing to forward multicast to 224.0.0.251 — which is exactly what the real
network does, and everything else follows from it.

The scenarios, all asserted end to end:

| # | Scenario | What it proves |
|---|----------|----------------|
| 1 | The network itself | mDNS resolves on a normal network and stops resolving in SVA mode, while ARP still finds the printer's MAC |
| 2 | The queue you set up at home | `ipp://folk-printer.local`, `socket://folk-printer.local:9100` and a `dnssd://` queue are all repaired to numeric addresses, and a real job reaches the device |
| 3 | Nothing wrong | A healthy queue is left completely alone |
| 4 | The DHCP lease moves | Found again by MAC via a real ARP sweep, queue un-paused, `.local` name resolving again with no mDNS, and the job queued overnight prints itself |
| 5 | A laptop takes the old address | The watchdog refuses the impostor and finds the real printer by MAC; the job goes to the printer, not the laptop |
| 6 | The printer is switched off | No guessing, no thrashing: the queue is left as-is and the run exits non-zero; when the printer returns on a new address it is repaired |

The lab needs root (network namespaces) and, on Debian/Ubuntu:

```sh
apt-get install iproute2 iputils-ping cups cups-daemon cups-client \
                cups-filters avahi-daemon dbus
```

Note the `cups` package specifically: on Ubuntu, `cups-daemon` alone ships only
the `ipp` backend, so `socket://` queues fail with "Bad device-uri scheme". If
folk-SVA prints to port 9100, it needs `cups` installed too.

### What the emulation found

Three real defects, each fixed and then re-tested:

- **The IPP resource path was being thrown away.** Rewriting
  `ipp://folk-printer.local:631/printers/FolkPrinter` as `ipp://10.42.0.50/ipp/print`
  points at an address that answers and a path that doesn't exist, so the queue
  looks repaired and prints nothing. The watchdog now keeps the scheme and path
  and substitutes only the address, and warns when it has to guess a path for a
  `dnssd://` queue that never had one.
- **A DHCP squatter could be adopted.** The old check asked "where is the
  printer's MAC?", which answers nothing when the ARP table is empty — and
  nothing was treated as agreement, so whatever host inherited the printer's old
  lease would have been written into the queue. It now verifies the MAC *at* the
  address it is about to use, and rejects an address it cannot confirm.
- **Discovery gave up without a default route.** The subnet search only looked
  at the default route's interface, so a Folk machine reaching the printer over
  a second link (or with the WiFi default route down) would never scan the
  subnet the printer was actually on. It now searches every interface with an
  IPv4 address, best first.

## Check it

```sh
sudo folk-printer-watchdog --dry-run --verbose   # says what it would change
sudo folk-printer-watchdog --verbose             # does it
sudo folk-printer-watchdog folk-printer          # just one queue
tail -f /var/log/folk-printer-watchdog.log       # what the nightly run did
```

Exit status is non-zero if any printer could not be found or repaired, so cron
will mail the failure if the machine has mail set up.

## When it can't help

- **AP/client isolation.** If SVA's WiFi stops clients from talking to each
  other, nothing on the machine can reach the printer and no script fixes that —
  the log will show every candidate address closed. Wire the printer and the
  Folk machine to the same switch, or ask IT for a DHCP reservation.
- **A different subnet.** The scan only covers the machine's own subnet. If the
  printer lives elsewhere, give it a `FALLBACK_IP` (ideally a reservation).
- **A huge subnet.** Sweeping is skipped above `MAX_SWEEP_HOSTS` (1024) so the
  job can't spend the night pinging a /16; ARP-table and fallback lookups still
  run. Raise it if you know the network is quiet.
- **The queue doesn't exist yet.** The watchdog repairs queues, it doesn't guess
  drivers. Create it once, then it stays fixed:
  `sudo lpadmin -p folk-printer -E -v socket://<ip>:9100 -m everywhere`

The real cure is a DHCP reservation from SVA IT. This is the thing that keeps
printing working until then.
