#!/usr/bin/env tclsh
# tests/all.tcl -- run every .test file, each in its own interpreter.

set here [file dirname [file normalize [info script]]]
set files [lsort [glob -directory $here *.test]]
set failed {}
set total 0
set passed 0

foreach f $files {
    set out ""
    set code [catch {exec [info nameofexecutable] $f 2>@1} out]
    puts $out
    if {[regexp {Total\s+(\d+)\s+Passed\s+(\d+)} $out -> t p]} {
        incr total $t
        incr passed $p
    }
    if {$code} { lappend failed [file tail $f] }
}

puts "\n[string repeat = 52]"
puts [format "%d tests, %d passed, %d failed" $total $passed [expr {$total - $passed}]]
if {[llength $failed]} {
    puts "failing files: [join $failed {, }]"
    exit 1
}
puts "ok"
exit 0
