# Figma screens → text-embedded PDFs

Builds one searchable, selectable-text PDF per screen of the Collectory
prototype board (Figma file `hIlHmNtjlfw0oZm1R2pOHb`, page "screens / prototype").

Each PDF page is the pixel render of the frame at its Figma size (402 × 874 pt)
with every text layer written on top as invisible PDF text at its exact
bounding box, the way OCR makes a scan searchable. The page looks identical to
the Figma render, and the text can be selected, searched and copied.

## Layout

| Path | What |
|---|---|
| `screens.json` | The 46 screens in board order, plus the layers that were skipped and why |
| `data/<id>.json` | Text layers per screen (content, box, font size, alignment) |
| `data/page-metadata.xml` | Raw layer metadata for the whole page, from the Figma MCP `get_metadata` tool |
| `derive_from_metadata.py` | Fallback that derives `data/<id>.json` from the page metadata |
| `renders/` | Pixel renders of each screen, one PNG per screen (see below) |
| `build_pdfs.py` | Builds `pdfs/NN - <screen name>.pdf` and `pdfs/All screens.pdf` (with bookmarks) |

## Status of `data/`

14 screens were read directly from Figma with the Plugin API script below
(`"source"` absent): the first 10 onboarding screens, Main screen - Borrowing,
Main screen - Requests, Timeline and Add item. The other 32 carry
`"source": "metadata"`: the Figma MCP call quota for this seat ran out, so
they were derived from `page-metadata.xml` by `derive_from_metadata.py`. For
those screens the text comes from the layer names (Figma names text layers
after their content, folding line breaks to spaces), positions were validated
against the 14 directly-read screens, font size and alignment are estimated,
and text that lives inside component instances (for example shared list rows
or navigation bars) is not listed in the metadata and so is not embedded.
Re-running the script below for those ids once the quota resets replaces the
derived files with exact ones; the builder needs no change.

The invisible text uses DejaVu Sans, which has no colour emoji, so the 🎂 and
💖 characters on the profile screens are not searchable.

## Getting the renders

`renders/` needs one image per screen, named either by node id
(`47-572.png`) or by frame name (`Main screen - Borrowing.png`), optionally
with an `@2x`/`@3x` suffix. Either:

- **From Figma:** select all screen frames on the page, add a PNG export
  (1x or 2x) in the Export panel, export, and drop the files in `renders/`.
  Figma names the files after the frame, which the script matches.
- **From a Claude Code session whose environment allows `figma.com`:** ask it
  to call the Figma MCP `get_screenshot` for each id in `screens.json` and
  `curl` each returned URL into `renders/<id>.png`.

## Building

```sh
pip install pymupdf pillow
python3 build_pdfs.py               # all screens; exits 1 and lists any missing render
python3 build_pdfs.py --only 47:572 # one screen
python3 build_pdfs.py --placeholder # blank page where a render is missing (testing only)
```

The script prints, per PDF, how many text layers were embedded and verifies
that every layer's words can be found again by text extraction.

## Regenerating `data/`

Run this read-only Plugin API script in the file via the Figma MCP `use_figma`
tool, once per screen id, and save the result as `data/<id with ':'→'-'>.json`:

```js
const top = await figma.getNodeByIdAsync("47:572");
const tb = top.absoluteBoundingBox;
const items = [];
for (const t of top.findAllWithCriteria({ types: ["TEXT"] })) {
  if (!t.visible) continue;
  let hidden = false; let p = t.parent;
  while (p && p.id !== top.id) { if (p.visible === false) { hidden = true; break; } p = p.parent; }
  if (hidden) continue;
  const b = t.absoluteBoundingBox; if (!b || !t.characters.trim()) continue;
  const fs = t.fontSize, fn = t.fontName, lh = t.lineHeight;
  items.push({ id: t.id, c: t.characters, x: b.x - tb.x, y: b.y - tb.y, w: b.width, h: b.height,
    fs: typeof fs === "number" ? fs : null, font: fn && fn.family ? fn.family + " " + fn.style : null,
    lh: lh && lh.unit !== "AUTO" ? lh.value + (lh.unit === "PERCENT" ? "%" : "") : null,
    align: t.textAlignHorizontal, valign: t.textAlignVertical, o: t.opacity, rot: t.rotation || 0 });
}
return { id: top.id, name: top.name, w: tb.width, h: tb.height, count: items.length, texts: items };
```
