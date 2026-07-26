# folk_search_browser

The results of the web search **"Xteink X4 hardware ESP32 firmware GitHub"**,
parsed from the search-results JSON into three Folk programs.

## The programs

- **`browser.folk`** — the "query JSON browser". Shows one search result at a
  time: the result's Title as the page title, a PNG preview of the linked
  website in the middle, and `Wish $this is footnoted` with the full URL. A
  PNG QR code sits next to the footnote so you can scan it with a phone and
  see the source yourself.
- **`next.folk`** — point it at the browser page to advance to the next
  result. Steps once per pointing session (point away, then point again to
  step again).
- **`prev.folk`** — same, but goes back to the previous result.

The browser claims `$this is a query JSON browser`; that's what the two
pointer tools look for, so several browsers on the table each respond to
whichever tool is pointed at them. The current index lives in a
`Commit $b-search-result-index` claim, so both tools and the browser share
one piece of state.

## The data

- `results.json` — the 9 results (title + url + slug) parsed from the search
  JSON.
- `previews/<slug>.png` — a preview image per result. **Note:** these were
  rendered offline (the environment that generated them couldn't reach the
  live pages), so they're styled preview cards, not real screenshots. Run
  `./generate-assets.sh` on a normally-connected machine to replace them
  with real screenshots.
- `qr/<slug>.png` — a scannable QR code per result encoding the full URL.

`browser.folk` looks for this folder in a few common places (see
`assetRoots` at the top of the file); add your clone's path there if it
doesn't find the images.

## The results

1. [Vaulco/x4-firmware](https://github.com/Vaulco/x4-firmware)
2. [yattsu/biscuit](https://github.com/yattsu/biscuit)
3. [danmartinez78/biscuit](https://github.com/danmartinez78/biscuit)
4. [ohmygaugh-crypto/biscuit-eink](https://github.com/ohmygaugh-crypto/biscuit-eink)
5. [reukiodo/_V_](https://github.com/reukiodo/_V_)
6. [open-x4-epaper/sample-firmware](https://github.com/open-x4-epaper/sample-firmware)
7. [maddiedreese/xteink-terminal](https://github.com/maddiedreese/xteink-terminal)
8. [crosspoint-reader/crosspoint-reader](https://github.com/crosspoint-reader/crosspoint-reader)
9. [sample-firmware/README.md](https://github.com/open-x4-epaper/sample-firmware/blob/main/README.md)
