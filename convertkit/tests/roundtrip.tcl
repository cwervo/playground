#!/usr/bin/env tclsh
# roundtrip.tcl -- convertkit test suite.
# Runs every bidirectional pair through xconv and verifies the Tcl
# source survives byte-exactly. Exit 0 = all green.

set here   [file dirname [file normalize [info script]]]
set root   [file dirname $here]
set xconv  [file join $root bin xconv.tcl]
set outdir [file join $here out]
file delete -force $outdir
file mkdir $outdir

set pass 0
set fail 0

proc slurp {path} {
    set f [open $path rb]; set d [read $f]; close $f; return $d
}

proc check {label ok} {
    global pass fail
    if {$ok} { incr pass; puts "  ok   $label" } else { incr fail; puts "  FAIL $label" }
}

proc convert {in out} {
    global xconv
    exec [info nameofexecutable] $xconv $in $out
}

foreach sample [glob [file join $root samples *.tcl]] {
    set base [file rootname [file tail $sample]]
    puts "== $base =="
    set orig [slurp $sample]
    set d [file join $::outdir $base]
    file mkdir $d

    # seed converters: tcl -> xml -> tcl
    convert $sample $d/a.xml
    convert $d/a.xml $d/a.tcl
    check "tcl -> xml -> tcl" [expr {[slurp $d/a.tcl] eq $orig}]

    # xml -> png -> xml
    convert $d/a.xml $d/b.png
    convert $d/b.png $d/b.xml
    check "xml -> png -> xml" [expr {[slurp $d/b.xml] eq [slurp $d/a.xml]}]

    # full chain: tcl -> png -> tcl
    convert $sample $d/c.png
    convert $d/c.png $d/c.tcl
    check "tcl -> png -> tcl" [expr {[slurp $d/c.tcl] eq $orig}]

    # lossy carrier: tcl -> jpg -> tcl
    convert $sample $d/e.jpg
    convert $d/e.jpg $d/e.tcl
    check "tcl -> jpg -> tcl" [expr {[slurp $d/e.tcl] eq $orig}]

    # image -> image both ways keeps the payload
    convert $d/c.png $d/f.jpg
    convert $d/f.jpg $d/g.png
    convert $d/g.png $d/g.tcl
    check "png -> jpg -> png -> tcl" [expr {[slurp $d/g.tcl] eq $orig}]

    # jpeg alias extension
    convert $sample $d/h.jpeg
    convert $d/h.jpeg $d/h.tcl
    check "tcl -> jpeg -> tcl" [expr {[slurp $d/h.tcl] eq $orig}]
}

puts "----"
puts "pass: $pass  fail: $fail"
exit [expr {$fail > 0}]
