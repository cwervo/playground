# Compute Like Water

A 30-minute talk weaving three histories — literacy (scribes → Gutenberg → common
schools → a right), electricity (Pearl Street → municipal power rights → the REA → the
modern stall), and computing (the Kay/Victor "priesthood" critique → barefoot
developers → compute as a utility) — named for the are.na channel
[compute-like-water](https://www.are.na/andres-cuervo/compute-like-water).

## Layout

- **`index.html`** — canonical deliverable: side-by-side slides + transcript. Every
  in-text citation is a chip with a base64-SVG QR code (scannable → source URL,
  hover to zoom) hyperlinked to the works-cited entry mirrored at the bottom of the page.
- **`Works_Cited.html`** — standalone works cited, same data.
- **`sources/*.json`** — one record per source: url, author, publisher, dates,
  alt-text description, license, access date, notes.
- **`talk.md`** — the talk script: `@key` header, `=== slide` blocks
  (`@time/@heading/@image/@caption/@quote/@attribution`), paragraphs with `[ref:id]` markers.
- **`tools/`** — `talkgen`, the Rust generator (qrcode + serde + base64 crates).

## Build

```sh
cd tools
cargo run -- cite    # sources/*.json -> ../Works_Cited.html
cargo run -- build   # talk.md + sources -> ../index.html
```

`talkgen` validates that every `[ref:id]` has a matching `sources/<id>.json` (and warns
about unused sources), renders each QR once (cached by URL), and reports slide/word counts.

## Provenance notes

Built 2026-07-27 in a sandboxed environment where `are.na` and `archive.org` were
unreachable (egress-policy 403s); those two sources are cited with that caveat recorded in
their JSON. All slide imagery is hot-linked from Wikimedia Commons / Library of Congress
public-domain files, verified by filename before inclusion.

See also `../electricity.html` — the longer companion essay on NYC municipal
electricity rights.
