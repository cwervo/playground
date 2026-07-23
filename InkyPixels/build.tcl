#!/usr/bin/env tclsh
# Generates the InkyPixels demos from the inkypixels.tcl library.
set HERE [file dirname [file normalize [info script]]]
source [file join $HERE inkypixels.tcl]
namespace import ::inkypixels::*

# =====================================================================
#  DEMO 1 — A History of Photographic Color
# =====================================================================
set eraNames {Cyanotype Daguerreotype Tintype {Painted B/W} Autochrome {Film grain} {70mm color}}

proc era_section {n title kicker body} {
    return "<section class=\"ip-card\" style=\"margin:18px 0\">\
      <div style=\"display:flex;justify-content:space-between;align-items:baseline;gap:12px;flex-wrap:wrap\">\
        <h2 style=\"margin:0\">$title</h2>\
        <button class=\"ip-btn ghost\" onclick=\"ipSetEra($n)\">jump to well &rarr;</button>\
      </div>\
      <div class=\"ip-badge\" style=\"margin:6px 0 12px\">$kicker</div>\
      <p>$body</p></section>"
}

set d1_body "
<div class=\"ip-wrap\">
  <div class=\"ip-badge\">InkyPixels · off-thread CMYK ink engine</div>
  <h1>A History of Photographic Color</h1>
  <p class=\"ip-lede\">Cyanotypes, daguerreotypes, tin etching, painted black-and-white photography, the
  invention of colored-crystal photochemistry, and the long story of film grain and film-stock size
  (16&nbsp;mm&nbsp;&rarr;&nbsp;70&nbsp;mm) that gave us more and more and more development. Scrub the
  timeline: the page re-inks itself, and the four <b>data wells</b> at the bottom-left rise and fall with
  the simulated <b>C&nbsp;M&nbsp;Y&nbsp;K</b> laid down for each era.</p>

  <div class=\"ip-card\" style=\"margin:22px 0\">
    <div style=\"display:flex;justify-content:space-between;align-items:baseline\">
      <h3 style=\"margin:0 0 10px\">Timeline</h3>
      <div>era: <b id=\"ip-eraname\">Autochrome</b></div>
    </div>
    <input id=\"era-range\" class=\"ip-range\" type=\"range\" min=\"0\" max=\"6\" step=\"0.01\" value=\"4\"
           data-ip=\"segrange\" data-out=\"era-out\" data-bind=\"era\">
    <div style=\"display:flex;justify-content:space-between;font-size:11px;opacity:.7;margin-top:6px\">
      <span>1842 · Cyanotype</span><span>Daguerreotype</span><span>Tintype</span><span>Painted</span>
      <span>Autochrome</span><span>Film</span><span>70mm ·1970</span>
    </div>
    <div style=\"margin-top:14px;display:flex;gap:18px;flex-wrap:wrap;align-items:flex-end\">
      <div>
        <div style=\"font-size:11px;text-transform:uppercase;letter-spacing:.07em;opacity:.7;margin-bottom:6px\">ink budget · max non-paper coverage</div>
        [radio3 budget {{76% 0.76} {86% 0.86} {97% 0.97}}]
      </div>
      <div style=\"flex:1;min-width:200px\">
        <div style=\"font-size:11px;opacity:.7;margin-bottom:6px\">position <b id=\"era-out\">4</b> / 6 — drag to develop</div>
        <p style=\"margin:0;font-size:13px;opacity:.85\">The heavy per-pixel halftone runs in a background
        worker on an <b>OffscreenCanvas</b>; this thread only nudges the wells &amp; text, so scrubbing stays smooth.</p>
      </div>
    </div>
  </div>

  [era_section 0 {1842 · The Cyanotype} {iron salts · Prussian blue} {Anna Atkins presses ferric
   ammonium citrate and potassium ferricyanide into a single, stubborn blue. There is only one channel
   worth speaking of — <b>cyan</b> — so the C-well floods while the others sit nearly dry. A photograph
   that is also a chemistry lesson in what a single ink can carry.}]

  [era_section 1 {1839 · The Daguerreotype} {silvered copper · a mirror with a memory} {A polished
   silver plate, fumed with iodine and mercury, holds an image so fine it must be tilted into the dark to
   be seen at all. No pigment, only tone — the <b>K-well</b> dominates as pure luminance, the mirror doing
   the work of ink.}]

  [era_section 2 {1850s · Tin Etching &amp; the Tintype} {japanned iron · the field portrait} {Collodion on
   a lacquered iron plate: cheap, immediate, tough enough to mail home from the front. The palette warms —
   blacks and a scorched sepia — so <b>K</b> and <b>Y</b> climb together while cyan barely wets the nib.}]

  [era_section 3 {1860s · Painting the Photograph} {hand-tint · applied color before color existed} {Before
   the chemistry could hold a hue, colorists brushed it on — a blush of magenta at the cheek, a wash of
   yellow at the lamp. The wells show it: a monochrome base under deliberate, local <b>M</b> and <b>Y</b>.}]

  [era_section 4 {1907 · Colored-Crystal Photochemistry} {autochrome · dyed potato-starch grains} {The
   Lumi&egrave;re brothers scatter microscopic grains of starch, dyed orange, green and violet, across the
   plate — a random color mosaic that filters light before it ever reaches the silver. The first time all
   four wells fill at once: a true, if pointillist, color.}]

  [era_section 5 {1930s · The Story of Film Grain} {emulsion · the texture of light} {Silver-halide
   crystals are the grain, and the grain is the image. Push the stock and the crystals bloom; the whole
   frame breathes with noise. Coverage rides high across <b>C M Y</b> with a restless <b>K</b> underneath.}]

  [era_section 6 {16mm &rarr; 70mm · More and More Development} {stock size · resolution as real estate} {A
   bigger negative is simply more silver to develop — finer grain, deeper color, more room for every ink to
   sit down cleanly. From 16&nbsp;mm newsreels to 70&nbsp;mm spectacle, each jump in stock size is another jump
   in how much color the page can honestly hold.}]

  <div class=\"ip-note\" style=\"margin:22px 0\">The wells are a live read-out of the era model in
  <code>inkypixels.tcl</code> — mean CMYK per era &times; the coverage budget. Change the budget above and
  watch all four re-scale together.</div>

  <div class=\"ip-foot\">Rendered by the InkyPixels engine · WebGPU &rarr; WebGL2 &rarr; Canvas2D · off the main thread.</div>
</div>"

write [file join $HERE history-of-color index.html] \
    [doc "A History of Photographic Color — InkyPixels" $d1_body \
        [list wells 1 badge 1 startEra 4 eraNames $eraNames]]

# =====================================================================
#  DEMO 2 — Full-featured modern UI kit on one page
# =====================================================================
set tabInputs "<div class=\"ip-grid cols-2\">
  [card {Text fields} "[field {Plate name} [input {e.g. whole-plate}]][field {Exposure (s)} [input {12}]]"]
  [card {Range} "[slider {Screen pitch} 4 16 8][slider {Grain} 0 100 22]"]
</div>"

set tabControls "<div class=\"ip-grid cols-2\">
  [card {Toggles} "<div style=\"display:flex;flex-direction:column;gap:12px\">[toggle {Halftone screens} 1][toggle {Show registration} 0][toggle {Dry-down simulation} 1]</div>"]
  [card {Segmented} "<div style=\"display:flex;flex-direction:column;gap:14px\"><div>Fit<br>[seg fit {Cover Contain Tile}]</div><div>Blend<br>[seg blend {Multiply Screen Ink}]</div></div>"]
  [card {3-way ink budget} "[radio3 budget2 {{76% 0.76} {86% 0.86} {97% 0.97}}]"]
  [card {Buttons} "<div style=\"display:flex;flex-wrap:wrap;gap:8px\">[btn Primary primary][btn Cyan c][btn Magenta m][btn Ghost ghost][btn Disabled ghost disabled]</div>"]
</div>"

set tabFeedback "<div class=\"ip-grid cols-2\">
  [card {Progress} "<div style=\"display:flex;flex-direction:column;gap:12px\"><div>Developing… 38%[progress 38]</div><div>Fixing… 72%[progress 72]</div></div>"]
  [card {Badges & chips} "<div style=\"display:flex;flex-wrap:wrap;gap:8px;align-items:center\">[badge stable][badge beta][chip {C · 44%}][chip {M · 44%}][chip {palette · ⌘K}]</div>"]
  [card {Dialog} "<p style=\"margin-top:0\">Open a modal sheet.</p>[btn {Open dialog} primary {data-ip="modal-open" data-target="dlg1"}]"]
  [card {Toasts} "<p style=\"margin-top:0\">Fire a transient notice.</p>[btn {Ink a toast} m {data-ip="toast" data-msg="Deposited 32px of magenta."}]"]
</div>"

set d2_body "
<div class=\"ip-wrap\">
  <div class=\"ip-badge\">InkyPixels · UI kit</div>
  <h1>An Inky UI Kit</h1>
  <p class=\"ip-lede\">A full page of modern, accessible components — buttons, switches, ranges, segmented
  controls, a three-way ink-budget radio, tabs, cards, progress, badges, dialogs and toasts — every one of
  them floating over the <b>same</b> off-thread CMYK render loop that powers the history demo. Drive the
  background live below.</p>

  <div class=\"ip-card\" style=\"margin:20px 0\">
    <h3 style=\"margin:0 0 10px\">Drive the render loop</h3>
    <div class=\"ip-grid cols-2\">
      <div>[slider {Era} 0 6 4 0.01 {data-bind="era"}]<div style=\"font-size:12px;opacity:.7\">0 cyanotype … 6 · 70mm color</div></div>
      <div><div style=\"font-size:11px;text-transform:uppercase;letter-spacing:.07em;opacity:.7;margin-bottom:6px\">Coverage budget</div>[radio3 budget {{76% 0.76} {86% 0.86} {97% 0.97}}]</div>
    </div>
  </div>

  <h2>Components</h2>
  [tabs kit [list \
     [list Inputs   $tabInputs] \
     [list Controls $tabControls] \
     [list Feedback $tabFeedback] ]]

  <h2>Layout &amp; content</h2>
  <div class=\"ip-grid cols-3\" style=\"margin-top:8px\">
    [card {Card} {A translucent panel that blurs the ink behind it — the halftone reads as texture, never noise.}]
    [card {Note} [note {Left-ruled aside for asides, warnings, and the occasional printer's remark.}]]
    [card {Keyboard} "Press [kbd {⌘}] [kbd K] to summon the palette (decorative here)."]
  </div>

  <div class=\"ip-foot\">One engine, many widgets · progressive enhancement WebGPU &rarr; WebGL2 &rarr; Canvas2D · the heavy pixels never touch this thread.</div>
</div>
[modal dlg1 {A modal sheet} {<p style=\"margin-top:0\">Dialogs dim the page and trap nothing you can't escape.
 The background keeps developing behind the scrim — proof the render loop is independent of the DOM.</p>}]"

write [file join $HERE ui-kit index.html] \
    [doc "InkyPixels UI Kit" $d2_body [list wells 1 badge 1 startEra 4]]

puts stderr "done."
