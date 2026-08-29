#!/bin/sh
#
# Install folk-printer-watchdog on a Folk machine (folk-SVA) and schedule it
# to run every day at midnight.
#
# Usage:
#   ./install.sh                 install + nightly midnight cron
#   ./install.sh --at-boot       also run once at every boot
#   ./install.sh --uninstall     remove the cron entries and the script
#
# Run it from a checkout of this directory, on the machine itself.

set -eu

SRC_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
BIN=/usr/local/bin/folk-printer-watchdog
CONF=/etc/folk-printer-watchdog.conf
MARKER="# folk-printer-watchdog"
AT_BOOT=no
UNINSTALL=no

for arg in "$@"; do
    case "$arg" in
        --at-boot) AT_BOOT=yes ;;
        --uninstall) UNINSTALL=yes ;;
        -h|--help) sed -n '2,12p' "$0" | sed 's/^#\{0,1\} \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

if [ "$(id -u)" = 0 ]; then
    SUDO=""
elif command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
    echo "Not root; using sudo (lpadmin and the root crontab need it)."
else
    echo "ERROR: run this as root, or install sudo." >&2
    exit 1
fi

# The crontab we want, as one blob, so install and uninstall stay symmetric.
new_cron() {
    $SUDO crontab -l 2>/dev/null | grep -v "$MARKER" || true
    [ "$UNINSTALL" = yes ] && return 0
    echo "0 0 * * * $BIN --quiet $MARKER"
    [ "$AT_BOOT" = yes ] && echo "@reboot sleep 60 && $BIN --quiet $MARKER"
    return 0
}

if [ "$UNINSTALL" = yes ]; then
    new_cron | $SUDO crontab -
    $SUDO rm -f "$BIN"
    echo "Removed $BIN and its cron entries. $CONF was left in place."
    exit 0
fi

echo "Installing $BIN"
$SUDO install -m 0755 "$SRC_DIR/folk-printer-watchdog" "$BIN"

if [ -f "$CONF" ]; then
    echo "Keeping existing $CONF"
else
    echo "Installing example config to $CONF — edit it before this is useful"
    $SUDO install -m 0644 "$SRC_DIR/folk-printer-watchdog.conf.example" "$CONF"
fi

echo "Scheduling: every day at 00:00$([ "$AT_BOOT" = yes ] && echo ' (and at every boot)')"
new_cron | $SUDO crontab -
$SUDO crontab -l | grep "$MARKER"

cat <<MSG

Installed. Next steps on this machine:

  1. Put the real queue name and printer MAC in $CONF
     (current queues: $(lpstat -v 2>/dev/null | sed -n 's/^device for \([^:]*\):.*/\1/p' | tr '\n' ' ' || echo "run lpstat -v"))
  2. Test it without changing anything:
        sudo $BIN --dry-run --verbose
  3. Then for real:
        sudo $BIN --verbose

  Log: /var/log/folk-printer-watchdog.log
MSG
