#!/usr/bin/env tclsh
# talk.tcl -- tests for the landscape 4:3 talk build.

set here [file dirname [file normalize [info script]]]
set root [file dirname $here]
set tool [file join $root bin talk.tcl]
set build [file join $root docs talk build]

foreach mod {tclxml tclast pngcodec jpgcodec typeset pageframe} {
    source [file join $root lib $mod.tcl]
}

set pass 0
set fail 0
proc check {label ok} {
    global pass fail
    if {$ok} { incr pass; puts "  ok   $label" } else { incr fail; puts "  FAIL $label" }
}
proc slurp {p} { set f [open $p r]; fconfigure $f -encoding utf-8; set d [read $f]; close $f; return $d }

puts "== build =="
exec [info nameofexecutable] $tool build
check "talk.html exists" [file exists [file join $build talk.html]]
check "pp.4:3.html.pdf exists" [file exists [file join $build "talk.landscape.pp.4:3.html.pdf"]]
set slides [lsort [glob -nocomplain [file join $build talk.landscape.4x3.s*.png]]]
check "slide frames emitted" [expr {[llength $slides] >= 6}]

puts "== payloads =="
set html [slurp [file join $build talk.html]]
set got [exec [info nameofexecutable] $tool extract [file join $build "talk.landscape.pp.4:3.html.pdf"]]
check "extract(pdf) == talk.html" [expr {$got eq [string trimright $html \n]}]
set got [exec [info nameofexecutable] $tool extract [lindex $slides 0]]
check "extract(slide 1 tEXt) == talk.html" [expr {$got eq [string trimright $html \n]}]

puts "== slide frame self-description =="
set d [::printable::pageframe::decode [lindex $slides 3]]
set meta [dict get $d meta]
check "doc=talk" [expr {[dict get $meta doc] eq "talk"}]
check "paper=4:3-landscape-10x7.5in" [expr {[dict get $meta paper] eq "4:3-landscape-10x7.5in"}]
check "slide=4 of 8" [expr {[dict get $meta slide] == 4 && [dict get $meta slides] == 8}]
check "landscape absolute size (242.0 178.5 mm + quiet = 10x7.5in)" \
    [expr {[dict get $meta page_mm] eq "242.0 178.5"}]
check "slide decodes to its own text" \
    [string match "# Anatomy of a page frame*" [dict get $d source]]

puts "----"
puts "pass: $pass  fail: $fail"
exit [expr {$fail > 0}]
