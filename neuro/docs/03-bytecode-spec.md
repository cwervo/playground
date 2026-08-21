# NeuroVM v1 — display-file bytecode

A `.nvm` file is three things at once: derived data, a drawing program, and an
argument. Four hosts execute it and none of them re-derives a number.

Reference implementations:

| Host | File | Role |
|---|---|---|
| Emitter | `src/nvm.hpp`, `src/analyze.cpp` | the only writer |
| Reference interpreter | `tcl/nvm.tcl` | the tie-breaker when hosts disagree |
| Interactive, screen | `web/host.html`, `tcl/explore.tcl` | immediate mode |
| Static, paper | `physical/plot.tcl` | SVG, print and pen modes |
| Static, physical | `physical/solid.tcl`, `physical/card.tcl` | STL/SCAD, pocket card |

---

## Why

Sketchpad (Sutherland 1963) did not store a picture. It stored a *display file*
— a list of instructions re-executed on every refresh — so the drawing and the
model that produced it were the same object. Kay's version of the idea is that
you ship the interpreter rather than the image, because meaning should be bound
as late as possible. Engelbart's is that the analyst has to be able to
restructure the view without leaving it.

The practical payoff here is narrower and easier to check: **a browser, a Tk
window, a pen plotter and a 3D printer cannot disagree about what the data
says**, because none of them has an opinion. They execute the same 18 kB.

The corollary is the constraint the format is designed around: anything a host
needs to know must be *in the file*. That is why the explanations, the
severities, the margins, the citations and the prior-graph edges are all
opcodes, not sidecar JSON that a host might skip.

---

## Container

All integers little-endian. Header is 64 bytes.

| off | size | field |
|---|---|---|
| 0 | 4 | magic `NVM1` |
| 4 | 2 | version (1) |
| 6 | 2 | flags — bit 0: meta section present |
| 8 | 4 | strOff |
| 12 | 4 | strCount |
| 16 | 4 | strLen |
| 20 | 4 | symOff |
| 24 | 4 | symCount |
| 28 | 4 | codeOff |
| 32 | 4 | codeLen |
| 36 | 4 | metaOff |
| 40 | 4 | metaLen |
| 44 | 4 | crc32 of the **code section only** |
| 48 | 4 | entryPC, code-relative |
| 52 | 4 | canvasW |
| 56 | 4 | canvasH |
| 60 | 4 | reserved, must be 0 |

Sections follow in the order strings, symbols, code, meta.

The CRC covers only the code section. A mismatch means the drawing program is
damaged even though the numbers may have survived, and those are worth telling
apart: a host can still print a correct symbol table off a file whose code is
corrupt, and should say so rather than refusing.

### String pool

`u16 byteLen` then that many UTF-8 bytes. No terminator. Deduplicated by the
emitter, so a repeated label costs 2 bytes.

### Symbol table — 28 bytes per entry

| off | size | field |
|---|---|---|
| 0 | 2 | nameIdx — string pool index for the stable id (`erp.p3b_ratio`) |
| 2 | 2 | labelIdx — index for the human label, `0xFFFF` to fall back to name |
| 4 | 2 | flags |
| 6 | 2 | reserved |
| 8 | 4 | f32 value |
| 12 | 4 | f32 z |
| 16 | 4 | f32 dist |
| 20 | 4 | f32 refLo |
| 24 | 4 | f32 refHi |

flags: bits 0–1 severity (0 ok, 1 borderline, 2 deviant, 3 not measured);
bit 2 value-is-valid; bits 3–5 domain id; bit 6 reference band present.

The reference band is carried so a host can always name the line a value
crossed. Only about half the metrics have a hand-written `NOTE`; with `refLo`
and `refHi` in hand, a host can generate a true sentence for the rest instead of
showing an empty inspector.

`z` is a signed deviation in the metric's own natural direction — a true
normative z where the vendor supplied one, otherwise a half-band pseudo-z.

`dist` is distance past the nearer reference edge, normalised by the threshold
for one-sided criteria and by the band width for two-sided ones. Negative means
inside reference with that much margin. **Hosts are required to expose `dist`
somewhere.** It is the number that distinguishes a 4% miss from a 400% one, and
a host that shows only the severity colour has thrown away the finding.

### Meta

Optional UTF-8 JSON. Carries panel geometry (so a host can re-flow panels into
its own column layout without re-deriving anything), hypothesis scores, and the
permutation count and seed. A host may ignore it entirely.

---

## Instruction set

One-byte opcode, fixed-width operands. Operand widths are table-driven so an
unknown opcode can be skipped without desynchronising the stream — that is what
makes the format extensible without a version bump for every new primitive.

### Stack and constants

| op | name | operands | effect |
|---|---|---|---|
| 0x00 | HALT | | stop |
| 0x01 | PUSHF | f32 | push |
| 0x02 | PUSHI | i32 | push as float |
| 0x03 | PUSHS | u16 | push a string index |
| 0x04 | DUP | | |
| 0x05 | DROP | | |
| 0x06 | SWAP | | |
| 0x07 | OVER | | push second-from-top |

### Arithmetic

| op | name | effect |
|---|---|---|
| 0x10–0x13 | ADD SUB MUL DIV | binary; DIV by zero yields 0 |
| 0x14–0x15 | NEG ABS | unary |
| 0x16–0x17 | MIN MAX | binary |
| 0x18 | CLAMP | `v lo hi → clamped` |
| 0x19 | LERP | `a b t → a+(b−a)t` |
| 0x1A | MAP | `v i0 i1 o0 o1 → remapped` |

`MAP` is the workhorse. The timing panel remaps milliseconds to pixels inside
the VM rather than at emit time, so a host can retarget that axis at run time by
patching one `PUSHF` pair instead of regenerating the panel.

### Data access

| op | name | operands | effect |
|---|---|---|---|
| 0x20 | LOADV | u16 sym | push measured value |
| 0x21 | LOADZ | u16 sym | push signed deviation |
| 0x22 | LOADD | u16 sym | push distance past edge |

### Graphics state

| op | name | operands |
|---|---|---|
| 0x30 | RGBA | u8 ×4 |
| 0x31 | LINEW | f32 |
| 0x32 | FONT | u16 name, f32 size |
| 0x33 / 0x34 | PUSHMAT / POPMAT | |
| 0x35 | TRANS | `(x y)` from stack |
| 0x36 | SCALE | `(sx sy)` |
| 0x37 | ROT | `(radians)` |

The emitted palette is **light-theme ink**. A host rendering on a dark ground
must invert **lightness only**, keeping hue: naive `255−x` rotates hue by 180°
and turns the deviant red into a cyan, silently reassigning the meaning of every
colour on the page. Both interactive hosts implement the HSL round trip; the
plotter ignores colour entirely in pen mode.

Line widths and font sizes are scaled by the transform's uniform scale factor.
A host that zooms by post-scaling its output rather than by seeding the
transform will move the geometry and leave the type at its authored size, which
breaks the layout the emitter computed. `nvm::run` takes an optional seed matrix
precisely so zoom goes in the right place.

### Immediate-mode drawing

| op | name | operands | effect |
|---|---|---|---|
| 0x40 | CLEAR | | clear to host background |
| 0x41 / 0x42 | MOVETO / LINETO | | `(x y)` |
| 0x43 / 0x44 | PATH / CLOSE | | begin, close |
| 0x45 / 0x46 | STROKE / FILL | | emit the pending primitive |
| 0x47 | RECT | | `(x y w h)` |
| 0x48 | CIRCLE | | `(x y r)` |
| 0x49 | ARC | | `(x y r a0 a1)` |
| 0x4A | TEXT | u16 str, u8 anchor | `(x y)`; anchor 0 left, 1 centre, 2 right |

`RECT` accepts **negative width and height**, meaning "grow the other way". The
ladder panel relies on it for leftward bars, and a host that does not normalise
will drop every inside-reference bar on the page.

`RECT`, `CIRCLE` and `ARC` set a pending primitive that the next `STROKE` or
`FILL` emits. This is why the generated code is compact: a filled bar is four
`PUSHF`, a `RECT` and a `FILL`.

### Semantic layer

This is the part that makes a display file more than pixels.

| op | name | operands | meaning |
|---|---|---|---|
| 0x50 | PANEL | u16 id, u16 title | begin a named region |
| 0x51 | ENDPANEL | | |
| 0x52 | ANCHOR | u16 id | primitives until the next ANCHOR are one hit target |
| 0x53 | NOTE | u16 plain, u16 full | dual-register explanation for the current anchor |
| 0x54 | EDGE | u16 a, u16 b, u16 hyp, f32 w, i8 sign | declare a prior-graph relation |
| 0x55 | FLAG | u8 severity | |
| 0x56 | CITE | u16 str | provenance for the current anchor |

Three notes worth having learned the hard way:

**`NOTE` carries both registers, always.** A host chooses which to show — the
browser and Tk hosts offer plain / full-fat / both — but the file never contains
one without the other. Keeping the pair adjacent in the emitter source makes it
very hard for the plain version to drift into vagueness while the technical one
stays honest.

**`ANCHOR` opens a new instance, it does not re-open an existing one.** The same
metric id can be drawn in several panels. A host that accumulates all of an id's
primitives into one bounding box gets a rectangle spanning half the document,
which then swallows every click inside it. An id owns a *list* of boxes; hit
testing walks the list, and selecting an id should highlight every instance,
which is the more useful behaviour anyway.

**`EDGE` is a declaration, not a drawing instruction.** The emitter writes every
computable edge, whether or not both endpoints happen to be drawn in the chord
panel. Tying edge records to the drawing silently dropped the single most
interesting relation in this dataset — `srs.exec_attn ↔ beh.commission`, the one
the record contradicts — because commission errors rank too close to reference
to make a top-24 ring.

### Control

| op | name | operands |
|---|---|---|
| 0x60 | JMP | i16, relative to the byte after the operand |
| 0x61 | JZ | i16, taken when the popped value is 0 |
| 0x62 | CALL | u16 absolute code offset |
| 0x63 | RET | |

The ladder panel's ~48 bars all go through one four-instruction subroutine
reached by `CALL`:

```
     0  JMP       8 -> 11    ; jump over the subroutine body
     3  MUL                  ; x0 yTop (halfWidth * t) -> signed bar width
     4  PUSHF     9          ; bar height
     9  RECT
    10  RET
    11  CLEAR                ; entry point
```

Which you can read for yourself:

```
make disasm | head -40
```

That is the point of shipping a bytecode rather than a rendered image. A
dashboard you cannot read the source of is a dashboard you have to trust; one
whose entire drawing program disassembles in a few hundred lines is one you can
audit.

---

## Writing a new host

Implement these and hand the namespace to `nvm::run`:

```
clear                    rgba r g b a        linew w
font name size           text x y str anchor
path  moveto x y  lineto x y  close
stroke                   fill
rect how x y w h         circle how x y r    arc how x y r a0 a1
panel id title           endpanel
anchor id                note plain full     edge a b hyp w sign
flag severity            cite text
```

Every semantic proc may be a no-op. `physical/plot.tcl` drops `note`, `flag` and
`cite` in pen mode because paper has no hover state, and a note the reader
cannot reach is worse than no note at all. That is a legitimate reading of the
file, not a shortcut.

Do not implement a semantic op *incorrectly* — a host that renders `dist` as a
bare colour and never shows the number has changed what the page claims.

---

## Current file

```
version   1
canvas    1600 x 3004
entry     11
code      18663 bytes
strings   644
symbols   62
edges     32
CRC       ok
```

`make check` rebuilds from the seed and byte-compares, then runs every host over
the result.
