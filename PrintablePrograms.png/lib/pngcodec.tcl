# pngcodec.tcl -- pure-Tcl PNG chunk surgery for PrintablePrograms.png.
#
# The payload (the canonical XML document) travels in a tEXt chunk with
# keyword "printable", base64-encoded so it stays Latin-1 safe. The
# visible raster is a rendering of the code (done elsewhere, via
# ImageMagick when available); this module only reads/writes chunks, so
# it works on any valid PNG.

namespace eval ::printable::pngcodec {
    variable keyword "printable"
    variable pngsig  "\x89PNG\r\n\x1a\n"

    proc readFile {path} {
        set f [open $path rb]; set data [read $f]; close $f
        return $data
    }
    proc writeFile {path data} {
        set f [open $path wb]; puts -nonewline $f $data; close $f
    }

    proc isPng {data} {
        variable pngsig
        expr {[string range $data 0 7] eq $pngsig}
    }

    proc buildChunk {type payload} {
        set body $type$payload
        set crc [zlib crc32 $body]
        return [binary format Ia*I [string length $payload] $body $crc]
    }

    # Iterate chunks: returns list of {type payload} pairs.
    proc chunks {data} {
        set out {}
        set pos 8
        set len [string length $data]
        while {$pos + 8 <= $len} {
            binary scan [string range $data $pos [expr {$pos+7}]] Ia4 clen type
            set clen [expr {$clen & 0xffffffff}]
            set payload [string range $data [expr {$pos+8}] [expr {$pos+7+$clen}]]
            lappend out [list $type $payload]
            incr pos [expr {12 + $clen}]
            if {$type eq "IEND"} break
        }
        return $out
    }

    # Insert (or replace) the printable tEXt chunk right before IEND.
    proc embed {pngData text} {
        variable keyword
        if {![isPng $pngData]} { error "not a PNG file" }
        set b64 [binary encode base64 [encoding convertto utf-8 $text]]
        set chunk [buildChunk tEXt "$keyword\x00$b64"]
        set out "\x89PNG\r\n\x1a\n"
        foreach pair [chunks $pngData] {
            lassign $pair type payload
            if {$type eq "tEXt" && [string match "$keyword\x00*" $payload]} continue
            if {$type eq "IEND"} { append out $chunk }
            append out [buildChunk $type $payload]
        }
        return $out
    }

    # Pull the printable payload back out of a PNG.
    proc extract {pngData} {
        variable keyword
        if {![isPng $pngData]} { error "not a PNG file" }
        foreach pair [chunks $pngData] {
            lassign $pair type payload
            if {$type eq "tEXt" && [string match "$keyword\x00*" $payload]} {
                set b64 [string range $payload [string length "$keyword\x00"] end]
                return [encoding convertfrom utf-8 [binary decode base64 $b64]]
            }
        }
        error "no printable payload found in PNG"
    }

    # Minimal fallback raster: a solid-color 320x200 RGBA PNG built with
    # nothing but Tcl 8.6's zlib. Used when ImageMagick is unavailable.
    proc blankPng {{w 320} {h 200} {r 24} {g 24} {b 32}} {
        set ihdr [binary format IIccccc $w $h 8 6 0 0 0]
        set raw ""
        set row "\x00"
        for {set x 0} {$x < $w} {incr x} {
            append row [binary format cccc $r $g $b 255]
        }
        for {set y 0} {$y < $h} {incr y} { append raw $row }
        set idat [zlib compress $raw]
        set out "\x89PNG\r\n\x1a\n"
        append out [buildChunk IHDR $ihdr]
        append out [buildChunk IDAT $idat]
        append out [buildChunk IEND ""]
        return $out
    }
}
