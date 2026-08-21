#!/usr/bin/env tclsh
# plot.tcl — render a NeuroVM display file to SVG.
#
# Two modes, because paper and a pen plotter want different things:
#
#   --mode print   full colour, filled shapes, for a laser printer or screen.
#   --mode pen     every shape reduced to a stroked outline at one pen width,
#                  fills replaced by 45-degree hatching. Suitable for an AxiDraw
#                  or a laser cutter's vector pass. Semantic opcodes are
#                  deliberately dropped: paper has no hover state, and a NOTE
#                  the reader cannot reach is worse than no NOTE at all.
#
# This host proves the point of the bytecode. It shares nothing with the Tk
# explorer except tcl/nvm.tcl, it never sees an EEG number, and it cannot
# disagree with the screen about what the data says because it is executing the
# same instructions.
#
#   tclsh physical/plot.tcl build/dashboard.nvm build/dashboard.svg --mode print
#   tclsh physical/plot.tcl build/dashboard.nvm build/plot.svg      --mode pen

set here [file dirname [file normalize [info script]]]
lappend auto_path [file join [file dirname $here] tcl]
package require nvm

namespace eval bk::svg {
    variable out {}
    variable fill "#000000"
    variable op 1.0
    variable width 1.0
    variable fontFamily "Helvetica, Arial, sans-serif"
    variable fontWeight "normal"
    variable fontSize 10
    variable mode "print"
    variable penColour "#101010"
    variable penWidth 0.9
    variable anchorId ""
    variable panelId ""
    variable hatchIds {}
}

proc bk::svg::reset {newMode} {
    variable out      ; set out {}
    variable mode     ; set mode $newMode
    variable anchorId ; set anchorId ""
    variable panelId  ; set panelId ""
}

proc bk::svg::esc {s} {
    return [string map {& &amp; < &lt; > &gt; \" &quot;} $s]
}

proc bk::svg::add {line} { variable out ; lappend out $line }

# In pen mode every stroke is the same colour and width: a plotter has one pen
# down at a time and pretending otherwise produces a drawing that looks right on
# screen and wrong on paper.
proc bk::svg::strokeAttrs {} {
    variable mode ; variable fill ; variable op ; variable width
    variable penColour ; variable penWidth
    if {$mode eq "pen"} {
        return "fill=\"none\" stroke=\"$penColour\" stroke-width=\"$penWidth\""
    }
    return [format {fill="none" stroke="%s" stroke-opacity="%.3f" stroke-width="%.2f"} \
        $fill $op $width]
}

proc bk::svg::fillAttrs {} {
    variable mode ; variable fill ; variable op
    variable penColour ; variable penWidth
    if {$mode eq "pen"} {
        # Hatch instead of flood. The hatch pattern is defined once in <defs>
        # and the pen traverses it, which is what a plotter can actually do.
        return "fill=\"url(#hatch)\" stroke=\"$penColour\" stroke-width=\"$penWidth\""
    }
    return [format {fill="%s" fill-opacity="%.3f" stroke="none"} $fill $op]
}

proc bk::svg::tagAttr {} {
    variable anchorId ; variable panelId
    set a ""
    if {$panelId ne ""}  { append a " data-panel=\"[esc $panelId]\"" }
    if {$anchorId ne ""} { append a " data-anchor=\"[esc $anchorId]\"" }
    return $a
}

proc bk::svg::clear {} {}

proc bk::svg::rgba {r g b a} {
    variable fill ; variable op
    set fill [format "#%02x%02x%02x" $r $g $b]
    set op [expr {$a / 255.0}]
}
proc bk::svg::linew {w} { variable width ; set width [expr {max(0.25, $w)}] }

proc bk::svg::font {name size} {
    variable fontFamily ; variable fontWeight ; variable fontSize
    set fontFamily [expr {[string match *mono* $name]
        ? {"IBM Plex Mono", "DejaVu Sans Mono", monospace}
        : {"Inter", "Helvetica Neue", Helvetica, Arial, sans-serif}}]
    set fontWeight [expr {[string match *bold* $name] ? "600" : "400"}]
    set fontSize $size
}

proc bk::svg::rect {how x y w h} {
    add [format {<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" %s%s/>} \
        $x $y [expr {abs($w)}] [expr {abs($h)}] \
        [expr {$how eq "fill" ? [fillAttrs] : [strokeAttrs]}] [tagAttr]]
}

proc bk::svg::circle {how x y r} {
    add [format {<circle cx="%.2f" cy="%.2f" r="%.2f" %s%s/>} \
        $x $y $r [expr {$how eq "fill" ? [fillAttrs] : [strokeAttrs]}] [tagAttr]]
}

proc bk::svg::arc {how x y r a0 a1} {
    set x0 [expr {$x + $r*cos($a0)}] ; set y0 [expr {$y + $r*sin($a0)}]
    set x1 [expr {$x + $r*cos($a1)}] ; set y1 [expr {$y + $r*sin($a1)}]
    set large [expr {abs($a1-$a0) > 3.14159265 ? 1 : 0}]
    add [format {<path d="M %.2f %.2f A %.2f %.2f 0 %d 1 %.2f %.2f" %s%s/>} \
        $x0 $y0 $r $r $large $x1 $y1 [strokeAttrs] [tagAttr]]
}

proc bk::svg::polyline {how pts} {
    set d ""
    set first 1
    foreach {x y} $pts {
        append d [format "%s %.2f %.2f " [expr {$first ? "M" : "L"}] $x $y]
        set first 0
    }
    add [format {<path d="%s" %s%s/>} [string trim $d] \
        [expr {$how eq "fill" ? [fillAttrs] : [strokeAttrs]}] [tagAttr]]
}

proc bk::svg::text {x y str anchorMode} {
    variable mode ; variable fill ; variable op
    variable fontFamily ; variable fontWeight ; variable fontSize ; variable penColour
    set a [lindex {start middle end} $anchorMode]
    set colour [expr {$mode eq "pen" ? $penColour : $fill}]
    set o [expr {$mode eq "pen" ? 1.0 : $op}]
    add [format {<text x="%.2f" y="%.2f" text-anchor="%s" font-family=%s font-size="%.1f" font-weight="%s" fill="%s" fill-opacity="%.3f"%s>%s</text>} \
        $x $y $a "\"$fontFamily\"" $fontSize $fontWeight $colour $o [tagAttr] [esc $str]]
}

proc bk::svg::panel {id title} {
    variable panelId ; set panelId $id
    add "<!-- panel: $id -- [esc $title] -->"
}
proc bk::svg::endpanel {} { variable panelId ; set panelId "" }
proc bk::svg::anchor {id} { variable anchorId ; set anchorId $id }

# Notes, flags, citations and edges survive into the SVG as comments and data
# attributes rather than as marks. An SVG opened in a browser keeps them
# inspectable; an SVG sent to a plotter ignores them. Both are correct.
proc bk::svg::note {plain full} {
    variable anchorId
    add "<!-- note $anchorId | [esc $plain] -->"
}
proc bk::svg::flag {sev} {}
proc bk::svg::cite {t} {}
proc bk::svg::edge {a b hyp w sign} {
    add "<!-- edge $hyp $a -> $b w=[format %.2f $w] sign=$sign -->"
}

# ---------------------------------------------------------------------------
proc main {argv} {
    set inPath  [lindex $argv 0]
    set outPath [lindex $argv 1]
    set mode "print"
    for {set i 2} {$i < [llength $argv]} {incr i} {
        if {[lindex $argv $i] eq "--mode"} { set mode [lindex $argv [incr i]] }
    }
    if {$inPath eq "" || $outPath eq ""} {
        puts stderr "usage: plot.tcl <in.nvm> <out.svg> \[--mode print|pen\]"
        exit 1
    }

    set bc [nvm::load $inPath]
    set W [dict get $bc canvasW]
    set H [dict get $bc canvasH]

    bk::svg::reset $mode
    nvm::run $bc ::bk::svg

    set f [open $outPath w]
    fconfigure $f -encoding utf-8
    puts $f {<?xml version="1.0" encoding="UTF-8"?>}
    puts $f [format {<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">} $W $H $W $H]
    puts $f "  <defs>"
    puts $f {    <pattern id="hatch" width="6" height="6" patternTransform="rotate(45)" patternUnits="userSpaceOnUse">}
    puts $f {      <line x1="0" y1="0" x2="0" y2="6" stroke="#101010" stroke-width="0.6"/>}
    puts $f {    </pattern>}
    puts $f "  </defs>"
    if {$mode eq "print"} {
        puts $f [format {  <rect width="%d" height="%d" fill="#ffffff"/>} $W $H]
    }
    foreach line $::bk::svg::out { puts $f "  $line" }
    puts $f "</svg>"
    close $f

    puts stderr "plot: wrote $outPath  (${W}x${H}, mode $mode, [llength $::bk::svg::out] elements)"
}

main $argv
