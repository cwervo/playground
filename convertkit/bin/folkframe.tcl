#!/usr/bin/env tclsh
# folkframe.tcl -- print-survivable data-frame encoder/decoder CLI.
#
#   encode: tclsh folkframe.tcl encode program.tcl out.png ?options?
#     -pagewmm N -pagehmm N   physical page size (default 210x148, A5 landscape)
#     -bandmm N               data band width (default 60 = the ~6cm border)
#     -cellmm N               data cell size (default 2)
#     -quietmm N              white quiet margin (default 8)
#     -dpi N                  render resolution (default 150)
#     -host S -ip S -id N -file S    identity overrides (auto-detected)
#     -notext                 skip the human-readable code rendering
#
#   decode: tclsh folkframe.tcl decode image.(png|jpg|...)
#     prints recovered metadata (incl. self-encoded physical scale) and
#     writes the recovered source next to the image as <image>.recovered.tcl

set libdir [file join [file dirname [file dirname [file normalize [info script]]]] lib]
foreach mod {tclxml tclast pngcodec jpgcodec render dataframe} {
    source [file join $libdir $mod.tcl]
}

proc usage {} {
    puts stderr "usage: folkframe.tcl encode program.tcl out.png ?-option value ...?"
    puts stderr "       folkframe.tcl decode image"
    exit 2
}

if {[llength $argv] < 2} usage
set mode [lindex $argv 0]

switch -- $mode {
    encode {
        if {[llength $argv] < 3} usage
        lassign $argv - src out
        set opts [lrange $argv 3 end]
        set f [open $src r]; fconfigure $f -encoding utf-8
        set source [read $f]; close $f

        set notext [expr {"-notext" in $opts}]
        set opts [lsearch -all -inline -not -exact $opts -notext]

        set textpng ""
        if {!$notext} {
            set textpng $out.text-tmp.png
            if {![::convertkit::render::codePng $source $textpng]} { set textpng "" }
        }
        set res [::convertkit::dataframe::encode -source $source -out $out \
                     -textpng $textpng {*}$opts]
        if {$textpng ne ""} { file delete -force $textpng }

        # also stow the full canonical XML in a tEXt chunk: the digital
        # copy stays lossless even when the band only fits a prefix
        set xml [::convertkit::tclxml::tclToXml $source [file tail $src]]
        set png [::convertkit::pngcodec::readFile $out]
        ::convertkit::pngcodec::writeFile $out [::convertkit::pngcodec::embed $png $xml]

        dict for {k v} $res { puts [format "  %-10s %s" $k $v] }
        puts "folkframe: $src -> $out"
    }
    decode {
        set img [lindex $argv 1]
        set res [::convertkit::dataframe::decode $img]
        puts "== metadata =="
        dict for {k v} [dict get $res meta] { puts [format "  %-16s %s" $k $v] }
        puts "  grid             [dict get $res grid]"
        set outSrc $img.recovered.tcl
        set f [open $outSrc w]; fconfigure $f -encoding utf-8
        puts -nonewline $f [dict get $res source]; close $f
        puts "== source recovered from pixels -> $outSrc =="
        if {[dict exists $res meta complete] && ![dict get $res meta complete]} {
            puts "  (prefix only; full program at [dict get $res meta origin])"
        }
    }
    default usage
}
