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
