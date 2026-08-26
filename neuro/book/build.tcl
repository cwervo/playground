#!/usr/bin/env tclsh
# build.tcl &mdash; set the record as a large-format art book and print it.
#
#   tclsh book/build.tcl --out build/book/one-afternoon.html
#   node  book/topdf.mjs build/book/one-afternoon.html build/book/one-afternoon.pdf
#
# 300 x 380 mm, portrait, the size a big illustrated monograph is actually
# printed at. Every page is composed by hand rather than flowed: a coffee-table
# book is a sequence of designed spreads, and text that reflows into whatever
# space is left over is exactly what makes a document look like a report.
#
# WHERE THE NUMBERS COME FROM
# ---------------------------------------------------------------------------
# From build/dashboard.nvm and nowhere else. The display file carries the
# symbol table -- every measured value with its reference band, its signed
# deviation and its distance past threshold -- and a meta block with the five
# hypotheses and their permutation results. So this book is another host for
# the same bytecode the browser, the plotter and the 3D printer execute, and it
# cannot disagree with them about a number. It never opens the session JSON.
#
# THE QR CODES
# ---------------------------------------------------------------------------
# Every citation in the bibliography carries one, encoded by book/qr.tcl and
# drawn as SVG geometry rather than a bitmap, so it stays sharp at whatever
# resolution the page is printed at. A bibliography in a book is a dead end --
# you read the reference, you do not go and get the paper. A code you can point
# a phone at is the difference between citing a source and providing it.

encoding system utf-8

set here [file dirname [file normalize [info script]]]
set root [file dirname $here]
lappend auto_path [file join $root tcl]

source [file join $here qr.tcl]
package require nvm
source [file join $root conference sources.tcl]

set IMGDIR [file join $root build conference img]
set FRAMES [file join $root build book]
set NVM    [file join $root build dashboard.nvm]
set OUT    [file join $root build book one-afternoon.html]
for {set i 0} {$i < $argc} {incr i} {
    switch -- [lindex $argv $i] {
        --img    { set IMGDIR [lindex $argv [incr i]] }
        --frames { set FRAMES [lindex $argv [incr i]] }
        --nvm    { set NVM    [lindex $argv [incr i]] }
        --out    { set OUT    [lindex $argv [incr i]] }
    }
}
file mkdir [file dirname $OUT]

# ---------------------------------------------------------------------------
# the display file
# ---------------------------------------------------------------------------
set BC [nvm::load $NVM]
if {![dict get $BC crcOk]} {puts stderr "book: WARNING display file CRC does not check out"}

proc S {id} {
    global BC
    set s [nvm::sym $BC $id]
    if {$s eq ""} {error "book: no symbol '$id' in the display file"}
    return $s
}
proc V {id {dp 2}} {
    set v [dict get [S $id] value]
    return [format %.${dp}f $v]
}
proc SDEV {id {dp 2}} {return [format %+.${dp}f [dict get [S $id] z]]}
proc DIST {id {dp 3}} {return [format %.${dp}f [dict get [S $id] dist]]}
proc LABEL {id} {return [dict get [S $id] label]}
proc REF {id} {
    set s [S $id]
    if {![dict get $s hasRef]} {return "&mdash;"}
    set lo [dict get $s refLo]
    set hi [dict get $s refHi]
    if {$lo <= -3.0e38} {return "max [trim $hi]"}
    if {$hi >= 3.0e38} {return "min [trim $lo]"}
    return "[trim $lo]&ndash;[trim $hi]"
}
proc trim {v} {
    set s [format %.4g $v]
    return $s
}

# The meta block is JSON emitted by src/analyze.cpp. This is a targeted reader
# for that one emitter -- it knows the shape it is looking for -- and not a
# general JSON parser. If the emitter changes, this has to change with it.
set META [dict get $BC meta]
set HYP {}
foreach m [regexp -all -inline {\{"id":"(H\d)","name":"([^"]*)","C":([-0-9.e+]+),"p":([-0-9.e+]+),"nullMean":([-0-9.e+]+),"nullSd":([-0-9.e+]+),"zVsNull":([-0-9.e+]+),"edgesUsable":(\d+),"edgesTotal":(\d+)\}} $META] {
    lappend HYP $m
}
set HYPS {}
foreach {all id name C p nm nsd z eu et} $HYP {
    lappend HYPS [dict create id $id name $name C $C p $p nullSd $nsd z $z edges $eu]
}
if {[llength $HYPS] != 5} {error "book: expected 5 hypotheses in the display file, found [llength $HYPS]"}
regexp {"permutations":(\d+)} $META -> PERMS
regexp {"seed":(\d+)} $META -> SEED
regexp {"date":"([^"]+)"} $META -> DATE
regexp {"metricsMeasured":(\d+)} $META -> NMETRICS
regexp {Immune load: (\d+) of (\d+)} $META -> IMMPOS IMMN

# ---------------------------------------------------------------------------
# emitters
# ---------------------------------------------------------------------------
set ::H {}
proc out {s} {append ::H $s "\n"}
proc raw {s} {append ::H $s}

proc esc {s} {
    return [string map {& &amp; < &lt; > &gt; \" &quot;} $s]
}

# Numerals in IBM Plex Mono, as in the conference proceedings: a digit that is
# part of a word (P300, GAD-7, 10-20) stays in the running face.
proc nums {s} {
    set out ""
    set i 0
    set n [string length $s]
    while {$i < $n} {
        set c [string index $s $i]
        if {[string is digit $c]} {
            set prev [expr {$i > 0 ? [string index $s $i-1] : ""}]
            if {[string is alpha $prev]} {append out $c; incr i; continue}
            set run ""
            while {$i < $n && [regexp {[0-9.,]} [string index $s $i]]} {
                append run [string index $s $i]
                incr i
            }
            append out "<span class=n>$run</span>"
        } else {
            append out $c
            incr i
        }
    }
    return $out
}

proc b64 {path} {
    if {![file exists $path]} {puts stderr "book: missing $path"; return ""}
    set f [open $path rb]
    set d [read $f]
    close $f
    return [binary encode base64 $d]
}

proc figure {stem} {
    global IMGDIR
    foreach f [lsort [glob -nocomplain -directory $IMGDIR ${stem}_*.png]] {
        return "data:image/png;base64,[b64 $f]"
    }
    puts stderr "book: no figure $stem"
    return ""
}

proc frame {name} {
    global FRAMES
    set p [file join $FRAMES $name]
    if {![file exists $p]} {puts stderr "book: no frame $name"; return ""}
    return "data:image/png;base64,[b64 $p]"
}

set ::PAGE 0
set ::CONTENTS {}
proc page {cls body {chapter ""}} {
    incr ::PAGE
    if {$chapter ne ""} {lappend ::CONTENTS [list $chapter $::PAGE]}
    out "<section class=\"page $cls\" id=\"p$::PAGE\">$body<div class=folio>[expr {$::PAGE % 2 ? "" : ""}]<span class=n>$::PAGE</span></div></section>"
    return $::PAGE
}

# a plate caption, the small block that sits under or beside every image
proc cap {n title body} {
    return "<div class=cap><div class=capn>PLATE&nbsp;<span class=n>$n</span></div>\
<div class=capt>[nums $title]</div><div class=capb>[nums $body]</div></div>"
}

# ---------------------------------------------------------------------------
# fonts and style
# ---------------------------------------------------------------------------
set FDIR [file join $root assets fonts]
set F_SERIF   [b64 [file join $FDIR IBMPlexSerif-Regular.ttf]]
set F_SERIF_B [b64 [file join $FDIR IBMPlexSerif-Bold.ttf]]
set F_MONO    [b64 [file join $FDIR IBMPlexMono-Regular.ttf]]
set F_MONO_B  [b64 [file join $FDIR IBMPlexMono-Bold.ttf]]

out {<!doctype html><html lang="en"><head><meta charset="utf-8">}
out "<title>One Afternoon &mdash; a single clinical session, [nums $DATE]</title>"
out "<style>"
foreach {fam wt b64d} [list "Plex Serif" 400 $F_SERIF "Plex Serif" 700 $F_SERIF_B \
                            "Plex Mono" 400 $F_MONO "Plex Mono" 700 $F_MONO_B] {
    out "@font-face{font-family:'$fam';font-weight:$wt;font-style:normal;src:url(data:font/ttf;base64,$b64d) format('truetype');}"
}
out {
:root{
  --paper:#F2EFE8; --ink:#14130F; --ink2:#484438; --muted:#8B8474;
  --rule:#C9C1AF; --dark:#0F0E0C; --darker:#08080A;
  /* the film's two poles, and the same two darkened for ink on paper */
  --azure:#68ECFF; --gold:#FFE000;
  --azure-p:#1F5FA8; --gold-p:#8A6A05;
  --serif:'Plex Serif',Georgia,serif; --mono:'Plex Mono',ui-monospace,monospace;
}
@page{size:300mm 380mm;margin:0;}
*{box-sizing:border-box;}
html,body{margin:0;padding:0;background:#555;}
body{font-family:var(--serif);color:var(--ink);-webkit-print-color-adjust:exact;print-color-adjust:exact;}
.page{position:relative;width:300mm;height:380mm;overflow:hidden;background:var(--paper);
      page-break-after:always;break-after:page;}
.page:last-child{page-break-after:auto;}
.n{font-family:var(--mono);font-variant-numeric:tabular-nums;letter-spacing:-.012em;}
.folio{position:absolute;left:0;right:0;bottom:11mm;text-align:center;
       font-family:var(--mono);font-size:8pt;color:var(--muted);letter-spacing:.16em;}
.dark .folio,.bleed .folio{color:#6A665C;}
.dark{background:var(--dark);color:var(--paper);}
.dark .rule{background:#332F27;}
.nofolio .folio{display:none;}

/* --- the grid ------------------------------------------------------------ */
.pad{position:absolute;left:26mm;right:26mm;top:24mm;bottom:26mm;}
.stack .pad{display:flex;flex-direction:column;justify-content:space-between;}
/* a short table on a big page: let the rows breathe rather than leaving a
   hole under them */
.roomy td{padding:5.2mm 0;}
.rule{height:.6mm;background:var(--ink);width:100%;}
.hair{height:.25mm;background:var(--rule);width:100%;}
.run{position:absolute;top:13mm;left:26mm;right:26mm;display:flex;justify-content:space-between;
     font-family:var(--mono);font-size:7.6pt;letter-spacing:.2em;text-transform:uppercase;color:var(--muted);}
.dark .run{color:#7C766A;}

/* --- display type -------------------------------------------------------- */
h1{font-family:var(--serif);font-weight:700;letter-spacing:-.03em;line-height:.92;margin:0;}
.huge{font-size:118pt;}
.big{font-size:62pt;line-height:.94;}
.mid{font-size:34pt;line-height:1.02;letter-spacing:-.02em;}
.kicker{font-family:var(--mono);font-size:8.4pt;letter-spacing:.28em;text-transform:uppercase;color:var(--muted);}
.deck{font-size:15.5pt;line-height:1.42;color:var(--ink2);font-style:italic;}
.dark .deck{color:#BCB6A6;}

/* --- body ---------------------------------------------------------------- */
.cols{column-count:2;column-gap:14mm;font-size:11.4pt;line-height:1.58;text-align:justify;
      hyphens:auto;}
.cols.fill{position:absolute;left:0;right:0;bottom:0;}
.cols p{margin:0 0 5.4pt;}
.cols p:first-of-type::first-letter{font-size:34pt;line-height:.82;float:left;
      padding:2mm 2.4mm 0 0;font-weight:700;}
.one{font-size:11pt;line-height:1.56;max-width:170mm;}
.one p{margin:0 0 6pt;}
.lead{font-size:13.4pt;line-height:1.5;}

/* --- plates -------------------------------------------------------------- */
.bleed img,.bleed .bg{position:absolute;inset:0;width:100%;height:100%;object-fit:cover;}
.plate{position:absolute;display:flex;align-items:center;justify-content:center;}
.plate img{max-width:100%;max-height:100%;object-fit:contain;}
.inv{filter:invert(1);}
.cap{position:absolute;font-family:var(--mono);}
.capn{font-size:7.4pt;letter-spacing:.22em;color:var(--muted);margin-bottom:2.4mm;}
.capt{font-family:var(--serif);font-weight:700;font-size:11.5pt;line-height:1.25;margin-bottom:2mm;
      letter-spacing:-.01em;}
.capb{font-size:8.2pt;line-height:1.62;color:var(--ink2);max-width:76mm;}
.dark .capb{color:#A9A395;} .dark .capn{color:#7C766A;}

/* --- data ---------------------------------------------------------------- */
table{border-collapse:collapse;width:100%;font-size:10pt;}
th{font-family:var(--mono);font-size:7.4pt;letter-spacing:.18em;text-transform:uppercase;
   color:var(--muted);text-align:left;font-weight:400;padding:0 0 2.4mm;border-bottom:.5mm solid var(--ink);}
td{padding:3.1mm 0;border-bottom:.25mm solid var(--rule);vertical-align:baseline;}
td.num,th.num{text-align:right;font-family:var(--mono);font-variant-numeric:tabular-nums;}
th+th,td+td{padding-left:6mm;}
.dark th{color:#7C766A;border-bottom-color:var(--paper);}
.dark td{border-bottom-color:#332F27;}
.over{color:var(--gold-p);font-weight:700;}
.dark .over{color:var(--gold);}
.under{color:var(--azure-p);font-weight:700;}
.dark .under{color:var(--azure);}
.statnum{font-family:var(--serif);font-weight:700;font-size:52pt;line-height:.9;letter-spacing:-.03em;}
.statlab{font-family:var(--mono);font-size:7.6pt;letter-spacing:.2em;text-transform:uppercase;
         color:var(--muted);margin-top:3mm;}

/* a bar that shows how far past its line a value sits */
.bar{height:3.2mm;background:#DCD5C4;position:relative;}
.dark .bar{background:#2A2721;}
.bar i{position:absolute;left:0;top:0;bottom:0;background:var(--gold-p);}
.dark .bar i{background:var(--gold);}
.bar.u i{background:var(--azure-p);}
.dark .bar.u i{background:var(--azure);}

/* --- bibliography -------------------------------------------------------- */
.bib{display:grid;grid-template-columns:1fr 1fr;column-gap:12mm;align-content:space-between;
     position:absolute;left:0;right:0;bottom:0;}
.ref{display:grid;grid-template-columns:26mm 1fr;column-gap:5mm;break-inside:avoid;}
.ref .qr{width:26mm;height:26mm;}
.ref .qr svg{width:26mm;height:26mm;display:block;}
.ref .k{font-family:var(--mono);font-size:6.8pt;letter-spacing:.14em;color:var(--muted);
        margin-top:2mm;word-break:break-all;line-height:1.4;}
.ref .c{font-size:9pt;line-height:1.44;margin:0 0 1.6mm;}
.ref .nt{font-size:8pt;line-height:1.5;color:var(--ink2);margin:0;}
.ref .oa{font-family:var(--mono);font-size:6.6pt;letter-spacing:.16em;color:var(--gold-p);}
.tag{font-family:var(--mono);font-size:6.8pt;letter-spacing:.18em;text-transform:uppercase;
     color:var(--muted);}
}
out "</style></head><body>"

# ---------------------------------------------------------------------------
# 1. COVER
# ---------------------------------------------------------------------------
page "dark nofolio" "
<div style='position:absolute;left:0;right:0;top:0;height:242mm;overflow:hidden;background:#0B0A08;'>
  <img class=inv src='[figure EyesClosed_EEG-HeadMaps]'
       style='position:absolute;width:134%;left:-19%;top:-15%;opacity:.92;'>
  <div style='position:absolute;inset:0;background:linear-gradient(180deg,rgba(15,14,12,.34) 0%,rgba(15,14,12,0) 34%,rgba(15,14,12,.10) 72%,#0F0E0C 100%);'></div>
</div>
<div style='position:absolute;left:26mm;right:26mm;top:20mm;display:flex;justify-content:space-between;'>
  <span class=kicker style='color:#B9B2A2;'>Neuro</span>
  <span class=kicker style='color:#B9B2A2;'>Subj&nbsp;<span class=n>001</span></span>
</div>
<div style='position:absolute;left:26mm;right:26mm;bottom:30mm;'>
  <div class=rule style='background:var(--paper);margin-bottom:9mm;'></div>
  <h1 class=huge style='color:var(--paper);'>ONE<br>AFTERNOON</h1>
  <p class=deck style='margin:11mm 0 0;max-width:196mm;'>Five instruments, sixty&#8209;one measurements,<br>and the argument between them.</p>
  <div class=kicker style='margin-top:12mm;color:#8B8474;'>[nums "A single clinical session &nbsp;&middot;&nbsp; $DATE"]</div>
</div>"

# 2. dark flyleaf
page "dark nofolio" "
<div style='position:absolute;left:26mm;bottom:30mm;'>
  <div class=kicker style='color:#4A4640;'>[nums "$NMETRICS measured values &nbsp;&middot;&nbsp; $IMMN skin sites &nbsp;&middot;&nbsp; 19 scanned pages &nbsp;&middot;&nbsp; no text layer"]</div>
</div>"

# 3. half title
page "nofolio" "
<div class=pad>
  <div style='position:absolute;top:96mm;'>
    <h1 class=mid>One Afternoon</h1>
    <div class=kicker style='margin-top:7mm;'>Plates and readings</div>
  </div>
</div>"

# 4. frontispiece &mdash; the cardiac trace, full bleed, turned
page "dark bleed nofolio" "
<img src='[figure Resting_ECG-12Lead]' class=inv
     style='position:absolute;width:143%;left:-21%;top:50%;transform:translateY(-50%);opacity:.88;object-fit:contain;height:auto;'>
<div style='position:absolute;left:26mm;bottom:26mm;'>
  <div class=kicker style='color:#7C766A;'>Frontispiece</div>
  <div style='font-size:10.5pt;color:#BCB6A6;margin-top:3mm;max-width:150mm;line-height:1.5;'>
    [nums "Twelve-lead electrocardiogram, 14:51:16. The only figure in this record that prints a real acquisition time."]</div>
</div>"

# 5. title page
page "nofolio" "
<div class=pad>
  <div style='position:absolute;top:0;width:100%;'><div class=rule></div></div>
  <div style='position:absolute;top:74mm;'>
    <h1 class=big>ONE<br>AFTERNOON</h1>
    <p class=deck style='margin:14mm 0 0;max-width:180mm;'>Five instruments, sixty&#8209;one measurements,<br>and the argument between them.</p>
  </div>
  <div style='position:absolute;bottom:0;width:100%;'>
    <div class=hair style='margin-bottom:6mm;'></div>
    <div style='display:flex;justify-content:space-between;' class=kicker>
      <span>[nums "Session $DATE"]</span><span>Subject&nbsp;<span class=n>001</span></span>
    </div>
  </div>
</div>"

# 6. imprint
page "nofolio" "
<div class=pad>
 <div style='position:absolute;bottom:0;width:118mm;font-size:8.6pt;line-height:1.62;color:var(--ink2);'>
  <p style='margin:0 0 5mm;'><b>Not a diagnosis, and not medical advice.</b> This is a worked example of
  what a multimodal physiological battery does and does not license you to say. Every reading in it comes
  from one session with one subject. There is no sample here, and therefore no correlation, no effect size
  and no population claim.</p>
  <p style='margin:0 0 5mm;'>[nums "All figures are crops from the native embedded bitmaps of the source scans -- not
  re-renders -- at 203 ppi for the Evoke pages, 300 ppi for the twelve-lead, and 204 x 196 ppi for the faxed
  skin test, which is Group 3 fine mode."]</p>
  <p style='margin:0 0 5mm;'>[nums "Every number was derived once, by src/analyze.cpp, into a display-file
  bytecode. This book reads that bytecode. So do the browser dashboard, the pen plotter, the pocket card and
  the 3D-printed comb, which is why none of them can disagree with each other about a value.
  Permutation null: $PERMS iterations, seed $SEED."]</p>
  <p style='margin:0 0 5mm;'>Direct identifiers are not carried into this document. The subject is
  <span class=n>SUBJ-001</span>.</p>
  <p style='margin:0;'>[nums "Set in IBM Plex Serif and IBM Plex Mono. Composed in Tcl, printed from headless
  Chromium at 300 x 380 mm."]</p>
 </div>
</div>"

# 7. contents
page "nofolio" "
<div class=pad>
  <div class=rule style='margin-bottom:10mm;'></div>
  <h1 class=mid style='margin-bottom:14mm;'>Contents</h1>
  <div style='font-size:12pt;line-height:2.25;'>@@CONTENTS@@</div>
</div>"

# ---------------------------------------------------------------------------
# 8-9. opening essay
# ---------------------------------------------------------------------------
page "" "
<div class=run><span>Introduction</span><span>One Afternoon</span></div>
<div class=pad>
  <div class=rule style='margin-bottom:12mm;'></div>
  <h1 class=mid style='max-width:200mm;margin-bottom:10mm;'>An afternoon of being measured</h1>
  <div class='cols fill' style='top:52mm;'>
   <p>[nums "On the eighteenth of August, 2026, one person sat down in a clinic on 14th Street and was
   measured by five instruments in a single afternoon. A cap of nineteen electrodes recorded the electrical
   field of the scalp with the eyes open and again with the eyes closed. A checkerboard reversed on a screen
   several hundred times while the same electrodes averaged the response. A finger clip counted the interval
   between heartbeats. Ten adhesive electrodes took a twelve-lead electrocardiogram. Sixty needles marked a
   grid on the back and were read twenty minutes later with a ruler."]</p>
   <p>[nums "What came out was nineteen pages of paper with no text layer: head maps in grey, waveforms with
   printed peak values, gauges with needles, a handwritten grid transmitted by fax at 204 by 196 dots per
   inch. Sixty-one measured numbers, fifty-eight allergen sites, and one page order that arrived shuffled."]</p>
   <p>The battery had been ordered to look for attention deficit. It did not find it. The vendor's own
   decision engine returned a negative at ninety per cent confidence, and an independent scoring pass against
   six well-cited relationships lands in the same place. That is the least interesting thing in the record.</p>
   <p>What is interesting is everything the instruments said while they were being asked a different
   question. Anxiety at more than three times its threshold. Depression at three times. An immune system with
   twenty-six of fifty-eight sites positive and a fifteen-millimetre wheal to shagbark hickory. A heart-rate
   variability total that is completely normal and a distribution across frequency bands that is not. Three
   evoked components that arrive in an order the textbooks put the other way round.</p>
   <p>And three flags the report raises that are, on inspection, hairline: a theta-to-beta ratio four per
   cent over its line, a peak alpha frequency nine-tenths of one per cent over, a P3a latency four per cent
   over -- printed with the same weight as findings at two hundred per cent.</p>
   <p>This book sets the record out as a book: the plates the machines drew, at the size they deserve, and
   the numbers underneath them in the two registers a reader might want. It does not diagnose anything. It is
   an argument about how much weight a measurement can carry, made out of one afternoon's worth of them.</p>
  </div>
</div>"

page "dark stack" "
<div class=run><span>Introduction</span><span>What the battery is</span></div>
<div class=pad>
 <div>
  <div class=rule style='background:var(--paper);margin-bottom:12mm;'></div>
  <h1 class=mid style='color:var(--paper);max-width:210mm;'>Five instruments, one afternoon</h1>
  <p class=deck style='margin:11mm 0 0;max-width:190mm;'>Nineteen pages of paper, none of them with a text layer, and one page order that arrived shuffled.</p>
 </div>
  <div style='display:grid;grid-template-columns:1fr 1fr;column-gap:16mm;'>
   <div>
    <div class=kicker style='color:#7C766A;margin-bottom:6mm;'>The instruments</div>
    <table>
     <tr><th style='width:44%;'>Instrument</th><th>What it measures</th><th class=num>Pages</th></tr>
     <tr><td>[nums "Resting qEEG, 19 electrodes"]</td><td>[nums "Band power against an age-matched normative database, eyes open and eyes closed"]</td><td class=num>6</td></tr>
     <tr><td>[nums "Evoked potentials"]</td><td>[nums "Averaged response to checkerboard reversal and to targets: N100, P300a, P300b"]</td><td class=num>3</td></tr>
     <tr><td>[nums "Go / no-go task"]</td><td>Reaction time, its variability, omissions and commissions</td><td class=num>1</td></tr>
     <tr><td>[nums "Heart-rate variability"]</td><td>Interval series, spectral power in three bands, time-domain summaries</td><td class=num>2</td></tr>
     <tr><td>[nums "Twelve-lead ECG"]</td><td>Machine-read intervals and axis. Unconfirmed by a cardiologist</td><td class=num>1</td></tr>
     <tr><td>[nums "Percutaneous allergy panel"]</td><td>[nums "60 sites, wheal diameter in millimetres against a negative control"]</td><td class=num>1</td></tr>
     <tr><td>[nums "Self-report: PHQ-9, GAD-7, PCL-C"]</td><td>Depression, anxiety, post-traumatic symptom load</td><td class=num>3</td></tr>
    </table>
   </div>
   <div>
    <div class=kicker style='color:#7C766A;margin-bottom:6mm;'>What one session cannot settle</div>
    <div class=one style='font-size:10.4pt;color:#BCB6A6;'>
     <p>[nums "With n = 1 there is no sample to estimate a correlation from, so there is no correlation
     coefficient anywhere in this book. What is answerable is whether this person's pattern of deviations
     agrees with published effect directions more than a reshuffling of the same deviations would."]</p>
     <p>[nums "That is a permutation test on a concordance statistic over a graph of 32 directed edges taken
     from the vendors' own citations. It has a null, a statistic and a p-value, none of which pretend to be
     an r. The null is weak, and it is labelled as weak everywhere it appears."]</p>
     <p>Four things this afternoon cannot decide: whether any of it is stable across days, whether mood is
     driving the measurements or the measurements are driving mood, whether the allergic load has any
     cognitive consequence at all, and what the checkerboard actually looked like -- the report does not say
     what its check size or reversal rate were, and the interpretation of a delayed visual response depends
     on both.</p>
    </div>
   </div>
  </div>
</div>"

# ---------------------------------------------------------------------------
# One row per measured value: what it is, what it came out at, what the band
# was, how far outside in half-band units, and a bar of how far past the line.
# The bar length is `dist` -- distance past threshold normalised by the
# threshold itself for a one-sided criterion and by the band width for a
# two-sided one -- capped at 2, which is why the largest wheal runs off the end.
proc metricRows {ids} {
    set out ""
    foreach id $ids {
        set s [S $id]
        set d [dict get $s dist]
        set z [dict get $s z]
        set cls [expr {$z >= 0 ? "over" : "under"}]
        set bar ""
        if {$d > 0} {
            set w [expr {min(100.0, 100.0 * $d / 2.0)}]
            set u [expr {$z < 0 ? " u" : ""}]
            set bar "<div class='bar$u'><i style='width:[format %.1f $w]%'></i></div>"
        } else {
            set bar "<span class=tag>inside</span>"
        }
        append out "<tr><td>[nums [dict get $s label]]</td><td class=num>[trim [dict get $s value]]</td><td class=num style='color:var(--muted)'>[REF $id]</td><td class='num $cls'>[format %+.2f $z]</td><td>$bar</td></tr>
"
    }
    return $out
}

# The three spectral bands as bars, read out of the symbol table.
proc bandBars {} {
    set out ""
    set vals {}
    foreach id {ans.vlf ans.lf ans.hf} {lappend vals [dict get [S $id] value]}
    set mx [expr {max([lindex $vals 0], [lindex $vals 1], [lindex $vals 2])}]
    foreach id {ans.vlf ans.lf ans.hf} nm {VLF LF HF} v $vals {
        set h [expr {100.0 * $v / $mx}]
        set col [expr {$nm eq "HF" ? "var(--azure)" : "var(--gold)"}]
        append out "<div style='flex:1;display:flex;flex-direction:column;justify-content:flex-end;height:100%;'><div style='font-family:var(--mono);font-size:9pt;color:#BCB6A6;margin-bottom:2.5mm;'>[trim $v]</div><div style='height:[format %.1f $h]%;background:$col;'></div><div style='font-family:var(--mono);font-size:8pt;letter-spacing:.18em;color:#8B8474;margin-top:3mm;'>$nm</div></div>"
    }
    return $out
}

# Positive sites per allergen class, counted out of the display file's own
# per-site strings rather than from any second copy of the data.
proc classBars {} {
    global BC
    array set n {}
    array set p {}
    foreach s [dict get $BC strings] {
        if {[regexp {^([^\[]+) \[(food|grass|indoor|mold|tree|weed)\], wheal ([0-9.]+) mm} $s -> nm cls mm]} {
            incr n($cls)
            if {$mm >= 3} {incr p($cls)} else {if {![info exists p($cls)]} {set p($cls) 0}}
        }
    }
    set out "<div class=kicker style='margin-bottom:7mm;'>Positive sites by class</div>"
    foreach cls [lsort [array names n]] {
        set frac [expr {100.0 * $p($cls) / $n($cls)}]
        append out "<div style='margin-bottom:13mm;'><div style='display:flex;justify-content:space-between;align-items:baseline;margin-bottom:2.6mm;'><span style='font-family:var(--mono);font-size:10pt;letter-spacing:.2em;text-transform:uppercase;'>$cls</span><span style='font-family:var(--serif);font-weight:700;font-size:19pt;letter-spacing:-.02em;'>$p($cls)&thinsp;/&thinsp;$n($cls)</span></div><div class=bar style='height:9mm;'><i style='width:[format %.1f $frac]%'></i></div></div>"
    }
    return $out
}

# A shorter row for a narrow column: score and how far past the line.
proc metricRows2 {ids} {
    set out ""
    foreach id $ids {
        set s [S $id]
        set d [dict get $s dist]
        set z [dict get $s z]
        set cls [expr {$z >= 0 ? "over" : "under"}]
        set past [expr {$d > 0 ? "[format %+.0f [expr {100*$d}]]%" : "inside"}]
        append out "<tr><td>[nums [dict get $s label]]</td>\
<td class=num>[trim [dict get $s value]]</td>\
<td class='num [expr {$d > 0 ? $cls : ""}]'>$past</td></tr>\n"
    }
    return $out
}

# The five hypotheses, straight out of the display file's meta block.
proc hypRows {} {
    global HYPS
    set out ""
    foreach h $HYPS {
        set C [dict get $h C]
        set p [dict get $h p]
        set w [expr {min(100.0, 100.0 * abs($C))}]
        set sig [expr {$p < 0.01 ? "over" : ($p < 0.05 ? "" : "tag")}]
        set pt [expr {$p < 0.0001 ? "&lt; 0.0001" : [format %.4f $p]}]
        append out "<tr><td class=n style='color:var(--muted);'>[dict get $h id]</td>\
<td>[dict get $h name]</td>\
<td class='num $sig'>[format %+.3f $C]</td>\
<td class='num $sig'>$pt</td>\
<td class=num style='color:var(--muted);'>[format %.2f [dict get $h z]]</td>\
<td style='width:24%;'><div class=bar><i style='width:[format %.1f $w]%'></i></div></td></tr>\n"
    }
    return $out
}

# Everything outside its band, longest margin first.
proc ladderRows {n} {
    global BC
    set rows {}
    foreach s [dict get $BC symbols] {
        if {![dict get $s valid]} continue
        if {[dict get $s dist] <= 0} continue
        lappend rows [list [dict get $s dist] $s]
    }
    set rows [lsort -real -decreasing -index 0 $rows]
    set out ""
    set i 0
    foreach r $rows {
        if {[incr i] > $n} break
        set s [lindex $r 1]
        set d [dict get $s dist]
        set z [dict get $s z]
        set cls [expr {$z >= 0 ? "over" : "under"}]
        set u [expr {$z < 0 ? " u" : ""}]
        append out "<tr><td class=n style='color:var(--muted);'>[format %02d $i]</td>\
<td>[nums [dict get $s label]]</td>\
<td class=num>[trim [dict get $s value]]</td>\
<td class='num $cls'>[format %+.0f [expr {100*$d}]]%</td>\
<td style='width:36%;'><div class='bar$u'><i style='width:[format %.1f [expr {min(100.0, 100.0*$d/4.0)}]]%'></i></div></td></tr>\n"
    }
    return $out
}

proc chapter {num title deck stat statlab} {
    page "dark nofolio" "
    <div class=pad>
      <div class=rule style='background:var(--paper);'></div>
      <div style='position:absolute;top:26mm;'>
        <div style='font-family:var(--serif);font-weight:700;font-size:150pt;line-height:.8;
                    letter-spacing:-.04em;color:#2A2721;'>$num</div>
      </div>
      <div style='position:absolute;top:150mm;'>
        <h1 class=big style='color:var(--paper);max-width:220mm;'>$title</h1>
        <p class=deck style='margin:12mm 0 0;max-width:180mm;'>$deck</p>
      </div>
      <div style='position:absolute;bottom:0;'>
        <div class=statnum style='color:var(--gold);'>$stat</div>
        <div class=statlab>$statlab</div>
      </div>
    </div>" $title
}

# --- I. the resting brain ---------------------------------------------------
chapter "I" "The resting brain" \
    "Nineteen electrodes, ten seconds of eyes open and ten of eyes closed, scored against a normative database that stops at thirty-one." \
    "[V eeg.paf_ec 2]&thinsp;Hz" "Peak alpha frequency, eyes closed, against a ceiling of 11.0"

page "dark bleed" "
<img src='[figure EyesOpen_EEG-RawTrace]' class=inv
     style='position:absolute;width:150%;left:-25%;top:50%;transform:translateY(-50%);height:auto;object-fit:contain;opacity:.95;'>
<div style='position:absolute;left:26mm;top:22mm;' class=kicker>Plate&nbsp;<span class=n>I</span> &nbsp;&middot;&nbsp; Eyes open</div>
<div style='position:absolute;left:26mm;bottom:24mm;max-width:150mm;'>
  <div style='font-size:10pt;color:#BCB6A6;line-height:1.5;'>[nums "Ten seconds of the raw montage, nineteen rows, anterior at the top. Four electrodes -- FZ, T8, P3, P8 -- were rejected by the vendor's artefact stage and print as flat lines. They are reproduced here rather than removed: a montage that hides what it threw away is a montage you cannot audit."]</div>
</div>"

page "dark bleed" "
<img src='[figure EyesClosed_EEG-RawTrace]' class=inv
     style='position:absolute;width:150%;left:-25%;top:50%;transform:translateY(-50%);height:auto;object-fit:contain;opacity:.95;'>
<div style='position:absolute;left:26mm;top:22mm;' class=kicker>Plate&nbsp;<span class=n>II</span> &nbsp;&middot;&nbsp; Eyes closed</div>
<div style='position:absolute;left:26mm;bottom:24mm;max-width:150mm;'>
  <div style='font-size:10pt;color:#BCB6A6;line-height:1.5;'>[nums "The same ten seconds with the eyes shut. Posterior alpha arrives: the parietal and occipital rows thicken into a regular rhythm at just over nine cycles a second. Adrian and Matthews demonstrated exactly this contrast in 1934 and it is the single most reproducible finding in electroencephalography."]</div>
</div>"

foreach {stem plate cond note} [list \
  EyesOpen_EEG-HeadMaps   III "Eyes open" \
    "Twenty-nine one-hertz slices of the scalp field, scored in standard deviations against an age-matched reference population and printed as contour maps. This is the normative-database idea John and colleagues introduced in 1977, and it is the weak joint in the whole battery." \
  EyesClosed_EEG-HeadMaps IV "Eyes closed" \
    "The same twenty-nine slices with the eyes shut. Peak alpha frequency reads 11.10 Hz against a ceiling of 11.0 -- nine-tenths of one per cent over, printed as a flag. The reference tables this vendor uses do not extend past age thirty-one, and the subject is thirty-one years and two months old."] {
page "" "
<div class=run><span>I &nbsp;&middot;&nbsp; The resting brain</span><span>Spectral maps &nbsp;&middot;&nbsp; $cond</span></div>
<div style='position:absolute;left:38mm;right:38mm;top:32mm;height:265mm;' class=plate>
  <img src='[figure $stem]' style='max-height:100%;width:auto;'></div>
<div style='position:absolute;left:26mm;right:26mm;bottom:26mm;display:grid;grid-template-columns:56mm 1fr;column-gap:12mm;'>
  <div>
    <div class=capn>Plate&nbsp;<span class=n>$plate</span></div>
    <div class=capt>[nums $cond]</div>
  </div>
  <div class=capb style='max-width:none;'>[nums $note]</div>
</div>"
}

page "stack roomy" "
<div class=run><span>I &nbsp;&middot;&nbsp; The resting brain</span><span>Readings</span></div>
<div class=pad>
 <div>
  <div class=rule style='margin-bottom:9mm;'></div>
  <h1 class=mid style='margin-bottom:11mm;'>What the spectrum says</h1>
  <table>
   <tr><th style='width:40%;'>Measure</th><th class=num>Value</th><th class=num>Reference</th><th class=num>Deviation</th><th style='width:26%;'>Past the line</th></tr>
[metricRows {eeg.tbr_eo eeg.paf_ec eegz.c.alpha2 eegz.g.beta eeg.quality}]
  </table>
 </div>
 <div style='display:grid;grid-template-columns:92mm 1fr;column-gap:16mm;align-items:end;'>
  <div class=plate style='position:static;height:112mm;'>
    <img src='[figure EyesClosed_EEG-HeadMaps-Summary]' style='max-height:100%;width:auto;'></div>
  <div class=capb style='max-width:none;'>[nums {Plate XIII. The vendor's own summary map, eyes closed: the four classical bands averaged into one head each, with the peak alpha frequency printed above. It is the page a clinician actually looks at, and it is the page furthest from the raw measurement.}]</div>
 </div>
  <div style='display:grid;grid-template-columns:1fr 1fr;column-gap:14mm;'>
   <div class=one style='font-size:10.4pt;'>
    <div class=kicker style='margin-bottom:5mm;'>In plain language</div>
    <p>[nums "The slow-to-fast wave ratio came back four per cent over its line. Four per cent is nothing.
    It is inside the error of the measurement, inside the difference between one ten-second sample and the
    next, and inside the difference between this vendor's normative table and the next vendor's."]</p>
    <p>[nums "It was printed as a flag anyway, on the same page and in the same weight as the anxiety score,
    which is at two hundred and twenty-five per cent of its threshold."]</p>
   </div>
   <div class=one style='font-size:10.4pt;'>
    <div class=kicker style='margin-bottom:5mm;'>Full fat</div>
    <p>[nums "The theta:beta ratio has been the most-cited quantitative EEG marker in attention research for
    thirty years and has been coming apart for fifteen. Arns and colleagues' 2013 meta-analysis found effect
    sizes declining year on year. A January 2026 multiverse analysis ran 576 defensible pipelines across
    1,499 subjects and an independent validation sample of 381, and concluded that apparent case-control
    differences are substantially driven by aperiodic -- 1/f -- activity rather than by oscillatory theta or
    beta at all."]</p>
   </div>
  </div>
</div>"

# --- II. the evoked response ------------------------------------------------
chapter "II" "The evoked response" \
    "A checkerboard reverses. Three hundred trials are averaged until the noise cancels and what is left is the brain answering." \
    "[V erp.p3b_ratio 3]" "P3b to P3a amplitude ratio, against a stated floor of 0.50"

page "" "
<div class=run><span>II &nbsp;&middot;&nbsp; The evoked response</span><span>Three curves</span></div>
<div style='position:absolute;left:26mm;right:26mm;top:28mm;'>
  <div class=rule></div>
</div>
<div style='position:absolute;left:26mm;right:26mm;top:36mm;height:92mm;' class=plate>
  <img src='[figure GoNoGo_ERP-P300a-Cz]' style='max-height:100%;width:auto;'></div>
<div style='position:absolute;left:26mm;right:26mm;top:132mm;height:92mm;' class=plate>
  <img src='[figure GoNoGo_ERP-P300b-Pz]' style='max-height:100%;width:auto;'></div>
<div style='position:absolute;left:26mm;right:26mm;top:228mm;height:92mm;' class=plate>
  <img src='[figure GoNoGo_ERP-N100-O2]' style='max-height:100%;width:auto;'></div>
<div style='position:absolute;left:26mm;right:26mm;bottom:22mm;display:grid;grid-template-columns:1fr 1fr;column-gap:14mm;'>
  <div class=cap style='position:static;'>
    <div class=capn>Plates&nbsp;<span class=n>IV</span>&ndash;<span class=n>VI</span></div>
    <div class=capt>[nums "P300a at Cz, P300b at Pz, N100 at O2"]</div>
    <div class=capb style='max-width:none;'>[nums "Each is an average over several hundred trials, plotted from -200 to +1000 milliseconds. The printed peak values are 17.26, 6.60 and -7.55 microvolts. Digitising the ink back into numbers -- calibrating from the tick marks alone, never from those printed values -- returns 17.92, 6.78 and -7.73, which is how we know the tracing is sound."]</div>
  </div>
  <div class=one style='font-size:10pt;'>
    <p>[nums "The P300 was found by Sutton, Braren, Zubin and John in 1965 and reported in Science: a
    positive deflection about three hundred milliseconds after a stimulus, larger when the stimulus was
    uncertain. Squires, Squires and Hillyard split it in two ten years later. P3a is frontocentral and
    responds to novelty; P3b is temporal-parietal and reflects context updating."]</p>
    <p>[nums "This record has both. P3a is close to three times its floor. P3b is ten per cent above it.
    The quotient is 0.382 against a 0.50 floor the report states in prose on the same page and never
    computes."]</p>
  </div>
</div>"

page "dark stack" "
<div class=run><span>II &nbsp;&middot;&nbsp; The evoked response</span><span>Order of arrival</span></div>
<div class=pad>
  <div class=rule style='background:var(--paper);margin-bottom:10mm;'></div>
  <h1 class=mid style='color:var(--paper);max-width:190mm;'>The components arrive in the wrong order</h1>
  <div style='display:grid;grid-template-columns:1fr 1fr;column-gap:16mm;margin-top:12mm;'>
    <div>
      <table>
        <tr><th>Rank</th><th>Channel</th><th class=num>Latency</th><th class=num>Amplitude</th><th>Component</th></tr>
        <tr><td class=n>1</td><td>O2</td><td class=num>287 ms</td><td class='num under'>-7.61 &micro;V</td><td>N100</td></tr>
        <tr><td class=n>2</td><td>Pz</td><td class=num>387 ms</td><td class='num over'>+6.67 &micro;V</td><td>[nums "P3b, parietal"]</td></tr>
        <tr><td class=n>3</td><td>Cz</td><td class=num>464 ms</td><td class='num over'>+17.69 &micro;V</td><td>[nums "P3a, frontocentral"]</td></tr>
      </table>
      <div class=one style='font-size:10.4pt;color:#BCB6A6;margin-top:9mm;'>
        <p>[nums "The conventional sequence puts P3a first: it is the earlier, faster, stimulus-driven
        orienting response, and P3b follows it. Here the orienting response arrives seventy-seven
        milliseconds after the consolidation response."]</p>
        <p>[nums "That is the same dissociation the 0.382 amplitude quotient describes, arriving by an
        independent route. One measures how big the two responses are; the other measures which one gets
        there first; they agree. It is corroboration rather than a second finding -- and it is legible
        directly in the printed curves and appears nowhere in the printed text."]</p>
        <p style='color:#8B8474;'>[nums "Caveats, in order of size. These are three separate single-channel
        averages, not a simultaneous multichannel recording, so the order is the order of three printed
        curves and not a propagation delay measured across a field. Cz and O2 come from the checkerboard
        condition and Pz from the target condition, and the report does not say whether the averages share
        epochs."]</p>
      </div>
    </div>
    <div style='display:flex;flex-direction:column;gap:6mm;'>
      <img src='[frame frame-10.6s.png]' style='width:100%;height:auto;'>
      <div class=capb style='color:#8B8474;'>[nums "Frames from the sonified reel of the same three curves. Magnitude is lightness and polarity is hue -- azure negative, gold positive -- because the green-to-red ramp the eye expects is the one axis that both common colour blindnesses collapse."]</div>
    </div>
  </div>
</div>"

page "stack roomy" "
<div class=run><span>II &nbsp;&middot;&nbsp; The evoked response</span><span>Readings</span></div>
<div class=pad>
  <div class=rule style='margin-bottom:9mm;'></div>
  <h1 class=mid style='margin-bottom:11mm;'>The timing chain</h1>
  <table>
   <tr><th style='width:40%;'>Measure</th><th class=num>Value</th><th class=num>Reference</th><th class=num>Deviation</th><th style='width:26%;'>Past the line</th></tr>
[metricRows {erp.n100_lat erp.p3b_lat erp.p3a_lat erp.timing_sum erp.p3b_ratio erp.p3a_amp erp.p3b_amp erp.n100_amp}]
  </table>
  <div class=one style='margin-top:13mm;max-width:200mm;font-size:10.6pt;'>
   <p>[nums "The N100 is a largely pre-attentive index of early sensory registration. A thirty-eight
   millisecond delay at the first cortical stage propagates into every downstream latency, which is why
   these are plotted as a chain against their own ceilings rather than as five independent flags: the
   deficit accumulates, it does not appear at one stage."]</p>
   <p>[nums "The electrophysiological reading is that attentional capture is intact and possibly strong,
   while the downstream consolidation that converts capture into a retained, categorised event is
   comparatively weak. Compare the subjective complaint: pulled toward new things, then losing the thread.
   That mapping is far better supported than the theta:beta ratio that got flagged instead."]</p>
  </div>
</div>"

# --- III. the heart ---------------------------------------------------------
chapter "III" "The heart" \
    "A finger clip counts the gap between beats. The total variability is fine. Its distribution across frequency bands is not." \
    "[format %.1f [expr {100*[dict get [S ans.hf_frac] value]}]]&thinsp;%" "HF share of total power, against a floor of 15 %"

page "dark bleed" "
<img src='[figure Resting_ECG-12Lead]' class=inv
     style='position:absolute;width:158%;left:-29%;top:50%;transform:translateY(-50%);height:auto;object-fit:contain;opacity:.92;'>
<div style='position:absolute;left:26mm;top:22mm;' class=kicker>Plate&nbsp;<span class=n>VII</span> &nbsp;&middot;&nbsp; Twelve leads</div>
<div style='position:absolute;left:26mm;bottom:24mm;max-width:158mm;'>
  <div style='font-size:10pt;color:#BCB6A6;line-height:1.5;'>[nums "Einthoven's string galvanometer, 1903, in its modern form: ten electrodes producing twelve views of one electrical event. Every interval on this page is within reference -- PR 136 ms, QRS 88 ms, QTc 393 ms, rate 57. It is machine-read and has not been confirmed by a cardiologist, which is stated on the page and is the reason it is reproduced here at full width rather than summarised in a table."]</div>
</div>"

page "" "
<div class=run><span>III &nbsp;&middot;&nbsp; The heart</span><span>Interval and spectrum</span></div>
<div style='position:absolute;left:26mm;right:26mm;top:30mm;height:58mm;' class=plate>
  <img src='[figure Resting_HRV-Tachogram]' style='max-height:100%;width:auto;'></div>
<div style='position:absolute;left:26mm;width:132mm;top:100mm;height:118mm;' class=plate>
  <img src='[figure Resting_HRV-PowerSpectrum]' style='max-height:100%;width:auto;'></div>
<div style='position:absolute;right:26mm;width:112mm;top:100mm;'>
  <div class=capn>Plates&nbsp;<span class=n>VIII</span>&ndash;<span class=n>IX</span></div>
  <div class=capt>Tachogram and power spectrum</div>
  <div class=capb style='max-width:none;'>[nums "Akselrod and colleagues showed in Science in 1981 that the beat-to-beat interval series has structure in the frequency domain, and that the bands mean different things: high frequency is respiratory sinus arrhythmia and the cleanest non-invasive index of vagal tone available; low frequency is mixed; very low frequency, over a five-minute record, is not interpretable as a physiological quantity at all and the 1996 Task Force standard says so."]</div>
</div>
<div style='position:absolute;left:26mm;right:26mm;bottom:30mm;'>
  <div class=hair style='margin-bottom:8mm;'></div>
  <table>
   <tr><th style='width:40%;'>Measure</th><th class=num>Value</th><th class=num>Reference</th><th class=num>Deviation</th><th style='width:26%;'>Past the line</th></tr>
[metricRows {ans.sdnn ans.tp ans.vlf_ratio ans.lf_hf ans.hf_frac ans.spec_entropy}]
  </table>
</div>"

page "dark stack" "
<div class=run><span>III &nbsp;&middot;&nbsp; The heart</span><span>The distribution</span></div>
<div class=pad>
  <div class=rule style='background:var(--paper);margin-bottom:10mm;'></div>
  <h1 class=mid style='color:var(--paper);max-width:200mm;'>No single-number summary can see this</h1>
  <div style='display:grid;grid-template-columns:1.15fr 1fr;column-gap:16mm;margin-top:14mm;'>
    <div>
      <div style='display:flex;align-items:flex-end;gap:9mm;height:148mm;margin-bottom:6mm;'>
[bandBars]
      </div>
      <div class=hair style='background:#332F27;'></div>
      <div class=capb style='color:#8B8474;margin-top:5mm;max-width:none;'>[nums "Absolute power in each band, in square milliseconds. The expected ordering for this vendor's own reference is VLF below LF above HF. Observed is VLF above LF above HF."]</div>
    </div>
    <div class=one style='font-size:10.6pt;color:#BCB6A6;'>
      <p>[nums "SDNN is 82.09 milliseconds and total power is 2,324 square milliseconds. Both score
      completely normal. A clinician reading a one-line HRV summary would move on."]</p>
      <p>[nums "Underneath: the VLF-to-LF ratio is 1.173 against a 0.5 threshold, and high frequency is
      11.1 per cent of total power against a 15 per cent floor. The total is fine because the missing vagal
      power has been replaced by power in a band that means less."]</p>
      <p>[nums "Spectral entropy over the three bands is 1.388 bits of a possible 1.585. That is the same
      observation stated as information: the distribution has collapsed toward one band, and the number that
      would have told you is not printed anywhere in the report."]</p>
    </div>
  </div>
</div>"

# --- IV. the skin -----------------------------------------------------------
chapter "IV" "The skin" \
    "Sixty needles, a grid drawn on a back, and a ruler twenty minutes later. The oldest instrument in the battery and the least ambiguous." \
    "[expr {int([dict get [S spt.max_wheal] value])}]&thinsp;mm" "Largest wheal, against a positive threshold of 3 mm"

page "bleed" "
<img src='[figure Percutaneous_SPT-40Panel]'
     style='position:absolute;width:112%;left:-6%;top:50%;transform:translateY(-50%);height:auto;object-fit:contain;'>
<div style='position:absolute;left:26mm;top:22mm;' class=kicker>Plate&nbsp;<span class=n>X</span> &nbsp;&middot;&nbsp; Sixty sites</div>
<div style='position:absolute;left:20mm;bottom:16mm;right:20mm;background:rgba(242,239,232,.93);padding:7mm 8mm;'>
  <div style='font-size:9.6pt;color:var(--ink2);line-height:1.5;max-width:210mm;'>[nums "Blackley pricked his own skin with pollen in 1873 and described the wheal. This page is the same experiment, industrialised: 60 sites, a positive and a negative control, wheal diameter read in millimetres and written by hand. It reached this record as a fax at 204 by 196 dots per inch -- Group 3 fine mode -- and the 16:51 stamp it carries is the transmission time, not the time of the test."]</div>
</div>"

page "" "
<div class=run><span>IV &nbsp;&middot;&nbsp; The skin</span><span>Readings</span></div>
<div class=pad>
  <div class=rule style='margin-bottom:9mm;'></div>
  <h1 class=mid style='margin-bottom:12mm;'>[nums "$IMMPOS of $IMMN sites positive"]</h1>
  <div style='display:grid;grid-template-columns:1.25fr 1fr;column-gap:18mm;'>
    <div>
[classBars]
    </div>
    <div class=one style='font-size:10.6pt;'>
      <p>[nums "Every grass tested came back positive. Ten of twelve trees. Six of seven weeds. Two of
      twenty foods, and none of the five moulds. That is a clean outdoor-pollen pattern rather than a
      diffuse everything-is-positive one, which matters: a panel that lights up everywhere usually means
      dermatographism, and this one does not."]</p>
      <p>[nums "Wheal size indexes sensitisation, not clinical severity. A 15 mm wheal to shagbark hickory
      says the immune system has committed to that antigen; whether it produces symptoms depends on exposure
      history that the record does not contain."]</p>
      <p>[nums "Why it is in a book about attention at all: the concordance pass scores an allergic and
      inflammatory story at C = 0.528, p = 0.004. Not because allergy causes inattention, but because a
      2019 line of work on inflammatory load and cognitive fog gives a published direction to test, and this
      subject's deviations agree with it more than a reshuffle would."]</p>
    </div>
  </div>
  <div style='position:absolute;left:0;right:0;bottom:0;'>
    <div class=hair style='margin-bottom:7mm;'></div>
    <table>
     <tr><th style='width:40%;'>Measure</th><th class=num>Value</th><th class=num>Reference</th><th class=num>Deviation</th><th style='width:26%;'>Past the line</th></tr>
[metricRows {spt.max_wheal spt.burden}]
    </table>
  </div>
</div>"

# --- V. the self-report -----------------------------------------------------
chapter "V" "The self-report" \
    "Four questionnaires and a screener. The only instrument in the battery that asks rather than measures, and the one furthest outside its band." \
    "+[format %.0f [expr {100*[dict get [S psy.gad7] dist]}]]&thinsp;%" "GAD-7 anxiety, past its threshold"

page "" "
<div class=run><span>V &nbsp;&middot;&nbsp; The self-report</span><span>Domains</span></div>
<div style='position:absolute;left:26mm;right:26mm;top:30mm;height:106mm;' class=plate>
  <img src='[figure SelfReport_Screener-Domains]'></div>
<div style='position:absolute;left:26mm;width:118mm;top:150mm;height:120mm;' class=plate>
  <img src='[figure GoNoGo_Result-Gauges]'></div>
<div style='position:absolute;right:26mm;width:118mm;top:150mm;'>
  <div class=capn>Plates&nbsp;<span class=n>XI</span>&ndash;<span class=n>XII</span></div>
  <div class=capt>[nums "Screener domains, and the decision engine's gauges"]</div>
  <div class=capb style='max-width:none;'>[nums "Seven self-reported domains against their reference ranges, and the vendor's own summary needles. The engine returned a negative for attention deficit at 90 per cent confidence. An independent scoring pass here, against six well-cited relationships, lands in the same place at p = 0.17."]</div>
  <div style='margin-top:9mm;'>
   <table>
    <tr><th style='width:52%;'>Instrument</th><th class=num>Score</th><th class=num>Past line</th></tr>
[metricRows2 {psy.phq9 psy.gad7 psy.pclc srs.global srs.exec_attn srs.affect}]
   </table>
  </div>
</div>"

page "dark stack" "
<div class=run><span>V &nbsp;&middot;&nbsp; The self-report</span><span>Where the instruments disagree</span></div>
<div class=pad>
  <div class=rule style='background:var(--paper);margin-bottom:10mm;'></div>
  <h1 class=mid style='color:var(--paper);max-width:200mm;'>Feels much worse than it measures</h1>
  <div style='margin-top:13mm;display:grid;grid-template-columns:1.1fr 1fr;column-gap:16mm;'>
   <div>
    <table>
     <tr><th style='width:34%;'>Construct</th><th class=num>Felt</th><th class=num>Measured</th><th class=num>Gap</th></tr>
     <tr><td>Executive control</td><td class='num under'>-3.70</td><td class='num'>+0.63</td><td class='num over'>3.07</td></tr>
     <tr><td>Memory</td><td class='num under'>-1.81</td><td class='num'>+0.59</td><td class='num over'>2.40</td></tr>
     <tr><td>Motor</td><td class='num under'>-2.63</td><td class='num'>-0.61</td><td class='num over'>2.02</td></tr>
     <tr><td>Word fluency</td><td class='num under'>-2.53</td><td class='num under'>-3.26</td><td class=num>0.73</td></tr>
     <tr><td>Affect</td><td class='num under'>-3.27</td><td class='num over'>+5.00</td><td class=num>&mdash;</td></tr>
    </table>
    <div class=capb style='color:#8B8474;margin-top:6mm;max-width:none;'>[nums "Felt is the self-report domain in half-band units. Measured is the closest objective proxy: commission errors for executive control, episodic recall for memory, reaction time for motor, semantic word knowledge for fluency, PHQ-9 for affect. Positive is the natural direction of each measure, not badness."]</div>
   </div>
   <div class=one style='font-size:10.6pt;color:#BCB6A6;'>
    <p>[nums "On four of five constructs the subjective report sits well below the objective measurement.
    Executive control feels 3.7 half-bands below normal and measures very slightly above it. That gap is
    the single largest structural feature of this record."]</p>
    <p>[nums "Affect is the exception, and the interesting one: the self-report is low and the objective
    instrument -- PHQ-9 at 12, GAD-7 at 13 -- agrees with it. Where the complaint is about mood, the
    instruments concur. Where the complaint is about cognition, they do not."]</p>
    <p>[nums "That is what the concordance pass is reading when it scores the mood story at C = 0.740,
    p < 0.0001: not that this person is depressed rather than inattentive, but that how bad it feels is
    tracking mood more closely than it is tracking performance."]</p>
   </div>
  </div>
</div>"

# --- VI. the argument -------------------------------------------------------
chapter "VI" "The argument" \
    "Five stories that could account for this record, scored against thirty-two directed edges taken from the vendors' own citations." \
    "[format %.3f [dict get [lindex $HYPS 2] C]]" "Concordance of the mood story, p &lt; 0.0001"

page "stack roomy" "
<div class=run><span>VI &nbsp;&middot;&nbsp; The argument</span><span>Five stories</span></div>
<div class=pad>
  <div class=rule style='margin-bottom:9mm;'></div>
  <h1 class=mid style='margin-bottom:4mm;'>Five stories, scored</h1>
  <p class=deck style='margin:0 0 11mm;max-width:190mm;font-size:12.5pt;'>[nums "$PERMS permutations, seed $SEED"]</p>
  <table>
   <tr><th style='width:6%;'></th><th style='width:34%;'>Hypothesis</th><th class=num>C</th><th class=num>p</th><th class=num>z vs null</th><th>Concordance</th></tr>
[hypRows]
  </table>
  <div style='display:grid;grid-template-columns:1fr 1fr;column-gap:14mm;margin-top:14mm;'>
   <div class=one style='font-size:10.4pt;'>
    <div class=kicker style='margin-bottom:5mm;'>What C is</div>
    <p>[nums "For each hypothesis, a set of directed edges: pairs of measurements that the literature says
    should move together, or apart, if the story is true. C is the weighted average agreement between this
    subject's deviations and those published directions, squashed so that no single extreme value can carry
    the whole score. It runs from -1 to +1."]</p>
    <p>[nums "The p-value is the fraction of 200,000 random reshufflings of the same deviations that
    produce a C at least this large. It is not a correlation. There is no sample here to correlate."]</p>
   </div>
   <div class=one style='font-size:10.4pt;'>
    <div class=kicker style='margin-bottom:5mm;'>What it is not</div>
    <p>[nums "The null is weak, and is labelled as weak everywhere it appears. Reshuffling deviations across
    metrics destroys the prior graph's structure but keeps the marginal distribution, so a low p-value says
    the pattern is not arbitrary -- not that the hypothesis is true."]</p>
    <p>[nums "Four of five stories clear their null. That is not five competing diagnoses; it is one
    afternoon that is legibly consistent with several overlapping accounts, and a battery that was ordered
    to test the fifth."]</p>
   </div>
  </div>
</div>"

page "dark stack" "
<div class=run><span>VI &nbsp;&middot;&nbsp; The argument</span><span>The ladder</span></div>
<div class=pad>
  <div class=rule style='background:var(--paper);margin-bottom:9mm;'></div>
  <h1 class=mid style='color:var(--paper);margin-bottom:4mm;'>How far past the line, really</h1>
  <p class=deck style='margin:0 0 10mm;max-width:190mm;font-size:12pt;'>Every measurement outside its reference band, longest margin first, on one axis.</p>
  <table>
   <tr><th style='width:5%;'></th><th style='width:33%;'>Measure</th><th class=num>Value</th><th class=num>Past</th><th>Margin</th></tr>
[ladderRows 18]
  </table>
  <div class=capb style='color:#8B8474;margin-top:8mm;max-width:none;'>[nums "Distance past threshold, normalised by the threshold itself for a one-sided criterion and by the band width for a two-sided one, so a 4 per cent overshoot and a 400 per cent one can share an axis. The bar is capped at 400 per cent, which is why the largest wheal fills it. Gold is above the natural direction of the measure, azure below."]</div>
</div>"

page "stack" "
<div class=run><span>VI &nbsp;&middot;&nbsp; The argument</span><span>Three hairlines</span></div>
<div class=pad>
  <div class=rule style='margin-bottom:12mm;'></div>
  <div style='display:grid;grid-template-columns:repeat(3,1fr);column-gap:12mm;margin-bottom:16mm;'>
   <div><div class=statnum>+<span class=n>4</span>%</div><div class=statlab>Theta : beta ratio</div></div>
   <div><div class=statnum>+<span class=n>0.9</span>%</div><div class=statlab>Peak alpha frequency</div></div>
   <div><div class=statnum>+<span class=n>4</span>%</div><div class=statlab>P300a latency</div></div>
  </div>
  <div class=hair style='margin-bottom:12mm;'></div>
  <div style='display:grid;grid-template-columns:repeat(3,1fr);column-gap:12mm;margin-bottom:16mm;'>
   <div><div class=statnum style='color:var(--gold-p);'>+<span class=n>225</span>%</div><div class=statlab>GAD-7 anxiety</div></div>
   <div><div class=statnum style='color:var(--gold-p);'>+<span class=n>200</span>%</div><div class=statlab>PHQ-9 depression</div></div>
   <div><div class=statnum style='color:var(--gold-p);'>+<span class=n>199</span>%</div><div class=statlab>Allergen burden</div></div>
  </div>
  <div class=one style='max-width:200mm;font-size:11.5pt;'>
   <p>[nums "The top row is what the report flagged. The bottom row is what it printed in the same weight
   beside them. Three of the vendor's flags are hairline -- four per cent, nine-tenths of one per cent, four
   per cent past their lines -- and the theta:beta threshold comes from normative tables the report itself
   says do not extend past age thirty-one, applied to a subject aged thirty-one years and two months."]</p>
   <p>[nums "This is not an accusation of error. Every one of those three values is correctly computed and
   correctly compared. It is an observation about presentation: a flag is a binary, a margin is a
   quantity, and a page that prints only the flag has thrown away the quantity that tells you whether to
   care."]</p>
  </div>
</div>"

# ---------------------------------------------------------------------------
# Plates catalogue. Read from the figure manifest, which is written by
# figures/extract-figures.py at the moment the crops are cut, so the ppi and
# the pixel dimensions on this page are the real ones and not a guess.
# ---------------------------------------------------------------------------
proc csvrow {line} {
    set out {}
    set cur ""
    set q 0
    foreach ch [split $line ""] {
        if {$q} {
            if {$ch eq "\""} {set q 0} else {append cur $ch}
        } elseif {$ch eq "\""} {
            set q 1
        } elseif {$ch eq ","} {
            lappend out $cur
            set cur ""
        } else {
            append cur $ch
        }
    }
    lappend out $cur
    return $out
}

set MANIFEST [file join $root build figures MANIFEST.csv]
set PLATES {}
if {[file exists $MANIFEST]} {
    set f [open $MANIFEST r]
    fconfigure $f -encoding utf-8
    set hdr [csvrow [gets $f]]
    while {[gets $f line] >= 0} {
        if {[string trim $line] eq ""} continue
        set r [csvrow $line]
        set d {}
        foreach k $hdr v $r {dict set d $k $v}
        lappend PLATES $d
    }
    close $f
}

set rows ""
set i 0
foreach pl $PLATES {
    incr i
    append rows "<tr><td class=n style='color:var(--muted);'>[format %02d $i]</td>\
<td>[nums [dict get $pl caption]]</td>\
<td class=tag>[dict get $pl company]</td>\
<td class=num>[dict get $pl width_px]&thinsp;&times;&thinsp;[dict get $pl height_px]</td>\
<td class=num>[dict get $pl ppi_x]<span style='color:var(--muted)'>[expr {[dict get $pl ppi_x] eq [dict get $pl ppi_y] ? "" : " &times; [dict get $pl ppi_y]"}]</span></td>\
<td class=num style='color:var(--muted);'>[dict get $pl timestamp]</td></tr>\n"
}

page "stack roomy" "
<div class=run><span>Catalogue</span><span>Plates</span></div>
<div class=pad>
  <div class=rule style='margin-bottom:9mm;'></div>
  <h1 class=mid style='margin-bottom:4mm;'>The plates</h1>
  <p class=deck style='margin:0 0 11mm;max-width:200mm;font-size:12.5pt;'>Every figure is a crop out of the page's native embedded bitmap. Nothing here was re-rendered, resampled or redrawn.</p>
  <table style='font-size:9.2pt;'>
   <tr><th style='width:5%;'></th><th style='width:44%;'>Figure</th><th>Instrument</th><th class=num>Pixels</th><th class=num>PPI</th><th class=num>Time</th></tr>
$rows
  </table>
  <div class=capb style='margin-top:9mm;max-width:none;'>[nums {Only the twelve-lead prints a real acquisition time, 14:51:16. The Evoke figures carry 15:22 from the cover page, accurate to the minute. The skin test prints no time at all, so its 16:51 is the fax transmission stamp -- an upper bound, not a test time.}]</div>
</div>"

# ---------------------------------------------------------------------------
# Bibliography. Every reference carries a QR code of its most durable link.
# ---------------------------------------------------------------------------
set AREANAME {
    eeg    "Resting quantitative EEG"
    erp    "Event-related potentials"
    photic "Photic stimulation and the visual pathway"
    hrv    "Heart-rate variability and the ECG"
    spt    "Percutaneous allergy testing"
    psych  "Self-report instruments"
}

# flatten the two lists per area into one ordered catalogue
set REFS {}
foreach area {eeg erp photic hrv spt psych} {
    set a [dict get $SOURCES $area]
    foreach kind {origin modern} {
        foreach e [dict get $a $kind] {
            if {[dict get $e url] eq ""} continue
            dict set e area $area
            dict set e kind $kind
            lappend REFS $e
        }
    }
}

proc refCell {e} {
    set url [dict get $e url]
    set oa [expr {[dict get $e oa] ? "<span class=oa>OPEN ACCESS</span>" : ""}]
    set kind [expr {[dict get $e kind] eq "origin" ? "Origin" : "Current"}]
    return "<div class=ref>
      <div>
        <div class=qr>[qr::svg $url -level Q -size 100]</div>
        <div class=k>[esc $url]</div>
      </div>
      <div>
        <div class=tag style='margin-bottom:2.4mm;'>$kind &nbsp;&middot;&nbsp; [dict get $e key]</div>
        <p class=c>[nums [esc [dict get $e cite]]]</p>
        <p class=nt>[nums [esc [dict get $e note]]]</p>
        $oa
      </div>
    </div>"
}

set n [llength $REFS]
set per 8
set first 1
for {set i 0} {$i < $n} {incr i $per} {
    set cells ""
    foreach e [lrange $REFS $i [expr {$i + $per - 1}]] {append cells [refCell $e]}
    set head ""
    if {$first} {
        set head "<div class=rule style='margin-bottom:9mm;'></div>
        <h1 class=mid style='margin-bottom:4mm;'>Sources</h1>
        <p class=deck style='margin:0 0 12mm;max-width:200mm;font-size:12.5pt;'>[nums {Where each instrument came from, and what the literature says about it now. Point a phone at the code.}]</p>"
        set first 0
    } else {
        set head "<div class=hair style='margin-bottom:11mm;'></div>"
    }
    set runhead [nums "$n references, $n codes"]
    page "" "
    <div class=run><span>Sources</span><span>$runhead</span></div>
    <div class=pad>$head<div class=bib style='top:[expr {$i == 0 ? 64 : 18}]mm;'>$cells</div></div>"
}

# --- the verdicts -----------------------------------------------------------
set vrows ""
foreach area {eeg erp photic hrv spt psych} {
    set a [dict get $SOURCES $area]
    append vrows "<div style='break-inside:avoid;margin-bottom:9mm;'>
      <div class=kicker style='margin-bottom:3.5mm;'>[dict get $AREANAME $area]</div>
      <div style='font-size:10.2pt;line-height:1.52;'>[nums [esc [dict get $a verdict]]]</div></div>"
}

page "dark stack" "
<div class=run><span>Sources</span><span>How much weight each will carry</span></div>
<div class=pad>
 <div>
  <div class=rule style='background:var(--paper);margin-bottom:10mm;'></div>
  <h1 class=mid style='color:var(--paper);margin-bottom:4mm;'>What each instrument is good for</h1>
  <p class=deck style='margin:0;max-width:200mm;font-size:12.5pt;'>Editorial judgement, and labelled as such.</p>
 </div>
  <div style='column-count:2;column-gap:14mm;color:#BCB6A6;'>$vrows</div>
</div>"

# --- colophon ---------------------------------------------------------------
page "nofolio" "
<div class=pad>
  <div style='position:absolute;top:0;width:100%;'><div class=rule></div></div>
  <div style='position:absolute;top:40mm;width:150mm;'>
    <div class=kicker style='margin-bottom:9mm;'>Colophon</div>
    <div class=one style='font-size:10.2pt;'>
     <p>[nums {ONE AFTERNOON was composed in Tcl and printed from headless Chromium at 300 by 380 millimetres. The text is IBM Plex Serif; every numeral, label and code is IBM Plex Mono. Both are used under the SIL Open Font License and are embedded in the file.}]</p>
     <p>[nums {The plates are crops from the native embedded bitmaps of nineteen scanned pages. The numbers are read out of a display-file bytecode produced by a single numeric pass in C++; the browser dashboard, the pen plotter, the pocket card, the 3D-printed comb and this book are five hosts executing the same bytes.}]</p>
     <p>[nums {The QR codes were encoded by book/qr.tcl -- byte mode, error-correction level Q, versions one through ten -- and drawn as SVG geometry rather than bitmaps, so they are resolution-independent. Every one was checked module by module, across all eight mask patterns, against an independent implementation.}]</p>
     <p style='color:var(--muted);'>[nums {Not a diagnosis. Not medical advice. One session, one subject, n = 1.}]</p>
    </div>
  </div>
  <div style='position:absolute;bottom:0;width:100%;'>
    <div class=hair style='margin-bottom:6mm;'></div>
    <div class=kicker>[nums {Subj 001 &nbsp;&middot;&nbsp; 2026-08-18 &nbsp;&middot;&nbsp; end}]</div>
  </div>
</div>"

page "dark nofolio" ""

# ---------------------------------------------------------------------------
# contents, now that every page number is known
# ---------------------------------------------------------------------------
set toc ""
foreach c $::CONTENTS {
    lassign $c title pg
    append toc "<div style='display:flex;align-items:baseline;gap:4mm;'>
      <span style='flex:0 0 auto;'>$title</span>
      <span style='flex:1 1 auto;border-bottom:.25mm dotted var(--rule);transform:translateY(-1.2mm);'></span>
      <span class=n style='flex:0 0 auto;'>$pg</span></div>"
}
set ::H [string map [list @@CONTENTS@@ $toc] $::H]

out "</body></html>"

set f [open $OUT w]
fconfigure $f -encoding utf-8
puts $f $::H
close $f
puts stderr "book: wrote $OUT  $::PAGE pages, [llength $REFS] references with codes"
