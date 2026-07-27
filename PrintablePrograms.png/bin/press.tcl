#!/usr/bin/env tclsh
# press.tcl -- the PrintablePrograms format press.
#
#   tclsh press.tcl input.ext output.ext
#
# Supported extensions: .tcl .xml .png .jpg .jpeg
# Every conversion routes through the canonical XML document:
#
#   .tcl <-> .xml <-> .png <-> .jpg/.jpeg
#
# so any pair of the above is bidirectional and byte-exact for the
# embedded Tcl source, regardless of lossy raster codecs in between.

set libdir [file join [file dirname [file dirname [file normalize [info script]]]] lib]
foreach mod {tclxml tclast pngcodec jpgcodec typeset} {
    source [file join $libdir $mod.tcl]
}

proc slurpText {path} {
    set f [open $path r]; fconfigure $f -encoding utf-8
    set d [read $f]; close $f; return $d
}
proc spitText {path data} {
    set f [open $path w]; fconfigure $f -encoding utf-8
    puts -nonewline $f $data; close $f
}

proc kindOf {path} {
    switch -- [string tolower [file extension $path]] {
        .tcl          { return tcl }
        .xml          { return xml }
        .png          { return png }
        .jpg - .jpeg  { return jpg }
        default { error "unsupported extension on '$path' (want .tcl/.xml/.png/.jpg/.jpeg)" }
    }
}

# --- read any input into the canonical XML document ---------------------
proc toCanonicalXml {path} {
    switch -- [kindOf $path] {
        tcl { return [::printable::tclxml::tclToXml [slurpText $path] [file tail $path]] }
        xml { return [slurpText $path] }
        png { return [::printable::pngcodec::extract [::printable::pngcodec::readFile $path]] }
        jpg { return [::printable::jpgcodec::extract [::printable::jpgcodec::readFile $path]] }
    }
}

# --- write the canonical XML document out as any format -----------------
proc fromCanonicalXml {xml outPath srcPath} {
    switch -- [kindOf $outPath] {
        xml { spitText $outPath $xml }
        tcl { spitText $outPath [::printable::tclxml::xmlToTcl $xml] }
        png {
            set source [::printable::tclxml::xmlToTcl $xml]
            if {[kindOf $srcPath] in {png jpg}} {
                # keep the existing raster when converting image -> image
                if {[kindOf $srcPath] eq "jpg"} {
                    ::printable::typeset::jpgToPngRaster $srcPath $outPath
                } else {
                    file copy -force $srcPath $outPath
                }
            } else {
                ::printable::typeset::codePng $source $outPath
            }
            set png [::printable::pngcodec::readFile $outPath]
            ::printable::pngcodec::writeFile $outPath [::printable::pngcodec::embed $png $xml]
        }
        jpg {
            set tmp "$outPath.printable-tmp.png"
            if {[kindOf $srcPath] eq "png"} {
                file copy -force $srcPath $tmp
            } elseif {[kindOf $srcPath] eq "jpg"} {
                file copy -force $srcPath $outPath
                set jpg [::printable::jpgcodec::readFile $outPath]
                ::printable::jpgcodec::writeFile $outPath [::printable::jpgcodec::embed $jpg $xml]
                return
            } else {
                set source [::printable::tclxml::xmlToTcl $xml]
                ::printable::typeset::codePng $source $tmp
            }
            ::printable::typeset::pngToJpgRaster $tmp $outPath
            file delete -force $tmp
            set jpg [::printable::jpgcodec::readFile $outPath]
            ::printable::jpgcodec::writeFile $outPath [::printable::jpgcodec::embed $jpg $xml]
        }
    }
}

proc main {argv} {
    if {[llength $argv] != 2} {
        puts stderr "usage: press.tcl input.(tcl|xml|png|jpg|jpeg) output.(tcl|xml|png|jpg|jpeg)"
        exit 2
    }
    lassign $argv in out
    if {![file exists $in]} { puts stderr "press: no such file: $in"; exit 1 }
    set xml [toCanonicalXml $in]
    fromCanonicalXml $xml $out $in
    puts "press: $in -> $out ([kindOf $in] -> [kindOf $out])"
}

main $argv
