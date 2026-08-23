#!/usr/bin/env tclsh
# build.tcl &mdash; render the simulated proceedings to a print-ready HTML document.
#
# The PDF is produced by printing this HTML from headless Chromium. Tcl builds
# the document; the browser does layout; a small amount of JavaScript runs after
# layout to paginate the transcript and to draw the ley lines, because line
# endpoints are not knowable until the text has been set.
#
# ---------------------------------------------------------------------------
# XANADU IN A PAGED MEDIUM
# ---------------------------------------------------------------------------
# Ted Nelson's transpointing windows put two documents side by side and draw
# visible lines between the passages that correspond. The lines are the point:
# a link you cannot see is a link you have to take on trust.
#
# Paper cannot carry a line from page 14 to page 47. So the link is split into
# two halves that meet at the page edge, and made whole three other ways:
#
#   1. Within a page the ley line is REAL -- a drawn curve from the highlighted
#      phrase out to a stub in the margin.
#   2. The stub carries the link id, the target page, and the target region, in
#      the same colour at both ends. A reader can complete the line by hand.
#   3. Every stub is a live internal PDF link. Click it and you are there;
#      the target stub links back.
#   4. One spread at the end draws every link at once, as a bundled edge
#      diagram between transcript pages and report regions. That is the sheet
#      where the ley lines are actually visible as a system.
#
# Colour is by speaker, not by link, so the bundle at the end reads as "who
# pointed at what".
#
#   tclsh conference/build.tcl --img build/conference/img --out build/conference/proceedings.html
# ---------------------------------------------------------------------------

# These source files are UTF-8 and carry accented names (Vásárhelyi, Pflügers,
# Über). Tcl reads scripts in the system encoding, which in a bare container is
# not UTF-8, so this has to be set before anything is sourced or the names
# double-encode into mojibake.
encoding system utf-8

set here [file dirname [file normalize [info script]]]
set root [file dirname $here]

source [file join $here sources.tcl]
source [file join $here proceedings.tcl]

# ---------------------------------------------------------------------------
set IMGDIR [file join $root build conference img]
set OUT    [file join $root build conference proceedings.html]
for {set i 0} {$i < $argc} {incr i} {
    switch -- [lindex $argv $i] {
        --img { set IMGDIR [lindex $argv [incr i]] }
        --out { set OUT    [lindex $argv [incr i]] }
    }
}
file mkdir [file dirname $OUT]

# ---------------------------------------------------------------------------
proc slurpB64 {path} {
    if {![file exists $path]} { return "" }
    set f [open $path rb]
    set d [read $f]
    close $f
    return [binary encode base64 $d]
}

# A JS string literal. Newlines fold to spaces because every string that comes
# through here is a one-line label.
proc jsstr {s} {
    set out "\""
    foreach ch [split $s ""] {
        switch -- $ch {
            "\\"   { append out "\\\\" }
            "\""   { append out "\\\"" }
            "\n"   { append out " " }
            default { append out $ch }
        }
    }
    return "$out\""
}

proc esc {s} {
    return [string map {& &amp; < &lt; > &gt; \" &quot;} $s]
}

# Wrap bare numeric tokens in IBM Plex Mono. A digit run that is preceded by a
# letter is part of an identifier -- P300a, N100, r5.9.1 -- and is left alone,
# because setting half a word in a different face is worse than setting none of
# it.
proc nums {s} {
    set out ""
    set n [string length $s]
    set i 0
    while {$i < $n} {
        set c [string index $s $i]
        set prev [expr {$i > 0 ? [string index $s $i-1] : " "}]
        if {[string match {[0-9]} $c] && ![string match {[A-Za-z0-9]} $prev]} {
            set j $i
            # optional leading sign is folded in by looking back one character
            while {$j < $n && [string match {[0-9.,]} [string index $s $j]]} { incr j }
            # do not swallow a sentence-final period
            while {$j > $i && [string match {[.,]} [string index $s $j-1]]} { incr j -1 }
            set tok [string range $s $i $j-1]
            append out "<span class=\"n\">$tok</span>"
            set i $j
        } else {
            append out $c
            incr i
        }
    }
    return $out
}

# [[L-001|phrase]] -> highlighted anchor. Returns {html linkIdsUsed}
proc marks {s speaker} {
    global LINKS REGIONS
    set html ""
    set used {}
    set rest $s
    while {[regexp {^(.*?)\[\[(L-\d+)\|(.*?)\]\](.*)$} $rest -> pre id phrase post]} {
        append html [nums [esc $pre]]
        set rid [expr {[dict exists $LINKS $id] ? [dict get $LINKS $id] : ""}]
        append html "<mark class=\"hl\" id=\"src-$id\" data-link=\"$id\" data-sp=\"$speaker\">"
        append html [nums [esc $phrase]]
        append html "<a class=\"tick\" href=\"#reg-$rid\">$id</a></mark>"
        lappend used [list $id $rid $speaker]
        set rest $post
    }
    append html [nums [esc $rest]]
    return [list $html $used]
}

# ---------------------------------------------------------------------------
# Assets
# ---------------------------------------------------------------------------
set FONT [slurpB64 [file join $root .. PrintablePrograms.png fonts IBMPlexMono-Regular.ttf]]
if {$FONT eq ""} {
    set FONT [slurpB64 [file join [file dirname $root] PrintablePrograms.png fonts IBMPlexMono-Regular.ttf]]
}
if {$FONT eq ""} { puts stderr "build: WARNING IBM Plex Mono not found, falling back to a generic mono" }

set IMG [dict create]
foreach p [glob -nocomplain [file join $IMGDIR *.png]] {
    dict set IMG [file rootname [file tail $p]] [slurpB64 $p]
}
if {[dict size $IMG] == 0} {
    puts stderr "build: no PNGs in $IMGDIR -- run 'make figures' first"
    exit 1
}

# ---------------------------------------------------------------------------
# Plates: which figures go on which annotated back-matter page
# ---------------------------------------------------------------------------
set PLATES {
    {A "Resting EEG, eyes open"      {EyesOpen_EEG-RawTrace EyesOpen_EEG-HeadMaps}}
    {B "Resting EEG, eyes closed"    {EyesClosed_EEG-HeadMaps}}
    {C "Event-related potentials"    {GoNoGo_ERP-P300a-Cz GoNoGo_ERP-P300b-Pz GoNoGo_ERP-N100-O2}}
    {D "Cardiac and autonomic"       {Resting_ECG-Waveform Resting_HRV-Tachogram Resting_HRV-PowerSpectrum}}
    {E "12-lead electrocardiogram"   {Resting_ECG-12Lead}}
    {F "Percutaneous allergy panel"  {Percutaneous_SPT-40Panel}}
    {G "Self-report and gauges"      {SelfReport_Screener-Domains GoNoGo_Result-Gauges}}
}

proc figKey {name} {
    # the extracted TIFFs carry the date and timestamp; the plates name the stem
    global IMG
    foreach k [dict keys $IMG] {
        if {[string match "${name}_*" $k]} { return $k }
    }
    return ""
}

# ---------------------------------------------------------------------------
# Emit
# ---------------------------------------------------------------------------
set H {}
proc out {s} { global H ; append H $s "\n" }

out {<!doctype html><html lang="en"><head><meta charset="utf-8">}
out {<title>Proceedings &mdash; A Simulated Working Conference</title>}
out "<style>"
if {$FONT ne ""} {
    out "@font-face{font-family:'IBM Plex Mono';font-weight:400;font-style:normal;src:url(data:font/ttf;base64,$FONT) format('truetype');}"
}
out {
:root{
  --ink:#14161c; --ink2:#3d4352; --muted:#6b7183; --rule:#c9ced9; --rule2:#e6e9ef;
  --paper:#ffffff; --panel:#f6f7f9;
  --hl:#FFE94A;                 /* highlighter */
  --plex:'IBM Plex Mono', ui-monospace, Menlo, Consolas, monospace;
  --serif:"Iowan Old Style","Palatino Linotype",Palatino,Georgia,"Times New Roman",serif;
  --sans:Inter,-apple-system,"Helvetica Neue",Helvetica,Arial,sans-serif;
}
*{box-sizing:border-box;}
html,body{margin:0;padding:0;background:#8b8f99;}
@page{ size:11in 8.5in; margin:0; }
@media print{ html,body{background:#fff;} .page{box-shadow:none !important;margin:0 !important;} }

/* Page-modifier classes are prefixed pg- because several content classes on
   these pages (.cover, .plate, .map) are position:absolute. An unprefixed
   modifier matches both, takes the page itself out of flow, and silently drops
   it from the printed document. */
.page{
  position:relative; width:11in; height:8.5in; background:var(--paper);
  overflow:hidden; break-after:page; page-break-after:always;
  margin:0 auto 16px; box-shadow:0 2px 14px rgba(0,0,0,.35);
  color:var(--ink); font-family:var(--serif); font-size:10.4pt; line-height:1.44;
}
.page:last-of-type{break-after:auto;page-break-after:auto;}
.n{font-family:var(--plex);font-size:.94em;font-variant-numeric:tabular-nums;letter-spacing:-.01em;}

/* --- running furniture ------------------------------------------------- */
.rh{position:absolute;top:.34in;left:.62in;right:.62in;display:flex;justify-content:space-between;
    font-family:var(--plex);font-size:7pt;letter-spacing:.14em;text-transform:uppercase;color:var(--muted);
    border-bottom:.5pt solid var(--rule2);padding-bottom:5px;}
.rf{position:absolute;bottom:.32in;left:.62in;right:.62in;display:flex;justify-content:space-between;
    font-family:var(--plex);font-size:7pt;color:var(--muted);}
.body{position:absolute;top:.72in;left:.62in;right:.62in;bottom:.62in;}

/* --- cover -------------------------------------------------------------- */
.cover{position:absolute;inset:0;padding:.9in 1.1in;display:flex;flex-direction:column;}
.cover h1{font-family:var(--sans);font-size:34pt;line-height:1.04;letter-spacing:-.022em;margin:0 0 .12in;font-weight:600;}
.cover .sub{font-family:var(--sans);font-size:13pt;color:var(--ink2);margin:0 0 .34in;max-width:7.4in;}
.cover .meta{font-family:var(--plex);font-size:8.6pt;color:var(--muted);line-height:1.9;}
.warn{border:1.6pt solid #B4231E;background:#FFF6F5;color:#7d1a16;padding:12px 15px;margin:.2in 0;
      font-family:var(--sans);font-size:9.6pt;line-height:1.5;max-width:7.6in;}
.warn b{font-size:10.4pt;letter-spacing:.02em;}

/* --- people ------------------------------------------------------------- */
.people{display:grid;grid-template-columns:repeat(5,1fr);gap:12px;margin-top:.16in;}
.person{border-top:3pt solid var(--c);padding-top:9px;}
.person .ini{font-family:var(--plex);font-size:15pt;font-weight:400;color:var(--c);letter-spacing:.04em;}
.person .nm{font-family:var(--sans);font-weight:600;font-size:9.6pt;margin:3px 0 1px;line-height:1.25;}
.person .rl{font-family:var(--sans);font-size:8.2pt;color:var(--ink2);}
.person .wh{font-family:var(--plex);font-size:7.4pt;color:var(--muted);margin:2px 0 6px;}
.person .bio{font-size:8.6pt;line-height:1.42;color:var(--ink2);}

/* --- generic type ------------------------------------------------------- */
h2.sec{font-family:var(--sans);font-size:19pt;font-weight:600;letter-spacing:-.015em;margin:0 0 2px;}
p.dek{font-family:var(--sans);font-size:10pt;color:var(--muted);margin:0 0 .16in;}
h3{font-family:var(--sans);font-size:11pt;font-weight:600;margin:.14in 0 4px;}

/* --- transcript --------------------------------------------------------- */
.tcol{position:absolute;top:.72in;left:.62in;width:6.85in;bottom:.62in;overflow:hidden;}
.gutter{position:absolute;top:.72in;right:.62in;width:2.55in;bottom:.62in;}
.turn{display:grid;grid-template-columns:.42in 1fr;gap:11px;margin-bottom:9px;break-inside:avoid;}
.turn .who{font-family:var(--plex);font-size:8.6pt;color:var(--c);letter-spacing:.05em;padding-top:2px;}
.turn .said{font-size:10.2pt;line-height:1.46;}
.daybar{margin:0 0 10px;border-bottom:1.4pt solid var(--ink);padding-bottom:6px;}
.daybar .d{font-family:var(--plex);font-size:8pt;letter-spacing:.18em;text-transform:uppercase;color:var(--muted);}
.daybar .t{font-family:var(--sans);font-size:17pt;font-weight:600;letter-spacing:-.015em;}
.daybar .s{font-family:var(--sans);font-size:9.4pt;color:var(--ink2);}

/* --- the highlighter ---------------------------------------------------- */
mark.hl{
  background:var(--hl); color:#000; padding:.5px 0; box-decoration-break:clone;
  -webkit-box-decoration-break:clone; border-radius:1px;
}
mark.hl .n{color:#000;}
a.tick{
  font-family:var(--plex);font-size:6.6pt;letter-spacing:.03em;text-decoration:none;
  color:#000;background:#000;color:#FFE94A;padding:1px 3px;margin-left:4px;border-radius:2px;
  vertical-align:.12em;
}

/* --- gutter stubs ------------------------------------------------------- */
.stub{position:absolute;left:0;width:100%;border-left:3pt solid var(--c);padding:3px 0 4px 8px;
      font-family:var(--plex);font-size:7.2pt;line-height:1.32;color:var(--ink2);text-decoration:none;display:block;}
.stub .id{color:var(--c);letter-spacing:.06em;}
.stub .to{color:var(--muted);}
.stub .lb{display:block;color:var(--ink);font-size:6.9pt;margin-top:1px;}
.guthead{position:absolute;top:-16px;left:0;font-family:var(--plex);font-size:6.6pt;
         letter-spacing:.16em;text-transform:uppercase;color:var(--muted);}

/* --- ley lines ---------------------------------------------------------- */
svg.ley{position:absolute;inset:0;width:100%;height:100%;pointer-events:none;z-index:5;}
svg.ley path{fill:none;stroke-width:.9;opacity:.85;}
svg.ley circle{stroke:none;}

/* --- plates ------------------------------------------------------------- */
.plate{position:absolute;top:.72in;left:3.05in;right:.62in;bottom:.62in;
       display:flex;flex-direction:column;justify-content:center;gap:12px;}
/* flex:1 1 0 with min-height:0 makes the figures divide the column between
   them. Without min-height:0 a flex item refuses to shrink below its content
   and every figure on a three-figure plate tries to claim the full height. */
.figwrap{position:relative;flex:1 1 0;min-height:0;display:flex;flex-direction:column;
         align-items:center;justify-content:center;}
.figwrap img{max-width:100%;max-height:calc(100% - 12px);width:auto;height:auto;
             object-fit:contain;display:block;border:.5pt solid var(--rule);}
.figcap{font-family:var(--plex);font-size:6.4pt;color:var(--muted);margin-top:3px;align-self:flex-start;}
.rbox{position:absolute;border:1.6pt solid var(--c);background:rgba(255,233,74,.26);}
/* A region that is most of the figure is a pointer at the figure, not a
   highlight within it. Flooding it in yellow buries the trace it is pointing
   at, so those get an outline only. */
.rbox.whole{background:rgba(255,233,74,.07);border-style:dashed;}
.rflag{position:absolute;font-family:var(--plex);font-size:7pt;background:#000;color:var(--hl);
       padding:1px 4px;border-radius:2px;white-space:nowrap;transform:translate(0,-100%);}
.pgut{position:absolute;top:.72in;left:.62in;width:2.25in;bottom:.62in;}
.pgut .rstub{border-left:3pt solid var(--c);padding:4px 0 6px 8px;margin-bottom:9px;display:block;
             text-decoration:none;font-family:var(--plex);font-size:7.4pt;line-height:1.35;color:var(--ink2);}
.pgut .rstub .id{color:var(--c);letter-spacing:.06em;}
.pgut .rstub .lb{display:block;color:var(--ink);font-size:7pt;margin-top:2px;}
.pgut .rstub .from{display:block;color:var(--muted);font-size:6.6pt;margin-top:3px;}

/* --- tables ------------------------------------------------------------- */
table{width:100%;border-collapse:collapse;font-size:8.6pt;}
th{font-family:var(--plex);font-size:6.9pt;letter-spacing:.13em;text-transform:uppercase;
   color:var(--muted);text-align:left;border-bottom:.8pt solid var(--ink);padding:0 8px 4px 0;font-weight:400;}
td{padding:4px 8px 4px 0;border-bottom:.4pt solid var(--rule2);vertical-align:top;line-height:1.35;}
td.k{font-family:var(--plex);font-size:7.4pt;color:var(--muted);white-space:nowrap;}
.oa{font-family:var(--plex);font-size:6.6pt;background:#1f6b4d;color:#fff;padding:1px 4px;border-radius:2px;}
.pw{font-family:var(--plex);font-size:6.6pt;background:#e6e9ef;color:var(--muted);padding:1px 4px;border-radius:2px;}
.verdict{background:var(--panel);border-left:3pt solid var(--ink);padding:8px 11px;margin-top:7px;
         font-size:9pt;line-height:1.45;}
.cols2{column-count:2;column-gap:.34in;}
.src{margin-bottom:7px;break-inside:avoid;}
.src .c{font-size:8.6pt;line-height:1.34;}
.src .nt{font-size:8.2pt;color:var(--ink2);line-height:1.36;margin-top:2px;}
.src .u{font-family:var(--plex);font-size:6.8pt;color:#2F5FA8;word-break:break-all;}

/* --- link map ----------------------------------------------------------- */
.map{position:absolute;top:.72in;left:.62in;right:.62in;bottom:.62in;}
.mapnode{position:absolute;font-family:var(--plex);font-size:7pt;white-space:nowrap;}
}
out "</style></head><body>"

# ===========================================================================
# helper page shells
# ===========================================================================
set PAGENO 0
proc pageOpen {kind {rhL ""} {rhR ""}} {
    global PAGENO
    incr PAGENO
    out "<section class=\"page $kind\" data-pg=\"$PAGENO\">"
    if {$rhL ne "" || $rhR ne ""} {
        out "<div class=\"rh\"><span>[esc $rhL]</span><span>[esc $rhR]</span></div>"
    }
    return $PAGENO
}
proc pageClose {{fL ""} {fR ""}} {
    global PAGENO
    out "<div class=\"rf\"><span>[esc $fL]</span><span>[esc $fR]</span></div>"
    out "</section>"
}

# ---------------------------------------------------------------------------
# 1. Cover
# ---------------------------------------------------------------------------
pageOpen pg-cover
out {<div class="cover">}
out {<div style="flex:1">}
out {<div class="meta" style="margin-bottom:.5in">SUBJ-001 &nbsp;&middot;&nbsp; SESSION 2026-08-18 &nbsp;&middot;&nbsp; FIVE INSTRUMENTS &nbsp;&middot;&nbsp; NINETEEN SCANNED PAGES</div>}
out {<h1>Proceedings of a Working Conference<br>on a Single Afternoon of Measurement</h1>}
out {<p class="sub">Five readers, five days, one battery. With transpointing links from every claim back to the page it was read off.</p>}
out {<div class="warn"><b>THIS IS A SIMULATION.</b><br>
The five participants are invented composite characters. They are not real people, they are not modelled on
real people, and their institutional affiliations are fictional. No clinician has reviewed this record.
The arguments are drawn from the published literature catalogued on the following pages, but they are
arguments assembled by software and put into imaginary mouths, and they carry exactly that much weight.
This document is not medical advice, not a consultation, and not a diagnosis.</div>}
out {</div>}
out {<div class="meta">GENERATED BY conference/build.tcl &nbsp;&middot;&nbsp; LEY LINES DRAWN AFTER LAYOUT &nbsp;&middot;&nbsp; SET IN IBM PLEX MONO AND A TRANSITIONAL SERIF</div>}
out {</div>}
pageClose "" ""

# ---------------------------------------------------------------------------
# 2. Participants
# ---------------------------------------------------------------------------
pageOpen "" "The participants" "Simulated"
out {<div class="body">}
out {<h2 class="sec">Who is in the room</h2>}
out {<p class="dek">Colour is used consistently: each participant's colour marks their gutter stubs and their ley lines throughout.</p>}
out {<div class="people">}
foreach k {AR NF IV KM PR} {
    set p [dict get $PEOPLE $k]
    out "<div class=\"person\" style=\"--c:[dict get $p colour]\">"
    out "<div class=\"ini\">[dict get $p initials]</div>"
    out "<div class=\"nm\">[esc [dict get $p name]]</div>"
    out "<div class=\"rl\">[esc [dict get $p role]]</div>"
    out "<div class=\"wh\">[esc [dict get $p where]]</div>"
    out "<div class=\"bio\">[esc [dict get $p bio]]</div>"
    out "</div>"
}
out {</div>}

out {<h3 style="margin-top:.3in">How to read the links</h3>}
out {<div style="display:grid;grid-template-columns:1.6fr 1fr;gap:.34in;font-size:9.2pt;line-height:1.5">}
out {<div>
<p style="margin:0 0 7px">A claim in the transcript that rests on something visible in the source documents is
<mark class="hl">highlighted<a class="tick" href="#linkindex">L-000</a></mark> and carries a link id. A ley line
runs from the highlight out to a stub in the right margin. The stub names the target page and region.</p>
<p style="margin:0 0 7px">The target lives on one of the annotated plates at the back. There the line runs the
other way &mdash; from a stub in the left margin into a boxed region on the figure itself.</p>
<p style="margin:0">Paper cannot carry a line across a page break, so a link is two half-lines that meet at the
page edge, in the same colour, under the same id. In the PDF both stubs are live: click either end. The last
spread draws every link at once, which is the only place the full structure is visible.</p>
</div>}
out {<div style="background:var(--panel);padding:11px 13px;font-family:var(--plex);font-size:7.6pt;line-height:1.75">
<div style="letter-spacing:.14em;color:var(--muted);margin-bottom:6px">LEGEND</div>
<div><span style="background:#FFE94A;color:#000;padding:1px 4px">yellow</span> &nbsp;a claim with a source</div>
<div><span style="background:#000;color:#FFE94A;padding:1px 4px">L-014</span> &nbsp;link id, clickable</div>
<div><span style="border-left:3pt solid #2F5FA8;padding-left:6px">stub</span> &nbsp;margin anchor, coloured by speaker</div>
<div><span style="border:1.6pt solid #A8306B;background:rgba(255,233,74,.3);padding:1px 5px">box</span> &nbsp;the annotated region</div>
<div style="margin-top:6px;color:var(--muted)">every numeral is set in IBM&nbsp;Plex&nbsp;Mono</div>
</div>}
out {</div>}
out {</div>}
pageClose "" "2"

# ---------------------------------------------------------------------------
# 3. Origins &mdash; one page per test area, flowed
# ---------------------------------------------------------------------------
proc srcBlock {s} {
    set h "<div class=\"src\">"
    append h "<div class=\"c\">[nums [esc [dict get $s cite]]]"
    if {[dict get $s oa]} { append h " <span class=\"oa\">OPEN</span>" } else { append h " <span class=\"pw\">PAYWALL</span>" }
    append h "</div>"
    if {[dict get $s note] ne ""} { append h "<div class=\"nt\">[nums [esc [dict get $s note]]]</div>" }
    if {[dict get $s url] ne ""}  { append h "<div class=\"u\">[esc [dict get $s url]]</div>" }
    append h "</div>"
    return $h
}

set ORDER {eeg erp hrv spt psych photic}
set n 0
foreach key $ORDER {
    set S [dict get $SOURCES $key]
    pageOpen "" "Origins and cross-correlation" [dict get $S test]
    out {<div class="body">}
    out "<h2 class=\"sec\">[esc [dict get $S test]]</h2>"
    out {<p class="dek">Left: the twentieth-century work that created the measurement. Right: what the literature has done to it since, weighted toward the last three years.</p>}
    out {<div style="display:grid;grid-template-columns:1fr 1fr;gap:.34in">}
    out {<div><h3 style="margin-top:0">Origin</h3>}
    foreach s [dict get $S origin] { out [srcBlock $s] }
    out {</div>}
    out {<div><h3 style="margin-top:0">Cross-correlation &mdash; PubMed and the journals</h3>}
    foreach s [dict get $S modern] { out [srcBlock $s] }
    out {</div>}
    out {</div>}
    out "<div class=\"verdict\"><b>Weight this record can carry.</b> [nums [esc [dict get $S verdict]]]</div>"
    out {</div>}
    incr n
    pageClose "" [expr {$PAGENO}]
}

# ---------------------------------------------------------------------------
# 4. Transcript &mdash; emitted as a pool; JS paginates into .page shells
# ---------------------------------------------------------------------------
out {<div id="pool" style="display:none">}
foreach D $DAYS {
    set dn [dict get $D n]
    out "<div class=\"daybar\" data-day=\"$dn\" data-title=\"[esc [dict get $D title]]\">"
    out "<div class=\"d\">Day $dn of 5</div>"
    out "<div class=\"t\">[esc [dict get $D title]]</div>"
    out "<div class=\"s\">[esc [dict get $D subtitle]]</div></div>"
    foreach t [dict get $D turns] {
        lassign $t sp text
        set p [dict get $PEOPLE $sp]
        lassign [marks $text $sp] html used
        out "<div class=\"turn\" data-day=\"$dn\" style=\"--c:[dict get $p colour]\">"
        out "<div class=\"who\">[dict get $p initials]</div>"
        out "<div class=\"said\">$html</div></div>"
    }
}
out {</div>}

# ---------------------------------------------------------------------------
# 5. Annotated plates
# ---------------------------------------------------------------------------
foreach PL $PLATES {
    lassign $PL pid ptitle figs
    # which regions land on this plate
    set rs {}
    foreach rid [dict keys $REGIONS] {
        set r [dict get $REGIONS $rid]
        if {[lsearch -exact $figs [dict get $r fig]] >= 0} { lappend rs $rid }
    }
    set rs [lsort $rs]

    pageOpen "pg-plate" "Annotated source &mdash; plate $pid" $ptitle
    out {<div class="pgut">}
    out {<div class="guthead" style="position:absolute;top:-16px;left:0;font-family:var(--plex);font-size:6.6pt;letter-spacing:.16em;text-transform:uppercase;color:var(--muted)">Incoming links</div>}
    foreach rid $rs {
        set r [dict get $REGIONS $rid]
        # who pointed here
        set froms {}
        dict for {lid target} $LINKS {
            if {$target eq $rid} { lappend froms $lid }
        }
        # colour = first inbound speaker, resolved in JS; default to ink
        out "<a class=\"rstub\" id=\"reg-$rid\" data-region=\"$rid\" href=\"#src-[lindex $froms 0]\" style=\"--c:#14161c\">"
        out "<span class=\"id\">$rid</span>"
        out "<span class=\"lb\">[nums [esc [dict get $r label]]]</span>"
        out "<span class=\"from\">cited at [nums [esc [join $froms {, }]]]</span>"
        out "</a>"
    }
    out {</div>}

    out {<div class="plate">}
    foreach f $figs {
        set k [figKey $f]
        if {$k eq ""} { continue }
        out "<div class=\"figwrap\" data-fig=\"$f\">"
        out "<img src=\"data:image/png;base64,[dict get $IMG $k]\" alt=\"[esc $f]\">"
        out "<div class=\"figcap\">[esc $k].tiff</div>"
        out "</div>"
    }
    out {</div>}
    pageClose "Plate $pid" $PAGENO
}

# ---------------------------------------------------------------------------
# 6. Link index
# ---------------------------------------------------------------------------
pageOpen "" "Link index" "Every transpointing link in the document"
out {<div class="body">}
out {<h2 class="sec">Link index</h2>}
out {<p class="dek">Source page and target plate are filled in after layout. Both ends are live in the PDF.</p>}
out {<div class="cols2"><table id="linkindex"><thead><tr>}
out {<th>Link</th><th>Said by</th><th>Page</th><th>Region</th><th>What it points at</th>}
out {</tr></thead><tbody>}
dict for {lid rid} $LINKS {
    set r [dict get $REGIONS $rid]
    out "<tr data-link=\"$lid\"><td class=\"k\">$lid</td><td class=\"k sp\">&mdash;</td><td class=\"k pg\">&mdash;</td>"
    out "<td class=\"k\">$rid</td><td>[nums [esc [dict get $r label]]]</td></tr>"
}
out {</tbody></table></div>}
out {</div>}
pageClose "" $PAGENO

# ---------------------------------------------------------------------------
# 7. The link map
# ---------------------------------------------------------------------------
pageOpen "pg-map" "Link map" "All links at once"
out {<div class="body" style="bottom:.9in">}
out {<h2 class="sec">The whole structure on one sheet</h2>}
out {<p class="dek">Left: transcript pages. Right: annotated regions. Every curve is one link, coloured by who drew it. This is the only page where the ley lines are visible as a system rather than as fragments meeting a page edge.</p>}
out {<div class="map" id="linkmap" style="top:1.35in"></div>}
out {</div>}
pageClose "" $PAGENO

# ---------------------------------------------------------------------------
# JS: paginate, draw, cross-reference
# ---------------------------------------------------------------------------
out {<script>
"use strict";
/* ---------------------------------------------------------------------------
   Layout runs in three passes, in this order, because each needs the previous
   one to have settled:
     1. paginate  -- move transcript turns into fixed-size pages
     2. anchor    -- place gutter stubs opposite their highlights
     3. draw      -- measure both endpoints and stroke the ley lines
   Chromium's print-to-PDF fires after all of this, so what is measured is what
   is printed.
--------------------------------------------------------------------------- */
}
out "const LINKS = {"
dict for {lid rid} $LINKS {
    set r [dict get $REGIONS $rid]
    out "\"$lid\":{r:\"$rid\",label:[jsstr [dict get $r label]]},"
}
out "};"

out "const REGIONS = {"
dict for {rid r} $REGIONS {
    lassign [dict get $r box] bx by bw bh
    out "\"$rid\":{fig:\"[dict get $r fig]\",box:\[$bx,$by,$bw,$bh\],label:[jsstr [dict get $r label]]},"
}
out "};"

out "const SPCOL = {"
foreach k {AR NF IV KM PR} { out "\"$k\":\"[dict get [dict get $PEOPLE $k] colour]\"," }
out "};"

out {
/* Images are inlined as base64, which does NOT mean they are laid out by the
   time this script runs. Measuring a region box against an undecoded image
   yields zero width and throws the ley line off the page. Everything below
   therefore waits for decode. */
function start(){

/* --- 1. pagination ------------------------------------------------------ */
const pool = document.getElementById("pool");
const items = Array.from(pool.children);
const platesFirst = document.querySelector(".page.pg-plate");

function makeTranscriptPage(day, title){
  const p = document.createElement("section");
  p.className = "page pg-transcript";
  p.innerHTML =
    '<div class="rh"><span>Day ' + day + ' &mdash; ' + title + '</span><span>Simulated proceedings</span></div>' +
    '<div class="tcol"></div>' +
    '<div class="gutter"><div class="guthead">Links from this page</div></div>' +
    '<svg class="ley"></svg>' +
    '<div class="rf"><span></span><span class="pn"></span></div>';
  platesFirst.parentNode.insertBefore(p, platesFirst);
  return p;
}

/* A day starts a new page only when the current one is nearly full. Forcing a
   break at every day boundary produced pages holding a single orphaned line,
   which reads as a bug rather than as a section break. 210px is a little under
   two inches -- below that there is no room for a heading plus a first turn.
   Room is measured from the bottom of the last child, NOT from scrollHeight:
   on a box with top and bottom both pinned, scrollHeight never reports below
   clientHeight, so the difference is always zero and every day would break. */
const MIN_ROOM = 210;
function roomLeft(col){
  const last = col.lastElementChild;
  if (!last) return col.clientHeight;
  return col.getBoundingClientRect().bottom - last.getBoundingClientRect().bottom;
}
let curDay = 0, curTitle = "", page = null, col = null;
for (const el of items){
  if (el.classList.contains("daybar")){
    curDay = el.dataset.day; curTitle = el.dataset.title;
    if (!page || roomLeft(col) < MIN_ROOM){
      page = makeTranscriptPage(curDay, curTitle);
      col = page.querySelector(".tcol");
    } else {
      el.style.marginTop = "16px";
      page.querySelector(".rh span").textContent =
        page.querySelector(".rh span").textContent + "  /  Day " + curDay + " " + curTitle;
    }
    col.appendChild(el);
    continue;
  }
  col.appendChild(el);
  if (col.scrollHeight > col.clientHeight){
    col.removeChild(el);
    page = makeTranscriptPage(curDay, curTitle);
    col = page.querySelector(".tcol");
    col.appendChild(el);
  }
}
pool.remove();

/* --- renumber every page ------------------------------------------------ */
const pages = Array.from(document.querySelectorAll(".page"));
pages.forEach((p,i) => {
  p.dataset.pg = i+1;
  const pn = p.querySelector(".rf .pn") || p.querySelector(".rf span:last-child");
  if (pn) pn.textContent = i+1;
});
const pgOf = el => { const p = el.closest(".page"); return p ? +p.dataset.pg : 0; };

/* --- 2. stubs opposite their highlights --------------------------------- */
/* Placing a stub at its highlight's own vertical position is what makes the
   ley line short and readable. Where two links land within 16px of each other
   the later one is pushed down, because two curves ending on the same point
   is indistinguishable from one curve. */
const regionPage = {};
document.querySelectorAll("a.rstub[data-region]").forEach(a => regionPage[a.dataset.region] = pgOf(a));

document.querySelectorAll(".page.pg-transcript").forEach(page => {
  const gut = page.querySelector(".gutter");
  const gr = gut.getBoundingClientRect();
  let lastY = -999;
  page.querySelectorAll("mark.hl[data-link]").forEach(m => {
    const id  = m.dataset.link, sp = m.dataset.sp;
    const L   = LINKS[id]; if (!L) return;
    const mr  = m.getBoundingClientRect();
    let y = mr.top - gr.top;
    if (y < lastY + 34) y = lastY + 34;
    lastY = y;
    const a = document.createElement("a");
    a.className = "stub";
    a.href = "#reg-" + L.r;
    a.style.setProperty("--c", SPCOL[sp] || "#14161c");
    a.style.top = y + "px";
    a.dataset.for = id;
    a.innerHTML = '<span class="id">' + id + '</span> <span class="to">&rarr; p.' +
                  (regionPage[L.r]||"?") + ' ' + L.r + '</span>' +
                  '<span class="lb">' + L.label + '</span>';
    gut.appendChild(a);
  });
});

/* --- 3. region boxes on the plates -------------------------------------- */
/* Drawn as absolutely-positioned overlays measured against the rendered image
   rather than baked into the image, so the same normalised box survives a
   change of figure resolution. */
document.querySelectorAll(".page.pg-plate").forEach(page => {
  const inbound = {};
  page.querySelectorAll("a.rstub[data-region]").forEach(a => {
    const rid = a.dataset.region;
    for (const lid in LINKS) if (LINKS[lid].r === rid) (inbound[rid] ||= []).push(lid);
  });
  page.querySelectorAll(".figwrap").forEach(w => {
    const img = w.querySelector("img");
    for (const rid in REGIONS){
      const R = REGIONS[rid];
      if (R.fig !== w.dataset.fig) continue;
      const stub = page.querySelector('a.rstub[data-region="' + rid + '"]');
      const sp = stub ? getComputedStyle(stub).getPropertyValue("--c") : "#14161c";
      const b = document.createElement("div");
      b.className = "rbox" + ((R.box[2]*R.box[3] > 0.55) ? " whole" : "");
      b.dataset.region = rid;
      b.style.setProperty("--c", sp);
      const iw = img.offsetWidth, ih = img.offsetHeight;
      const ix = img.offsetLeft, iy = img.offsetTop;
      b.style.left = (ix + R.box[0]*iw) + "px";
      b.style.top  = (iy + R.box[1]*ih) + "px";
      b.style.width  = (R.box[2]*iw) + "px";
      b.style.height = (R.box[3]*ih) + "px";
      w.appendChild(b);
      const f = document.createElement("div");
      f.className = "rflag";
      f.textContent = rid;
      f.style.left = b.style.left; f.style.top = b.style.top;
      w.appendChild(f);
    }
  });
});

/* --- 4. colour the plate stubs by their first inbound speaker ------------ */
const speakerOf = {};
document.querySelectorAll("mark.hl[data-link]").forEach(m => speakerOf[m.dataset.link] = m.dataset.sp);
document.querySelectorAll("a.rstub[data-region]").forEach(a => {
  const rid = a.dataset.region;
  for (const lid in LINKS) if (LINKS[lid].r === rid && speakerOf[lid]){
    a.style.setProperty("--c", SPCOL[speakerOf[lid]]);
    break;
  }
});
document.querySelectorAll(".rbox").forEach(b => {
  const stub = document.querySelector('a.rstub[data-region="' + b.dataset.region + '"]');
  if (stub) b.style.setProperty("--c", getComputedStyle(stub).getPropertyValue("--c"));
});

/* --- 5. draw the ley lines ---------------------------------------------- */
/* A cubic with purely horizontal control handles. The handle length is capped
   so that a link spanning most of the page does not bow out past the trim --
   an uncapped 0.42 of a nine-inch span throws the curve off the sheet. */
function curve(svg, x1,y1,x2,y2, colour){
  const dx = Math.min(90, Math.max(22, Math.abs(x2-x1)*0.38));
  const d = "M" + x1 + "," + y1 + " C" + (x1+dx) + "," + y1 + " " + (x2-dx) + "," + y2 + " " + x2 + "," + y2;
  const p = document.createElementNS("http://www.w3.org/2000/svg","path");
  p.setAttribute("d", d); p.setAttribute("stroke", colour);
  svg.appendChild(p);
  for (const [cx,cy] of [[x1,y1],[x2,y2]]){
    const c = document.createElementNS("http://www.w3.org/2000/svg","circle");
    c.setAttribute("cx",cx); c.setAttribute("cy",cy); c.setAttribute("r",2.1);
    c.setAttribute("fill",colour); svg.appendChild(c);
  }
}

document.querySelectorAll(".page.pg-transcript").forEach(page => {
  const svg = page.querySelector("svg.ley");
  const pr = page.getBoundingClientRect();
  const cr = page.querySelector(".tcol").getBoundingClientRect();
  page.querySelectorAll("mark.hl[data-link]").forEach(m => {
    const stub = page.querySelector('.stub[data-for="' + m.dataset.link + '"]');
    if (!stub) return;
    const mr = m.getBoundingClientRect(), sr = stub.getBoundingClientRect();
    /* The line leaves from the RIGHT EDGE OF THE COLUMN at the highlight's
       height, not from the right edge of the highlight itself. Starting at the
       mark draws the line straight through whatever sentence follows it on the
       same line, which reads as a strike-through. */
    curve(svg,
      Math.max(mr.right, cr.right - 2) - pr.left, mr.top - pr.top + mr.height/2,
      sr.left - pr.left, sr.top - pr.top + 7,
      SPCOL[m.dataset.sp] || "#14161c");
  });
});

/* Plates route orthogonally rather than as a free curve. A bezier from a left
   gutter to a box in the middle of a wide figure sweeps diagonally across the
   whole trace; a stub, a vertical spine and a horizontal approach stay out of
   the way and read as a route rather than as a scribble. */
function routed(svg, x1,y1,x2,y2, colour, spineX){
  const r = 7, dir = (y2 > y1) ? 1 : -1;
  let d;
  if (Math.abs(y2-y1) < 2*r + 2 || spineX <= x1 + r || spineX >= x2 - r){
    d = "M"+x1+","+y1+" L"+x2+","+y2;
  } else {
    d = "M"+x1+","+y1+" L"+(spineX-r)+","+y1+
        " Q"+spineX+","+y1+" "+spineX+","+(y1+dir*r)+
        " L"+spineX+","+(y2-dir*r)+
        " Q"+spineX+","+y2+" "+(spineX+r)+","+y2+
        " L"+x2+","+y2;
  }
  const p = document.createElementNS("http://www.w3.org/2000/svg","path");
  p.setAttribute("d", d); p.setAttribute("stroke", colour);
  svg.appendChild(p);
  for (const [cx,cy] of [[x1,y1],[x2,y2]]){
    const c = document.createElementNS("http://www.w3.org/2000/svg","circle");
    c.setAttribute("cx",cx); c.setAttribute("cy",cy); c.setAttribute("r",2.1);
    c.setAttribute("fill",colour); svg.appendChild(c);
  }
}

document.querySelectorAll(".page.pg-plate").forEach(page => {
  let svg = page.querySelector("svg.ley");
  if (!svg){
    svg = document.createElementNS("http://www.w3.org/2000/svg","svg");
    svg.setAttribute("class","ley"); page.appendChild(svg);
  }
  const pr = page.getBoundingClientRect();
  page.querySelectorAll("a.rstub[data-region]").forEach(stub => {
    const box = page.querySelector('.rbox[data-region="' + stub.dataset.region + '"]');
    if (!box) return;
    const sr = stub.getBoundingClientRect(), br = box.getBoundingClientRect();
    const x1 = sr.right - pr.left;
    routed(svg,
      x1, sr.top - pr.top + 8,
      br.left - pr.left, br.top - pr.top + br.height/2,
      getComputedStyle(stub).getPropertyValue("--c").trim() || "#14161c",
      x1 + 20);
  });
});

/* --- 6. fill the link index --------------------------------------------- */
document.querySelectorAll("#linkindex tbody tr").forEach(tr => {
  const lid = tr.dataset.link;
  const m = document.getElementById("src-" + lid);
  if (m){
    tr.querySelector(".sp").textContent = m.dataset.sp;
    tr.querySelector(".pg").textContent = pgOf(m) + " \u2192 " + (regionPage[LINKS[lid].r]||"?");
  }
});

/* --- 7. the link map ---------------------------------------------------- */
/* Bundled edges: every link leaves its transcript page from one point and
   enters its region at another, and the bundle is what shows which
   participant's argument depends on which part of the record. */
(function(){
  const host = document.getElementById("linkmap");
  if (!host) return;
  const W = host.clientWidth, H = host.clientHeight;
  const srcPages = [...new Set(Object.keys(LINKS).map(l => {
    const m = document.getElementById("src-"+l); return m ? pgOf(m) : null;
  }).filter(Boolean))].sort((a,b)=>a-b);
  const regs = Object.keys(REGIONS).sort();

  const svg = document.createElementNS("http://www.w3.org/2000/svg","svg");
  svg.setAttribute("class","ley"); svg.style.pointerEvents = "none";
  host.appendChild(svg);

  const lx = 118, rx = W - 300;
  const sy = p => 16 + srcPages.indexOf(p) * ((H-40) / Math.max(1,srcPages.length-1));
  const ry = r => 16 + regs.indexOf(r) * ((H-40) / Math.max(1,regs.length-1));

  srcPages.forEach(p => {
    const d = document.createElement("div");
    d.className = "mapnode";
    d.style.left = "0px"; d.style.top = (sy(p)-6) + "px";
    d.innerHTML = '<span style="color:#6b7183">transcript p.</span>' + p;
    host.appendChild(d);
  });
  regs.forEach(r => {
    const R = REGIONS[r];
    const d = document.createElement("div");
    d.className = "mapnode";
    d.style.left = (rx + 14) + "px"; d.style.top = (ry(r)-6) + "px";
    d.innerHTML = '<b>'+r+'</b> <span style="color:#6b7183">'+R.label.slice(0,46)+'</span>';
    host.appendChild(d);
  });

  for (const lid in LINKS){
    const m = document.getElementById("src-"+lid);
    if (!m) continue;
    const p = pgOf(m), r = LINKS[lid].r;
    const y1 = sy(p), y2 = ry(r);
    const mid = (lx + rx) / 2;
    const path = document.createElementNS("http://www.w3.org/2000/svg","path");
    path.setAttribute("d","M"+lx+","+y1+" C"+mid+","+y1+" "+mid+","+y2+" "+rx+","+y2);
    path.setAttribute("stroke", SPCOL[m.dataset.sp] || "#14161c");
    path.setAttribute("stroke-width","0.8");
    path.setAttribute("opacity","0.62");
    svg.appendChild(path);
  }
  srcPages.forEach(p => { const c=document.createElementNS("http://www.w3.org/2000/svg","circle");
    c.setAttribute("cx",lx);c.setAttribute("cy",sy(p));c.setAttribute("r",2.6);c.setAttribute("fill","#14161c");svg.appendChild(c); });
  regs.forEach(r => { const c=document.createElementNS("http://www.w3.org/2000/svg","circle");
    c.setAttribute("cx",rx);c.setAttribute("cy",ry(r));c.setAttribute("r",2.6);c.setAttribute("fill","#14161c");svg.appendChild(c); });
})();

document.documentElement.dataset.ready = "1";
}

Promise.all(Array.from(document.images).map(i =>
  i.decode ? i.decode().catch(() => {}) : Promise.resolve()
)).then(start);
</script>}
out {</body></html>}

# ---------------------------------------------------------------------------
set f [open $OUT w]
fconfigure $f -encoding utf-8
puts -nonewline $f $H
close $f
puts stderr [format "conference: wrote %s  (%.0f kB, %d fixed pages before pagination, %d links, %d regions)" \
    $OUT [expr {[string length $H]/1024.0}] $PAGENO [dict size $LINKS] [dict size $REGIONS]]
