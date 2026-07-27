#!/usr/bin/env tclsh
# xconv.tcl -- convertkit's extension-driven converter.
#
#   tclsh xconv.tcl input.ext output.ext
#
# Supported extensions: .tcl .xml .png .jpg .jpeg
# Every conversion routes through the canonical XML document:
#
#   .tcl <-> .xml <-> .png <-> .jpg/.jpeg
#
# so any pair of the above is bidirectional and byte-exact for the
# embedded Tcl source, regardless of lossy raster codecs in between.

set libdir [file join [file dirname [file dirname [file normalize [info script]]]] lib]
foreach mod {tclxml tclast pngcodec jpgcodec render} {
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
        tcl { return [::convertkit::tclxml::tclToXml [slurpText $path] [file tail $path]] }
        xml { return [slurpText $path] }
        png { return [::convertkit::pngcodec::extract [::convertkit::pngcodec::readFile $path]] }
        jpg { return [::convertkit::jpgcodec::extract [::convertkit::jpgcodec::readFile $path]] }
    }
}

# --- write the canonical XML document out as any format -----------------
proc fromCanonicalXml {xml outPath srcPath} {
    switch -- [kindOf $outPath] {
        xml { spitText $outPath $xml }
        tcl { spitText $outPath [::convertkit::tclxml::xmlToTcl $xml] }
        png {
            set source [::convertkit::tclxml::xmlToTcl $xml]
            if {[kindOf $srcPath] in {png jpg}} {
                # keep the existing raster when converting image -> image
                if {[kindOf $srcPath] eq "jpg"} {
                    ::convertkit::render::jpgToPngRaster $srcPath $outPath
                } else {
                    file copy -force $srcPath $outPath
                }
            } else {
                ::convertkit::render::codePng $source $outPath
            }
            set png [::convertkit::pngcodec::readFile $outPath]
            ::convertkit::pngcodec::writeFile $outPath [::convertkit::pngcodec::embed $png $xml]
        }
        jpg {
            set tmp "$outPath.convertkit-tmp.png"
            if {[kindOf $srcPath] eq "png"} {
                file copy -force $srcPath $tmp
            } elseif {[kindOf $srcPath] eq "jpg"} {
                file copy -force $srcPath $outPath
                set jpg [::convertkit::jpgcodec::readFile $outPath]
                ::convertkit::jpgcodec::writeFile $outPath [::convertkit::jpgcodec::embed $jpg $xml]
                return
            } else {
                set source [::convertkit::tclxml::xmlToTcl $xml]
                ::convertkit::render::codePng $source $tmp
            }
            ::convertkit::render::pngToJpgRaster $tmp $outPath
            file delete -force $tmp
            set jpg [::convertkit::jpgcodec::readFile $outPath]
            ::convertkit::jpgcodec::writeFile $outPath [::convertkit::jpgcodec::embed $jpg $xml]
        }
    }
}

proc main {argv} {
    if {[llength $argv] != 2} {
        puts stderr "usage: xconv.tcl input.(tcl|xml|png|jpg|jpeg) output.(tcl|xml|png|jpg|jpeg)"
        exit 2
    }
    lassign $argv in out
    if {![file exists $in]} { puts stderr "xconv: no such file: $in"; exit 1 }
    set xml [toCanonicalXml $in]
    fromCanonicalXml $xml $out $in
    puts "xconv: $in -> $out ([kindOf $in] -> [kindOf $out])"
}

main $argv
