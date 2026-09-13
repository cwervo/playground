#!/bin/sh
# Offline engine checks: renders the four fixture pages and asserts that the
# text each page is known for actually comes out, that links resolve to
# absolute URLs, that forms are found, and that the JSON is well formed.
#
#   usage: test/check-engine.sh o/<host>/minibrowser

CLI=${1:?path to minibrowser cli}
cd "$(dirname "$0")/.." || exit 1

fail=0
pass=0

expect() { # expect FILE PATTERN
  if grep -q -- "$2" "$1"; then
    pass=$((pass + 1))
  else
    echo "FAIL: expected '$2' in $1"
    fail=$((fail + 1))
  fi
}

render() { # render NAME BASE
  "$CLI" -w 100 -b "$2" "fixtures/$1.html" > "o/check-$1.txt" || {
    echo "FAIL: $CLI exited $? on fixtures/$1.html"
    fail=$((fail + 1))
  }
  "$CLI" -l -w 100 -b "$2" "fixtures/$1.html" > "o/check-$1.links.txt" || fail=$((fail + 1))
  "$CLI" -j -b "$2" "fixtures/$1.html" > "o/check-$1.json" || fail=$((fail + 1))
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "import json,sys; d=json.load(open('o/check-$1.json')); assert d['blocks'], 'no blocks'" ||
      { echo "FAIL: o/check-$1.json is not valid JSON"; fail=$((fail + 1)); }
  fi
}

mkdir -p o

# -- google -----------------------------------------------------------------
render google https://www.google.com/
expect o/check-google.txt '^Google$'
expect o/check-google.txt '\[Google Search\]'
expect o/check-google.txt "\[I'm Feeling Lucky\]"
expect o/check-google.txt 'Advanced search'
expect o/check-google.txt 'Gmail'
expect o/check-google.links.txt 'https://www.google.com/intl/en/policies/privacy/'
expect o/check-google.json '"action":"https://www.google.com/search"'
expect o/check-google.json '"name":"q"'

# -- facebook ---------------------------------------------------------------
render facebook https://www.facebook.com/
expect o/check-facebook.txt '^Facebook – log in or sign up$'
expect o/check-facebook.txt 'Facebook helps you connect and share'
expect o/check-facebook.txt '\[text: Email address or phone number\]'
expect o/check-facebook.txt '\[password: Password\]'
expect o/check-facebook.txt '\[Log in\]'
expect o/check-facebook.txt 'Forgotten password?'
expect o/check-facebook.txt 'Create new account'
expect o/check-facebook.json '"method":"post"'

# -- apple ------------------------------------------------------------------
render apple https://www.apple.com/
expect o/check-apple.txt '^Apple$'
expect o/check-apple.txt 'iPhone 17 Pro'
expect o/check-apple.txt 'MacBook Air'
expect o/check-apple.txt 'TV & Home'
expect o/check-apple.txt 'Copyright © 2026 Apple Inc'
expect o/check-apple.links.txt 'https://www.apple.com/mac/'
expect o/check-apple.links.txt 'https://support.apple.com/'

# -- wikipedia --------------------------------------------------------------
render wikipedia https://en.wikipedia.org/wiki/Main_Page
expect o/check-wikipedia.txt '^Wikipedia, the free encyclopedia$'
expect o/check-wikipedia.txt 'Welcome to Wikipedia'
expect o/check-wikipedia.txt "From today's featured article"
expect o/check-wikipedia.txt 'In the news'
expect o/check-wikipedia.txt 'Did you know'
expect o/check-wikipedia.txt 'On this day'
expect o/check-wikipedia.txt '\[search: Search Wikipedia\]'
expect o/check-wikipedia.links.txt 'https://en.wikipedia.org/wiki/Aurora'
expect o/check-wikipedia.json '"img":"https://upload.wikimedia.org/wikipedia/commons'
expect o/check-wikipedia.json '"action":"https://en.wikipedia.org/w/index.php"'

# -- misc engine behaviour ----------------------------------------------------
printf '<p>a &amp; b &lt;c&gt; &copy; &#8212; &#x263A;<a href="../x">y</a>' |
  "$CLI" -l -b https://h.example/a/b/c.html - > o/check-misc.txt
expect o/check-misc.txt 'a & b <c> © — ☺y\[1\]'
expect o/check-misc.txt 'https://h.example/a/x'

echo "engine checks: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
