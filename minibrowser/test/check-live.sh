#!/bin/sh
# Live checks: fetch and render real home pages through the C engine.
# Needs network access and a TLS-capable CLI (make TLS=openssl).
#
#   usage: test/check-live.sh o/<host>/minibrowser URL...

CLI=${1:?path to minibrowser cli}
shift
cd "$(dirname "$0")/.." || exit 1
mkdir -p o/live
fail=0
for url in "$@"; do
  name=$(echo "$url" | sed -e 's|https\{0,1\}://||' -e 's|[^A-Za-z0-9]|_|g')
  printf '%-45s ' "$url"
  if "$CLI" -l -w 100 "$url" > "o/live/$name.txt" 2> "o/live/$name.err"; then
    title=$(head -1 "o/live/$name.txt")
    lines=$(wc -l < "o/live/$name.txt")
    links=$(grep -c '^ *[0-9]*\. http' "o/live/$name.txt")
    if [ "$lines" -gt 5 ] && [ "$links" -gt 0 ]; then
      echo "ok   title='$title' lines=$lines links=$links"
    else
      echo "FAIL rendered only $lines lines / $links links"
      fail=$((fail + 1))
    fi
  else
    # exit 3 means the server answered with an HTTP error: show its first line
    echo "FAIL $(cat "o/live/$name.err") $(head -1 "o/live/$name.txt")"
    fail=$((fail + 1))
  fi
done
[ "$fail" -eq 0 ]
