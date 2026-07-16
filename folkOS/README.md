# folkOS

Tooling for treating **folklang** — the language of
[Folk](https://github.com/folkcomputer/folk) — as a portable language
standard, so we can build simulators and renderers for it beyond the
upstream C/Tcl/Vulkan implementation.

## The source of truth

**[`folklang.bnf.tcl`](folklang.bnf.tcl)** is the single source of
truth. It's a Tcl program (deliberately — Tcl is folklang's host
language, so the descriptor can be sourced by Folk itself and its
pattern literals read exactly like live folk code) that describes:

- **Grammar, in four layers** — an EBNF-as-data description of
  - *Layer 0*: Tcl word/command structure (what any reader must parse),
  - *Layer 1*: the reactive forms (`Claim` / `Wish` / `When` / `Say` /
    `Hold!` / `On unmatch` / `Query!` / …) with their exact modifier
    flags from upstream `prelude.tcl`,
  - *Layer 2*: the statement-pattern sublanguage (`/var/`,
    `/...rest/`, wildcards `any|anyone|someone|something|anything`,
    negation `nobody|nothing`, `&` joins, `$bound` references — all
    verified against upstream `trie.c`),
  - *Layer 3*: the natural-language clause *conventions*
    (`has`/`is`/`with key value…` shapes).
- **Standard-library vocabulary** — the ~44 statement shapes that make
  up the practical stdlib (labels, outlines, titles, canvases, draw
  commands, image/GIF display, camera slices, AprilTags, geometry,
  keyboard, clock, Unix commands, …), each tagged with the
  `builtin-programs/` file that provides it (this directory was
  `virtual-programs/` in older folk revisions).
- **Feature registry + renderer capability matrix** — 30 feature axes
  × 12 target backends (upstream Vulkan reference, folkOS Vulkan
  clone, JS/WASM/C++ headless simulators, ASCII/SDL/canvas/WebGPU/
  Metal renderers), so conformance is tracked per-feature per-target.

Provenance is pinned in the file: extracted from
`folkcomputer/folk @ 33e89446` (2026-07-10), from `prelude.tcl`,
`trie.c`, `folk.c`, and `builtin-programs/`.

## Usage

```sh
tclsh folklang.bnf.tcl validate       # self-check: grammar closure,
                                      # reachability, registry integrity
tclsh folklang.bnf.tcl emit ebnf      # human-readable EBNF
tclsh folklang.bnf.tcl emit json      # machine-readable, for JS/C++/WASM tools
tclsh folklang.bnf.tcl emit matrix    # renderer capability matrix (markdown)
make                                  # validate + regenerate generated/
```

Committed snapshots of the emitter output live in
[`generated/`](generated/) — regenerate them (`make`) whenever
`folklang.bnf.tcl` changes. Downstream simulators should consume
`generated/folklang.json` (or run the emitter themselves), never
hand-copy the grammar.

## Why a Tcl descriptor rather than a plain `.bnf` file?

Because folklang is not a context-free language you can capture
honestly in one flat BNF:

1. **The top layer is Tcl.** A `.folk` file is a Tcl script; meaning
   comes from command dispatch and runtime substitution. The
   *parseable* core — word structure, the reactive forms, the pattern
   sublanguage — is genuinely BNF-able and is what a conforming
   simulator must implement. That's Layers 0–2.
2. **Most of "the language" is vocabulary, not syntax.** `Wish $this
   is outlined red` is grammatically just words; what makes it *mean*
   something is a `When` handler in the stdlib. A BNF alone would
   describe almost nothing of what users experience as folklang. So
   the descriptor carries the vocabulary and feature registries as
   first-class data, which is exactly what the renderer capability
   matrix needs to be keyed on.
3. **One file, many outputs.** Keeping grammar + vocabulary + matrix
   in one validated, executable document means the EBNF, the JSON
   consumed by a JS parser generator, and the conformance matrix can
   never drift from each other.

## Roadmap (targets registered in the matrix)

Engine-first: `sim-js-cli` (headless JS simulator: reader + reactive
trie DB + synthetic camera/clock/tag claims) is the cheapest way to
lock down Layers 0–2 semantics with a conformance test suite, then the
WASM build shares that core with all browser renderers
(`render-js-canvas`, `render-js-wasm-canvas`, `render-webgpu`), while
`sim-cpp-cli` grounds the native line (SDL, Metal macOS/iOS, and the
refined Vulkan clone).
