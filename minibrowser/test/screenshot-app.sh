#!/bin/sh
# Launches the built Linux desktop app on each fixture page (served as
# file:// URLs) inside a virtual X display and captures a screenshot of the
# real window into o/screenshots/app-<name>.png.
#
#   usage: test/screenshot-app.sh [path/to/bundle/minibrowser]
#   needs: Xvfb, ImageMagick's `import` (apt install xvfb imagemagick)

cd "$(dirname "$0")/.." || exit 1
BIN=${1:-app/build/linux/x64/release/bundle/minibrowser}
[ -x "$BIN" ] || { echo "no app binary at $BIN (run: make app)"; exit 1; }
DISPLAY_NUM=${DISPLAY_NUM:-:99}
mkdir -p o/screenshots
started_x=0
if ! DISPLAY=$DISPLAY_NUM xdpyinfo >/dev/null 2>&1 && ! pgrep -f "Xvfb $DISPLAY_NUM" >/dev/null 2>&1; then
  Xvfb "$DISPLAY_NUM" -screen 0 1280x900x24 >/dev/null 2>&1 &
  started_x=$!
  sleep 2
fi
fail=0
for name in google facebook apple wikipedia; do
  url="file://$(pwd)/fixtures/$name.html"
  DISPLAY=$DISPLAY_NUM "$BIN" "$url" >"o/screenshots/app-$name.log" 2>&1 &
  pid=$!
  sleep "${SETTLE:-6}"
  if DISPLAY=$DISPLAY_NUM import -window root "o/screenshots/app-$name.png" 2>>"o/screenshots/app-$name.log"; then
    echo "o/screenshots/app-$name.png"
  else
    echo "FAIL: could not capture $name"
    fail=$((fail + 1))
  fi
  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
done
[ "$started_x" != 0 ] && kill "$started_x" 2>/dev/null
[ "$fail" -eq 0 ]
