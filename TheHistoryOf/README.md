# TheHistoryOf

A series of whitepapers on the history of dynamic media and physical
computation, authored as `.toml` sources and compiled by the
[PrintablePrograms.png](../PrintablePrograms.png) framework into PDFs
and PNG page sequences.

## The series

| # | chapter | source |
|---|---------|--------|
| 1 | Smalltalk (starting from worrydream's annotated *Early History of Smalltalk*) | [`src/01-smalltalk.toml`](src/01-smalltalk.toml) |
| 2 | Erlang | [`src/02-erlang.toml`](src/02-erlang.toml) |
| 3 | Squeak | [`src/03-squeak.toml`](src/03-squeak.toml) |
| 4 | Pharo | [`src/04-pharo.toml`](src/04-pharo.toml) |
| 5 | The Dynabook | [`src/05-dynabook.toml`](src/05-dynabook.toml) |
| 6 | Xanadu | [`src/06-xanadu.toml`](src/06-xanadu.toml) |
| 7 | Hypertext — memex → HyperCard/Knowledge Navigator → CERN/Web → Scuttlebutt/DAT/Beaker/IPFS/AT Protocol | [`src/07-hypertext.toml`](src/07-hypertext.toml) |
| 8 | Printed Computational Data — Jacquard → Hollerith → punched cards → listings → Dynamicland/Folk/Paper Programs | [`src/08-printed-computation.toml`](src/08-printed-computation.toml) |

Citations draw on the Internet Archive, YouTube, and stable public
archives; every chapter ends with a numbered `SOURCES & CITATIONS`
section rendered into the paper itself.

## The vendored fork

[`EarlyHistoryOfSmalltalk/`](EarlyHistoryOfSmalltalk/) is a fork
(vendored copy) of
[github.com/worrydream/EarlyHistoryOfSmalltalk](https://github.com/worrydream/EarlyHistoryOfSmalltalk)
— Bret Victor's reader-repaired hypertext edition of Alan Kay's HOPL II
essay. See [`EarlyHistoryOfSmalltalk/FORK-NOTE.md`](EarlyHistoryOfSmalltalk/FORK-NOTE.md)
for provenance and what was omitted.

## Building

Requirements: Tcl 8.6+, ImageMagick (`convert`/`magick`). The IBM Plex
Mono font and all codecs come vendored with the framework.

```sh
tclsh bin/compile.tcl              # all chapters
tclsh bin/compile.tcl src/02-erlang.toml   # one chapter
```

Outputs, per chapter `<id>`:

- `build/<id>/page-NNN.png` — the **PNG page sequence**. US-letter pages
  at 300 dpi, 12 pt IBM Plex Mono in `#1010FF` on white (the framework's
  house style). Every page carries the chapter's complete `.toml` source
  in a PNG `tEXt` chunk — `tclsh ../PrintablePrograms.png/bin/press.tcl`-style
  digital recovery — and the **final page is a PrintablePrograms
  page-frame printout** of the `.toml`: print it, photograph it, and
  decode the chapter source back out of the pixels with
  `tclsh ../PrintablePrograms.png/bin/printout.tcl decode <photo>`.
- `build/<id>.pdf` — the same pages bound as a PDF by a pure-Tcl
  assembler ([`lib/pdf.tcl`](lib/pdf.tcl), JPEG/DCTDecode pages — no
  Ghostscript involved).
- `build/firstpages-4k/<id>-page-001-4k.png` — the first page re-rendered
  natively at 4K (3840 px tall) for gallery/preview use.

## Layout

```
src/                   the eight .toml chapter sources
bin/compile.tcl        the compiler (drives PrintablePrograms.png)
lib/toml.tcl           TOML-subset reader
lib/pdf.tcl            minimal pure-Tcl PDF assembler (DCTDecode pages)
build/                 compiled PDFs, page sequences, 4K first pages
EarlyHistoryOfSmalltalk/   vendored fork of worrydream's edition
```
