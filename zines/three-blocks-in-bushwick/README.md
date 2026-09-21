# Three Blocks in Bushwick

An A5, 24-page mini zine built from a single photograph: the one-story 1931
"taxpayer" building at 56-14 to 56-30 Myrtle Avenue in Ridgewood, Queens
(three blocks past the Brooklyn line, and a Brooklyn mailing address until
1982), its tenants (Sunnyvale Physical Therapy, CityMD, a pharmacy, Wonder in
the old Rainbow), the painted "King Arthur Discounts" wall behind it, the Q55
bus shelter in front of it, and the two blocks it takes to walk there from
Wyckoff Avenue.

## Files

| file | what |
|---|---|
| `index.html` | the zine, one `<section class="page">` per A5 page; open in a browser to read or edit |
| `out/three-blocks-in-bushwick-A5-pages.pdf` | 24 sequential A5 pages, for screens or single-page printing |
| `out/three-blocks-in-bushwick-A4-booklet.pdf` | 12 A4-landscape sides, imposed for saddle stitching |
| `out/proofs/` | PNG proof of every page |
| `img/` | the source screenshot and the crops derived from it |
| `fonts/` | Anton, Source Serif 4, IBM Plex Mono (Google Fonts, OFL), so the HTML renders offline |
| `make_images.py` | derives the crops from `img/source-screenshot.jpg` |
| `render.js` | Playwright + Chromium: HTML to A5 PDF, plus an overflow check and proofs |
| `impose.py` | A5 pages to A4 booklet sheets (pypdf) |
| `build.sh` | runs all three |

## Printing on an office inkjet

1. Print `out/three-blocks-in-bushwick-A4-booklet.pdf` on A4, **double-sided, flip on the short edge**, at 100 % scale (no "fit to page"). Six sheets per copy.
2. Stack the sheets in the order they came out, fold the stack in half.
3. Staple twice on the fold (a long-reach stapler, or a saddle stapler).
4. Optional: trim the fore-edge 2–3 mm so the inner pages stop creeping.

If your printer only has Letter, print the A4 booklet at 100 % on Letter and
trim, or edit `impose.py` to place the A5 pages on a Letter-landscape sheet.

## Rebuilding

```sh
pip install pillow pypdf
npm install -g playwright   # Chromium must be available to Playwright
./build.sh
```

`render.js` prints `overflow: []` when every page fits its 148 x 210 mm box.
If you edit text and a page number appears there, trim that page.

## Editing notes

- Body text is set at 9.6 pt; each page is a fixed box with `overflow: hidden`, so anything that does not fit is silently cut. Always check the proofs.
- Page count must stay a multiple of four for the booklet; `impose.py` pads with blanks if not.
- The afterword text is the author's. One attribution was corrected during
  editing: *Here* is by Richard McGuire (2014), not Chris Ware.
