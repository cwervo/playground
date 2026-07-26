#!/bin/bash
# Regenerate the preview screenshots and QR code PNGs for browser.folk.
#
# Run this on a machine with normal internet access to replace the offline
# preview cards with real screenshots of each linked page.
#
# Needs: python3 with the "qrcode" + "pillow" packages (pip install qrcode pillow)
#        and Chromium or Google Chrome for the screenshots.
set -eu
cd "$(dirname "$0")"
mkdir -p previews qr

CHROME="${CHROME:-$(command -v chromium || command -v chromium-browser || command -v google-chrome || true)}"
if [ -z "$CHROME" ]; then
  echo "No chromium/chrome found; set CHROME=/path/to/chrome" >&2
  exit 1
fi

python3 - <<'EOF'
import json, qrcode
data = json.load(open('results.json'))
for r in data['results']:
    qrcode.make(r['url'], box_size=8, border=2).save(f"qr/{r['slug']}.png")
    print('qr ok:', r['slug'])
EOF

python3 -c "
import json
for r in json.load(open('results.json'))['results']:
    print(r['slug'] + '\t' + r['url'])
" | while IFS=$'\t' read -r slug url; do
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars \
    --window-size=1024,768 --screenshot="previews/$slug.png" "$url" >/dev/null 2>&1
  if [ -s "previews/$slug.png" ]; then echo "shot ok: $slug"; else echo "shot FAILED: $slug"; fi
done
