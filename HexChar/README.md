# HexChar

A hexagonally packed web keyboard for IPA and Unicode symbols. Type into the
field at the top, tap keys in the honeycomb, copy the result.

Inspired by the hex-grid character browsers on iOS (Unicode Pad, UniChar) and
by the category strip along the bottom of the Instagram symbol keyboard.

    open HexChar/index.html

No build step, no dependencies — three static files plus generated data.

## What's in it

- **1,356 characters** in 22 categories, in two groups: IPA (vowels,
  consonants, clicks, diacritics, tone & stress, modifier letters, and the
  whole U+0250–02AF IPA Extensions block) and Symbols (arrows, math,
  punctuation, currency, keys & UI, shapes, stars, signs, music, Greek,
  letterlike, games, sky, box drawing, dingbats).
- **Search** by Unicode name or code point — `schwa`, `arrow`, `U+2318`,
  `0x2318`. A code point that isn't on any key still comes back as a result.
- **Recents and favorites**, kept in `localStorage`. Long-press (or
  right-click) a key to open its detail card and favorite it.
- **Detail card** per character: code point, general category, HTML entity,
  JavaScript escape, UTF-8 bytes.
- Combining marks are drawn on a dotted circle (◌̃) and delete as one unit —
  backspace removes a whole grapheme cluster, base plus stacked marks.
- Keyboard support: arrow keys walk the honeycomb (including the diagonal
  neighbours), Enter inserts, `/` focuses search, Esc closes.
- Light and dark, following the system theme.

## Layout

Keys are pointy-top hexagons: rows overlap by a quarter of a hexagon's height
and every other row is offset by half a key, which is what makes the packing
read as a honeycomb. The key width is recomputed on resize so a whole number
of hexagons spans the column exactly — 7 across on a phone, 12 on a desktop.
Each key is clipped to its hexagon (`clip-path`), so taps near the corners go
to the key you can see rather than to the rectangle overlapping it.

## Data

`data.js` is generated — don't edit it by hand:

    python3 tools/gen_data.py

The category spec (which characters, in what order, under what label) lives at
the top of `tools/gen_data.py`. Names, general categories and combining
classes come from Python's `unicodedata`, so the metadata matches the Unicode
Character Database of the Python that generated it — currently Unicode 14.0.
Code points with no name in that database are dropped rather than shipped as
an empty box.

## iOS version

`ios/` holds a native CoreGraphics implementation of the same keyboard,
built and tested entirely from the command line (swiftc + simctl, no Xcode
IDE) with a headless self-test and a 15 ms render budget gate. On a Mac with
the Xcode toolchain: `cd ios && ./simulate.sh`. See `ios/README.md`.

## Fonts

Noto Sans, with Noto Sans Symbols 2, Noto Sans Math and Noto Music behind it
for the glyphs Noto Sans doesn't carry, all from Google Fonts. Offline, or
with the CDN blocked, the page falls back to the platform's own symbol fonts
and everything still works — the glyphs just aren't Noto.
