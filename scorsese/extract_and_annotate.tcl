#!/usr/bin/env tclsh
# =============================================================================
# extract_and_annotate.tcl
#
# Reads a screenshot (IMG_7339.png) of a text message about Scorsese shorts,
# EXTRACTS the "?" / "???" unknowns straight out of the pixels, CORRELATES each
# one with an X/Y position in the original bitmap, and REPRODUCES the message as
# an annotated composition:
#
#   * the message re-typeset in IBM Plex Mono (Google Fonts),
#   * every unknown "?" carries a superscript footnote marker  ?^1 ?^2 ...,
#   * hand-drawn arrows lead from each marker to its answer,
#   * the answers live on a highlighter-yellow panel with a rice-paper grain
#     built from fractal noise, the ink rendered in rich navy blue and roughened
#     with Gaussian blur + turbulence displacement so it bleeds like real ink.
#
# Pipeline is pure Tcl (built-in zlib for the PNG) and emits an SVG; the SVG is
# rasterised to PNG with rsvg-convert.
# =============================================================================

set here [file dirname [file normalize [info script]]]
source [file join $here png_reader.tcl]

# ------------------------------------------------------------------ config ----
set IN    [lindex $argv 0]
if {$IN eq ""} {
    set IN /root/.claude/uploads/b50c505c-39e1-5581-9641-35be58eb610f/148987d0-IMG_7339.png
}
set OUTSVG [file join $here scorsese_annotated.svg]
set OUTPNG [file join $here scorsese_annotated.png]

# =============================================================================
# 1.  PIXEL EXTRACTION  --  find the text-line bands from a brightness profile
# =============================================================================
puts "\[1\] decoding pixels ..."
set doc  [png::read_gray $IN 1040]         ;# only the message half of the shot
set W    [dict get $doc width]
set gray [dict get $doc gray]

# Row projection: how many light (glyph) pixels sit on each scanline.
proc bright_count {row {thr 150}} {
    binary scan $row cu* px
    set n 0
    foreach v $px { if {$v > $thr} {incr n} }
    return $n
}
set rowInk {}
foreach row $gray { lappend rowInk [bright_count $row] }

# Collapse the profile into bands (contiguous inky rows) inside the message
# region only (y>340 skips the status bar / navigation chrome up top).
proc find_bands {rowInk y0 y1 thr minh gap} {
    set bands {}
    set in 0; set start 0; set lastInk 0
    for {set y $y0} {$y <= $y1} {incr y} {
        set c [lindex $rowInk $y]
        if {!$in && $c > $thr} { set in 1; set start $y }
        if {$in && $c <= $thr} {
            if {$y - $lastInk > $gap} {
                if {$lastInk - $start >= $minh} { lappend bands [list $start $lastInk] }
                set in 0
            }
        }
        if {$c > $thr} { set lastInk $y }
    }
    if {$in && $lastInk - $start >= $minh} { lappend bands [list $start $lastInk] }
    return $bands
}
set bands [find_bands $rowInk 340 1030 9 10 8]
puts "    detected [llength $bands] text bands: $bands"

# Horizontal ink extent (xmin..xmax) of a band, so we can place a token's X by
# its character fraction along the real detected line.
proc band_xextent {gray top bot {thr 150}} {
    set xmin 1e9; set xmax -1
    for {set y $top} {$y <= $bot} {incr y} {
        binary scan [lindex $gray $y] cu* px
        set x 0
        foreach v $px {
            if {$v > $thr} {
                if {$x < $xmin} {set xmin $x}
                if {$x > $xmax} {set xmax $x}
            }
            incr x
        }
    }
    if {$xmax < 0} { return {0 0} }
    return [list $xmin $xmax]
}

# =============================================================================
# 2.  THE TRANSCRIPT  --  markers flag the unknowns we want to footnote.
#     \x01  -> a single "?"   unknown   (gets one superscript)
#     \x02  -> the "???"      unknown   (gets one superscript, shows "???")
#     literal "?" stays literal (rhetorical punctuation, not footnoted).
#
#     expectY is a rough centre used only to SNAP each line onto the nearest
#     real detected band -- the coordinate we report is the pixel one.
# =============================================================================
set U \x01
set T \x02
set LINES [list \
  [list {## "Letterboxd"}                                              369  0] \
  [list {}                                                               0  0] \
  [list {Scorsese shorts:}                                             506  0] \
  [list "\"The Big Shave (5m, ${U}, funded by ${U})"                   578  1] \
  [list "\"it's Not Just You Murray (${U}m, 1964, ${U})"              648  1] \
  [list {"What's a nice girl like you doing in a place like this?"}    716  0] \
  [list "(${U}, ${U}, ${U})"                                          778  1] \
  [list {}                                                               0  0] \
  [list "-${T}: What are the editors of these pictures? What"          920  1] \
  [list {else have they edited??}                                      989  0] \
]

# ---- snap each content line to the nearest detected band --------------------
proc nearest_band {bands cy} {
    set best {}; set bestd 1e9
    foreach b $bands {
        set c [expr {([lindex $b 0]+[lindex $b 1])/2.0}]
        set dd [expr {abs($c-$cy)}]
        if {$dd < $bestd} {set bestd $dd; set best $b}
    }
    return $best
}

# =============================================================================
# 3.  ANSWERS  --  researched facts for every footnote (Scorsese shorts).
# =============================================================================
set ANSWERS [list \
 {1 {"1967 — premiered that Dec." "at Knokke-le-Zoute, Belgium."}} \
 {2 {"Jacques Ledoux's EXPRMNTL" "festival: free Agfa-Gevaert" "stock; won the Prix de l'Age d'Or."}} \
 {3 {"~15 min, shot on 16mm B&W."}} \
 {4 {"NYU student film (Tisch) —" "won a Producers Guild award."}} \
 {5 {"9 minutes."}} \
 {6 {"1963."}} \
 {7 {"NYU — Scorsese's first film."}} \
 {8 {"Editors: Scorsese cut THE BIG" "SHAVE himself; Eli F. Bleich cut" "MURRAY!; Robert Hunsicker cut" "NICE GIRL — all NYU-era peers."}} \
]

# =============================================================================
# 4.  LAYOUT + SVG GENERATION
# =============================================================================
set CW 1500 ; set CH 1680
set LX 60             ;# left text block x
set FS 23.0          ;# message font-size
set ADV [expr {0.6*$FS}]   ;# IBM Plex Mono advance = 0.6 em (monospace)
set PITCH 44.0
set Y0 150.0         ;# first baseline
set SUPFS 15.0

set PX 902 ; set PW 556          ;# yellow answer panel
set PY 96  ; set PH 1512

proc esc {s} { string map {& &amp; < &lt; > &gt;} $s }

set svg {}
proc emit {s} { global svg; append svg $s "\n" }

emit "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
emit "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"$CW\" height=\"$CH\" viewBox=\"0 0 $CW $CH\" font-family=\"IBM Plex Mono\">"

# ---- defs: filters + arrowhead ---------------------------------------------
emit {<defs>}
# ink: warp glyph edges with turbulence + soften -> looks like bled ink
emit {  <filter id="ink" x="-25%" y="-25%" width="150%" height="150%">
    <feTurbulence type="fractalNoise" baseFrequency="0.014 0.017" numOctaves="2" seed="7" result="n"/>
    <feDisplacementMap in="SourceGraphic" in2="n" scale="3.4" xChannelSelector="R" yChannelSelector="G" result="d"/>
    <feGaussianBlur in="d" stdDeviation="0.55"/>
  </filter>}
# heavier ink for the big heading
emit {  <filter id="inkHeavy" x="-25%" y="-25%" width="150%" height="150%">
    <feTurbulence type="fractalNoise" baseFrequency="0.012 0.016" numOctaves="2" seed="3" result="n"/>
    <feDisplacementMap in="SourceGraphic" in2="n" scale="4.6" xChannelSelector="R" yChannelSelector="G" result="d"/>
    <feGaussianBlur in="d" stdDeviation="0.7"/>
  </filter>}
# rough: wavy highlighter edges
emit {  <filter id="rough" x="-8%" y="-25%" width="116%" height="150%">
    <feTurbulence type="fractalNoise" baseFrequency="0.013 0.03" numOctaves="3" seed="5" result="n"/>
    <feDisplacementMap in="SourceGraphic" in2="n" scale="11" xChannelSelector="R" yChannelSelector="G"/>
  </filter>}
# rice-paper grain: fine fractal-noise speckle turned translucent brown
emit {  <filter id="grain" x="0%" y="0%" width="100%" height="100%">
    <feTurbulence type="fractalNoise" baseFrequency="0.62" numOctaves="5" seed="42" stitchTiles="stitch" result="t"/>
    <feColorMatrix in="t" type="matrix"
       values="0 0 0 0 0.40
               0 0 0 0 0.32
               0 0 0 0 0.12
               1.15 0 0 0 -0.5"/>
  </filter>}
# rice-paper cloudy mottle: coarse low-frequency noise for uneven pulp
emit {  <filter id="mottle" x="0%" y="0%" width="100%" height="100%">
    <feTurbulence type="fractalNoise" baseFrequency="0.09" numOctaves="3" seed="23" stitchTiles="stitch" result="t"/>
    <feColorMatrix in="t" type="matrix"
       values="0 0 0 0 0.55
               0 0 0 0 0.48
               0 0 0 0 0.18
               0.5 0 0 0 -0.28"/>
  </filter>}
# rice-paper long fibres: anisotropic noise
emit {  <filter id="fibre" x="0%" y="0%" width="100%" height="100%">
    <feTurbulence type="fractalNoise" baseFrequency="0.006 0.42" numOctaves="3" seed="17" stitchTiles="stitch" result="t"/>
    <feColorMatrix in="t" type="matrix"
       values="0 0 0 0 0.48
               0 0 0 0 0.40
               0 0 0 0 0.18
               0.7 0 0 0 -0.44"/>
  </filter>}
# arrows: slight hand-drawn wobble
emit {  <filter id="wob" x="-20%" y="-20%" width="140%" height="140%">
    <feTurbulence type="fractalNoise" baseFrequency="0.02" numOctaves="2" seed="9" result="n"/>
    <feDisplacementMap in="SourceGraphic" in2="n" scale="2.2"/>
  </filter>}
emit {  <marker id="ah" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
    <path d="M0,0 L10,5 L0,10 L3,5 z" fill="#16234f"/>
  </marker>}
emit {</defs>}

# ---- background -------------------------------------------------------------
emit "<rect width=\"$CW\" height=\"$CH\" fill=\"#0b0d10\"/>"
emit "<rect x=\"28\" y=\"28\" width=\"[expr {$CW-56}]\" height=\"[expr {$CH-56}]\" rx=\"22\" fill=\"#111418\" stroke=\"#20262d\" stroke-width=\"1.5\"/>"

# ---- header -----------------------------------------------------------------
emit "<text x=\"60\" y=\"78\" font-size=\"25\" fill=\"#e9edf2\" font-weight=\"600\">Scorsese shorts — the ?’s, extracted &amp; answered</text>"
emit "<text x=\"60\" y=\"104\" font-size=\"14\" fill=\"#5f6b78\">glyphs pulled from IMG_7339.png pixels · reproduced in IBM Plex Mono</text>"

# =============================================================================
# 4a.  Left: reproduced message, superscripts, and pixel correlation.
# =============================================================================
set superAnchors {} ;# num -> {x y}
set correlations {} ;# report rows
set counter 0
set row 0
foreach entry $LINES {
    lassign $entry text expectY hasTok
    set baseY [expr {$Y0 + $row*$PITCH}]
    incr row
    if {$text eq ""} { continue }

    # snap this line to a real detected band (for the pixel coordinate report)
    set band {}
    set xext {0 0}
    if {$expectY > 0} {
        set band [nearest_band $bands $expectY]
        if {$band ne ""} { set xext [band_xextent $gray [lindex $band 0] [lindex $band 1]] }
    }
    lassign $band bTop bBot
    lassign $xext bXmin bXmax

    # walk the string, emitting tspans and recording superscript anchors
    set out ""
    set col 0        ;# visible column (monospace)
    set visLen 0     ;# total visible length for fraction mapping
    # first pass: visible length (markers count as their display width)
    foreach ch [split $text ""] {
        if {$ch eq $U} { incr visLen 1 } elseif {$ch eq $T} { incr visLen 3 } else { incr visLen 1 }
    }
    set fill "#dfe4ea"
    if {[string match {##*} $text]} { set fill "#8bd6c0" }
    foreach ch [split $text ""] {
        if {$ch eq $U || $ch eq $T} {
            incr counter
            set disp [expr {$ch eq $T ? "???" : "?"}]
            set dlen [string length $disp]
            append out "<tspan fill=\"#ffd23f\">[esc $disp]</tspan><tspan baseline-shift=\"super\" font-size=\"$SUPFS\" fill=\"#ff9e2c\" font-weight=\"600\">$counter</tspan>"
            set anchorX [expr {$LX + ($col+$dlen)*$ADV + 4}]
            set anchorY [expr {$baseY - $FS*0.55}]
            lappend superAnchors [list $counter $anchorX $anchorY]
            # pixel correlation: fraction of visible line -> real bitmap X
            set frac [expr {$visLen>0 ? ($col+$dlen/2.0)/$visLen : 0}]
            set pxX  [expr {$bXmin + $frac*($bXmax-$bXmin)}]
            set pxY  [expr {($bTop+$bBot)/2}]
            lappend correlations [list $counter $disp [expr {int($pxX)}] $pxY $bTop $bBot]
            incr col $dlen
        } else {
            append out [esc $ch]
            incr col
        }
    }
    emit "<text x=\"$LX\" y=\"[format %.1f $baseY]\" font-size=\"$FS\" fill=\"$fill\" xml:space=\"preserve\">$out</text>"
}

# ---- lower-left: pixel extraction log --------------------------------------
set logY 690
emit "<rect x=\"48\" y=\"[expr {$logY-42}]\" width=\"800\" height=\"902\" rx=\"14\" fill=\"#0e1519\" stroke=\"#1c2730\" stroke-width=\"1.3\"/>"
emit "<text x=\"70\" y=\"[expr {$logY-8}]\" font-size=\"17\" fill=\"#63b8a2\" font-weight=\"600\">▸ GLYPH EXTRACTION LOG  ·  ? tokens → pixel (x,y)</text>"
emit "<text x=\"70\" y=\"[expr {$logY+22}]\" font-size=\"13.5\" fill=\"#54606b\">detected [llength $bands] text bands in a [expr {$W}]px-wide bitmap by brightness projection</text>"
set ly [expr {$logY+58}]
emit "<text x=\"70\" y=\"$ly\" font-size=\"14\" fill=\"#7f8b96\" xml:space=\"preserve\">  #   token   orig-x   orig-y     band-rows</text>"
set ly [expr {$ly+30}]
foreach c $correlations {
    lassign $c num disp px py bt bb
    set line [format "  %d    %-5s   %5d    %5d      %d–%d" $num $disp $px $py $bt $bb]
    emit "<text x=\"70\" y=\"$ly\" font-size=\"15\" fill=\"#aeb8c2\" xml:space=\"preserve\">[esc $line]</text>"
    set ly [expr {$ly+30}]
}
set ly [expr {$ly+14}]
emit "<text x=\"70\" y=\"$ly\" font-size=\"13\" fill=\"#4c5762\" xml:space=\"preserve\">columns from character-fraction along each detected line's ink extent</text>"

# =============================================================================
# 4b.  Right: highlighter-yellow answer panel (rice-paper + navy ink).
# =============================================================================
# two overlapping marker swipes for a hand-drawn highlighter feel
emit "<g filter=\"url(#rough)\">"
emit "  <rect x=\"$PX\" y=\"$PY\" width=\"$PW\" height=\"$PH\" rx=\"16\" fill=\"#f6ea3d\"/>"
emit "  <rect x=\"[expr {$PX-6}]\" y=\"[expr {$PY+8}]\" width=\"[expr {$PW+8}]\" height=\"120\" fill=\"#fff36b\" opacity=\"0.75\"/>"
emit "</g>"
# rice-paper grain + fibres, clipped to the panel
emit "<clipPath id=\"pc\"><rect x=\"$PX\" y=\"$PY\" width=\"$PW\" height=\"$PH\" rx=\"16\"/></clipPath>"
emit "<g clip-path=\"url(#pc)\">"
emit "  <rect x=\"$PX\" y=\"$PY\" width=\"$PW\" height=\"$PH\" filter=\"url(#mottle)\" opacity=\"0.5\"/>"
emit "  <rect x=\"$PX\" y=\"$PY\" width=\"$PW\" height=\"$PH\" filter=\"url(#fibre)\" opacity=\"0.6\"/>"
emit "  <rect x=\"$PX\" y=\"$PY\" width=\"$PW\" height=\"$PH\" filter=\"url(#grain)\" opacity=\"0.8\"/>"
# faint highlighter streaks
for {set s 0} {$s < 6} {incr s} {
    set sy [expr {$PY+60+$s*260}]
    emit "  <rect x=\"$PX\" y=\"$sy\" width=\"$PW\" height=\"70\" fill=\"#efe22e\" opacity=\"0.18\"/>"
}
emit "</g>"

# panel title (navy ink)
emit "<text x=\"[expr {$PX+30}]\" y=\"[expr {$PY+56}]\" font-size=\"26\" fill=\"#16234f\" font-weight=\"700\" filter=\"url(#inkHeavy)\">MARGINALIA</text>"
emit "<text x=\"[expr {$PX+30}]\" y=\"[expr {$PY+84}]\" font-size=\"14.5\" fill=\"#23336a\" filter=\"url(#ink)\">answers, in ink</text>"

# answer entries; record each arrow target
set entryTargets {} ;# num -> {x y}
set cy [expr {$PY+128}]
set LH 34
set GAP 100
foreach a $ANSWERS {
    lassign $a num lines
    set nl [llength $lines]
    set badgeX [expr {$PX+42}]
    set badgeY [expr {$cy+18}]
    # navy badge with white number
    emit "<circle cx=\"$badgeX\" cy=\"$badgeY\" r=\"17\" fill=\"#16234f\"/>"
    emit "<text x=\"$badgeX\" y=\"[expr {$badgeY+6}]\" font-size=\"18\" fill=\"#f6ea3d\" font-weight=\"700\" text-anchor=\"middle\">$num</text>"
    lappend entryTargets [list $num [expr {$badgeX-18}] $badgeY]
    # answer text lines, navy ink
    set ty [expr {$cy+14}]
    foreach ln $lines {
        emit "<text x=\"[expr {$PX+74}]\" y=\"$ty\" font-size=\"20\" fill=\"#152a63\" filter=\"url(#ink)\" xml:space=\"preserve\">[esc $ln]</text>"
        set ty [expr {$ty+$LH}]
    }
    set cy [expr {$cy + $nl*$LH + $GAP}]
}

# =============================================================================
# 4c.  Arrows from each superscript to its answer badge.
# =============================================================================
proc anchor {lst num} { foreach e $lst { if {[lindex $e 0]==$num} {return $e} } ; return {} }
emit "<g filter=\"url(#wob)\">"
for {set n 1} {$n <= $counter} {incr n} {
    set s [anchor $superAnchors $n]
    set t [anchor $entryTargets $n]
    if {$s eq "" || $t eq ""} continue
    lassign $s _ sx sy
    lassign $t _ tx ty
    set c1x [expr {$sx + ($tx-$sx)*0.45}]
    set c1y [expr {$sy - 6}]
    set c2x [expr {$tx - 70}]
    set c2y $ty
    emit "<path d=\"M[format %.1f $sx],[format %.1f $sy] C[format %.1f $c1x],[format %.1f $c1y] [format %.1f $c2x],[format %.1f $c2y] [format %.1f $tx],[format %.1f $ty]\" fill=\"none\" stroke=\"#20356f\" stroke-width=\"2\" stroke-opacity=\"0.8\" marker-end=\"url(#ah)\"/>"
    emit "<circle cx=\"[format %.1f $sx]\" cy=\"[format %.1f $sy]\" r=\"3\" fill=\"#ff9e2c\"/>"
}
emit "</g>"

emit "</svg>"

# ------------------------------------------------------------------ write ----
set fh [open $OUTSVG w]; puts -nonewline $fh $svg; close $fh
puts "\[2\] wrote SVG -> $OUTSVG"

# console correlation report
puts "\[3\] ? / ??? tokens correlated to original-bitmap coordinates:"
puts "      #  token   x     y     band"
foreach c $correlations {
    lassign $c num disp px py bt bb
    puts [format "      %d  %-5s  %4d  %4d   %d-%d" $num $disp $px $py $bt $bb]
}

# rasterise
if {![catch {exec rsvg-convert --version} ver]} {
    exec rsvg-convert -w [expr {$CW*2}] -h [expr {$CH*2}] $OUTSVG -o $OUTPNG
    puts "\[4\] rasterised -> $OUTPNG ([file size $OUTPNG] bytes)"
} else {
    puts "\[4\] rsvg-convert not found; SVG only."
}
