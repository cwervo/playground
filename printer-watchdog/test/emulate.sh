#!/bin/bash
#
# emulate.sh — run folk-printer-watchdog against an emulated SVA network.
#
# Nothing in the path under test is faked. This builds a real layer-2 network
# out of Linux network namespaces (real MACs, real ARP, a real bridge acting as
# the AP), boots a real CUPS server on each side, a real Avahi on each side,
# and a real AppSocket/JetDirect device on port 9100. The watchdog runs against
# real lpstat/lpadmin/cupsenable/ip/ping the whole way through.
#
#   +--------------+        +---------------------+        +----------------+
#   |  fpw-folk    |        |   fpw-net (bridge)  |        |  fpw-printer   |
#   |  "folk-SVA"  |--eth0--|  the SVA AP: drops  |--eth0--|  the printer   |
#   |  cupsd,avahi |        |  mDNS multicast     |        |  cupsd :631    |
#   |  + watchdog  |        |                     |        |  jetdirect:9100|
#   +--------------+        +---------------------+        |  avahi         |
#                                     |                    +----------------+
#                            +----------------+
#                            | fpw-squatter   |  a laptop that grabs the
#                            | different MAC  |  printer's old DHCP lease
#                            +----------------+
#
# "SVA mode" is the switch refusing to forward multicast to 224.0.0.251, which
# is what kills mDNS on the real network. Everything else follows from that.
#
# Usage:
#   sudo ./emulate.sh            build the lab, run every scenario, tear down
#   sudo ./emulate.sh up         build the lab and leave it running
#   sudo ./emulate.sh shell      a shell on the emulated folk-SVA machine
#   sudo ./emulate.sh down       tear the lab down

set -uo pipefail

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
WATCHDOG=$HERE/../folk-printer-watchdog
LAB=/run/fpw                      # short path: unix sockets cap out at 108 chars
PRINTER_MAC=3c:2a:f4:ab:cd:01     # the printer's stable identity
SQUATTER_MAC=8a:11:22:33:44:55
SUBNET=10.42.0
FOLK_IP=$SUBNET.10
PRINTER_IP=$SUBNET.50
PPD=/usr/share/ppd/cupsfilters/Generic-PDF_Printer-PDF.ppd

PASSED=0; FAILED=0

# --- output ----------------------------------------------------------------

if [ -t 1 ]; then B=$(printf '\033[1m'); G=$(printf '\033[32m'); R=$(printf '\033[31m'); D=$(printf '\033[2m'); N=$(printf '\033[0m')
else B=""; G=""; R=""; D=""; N=""; fi

scenario() { printf '\n%s== %s ==%s\n' "$B" "$*" "$N"; }
step()     { printf '%s   %s%s\n' "$D" "$*" "$N"; }
ok()       { PASSED=$((PASSED+1)); printf '   %sPASS%s %s\n' "$G" "$N" "$*"; }
bad()      { FAILED=$((FAILED+1)); printf '   %sFAIL%s %s\n' "$R" "$N" "$*"; }

assert_eq() { # what, expected, actual
    if [ "$2" = "$3" ]; then ok "$1"; else bad "$1"$'\n'"        expected: $2"$'\n'"        actual:   $3"; fi
}
assert_has() { # what, needle, haystack
    case "$3" in *"$2"*) ok "$1" ;; *) bad "$1"$'\n'"        expected to contain: $2"$'\n'"        got: $3" ;; esac
}
assert_not() { # what, needle, haystack
    case "$3" in *"$2"*) bad "$1"$'\n'"        should NOT contain: $2"$'\n'"        got: $3" ;; *) ok "$1" ;; esac
}
assert_rc() { # what, expected_rc, actual_rc
    if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected exit $2, got $3)"; fi
}

# --- node plumbing ---------------------------------------------------------
# Each emulated machine is a process holding a network namespace AND a mount
# namespace, so it gets its own /run/dbus, /run/avahi-daemon and /etc/hosts —
# without that, the two machines would share one Avahi through the filesystem
# and "no mDNS" could not be emulated honestly.

start_node() { # ns, name, hostname [, extra setup command]
    local ns=$1 name=$2 host=$3 extra=${4:-true}
    mkdir -p "$LAB/$name"
    cp /etc/hosts "$LAB/$name/hosts"
    ip netns exec "$ns" unshare --mount --uts --propagation private -- sh -c "
        hostname $host
        $extra
        mount -t tmpfs none /run/dbus
        mount -t tmpfs none /run/avahi-daemon
        mount --bind $LAB/$name/hosts /etc/hosts
        echo \$\$ > $LAB/$name.pid
        exec sleep infinity" >/dev/null 2>&1 &
    local i=0
    while [ ! -s "$LAB/$name.pid" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done
    [ -s "$LAB/$name.pid" ] || { echo "node $name failed to start" >&2; exit 1; }
}

node() { # name, command...
    local name=$1; shift
    nsenter -t "$(cat "$LAB/$name.pid")" -m -n -u -- "$@"
}

folk()    { node folk env CUPS_SERVER=$LAB/folk/cups.sock "$@"; }
printer() { node printer env CUPS_SERVER=$LAB/printer/cups.sock "$@"; }

start_avahi() { # name, hostname
    local name=$1 host=$2
    cat > "$LAB/$name/avahi.conf" <<CONF
[server]
host-name=$host
use-ipv4=yes
use-ipv6=no
allow-interfaces=eth0
[publish]
publish-addresses=yes
publish-hinfo=no
publish-workstation=no
CONF
    node "$name" dbus-daemon --system --fork >/dev/null 2>&1
    sleep 1
    node "$name" avahi-daemon -f "$LAB/$name/avahi.conf" -D >/dev/null 2>&1
    sleep 2
}

start_cupsd() { # name, extra Listen line
    local name=$1 listen=$2
    local root=$LAB/$name
    mkdir -p "$root/etc" "$root/spool/tmp" "$root/state" "$root/cache" "$root/log" "$root/received"
    chmod 1770 "$root/spool/tmp"
    cat > "$root/etc/cups-files.conf" <<CONF
ServerRoot $root/etc
DataDir /usr/share/cups
DocumentRoot /usr/share/cups/doc-root
RequestRoot $root/spool
StateDir $root/state
CacheDir $root/cache
TempDir $root/spool/tmp
AccessLog $root/log/access_log
ErrorLog $root/log/error_log
PageLog $root/log/page_log
Printcap $root/printcap
FileDevice Yes
CONF
    cat > "$root/etc/cupsd.conf" <<CONF
LogLevel warn
ErrorPolicy stop-printer
JobRetryInterval 5
JobRetryLimit 20
Listen $root/cups.sock
$listen
Browsing Off
WebInterface No
DefaultShared Yes
<Location />
  Order allow,deny
  Allow all
</Location>
<Location /admin>
  Order allow,deny
  Allow all
</Location>
CONF
    node "$name" /usr/sbin/cupsd -c "$root/etc/cupsd.conf" >>"$root/log/cupsd.out" 2>&1
    local i=0
    while ! node "$name" env CUPS_SERVER="$root/cups.sock" lpstat -r >/dev/null 2>&1 && [ $i -lt 50 ]; do
        sleep 0.2; i=$((i+1))
    done
}

# --- the emulated network --------------------------------------------------

attach() { # ns, mac, cidr
    ip link add "p-$1" type veth peer name eth0 netns "$1"
    ip link set "p-$1" netns fpw-net
    ip netns exec fpw-net ip link set "p-$1" master br0 up
    ip netns exec "$1" ip link set eth0 address "$2"
    ip netns exec "$1" ip addr add "$3" dev eth0
    ip netns exec "$1" ip link set eth0 up
    ip netns exec "$1" ip link set lo up
}

sva_mode() { # on|off — the AP forwarding (or not) mDNS multicast
    local state=flood
    [ "$1" = on ] && state=off
    for port in p-fpw-folk p-fpw-printer p-fpw-squatter; do
        if [ "$1" = on ]; then
            ip netns exec fpw-net bridge link set dev "$port" mcast_flood off 2>/dev/null
        else
            ip netns exec fpw-net bridge link set dev "$port" mcast_flood on 2>/dev/null
        fi
    done
    step "network: mDNS multicast forwarding is now $([ "$1" = on ] && echo BLOCKED || echo allowed) ($state)"
}

move_printer() { # new ip — a new DHCP lease, same hardware
    ip netns exec fpw-printer ip addr flush dev eth0
    ip netns exec fpw-printer ip addr add "$1/24" dev eth0
    ip netns exec fpw-folk ip neigh flush all
    ip netns exec fpw-printer ip neigh flush all
    restart_jetdirect "$1"
    step "printer got a new DHCP lease: $1 (MAC still $PRINTER_MAC)"
}

restart_jetdirect() { # ip
    [ -s "$LAB/jetdirect.pid" ] && kill "$(cat "$LAB/jetdirect.pid")" 2>/dev/null
    node printer python3 "$HERE/jetdirect-device.py" --listen "$1" --port 9100 \
        --spool "$LAB/printer/jetdirect" >>"$LAB/printer/jetdirect.log" 2>&1 &
    echo $! > "$LAB/jetdirect.pid"
    sleep 1
}

squatter() { # on <ip> | off — a laptop that inherits the printer's old lease
    if [ "$1" = off ]; then
        [ -s "$LAB/squatter.pid" ] && kill "$(cat "$LAB/squatter.pid")" 2>/dev/null
        rm -f "$LAB/squatter.pid"
        return 0
    fi
    ip netns exec fpw-squatter ip addr add "$2/24" dev eth0 2>/dev/null
    ip netns exec fpw-squatter python3 -c '
import socket, sys, threading
def listen(port):
    s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind((sys.argv[1], port)); s.listen(5)
    while True:
        c, _ = s.accept(); c.close()
for p in (631, 9100):
    threading.Thread(target=listen, args=(p,), daemon=True).start()
threading.Event().wait()' "$2" >/dev/null 2>&1 &
    echo $! > "$LAB/squatter.pid"
    sleep 1
    step "a laptop ($SQUATTER_MAC) took over $2 and is answering on 631 and 9100"
}

# --- lab lifecycle ---------------------------------------------------------

preflight() {
    [ "$(id -u)" = 0 ] || { echo "must run as root (network namespaces)" >&2; exit 1; }
    local missing=""
    for c in ip nsenter unshare ping cupsd lpadmin lpstat lpinfo lp avahi-daemon dbus-daemon python3; do
        command -v "$c" >/dev/null 2>&1 || missing="$missing $c"
    done
    [ -f "$PPD" ] || missing="$missing $PPD"
    if [ -n "$missing" ]; then
        echo "missing:$missing" >&2
        echo "on Debian/Ubuntu: apt-get install iproute2 iputils-ping cups-daemon cups-client cups-filters avahi-daemon dbus" >&2
        exit 1
    fi
}

lab_up() {
    lab_down >/dev/null 2>&1
    mkdir -p "$LAB"
    step "building the emulated LAN"
    for ns in fpw-net fpw-folk fpw-printer fpw-squatter; do ip netns add "$ns"; done
    ip netns exec fpw-net ip link add br0 type bridge
    ip netns exec fpw-net ip link set br0 up
    attach fpw-folk     06:00:00:00:0f:01 $FOLK_IP/24
    attach fpw-printer  "$PRINTER_MAC"    $PRINTER_IP/24
    attach fpw-squatter "$SQUATTER_MAC"   $SUBNET.99/24

    # The printer's own backend set: the real ones plus a capture backend that
    # keeps the job bytes. Bind-mounted inside the printer's mount namespace,
    # so the machine running the tests is left alone.
    mkdir -p "$LAB/printer/backends"
    ln -sf /usr/lib/cups/backend/* "$LAB/printer/backends/" 2>/dev/null
    install -m 0700 "$HERE/capture-backend" "$LAB/printer/backends/capture"
    chmod 0755 "$LAB/printer/backends"

    start_node fpw-folk folk folk-sva
    start_node fpw-printer printer folk-printer \
        "mount --bind $LAB/printer/backends /usr/lib/cups/backend"

    step "booting the printer (avahi + cupsd on :631 + jetdirect on :9100)"
    start_avahi printer folk-printer
    start_cupsd printer "Port 631"
    printer lpadmin -p FolkPrinter -E -v "capture://$LAB/printer/received" \
        -P "$PPD" -o printer-is-shared=true 2>&1 | grep -v deprecated
    restart_jetdirect "$PRINTER_IP"

    step "booting folk-SVA (avahi + cupsd)"
    start_avahi folk folk-sva
    start_cupsd folk ""

    step "network is healthy for now; setting the printer up the way you would at home"
    sva_mode off
    sleep 2
    folk lpadmin -p folk-printer -E -v "ipp://folk-printer.local:631/printers/FolkPrinter" \
        -P "$PPD" 2>&1 | grep -v deprecated
    folk lpadmin -p folk-jetdirect -E -v "socket://folk-printer.local:9100" \
        -P "$PPD" 2>&1 | grep -v deprecated
    folk lpadmin -p folk-bonjour -E -v "dnssd://Folk%20Printer._ipp._tcp.local/cups" \
        -P "$PPD" 2>&1 | grep -v deprecated

    for q in folk-printer folk-jetdirect folk-bonjour; do
        folk lpadmin -p "$q" -o printer-error-policy=stop-printer 2>/dev/null
    done

    cat > "$LAB/folk/watchdog.conf" <<CONF
PIN_HOSTS=yes
folk-printer     $PRINTER_MAC   631    folk-printer.local   -
folk-jetdirect   $PRINTER_MAC   9100   -                    -
folk-bonjour     $PRINTER_MAC   631    -                    -
CONF
    mkdir -p "$LAB/folk/state"
}

lab_down() {
    for p in "$LAB"/*.pid; do [ -e "$p" ] && kill "$(cat "$p")" 2>/dev/null; done
    pkill -x cupsd 2>/dev/null; pkill -x avahi-daemon 2>/dev/null; pkill -x dbus-daemon 2>/dev/null
    pkill -f jetdirect-device.py 2>/dev/null
    sleep 1
    for ns in fpw-net fpw-folk fpw-printer fpw-squatter; do ip netns del "$ns" 2>/dev/null; done
    rm -rf "$LAB"
}

# --- things the tests ask the lab -----------------------------------------

uri_of()  { folk lpstat -v "$1" 2>/dev/null | sed -n 's/^device for [^:]*: //p'; }
state_of(){ folk lpstat -p "$1" 2>/dev/null | head -1; }

run_watchdog() {
    folk env FOLK_PRINTER_LOG="$LAB/folk/watchdog.log" FOLK_PRINTER_STATE="$LAB/folk/state" \
        "$WATCHDOG" -c "$LAB/folk/watchdog.conf" -v "$@" 2>&1
}

completed_jobs() { folk lpstat -W completed -o "$1" 2>/dev/null | wc -l; }

print_test_page() { # queue, marker  -> prints "ok" or an error
    local q=$1 marker=$2
    local f=$LAB/folk/job-$marker.txt
    echo "folk-SVA test page $marker $(date)" > "$f"
    local before; before=$(completed_jobs "$q")
    folk lp -d "$q" -t "$marker" "$f" >/dev/null 2>&1 || { echo "submit failed"; return 1; }
    local i=0
    while [ $i -lt 60 ]; do
        # count completions rather than looking for any completed job: an old
        # one from an earlier scenario would happily answer for this one
        [ "$(completed_jobs "$q")" -gt "$before" ] && { echo ok; return 0; }
        sleep 0.5; i=$((i+1))
    done
    echo "job never completed: $(folk lpstat -o "$q" 2>/dev/null | head -2)"
    return 1
}

device_received_bytes() { cat "$LAB"/printer/received/*.prn 2>/dev/null | wc -c; }

# The client calls a job complete once the transfer is done; the device still
# has to spool and print it. Give the hardware a moment, like real hardware.
device_got_more_than() { # bytes_before
    local i=0
    while [ $i -lt 40 ]; do
        [ "$(device_received_bytes)" -gt "$1" ] && return 0
        sleep 0.5; i=$((i+1))
    done
    return 1
}
jetdirect_got_more_than() { # jobs_before
    local i=0
    while [ $i -lt 40 ]; do
        [ "$(jetdirect_jobs)" -gt "$1" ] && return 0
        sleep 0.5; i=$((i+1))
    done
    return 1
}
jetdirect_jobs()        { wc -l < "$LAB/printer/jetdirect/received.log" 2>/dev/null || echo 0; }

# --- scenarios -------------------------------------------------------------

scenario_network() {
    scenario "1. The SVA network: mDNS is gone, ARP still works"
    step "healthy network first, as a control"
    sva_mode off; sleep 2
    local healthy; healthy=$(folk timeout 8 avahi-resolve -4 -n folk-printer.local 2>&1)
    assert_has "mDNS resolves folk-printer.local on a normal network" "$PRINTER_IP" "$healthy"

    step "now switch the AP into SVA mode"
    sva_mode on; folk avahi-daemon --kill >/dev/null 2>&1; start_avahi folk folk-sva; sleep 2
    local broken; broken=$(folk timeout 8 avahi-resolve -4 -n folk-printer.local 2>&1; echo "rc=$?")
    assert_not "mDNS no longer resolves folk-printer.local" "$PRINTER_IP" "$broken"
    local getent_out; getent_out=$(folk getent hosts folk-printer.local 2>&1; echo "rc=$?")
    assert_has "the machine cannot resolve the .local name at all" "rc=2" "$getent_out"

    step "but the printer is still right there on the wire"
    folk ping -c 2 -W 1 "$PRINTER_IP" >/dev/null 2>&1
    local arp; arp=$(folk ip neigh show "$PRINTER_IP")
    assert_has "ARP still sees the printer's real MAC" "$PRINTER_MAC" "$arp"
}

scenario_stale_name() {
    scenario "2. The queue set up at home is dead here (ipp://folk-printer.local)"
    assert_has "queue still points at the unresolvable name" "folk-printer.local" "$(uri_of folk-printer)"
    local before; before=$(print_test_page folk-printer before)
    assert_not "printing fails before the watchdog runs" "ok" "$before"

    step "running the watchdog"
    local out; out=$(run_watchdog); local rc=$?
    assert_rc "watchdog exits 0" 0 "$rc"
    assert_has "it reports the address change" "address moved" "$out"
    assert_eq "IPP queue now points at the printer's real address" \
        "ipp://$PRINTER_IP:631/printers/FolkPrinter" "$(uri_of folk-printer)"
    assert_eq "JetDirect queue too" "socket://$PRINTER_IP:9100" "$(uri_of folk-jetdirect)"
    assert_eq "the IPP resource path is preserved, not replaced with a guess" \
        "/printers/FolkPrinter" "/$(uri_of folk-printer | cut -d/ -f4-)"
    assert_not "the dead dnssd:// queue is gone" "dnssd" "$(uri_of folk-bonjour)"
    assert_has "and it warns that a dnssd queue's path had to be guessed" \
        "resource path may not be" "$out"

    step "and a real job now goes all the way to the device"
    local bytes_before; bytes_before=$(device_received_bytes)
    assert_eq "print job completes" "ok" "$(print_test_page folk-printer after)"
    device_got_more_than "$bytes_before" \
        && ok "the emulated printer actually received the job ($(device_received_bytes) bytes captured)" \
        || bad "device received nothing (still $bytes_before bytes)"
    local jd_before; jd_before=$(jetdirect_jobs)
    assert_eq "JetDirect job completes" "ok" "$(print_test_page folk-jetdirect jd)"
    jetdirect_got_more_than "$jd_before" \
        && ok "the JetDirect device logged the job: $(tail -1 "$LAB/printer/jetdirect/received.log")" \
        || bad "JetDirect device received nothing"
}

scenario_idempotent() {
    scenario "3. Nothing to fix: the watchdog stays out of the way"
    local uri_before; uri_before=$(uri_of folk-printer)
    local out; out=$(run_watchdog); local rc=$?
    assert_rc "watchdog exits 0" 0 "$rc"
    assert_not "it does not touch a healthy queue" "address moved" "$out"
    assert_eq "device-uri unchanged" "$uri_before" "$(uri_of folk-printer)"
}

scenario_dhcp_move() {
    scenario "4. Overnight the DHCP lease moves the printer"
    move_printer $SUBNET.77
    local completed_before; completed_before=$(completed_jobs folk-printer)
    step "let CUPS notice the queue is broken (this is what pauses it in the morning)"
    folk lp -d folk-printer "$LAB/folk/job-before.txt" >/dev/null 2>&1
    local i=0
    while [ $i -lt 30 ]; do
        case "$(state_of folk-printer)" in *disabled*) break ;; esac
        sleep 1; i=$((i+1))
    done
    case "$(state_of folk-printer)" in
        *disabled*) ;;
        *) step "this CUPS retries rather than pausing; pausing it as cupsd would"
           folk cupsdisable -r "Unable to connect" folk-printer ;;
    esac
    step "queue state: $(state_of folk-printer)"
    assert_has "CUPS paused the queue, as it does every morning" "disabled" "$(state_of folk-printer)"

    local out; out=$(run_watchdog); local rc=$?
    assert_rc "watchdog exits 0" 0 "$rc"
    assert_has "it hunts for the MAC on the subnet" "ARP hunt" "$out"
    assert_eq "IPP queue follows the printer to its new lease" \
        "ipp://$SUBNET.77:631/printers/FolkPrinter" "$(uri_of folk-printer)"
    assert_eq "JetDirect queue follows too" "socket://$SUBNET.77:9100" "$(uri_of folk-jetdirect)"
    assert_not "queue is no longer paused" "disabled" "$(state_of folk-printer)"

    step "the job that was queued overnight should now print itself"
    local queued_done=no i=0
    while [ $i -lt 60 ]; do
        [ "$(completed_jobs folk-printer)" -gt "$completed_before" ] && { queued_done=yes; break; }
        sleep 1; i=$((i+1))
    done
    assert_eq "the job queued while the printer was missing prints once repaired" yes "$queued_done"

    step "the .local name works again — on a network with no mDNS"
    local resolved; resolved=$(folk getent hosts folk-printer.local 2>&1)
    assert_has "folk-printer.local resolves to the new address" "$SUBNET.77" "$resolved"

    local bytes_before; bytes_before=$(device_received_bytes)
    assert_eq "printing works again" "ok" "$(print_test_page folk-printer moved)"
    device_got_more_than "$bytes_before" \
        && ok "the device received the job at its new address" \
        || bad "device received nothing after the move"
}

scenario_squatter() {
    scenario "5. A laptop takes the printer's old address"
    move_printer $SUBNET.123
    squatter on $SUBNET.77
    step "the watchdog's last-known address ($SUBNET.77) now answers — but it is not the printer"

    local out; out=$(run_watchdog); local rc=$?
    assert_rc "watchdog exits 0" 0 "$rc"
    assert_has "it notices the address is the wrong hardware" "not $PRINTER_MAC" "$out"
    assert_not "it does NOT point the queue at the laptop" "$SUBNET.77" "$(uri_of folk-printer)"
    assert_eq "it finds the real printer by MAC instead" \
        "ipp://$SUBNET.123:631/printers/FolkPrinter" "$(uri_of folk-printer)"

    local bytes_before; bytes_before=$(device_received_bytes)
    assert_eq "printing goes to the real printer" "ok" "$(print_test_page folk-printer squat)"
    device_got_more_than "$bytes_before" \
        && ok "the real device received the job, not the laptop" \
        || bad "device received nothing"
    squatter off
}

scenario_powered_off() {
    scenario "6. The printer is switched off"
    ip netns exec fpw-printer ip link set eth0 down
    step "printer unplugged from the network"
    local uri_before; uri_before=$(uri_of folk-printer)

    local out; out=$(run_watchdog); local rc=$?
    assert_rc "watchdog reports failure (cron will mail it)" 1 "$rc"
    assert_has "it says what it could not find" "could not find" "$out"
    assert_eq "it leaves the queue alone rather than guessing" "$uri_before" "$(uri_of folk-printer)"

    step "printer comes back in the morning, on yet another address"
    ip netns exec fpw-printer ip link set eth0 up
    move_printer $SUBNET.31
    out=$(run_watchdog); rc=$?
    assert_rc "watchdog exits 0 once the printer is back" 0 "$rc"
    assert_eq "queue repaired again" "ipp://$SUBNET.31:631/printers/FolkPrinter" "$(uri_of folk-printer)"
    assert_eq "printing works" "ok" "$(print_test_page folk-printer back)"
}

# --- main ------------------------------------------------------------------

case "${1:-test}" in
    up)    preflight; lab_up; echo "lab is up. try: sudo $0 shell" ;;
    down)  lab_down; echo "lab is down" ;;
    shell) exec nsenter -t "$(cat $LAB/folk.pid)" -m -n -u -- env CUPS_SERVER=$LAB/folk/cups.sock \
               PS1='folk-SVA# ' bash --norc ;;
    test)
        preflight
        trap 'lab_down' EXIT
        lab_up
        scenario_network
        scenario_stale_name
        scenario_idempotent
        scenario_dhcp_move
        scenario_squatter
        scenario_powered_off
        printf '\n%s== %d passed, %d failed ==%s\n' "$B" "$PASSED" "$FAILED" "$N"
        [ "$FAILED" -eq 0 ] || exit 1
        ;;
    *) echo "usage: $0 [test|up|down|shell]" >&2; exit 2 ;;
esac
