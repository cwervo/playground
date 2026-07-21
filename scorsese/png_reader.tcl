# png_reader.tcl -- minimal pure-Tcl PNG decoder (no Tk, no external libs).
# Handles the case we need: 8/16-bit, colour type 2 (RGB) or 6 (RGBA),
# non-interlaced.  Uses Tcl 8.6's built-in [zlib inflate] for the IDAT
# stream and reconstructs the filtered scanlines by hand.
#
# It exposes one command:
#     png::read_gray <path> ?maxRows?
# which returns a dict:
#     width  <int>   height <int>   rows <int actually decoded>
#     gray   <list of binary byte strings, one 8-bit grey scanline per row>
# Only the luma channel is kept (that is all the glyph-extraction needs) and
# decoding can be stopped early with maxRows so we never pay for the parts of
# the screenshot below the message we care about.

namespace eval png {}

proc png::_u32 {bytes off} {
    binary scan [string range $bytes $off [expr {$off+3}]] Iu v
    return $v
}

proc png::read_gray {path {maxRows 0}} {
    set fh [open $path rb]
    set data [read $fh]
    close $fh

    if {[string range $data 0 7] ne "\x89PNG\r\n\x1a\n"} {
        error "not a PNG file: $path"
    }

    set pos 8
    set idat ""
    set width 0; set height 0; set depth 0; set colour 0; set interlace 0
    set len [string length $data]
    while {$pos < $len} {
        set clen [png::_u32 $data $pos]
        set ctype [string range $data [expr {$pos+4}] [expr {$pos+7}]]
        set cstart [expr {$pos+8}]
        set cdata [string range $data $cstart [expr {$cstart+$clen-1}]]
        switch -- $ctype {
            IHDR {
                set width  [png::_u32 $cdata 0]
                set height [png::_u32 $cdata 4]
                binary scan [string range $cdata 8 12] cucucucucu depth colour comp filt interlace
            }
            IDAT { append idat $cdata }
            IEND { break }
        }
        set pos [expr {$cstart + $clen + 4}]   ;# skip data + CRC
    }

    if {$interlace != 0} { error "interlaced PNG unsupported" }
    switch -- $colour {
        2 { set channels 3 }
        6 { set channels 4 }
        0 { set channels 1 }
        default { error "unsupported colour type $colour" }
    }
    set sampleBytes [expr {$depth == 16 ? 2 : 1}]
    set bpp    [expr {$channels * $sampleBytes}]          ;# bytes per pixel
    set stride [expr {$width * $bpp}]                     ;# bytes per scanline

    set raw [zlib decompress $idat]

    # How many rows do we actually reconstruct?
    set rows $height
    if {$maxRows > 0 && $maxRows < $height} { set rows $maxRows }

    set gray {}
    set prev [binary format x$stride]        ;# "row above" for the first line
    set rp 0
    for {set y 0} {$y < $rows} {incr y} {
        set ftype [scan [string index $raw $rp] %c]
        incr rp
        set line [string range $raw $rp [expr {$rp+$stride-1}]]
        incr rp $stride

        # Reconstruct this scanline (recon list of ints), defiltering per byte.
        binary scan $line cu* cur
        binary scan $prev cu* up
        set rec {}
        for {set i 0} {$i < $stride} {incr i} {
            set x [lindex $cur $i]
            set b [lindex $up $i]
            set a [expr {$i >= $bpp ? [lindex $rec [expr {$i-$bpp}]] : 0}]
            set c [expr {$i >= $bpp ? [lindex $up  [expr {$i-$bpp}]] : 0}]
            switch -- $ftype {
                0 { set r $x }
                1 { set r [expr {($x + $a) & 255}] }
                2 { set r [expr {($x + $b) & 255}] }
                3 { set r [expr {($x + (($a + $b) >> 1)) & 255}] }
                4 {
                    set p  [expr {$a + $b - $c}]
                    set pa [expr {abs($p - $a)}]
                    set pb [expr {abs($p - $b)}]
                    set pc [expr {abs($p - $c)}]
                    if {$pa <= $pb && $pa <= $pc} { set pr $a } \
                    elseif {$pb <= $pc}           { set pr $b } \
                    else                          { set pr $c }
                    set r [expr {($x + $pr) & 255}]
                }
                default { error "bad filter type $ftype" }
            }
            lset cur $i $r          ;# keep as the reconstructed buffer too
            lappend rec $r
        }
        set prev [binary format cu* $rec]

        # Collapse to one 8-bit luma byte per pixel (high byte if 16-bit).
        set gline {}
        set step [expr {$sampleBytes == 2 ? 6 : $bpp}]     ;# stride to next pixel top byte
        if {$channels == 1} {
            for {set i 0} {$i < $stride} {incr i $sampleBytes} {
                lappend gline [lindex $rec $i]
            }
        } else {
            for {set i 0} {$i < $stride} {incr i $bpp} {
                set R [lindex $rec $i]
                set G [lindex $rec [expr {$i + $sampleBytes}]]
                set B [lindex $rec [expr {$i + 2*$sampleBytes}]]
                lappend gline [expr {(($R*77 + $G*151 + $B*28) >> 8)}]
            }
        }
        lappend gray [binary format cu* $gline]
    }

    return [dict create width $width height $height rows $rows gray $gray]
}
