#!/usr/bin/env tclsh
# whitepaper.tcl -- tests for the self-demoing white paper build.
# Builds every edition from WhitePaper.xml and verifies that the
# canonical XML round-trips out of each payload channel, that the US
# Letter page frames self-describe their absolute size, and that the
# folk carrier reproduces the HTML byte-exactly. (Go/Rust/C++ carriers
# are verified when their toolchains are on PATH.)

set here [file dirname [file normalize [info script]]]
set root [file dirname $here]
set wp   [file join $root bin whitepaper.tcl]
set xmlSrc [file join $root docs whitepaper WhitePaper.xml]
set build  [file join $root docs whitepaper build]

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
exec [info nameofexecutable] $wp build $xmlSrc
set xml [slurp $xmlSrc]
foreach f {WhitePaper.md WhitePaper.html WhitePaper.pdf WhitePaper.pp.pdf
           WhitePaper.pp.xml WhitePaper.pp.md WhitePaper.pp.html
           WhitePaper.pp.html.folk WhitePaper.pp.html.rust
           WhitePaper.pp.go WhitePaper.pp.cpp} {
    check "$f exists" [file exists [file join $build $f]]
}
set pages [lsort [glob -nocomplain [file join $build WhitePaper.8.5x11.p*.png]]]
check "US Letter pages emitted" [expr {[llength $pages] >= 3}]

puts "== payload round trips =="
foreach f {WhitePaper.pp.pdf WhitePaper.pp.md WhitePaper.pp.html WhitePaper.pp.xml} {
    if {[string match *.pp.xml $f]} {
        check "$f == canonical XML" [expr {[slurp [file join $build $f]] eq $xml}]
    } else {
        # exec strips one trailing newline from captured output
        set got [exec [info nameofexecutable] $wp extract [file join $build $f]]
        check "extract($f) == canonical XML" \
            [expr {$got eq [string trimright $xml \n]}]
    }
}
set got [exec [info nameofexecutable] $wp extract [lindex $pages 0]]
check "extract(page 1 PNG tEXt) == canonical XML" [expr {$got eq [string trimright $xml \n]}]

puts "== page frame self-description =="
set d [::printable::pageframe::decode [lindex $pages 1]]
set meta [dict get $d meta]
check "paper=usletter" [expr {[dict get $meta paper] eq "usletter"}]
check "page/pages present" [expr {[dict exists $meta page] && [dict exists $meta pages]}]
check "absolute size encoded (203.9 267.4 mm + quiet = 8.5x11in)" \
    [expr {[dict get $meta page_mm] eq "203.9 267.4"}]
check "scale self-recovered" [dict exists $meta scale_px_per_mm]
check "frame payload is the XML prefix" \
    [string equal -length 300 [dict get $d source] $xml]

puts "== folk carrier reproduces HTML =="
set tmp [file join $here out-whitepaper]
file delete -force $tmp
file mkdir $tmp
file copy [file join $build WhitePaper.pp.html.folk] $tmp
set savedPwd [pwd]
cd $tmp
exec [info nameofexecutable] WhitePaper.pp.html.folk
cd $savedPwd
check "folk carrier output == WhitePaper.html" \
    [expr {[slurp [file join $tmp WhitePaper.html]] eq [slurp [file join $build WhitePaper.html]]}]

puts "== compiled carriers (when toolchains available) =="
if {[llength [auto_execok go]]} {
    file copy -force [file join $build WhitePaper.pp.go] $tmp
    cd $tmp; exec go run WhitePaper.pp.go; cd $savedPwd
    set same [expr {[exec cmp -s [file join $tmp WhitePaper.pdf] [file join $build WhitePaper.pdf]; concat ok] eq "ok"}]
    check "go carrier output == WhitePaper.pdf" $same
} else { puts "  skip go (not installed)" }
if {[llength [auto_execok g++]]} {
    file copy -force [file join $build WhitePaper.pp.cpp] $tmp
    cd $tmp
    exec g++ -std=c++17 -o wpcpp WhitePaper.pp.cpp
    file delete -force [file join $tmp WhitePaper.pdf]
    exec ./wpcpp
    cd $savedPwd
    set same [expr {[exec cmp -s [file join $tmp WhitePaper.pdf] [file join $build WhitePaper.pdf]; concat ok] eq "ok"}]
    check "c++ carrier output == WhitePaper.pdf" $same
} else { puts "  skip g++ (not installed)" }
if {[llength [auto_execok rustc]]} {
    file copy -force [file join $build WhitePaper.pp.html.rust] [file join $tmp wp.rs]
    cd $tmp
    exec rustc -O --crate-name whitepaper -o wprust wp.rs
    file delete -force [file join $tmp WhitePaper.html]
    exec ./wprust
    cd $savedPwd
    set same [expr {[exec cmp -s [file join $tmp WhitePaper.html] [file join $build WhitePaper.html]; concat ok] eq "ok"}]
    check "rust carrier output == WhitePaper.html" $same
} else { puts "  skip rustc (not installed)" }

puts "----"
puts "pass: $pass  fail: $fail"
exit [expr {$fail > 0}]
