#!/usr/bin/env tclsh
# solid.tcl — turn the margin ladder into an object you can hold.
#
# ---------------------------------------------------------------------------
# WHY A PHYSICAL OBJECT AT ALL
# ---------------------------------------------------------------------------
# A colour-coded bar chart asks the reader to decode a legend. A profile you run
# your thumb along does not: the datum surface IS the threshold, pins that stand
# proud ARE the findings past it, and pins that sink below ARE the measures with
# margin to spare. There is no key to memorise and no colour to mistranslate,
# which also makes it the only rendering in this project that works if you
# cannot see it.
#
# The comb is 30 pins on a 4.7 mm pitch, sorted most-deviant first, so the shape
# under your hand is a decay curve: a cliff at the left where the immune and
# mood findings sit, a shoulder through the autonomic ratios, then the long flat
# run of everything that is fine.
#
#   tclsh physical/solid.tcl build/dashboard.nvm build/comb
#     -> build/comb.stl    printable now, no dependencies
#     -> build/comb.scad   the same object with engraved labels, needs OpenSCAD
#
# Print notes: 0.2 mm layers, no supports, PLA is fine. The pins are 4 x 14 mm
# so they survive handling. Total object is about 145 x 24 x 16 mm.
# ---------------------------------------------------------------------------

set here [file dirname [file normalize [info script]]]
lappend auto_path [file join [file dirname $here] tcl]
package require nvm

# -- object parameters, in millimetres --------------------------------------
set P(pins)      30
set P(pitch)     4.7
set P(pinW)      4.0
set P(pinD)      14.0
set P(baseH)     4.0
set P(baseD)     24.0
set P(datum)     4.0     ;# pin height at dist == 0; the threshold you feel
set P(range)     9.0     ;# extra height at dist -> +inf
set P(minPin)    0.8
set P(margin)    5.0

# ---------------------------------------------------------------------------
# ASCII STL emitter. A union of overlapping boxes is not strictly a closed
# manifold, but every slicer in common use resolves it correctly, and keeping
# the geometry to axis-aligned boxes means this file has no dependencies and
# the output is auditable by eye.
# ---------------------------------------------------------------------------
proc tri {f a b c n} {
    lassign $n nx ny nz
    puts $f [format "  facet normal %.5f %.5f %.5f" $nx $ny $nz]
    puts $f "    outer loop"
    foreach v [list $a $b $c] {
        lassign $v x y z
        puts $f [format "      vertex %.4f %.4f %.4f" $x $y $z]
    }
    puts $f "    endloop"
    puts $f "  endfacet"
}

proc box {f x0 y0 z0 x1 y1 z1} {
    set p000 [list $x0 $y0 $z0] ; set p100 [list $x1 $y0 $z0]
    set p110 [list $x1 $y1 $z0] ; set p010 [list $x0 $y1 $z0]
    set p001 [list $x0 $y0 $z1] ; set p101 [list $x1 $y0 $z1]
    set p111 [list $x1 $y1 $z1] ; set p011 [list $x0 $y1 $z1]
    tri $f $p000 $p110 $p100 {0 0 -1} ; tri $f $p000 $p010 $p110 {0 0 -1}
    tri $f $p001 $p101 $p111 {0 0  1} ; tri $f $p001 $p111 $p011 {0 0  1}
    tri $f $p000 $p100 $p101 {0 -1 0} ; tri $f $p000 $p101 $p001 {0 -1 0}
    tri $f $p010 $p111 $p110 {0  1 0} ; tri $f $p010 $p011 $p111 {0  1 0}
    tri $f $p000 $p001 $p011 {-1 0 0} ; tri $f $p000 $p011 $p010 {-1 0 0}
    tri $f $p100 $p110 $p111 { 1 0 0} ; tri $f $p100 $p111 $p101 { 1 0 0}
}

# ---------------------------------------------------------------------------
proc main {argv} {
    global P
    set inPath  [lindex $argv 0]
    set stem    [lindex $argv 1]
    if {$inPath eq "" || $stem eq ""} {
        puts stderr "usage: solid.tcl <in.nvm> <out-stem>"
        exit 1
    }

    set bc [nvm::load $inPath]

    # Rank by distance past threshold, same ordering as the ladder panel, so the
    # object and the screen tell the same story in the same sequence.
    set rows {}
    foreach s [dict get $bc symbols] {
        if {![dict get $s valid]} continue
        lappend rows [list [dict get $s dist] [dict get $s name] [dict get $s severity]]
    }
    set rows [lsort -real -decreasing -index 0 $rows]
    set rows [lrange $rows 0 [expr {$P(pins) - 1}]]
    set n [llength $rows]

    set totalW [expr {$P(margin)*2 + $n*$P(pitch)}]

    # -- STL ----------------------------------------------------------------
    set f [open "$stem.stl" w]
    puts $f "solid neuro_margin_comb"
    box $f 0 0 0 $totalW $P(baseD) $P(baseH)

    # A shallow rail at datum height along the back face: the tactile reference
    # for "the threshold". Everything taller than the rail is a finding.
    box $f 0 [expr {$P(baseD)-1.6}] $P(baseH) \
           $totalW $P(baseD) [expr {$P(baseH)+$P(datum)}]

    set i 0
    foreach row $rows {
        lassign $row dist name sev
        # tanh keeps a 400%-past-threshold wheal from producing a 40 mm spike
        # while still ranking it clearly above a 200% one.
        set h [expr {$P(datum) + $P(range) * tanh(0.6 * $dist)}]
        if {$h < $P(minPin)} { set h $P(minPin) }
        set x0 [expr {$P(margin) + $i*$P(pitch) + ($P(pitch)-$P(pinW))/2.0}]
        box $f $x0 3.0 $P(baseH) [expr {$x0+$P(pinW)}] [expr {3.0+$P(pinD)}] \
               [expr {$P(baseH)+$h}]
        incr i
    }
    puts $f "endsolid neuro_margin_comb"
    close $f

    # -- OpenSCAD -----------------------------------------------------------
    set f [open "$stem.scad" w]
    fconfigure $f -encoding utf-8
    puts $f "// neuro margin comb -- generated by physical/solid.tcl from [file tail $inPath]"
    puts $f "// Each pin is one metric. Pin height above the rail = distance past its own"
    puts $f "// reference threshold. Below the rail = margin to spare. Run a thumb along it."
    puts $f "// Render: openscad -o comb.stl [file tail $stem].scad"
    puts $f ""
    puts $f "\$fn = 24;"
    puts $f "label_depth = 0.6;"
    puts $f ""
    puts $f "module comb() {"
    puts $f "  difference() {"
    puts $f "    union() {"
    puts $f [format "      cube(\[%.2f, %.2f, %.2f\]);" $totalW $P(baseD) $P(baseH)]
    puts $f [format "      translate(\[0, %.2f, %.2f\]) cube(\[%.2f, 1.6, %.2f\]);" \
        [expr {$P(baseD)-1.6}] $P(baseH) $totalW $P(datum)]
    set i 0
    foreach row $rows {
        lassign $row dist name sev
        set h [expr {$P(datum) + $P(range) * tanh(0.6 * $dist)}]
        if {$h < $P(minPin)} { set h $P(minPin) }
        set x0 [expr {$P(margin) + $i*$P(pitch) + ($P(pitch)-$P(pinW))/2.0}]
        puts $f [format "      translate(\[%.2f, 3, %.2f\]) cube(\[%.2f, %.2f, %.2f\]);  // %s  %+.0f%%" \
            $x0 $P(baseH) $P(pinW) $P(pinD) $h $name [expr {$dist*100}]]
        incr i
    }
    puts $f "    }"
    puts $f "    // engraved labels on the front face, readable with the rail away from you"
    set i 0
    foreach row $rows {
        lassign $row dist name sev
        set x0 [expr {$P(margin) + $i*$P(pitch) + $P(pitch)/2.0}]
        puts $f [format "    translate(\[%.2f, %.2f, 1.2\]) rotate(\[0,0,90\])" $x0 2.2]
        puts $f [format "      linear_extrude(label_depth) text(\"%s\", size=1.7, halign=\"left\", valign=\"center\");" \
            [string map {\" ""} $name]]
        incr i
    }
    puts $f "  }"
    puts $f "}"
    puts $f ""
    puts $f "comb();"
    close $f

    puts stderr [format "solid: wrote %s.stl and %s.scad  (%d pins, %.0f x %.0f x %.0f mm)" \
        $stem $stem $n $totalW $P(baseD) [expr {$P(baseH)+$P(datum)+$P(range)}]]
    puts stderr "  tallest pin: [lindex [lindex $rows 0] 1] at [format %+.0f%% [expr {[lindex [lindex $rows 0] 0]*100}]]"
}

main $argv
