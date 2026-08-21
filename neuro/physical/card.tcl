#!/usr/bin/env tclsh
# card.tcl — a two-sided pocket card, cut from the same display file.
#
# Of everything in this project, this is the artefact most likely to change an
# outcome. Nineteen scanned pages across five documents do not survive contact
# with a fifteen-minute appointment. One card that names the findings which
# actually clear threshold, the caveats that undercut the rest, and the
# questions worth asking, does.
#
# Every y coordinate below is absolute rather than accumulated. On a fixed
# 88 x 55 mm card there is no reflow to fall back on: if a block grows, it must
# push something else off the card visibly at authoring time, not silently at
# print time. Absolute placement makes that failure obvious.
#
#   tclsh physical/card.tcl build/dashboard.nvm build/card.svg
#
# Output is two 88 x 55 mm cards side by side with trim boxes, 1 unit = 1 mm.
# Print at 100% scale with fit-to-page off.

set here [file dirname [file normalize [info script]]]
lappend auto_path [file join [file dirname $here] tcl]
package require nvm

set CW 88.0
set CH 55.0
set GAP 8.0
set PAD 5.0

# The meta section is JSON emitted by src/analyze.cpp with a shape this file
# controls, so a targeted regex is honest here in a way that parsing arbitrary
# JSON with one would not be. If the emitter's shape changes this stops matching
# and the card comes out empty, which is the loud failure we want.
proc hypotheses {meta} {
    set out {}
    set idx 0
    while {[regexp -start $idx -indices \
            {\{"id":"(H\d)","name":"([^"]*)","C":([-0-9.eE+]+),"p":([-0-9.eE+]+)} \
            $meta whole gi gn gc gp]} {
        lassign $gi a b ; set id   [string range $meta $a $b]
        lassign $gn a b ; set name [string range $meta $a $b]
        lassign $gc a b ; set C    [string range $meta $a $b]
        lassign $gp a b ; set p    [string range $meta $a $b]
        lappend out [list $id $name $C $p]
        lassign $whole a b ; set idx [expr {$b + 1}]
    }
    return $out
}

proc esc {s} { string map {& &amp; < &lt; > &gt;} $s }

proc T {x y size weight fill anchor str} {
    return [format {<text x="%.2f" y="%.2f" font-size="%.2f" font-weight="%s" fill="%s" text-anchor="%s" font-family="Inter, Helvetica, Arial, sans-serif">%s</text>} \
        $x $y $size $weight $fill $anchor [esc $str]]
}

proc rule {x y w {c "#c9ced9"}} {
    return [format {<line x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" stroke="%s" stroke-width="0.25"/>} \
        $x $y [expr {$x+$w}] $y $c]
}

proc main {argv} {
    global CW CH GAP PAD
    set inPath  [lindex $argv 0]
    set outPath [lindex $argv 1]
    if {$inPath eq "" || $outPath eq ""} {
        puts stderr "usage: card.tcl <in.nvm> <out.svg>"
        exit 1
    }
    set bc [nvm::load $inPath]

    set ranked {} ; set nDeviant 0 ; set nHair 0 ; set nMeasured 0
    foreach s [dict get $bc symbols] {
        if {![dict get $s valid]} continue
        incr nMeasured
        set sev [dict get $s severity]
        if {$sev == 2} { incr nDeviant }
        if {$sev == 1} { incr nHair }
        lappend ranked [list [dict get $s dist] [dict get $s label] $sev]
    }
    set ranked [lsort -real -decreasing -index 0 $ranked]
    set hyps [hypotheses [dict get $bc meta]]

    set ink "#171a21" ; set mut "#6c7385"
    set bad "#be463e" ; set acc "#3a60be"
    set W [expr {$CW*2+$GAP+8}] ; set H [expr {$CH+8}]

    set g {}
    lappend g [format {<rect width="%.1f" height="%.1f" fill="#ffffff"/>} $W $H]
    foreach ox [list 4.0 [expr {4.0+$CW+$GAP}]] {
        lappend g [format {<rect x="%.2f" y="4" width="%.2f" height="%.2f" fill="none" stroke="#dfe3ea" stroke-width="0.2"/>} \
            $ox $CW $CH]
    }

    # =====================================================================
    # FRONT
    # =====================================================================
    set ox 4.0
    set x [expr {$ox+$PAD}] ; set xr [expr {$ox+$CW-$PAD}]
    lappend g [T $x 11.0 4.2 600 $ink start "What this battery found"]
    lappend g [T $x 14.6 2.3 400 $mut start \
        "one session, 2026-08-18, five instruments. not a diagnosis."]
    lappend g [rule $x 16.4 [expr {$CW-2*$PAD}]]

    lappend g [T $x 20.4 2.4 600 $ink start \
        [format "FURTHEST PAST THEIR OWN THRESHOLD  (%d of %d measured)" $nDeviant $nMeasured]]
    set y 24.4
    set shown 0
    foreach r $ranked {
        lassign $r dist label sev
        if {$sev != 2 || $shown >= 7} continue
        lappend g [T $x $y 2.5 400 $ink start [string range $label 0 40]]
        lappend g [T $xr $y 2.5 600 $bad end [format "%+.0f%%" [expr {$dist*100}]]]
        set y [expr {$y + 2.95}]
        incr shown
    }

    lappend g [rule $x 46.0 [expr {$CW-2*$PAD}]]
    lappend g [T $x 49.6 2.7 600 $acc start "Vendor ADHD screen: NEGATIVE, 90% confidence"]
    lappend g [T $x 52.8 2.2 400 $mut start \
        [format "%d further flags are hairline: under 8%% past the line." $nHair]]

    # =====================================================================
    # BACK
    # =====================================================================
    set ox [expr {4.0+$CW+$GAP}]
    set x [expr {$ox+$PAD}] ; set xr [expr {$ox+$CW-$PAD}]
    lappend g [T $x 11.0 4.2 600 $ink start "Five stories, and the caveats"]
    lappend g [T $x 14.6 2.3 400 $mut start \
        "C = agreement with published effect directions. p from permutation."]
    lappend g [rule $x 16.4 [expr {$CW-2*$PAD}]]

    set y 20.6
    foreach h $hyps {
        lassign $h id name C p
        set strong [expr {$C > 0.25 && $p < 0.05}]
        lappend g [T $x $y 2.5 [expr {$strong ? 600 : 400}] \
            [expr {$strong ? $ink : $mut}] start "$id  [string range $name 0 30]"]
        lappend g [T $xr $y 2.4 [expr {$strong ? 600 : 400}] \
            [expr {$strong ? $acc : $mut}] end [format "%+.2f  p %.3f" $C $p]]
        set y [expr {$y + 3.15}]
    }

    lappend g [rule $x 37.6 [expr {$CW-2*$PAD}]]
    lappend g [T $x 41.0 2.4 600 $ink start "WHAT ONE SESSION CANNOT SETTLE"]
    set y 44.0
    foreach line {
        "15 of 19 EEG channels usable, so source localisation was off."
        "Medications logged UNKNOWN, on an in-season allergy-test day."
        "HRV from 2 minutes; VLF wants about 5. 12-lead is unread."
        "n = 1. Nothing on this card is a correlation coefficient."
    } {
        lappend g [T $x $y 2.15 400 $mut start "\u00b7 $line"]
        set y [expr {$y + 2.6}]
    }

    set f [open $outPath w]
    fconfigure $f -encoding utf-8
    puts $f {<?xml version="1.0" encoding="UTF-8"?>}
    puts $f [format {<svg xmlns="http://www.w3.org/2000/svg" width="%.1fmm" height="%.1fmm" viewBox="0 0 %.1f %.1f">} $W $H $W $H]
    foreach line $g { puts $f "  $line" }
    puts $f "</svg>"
    close $f
    puts stderr [format "card: wrote %s  (2 x %.0f x %.0f mm, %d deviant / %d hairline / %d measured)" \
        $outPath $CW $CH $nDeviant $nHair $nMeasured]
}

main $argv
