#!/usr/bin/env tclsh
# pageframe.tcl -- tests for the print-survivable page frame + AST.
# Includes a simulated screenshot (rescale) and a simulated cheap
# rescan (rescale + JPEG 80 + slight blur) to prove pixel-domain
# recovery, not metadata recovery.

set here   [file dirname [file normalize [info script]]]
set root   [file dirname $here]
set outdir [file join $here out-pageframe]
file delete -force $outdir
file mkdir $outdir

foreach mod {tclxml tclast pngcodec jpgcodec typeset pageframe} {
    source [file join $root lib $mod.tcl]
}

set pass 0
set fail 0
proc check {label ok} {
    global pass fail
    if {$ok} { incr pass; puts "  ok   $label" } else { incr fail; puts "  FAIL $label" }
}

# --- AST ---------------------------------------------------------------
puts "== tclast =="
set src [read [set f [open [file join $root samples hello.tcl] r]]]; close $f
set ast [::printable::tclast::parseScript $src]
check "parses sample into nodes" [expr {[llength $ast] > 3}]
set regen [::printable::tclast::astToTcl $ast]
# semantic equivalence: regenerated program runs and prints the same output
set i1 [exec [info nameofexecutable] [file join $root samples hello.tcl]]
set rf [file join $outdir regen.tcl]
set f [open $rf w]; puts -nonewline $f $regen; close $f
set i2 [exec [info nameofexecutable] $rf]
check "regenerated AST program produces identical output" [expr {$i1 eq $i2}]
set xml [::printable::tclxml::tclToXml $src hello.tcl]
check "canonical XML now carries <ast>" [string match "*<ast>*<cmd>*" $xml]

# --- data frame: encode ---------------------------------------------------
puts "== dataframe encode =="
set frame [file join $outdir frame.png]
set res [::printable::dataframe::encode \
    -source $src -out $frame \
    -pagewmm 140 -pagehmm 100 -cellmm 2.0 -bandmm 26 -quietmm 6 -dpi 120 \
    -host testhost -ip 10.0.0.42 -id 7 -file 20260727-000000-000Z.folk.png]
check "encoder reports >=1 packet copy" [expr {[dict get $res copies] >= 1}]
check "full program fit in band" [dict get $res complete]

# a tiny program should be repeated many times across the band
set tinyframe [file join $outdir tiny.png]
set tres [::printable::dataframe::encode -source "puts hi\n" -out $tinyframe \
    -pagewmm 140 -pagehmm 100 -cellmm 2.0 -bandmm 26 -quietmm 6 -dpi 120 \
    -host testhost -ip 10.0.0.42 -id 9]
check "tiny program gets >=2 redundant copies" [expr {[dict get $tres copies] >= 2}]

# --- decode: pristine PNG (pixels only; no metadata chunk present) --------
puts "== decode pristine =="
set d [::printable::dataframe::decode $frame]
check "source recovered byte-exact from pixels" [expr {[dict get $d source] eq $src}]
check "hostname recovered" [expr {[dict get $d meta host] eq "testhost"}]
check "ip recovered" [expr {[dict get $d meta ip] eq "10.0.0.42"}]
check "filename recovered" [expr {[dict get $d meta file] eq "20260727-000000-000Z.folk.png"}]
check "origin url derived" [string match "http://10.0.0.42/folk-data/program/*" [dict get $d meta origin]]
check "self-encoded scale present" [dict exists [dict get $d meta] scale_px_per_mm]

# --- decode: simulated screenshot (non-integer rescale) --------------------
puts "== decode screenshot (137% rescale) =="
set shot [file join $outdir screenshot.png]
exec convert $frame -resize 137% $shot
set d [::printable::dataframe::decode $shot]
check "survives rescale" [expr {[dict get $d source] eq $src}]

puts "== decode screenshot (63% downscale) =="
set shot2 [file join $outdir screenshot-small.png]
exec convert $frame -resize 63% $shot2
set d [::printable::dataframe::decode $shot2]
check "survives downscale" [expr {[dict get $d source] eq $src}]

# --- decode: simulated print+rescan (rescale + blur + JPEG 80) -------------
puts "== decode simulated rescan =="
set scan [file join $outdir rescan.jpg]
exec convert $frame -resize 119% -blur 0x0.8 -quality 80 $scan
set d [::printable::dataframe::decode $scan]
check "survives blur + JPEG 80" [expr {[dict get $d source] eq $src}]

# --- prefix mode: program too big for the band -----------------------------
puts "== oversize program -> prefix + origin pointer =="
set big ""
for {set i 0} {$i < 400} {incr i} { append big "puts \"line $i of a very long program\"\n" }
set bframe [file join $outdir bigframe.png]
set res [::printable::dataframe::encode -source $big -out $bframe \
    -pagewmm 140 -pagehmm 100 -cellmm 2.0 -bandmm 26 -quietmm 6 -dpi 120 \
    -host testhost -ip 10.0.0.42 -id 8]
check "encoder flags incomplete" [expr {![dict get $res complete]}]
set d [::printable::dataframe::decode $bframe]
check "prefix recovered matches program start" [string equal -length 200 [dict get $d source] $big]
check "complete=0 in metadata" [expr {[dict get $d meta complete] == 0}]

# --- minimal mode: geometry auto-sized, full round trip --------------------
puts "== minimal mode (auto geometry) =="
set mframe [file join $outdir minimal.png]
set res [::printable::dataframe::encode -source $src -out $mframe \
    -cellmm 2.0 -quietmm 6 -dpi 120 \
    -host testhost -ip 10.0.0.42 -id 10]
check "minimal frame fits full program" [dict get $res complete]
set d [::printable::dataframe::decode $mframe]
check "minimal frame decodes byte-exact" [expr {[dict get $d source] eq $src}]
# minimal really is smaller than the old fixed default for this program
scan [dict get $res grid] "%dx%d cells, band %d" mw mh mt
check "auto band is thinner than a 6cm band" [expr {$mt < 30}]

# minimal mode still handles oversize programs via the band-depth fallback
set mbig [file join $outdir minimal-big.png]
set res [::printable::dataframe::encode -source $big -out $mbig \
    -cellmm 2.0 -quietmm 6 -dpi 120 -maxbandmm 26 \
    -host testhost -ip 10.0.0.42 -id 11]
set d [::printable::dataframe::decode $mbig]
check "minimal+capped oversize decodes its prefix" \
    [string equal -length 100 [dict get $d source] $big]

puts "----"
puts "pass: $pass  fail: $fail"
exit [expr {$fail > 0}]
