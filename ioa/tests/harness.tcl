# tests/harness.tcl -- load the runtime for a test file.
package require tcltest
namespace import -force ::tcltest::*

set ::IOA_ROOT [file dirname [file dirname [file normalize [info script]]]]
foreach f {core transport frame codec budget products device fabric plan sim deploy session} {
    source [file join $::IOA_ROOT lib $f.tcl]
}
foreach f {rf optical wired virtual} {
    source [file join $::IOA_ROOT lib transports $f.tcl]
}

proc fixture {name} { file join $::IOA_ROOT tests fixtures $name }
proc studio {} { ioa::fabric::load [file join $::IOA_ROOT fabric studio.ioa] }

proc finish {} {
    ::tcltest::cleanupTests
    exit [expr {$::tcltest::numTests(Failed) > 0}]
}

proc struct_intersect {a b} {
    set out {}
    foreach x $a { if {$x in $b} { lappend out $x } }
    return $out
}
