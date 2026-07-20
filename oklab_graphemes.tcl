#!/usr/bin/env tclsh
#
# oklab_graphemes.tcl
# =============================================================================
# Color-separate a PNG or JPG into N "bins" that are equally spaced along the
# OKLAB lightness (L) axis, then search each bin ("channel") for graphemes:
# connected marks whose *orientation* and shape are measured -- the two things
# the source notes claim every grapheme encodes ("orientation" and "meaning").
#
# Self-contained: pure Tcl 8.6+.  Uses only the built-in `zlib` command.
# No Tk, no Img, no ImageMagick, no external processes.  Runs anywhere tclsh
# 8.6 runs.
#
#   Reads : PNG (8-bit, colour types 0/2/3/4/6, non-interlaced)
#           JPEG (baseline / SOF0, greyscale or YCbCr, any 4:x:x subsampling)
#           JPEG is decoded as its DC image (one pixel per 8x8 block, 1/8 scale)
#           which is both fast in pure Tcl and a natural working resolution.
#   Writes: <out>/bin_<k>.png            pixels whose L falls in bin k (RGBA)
#           <out>/bin_<k>_graphemes.png  the bin with detected graphemes drawn
#           <out>/bins_preview.png       whole image false-coloured by bin
#           <out>/graphemes.tsv          every grapheme, its features + glyph
#           <out>/summary.txt            human-readable run report
#
# Usage:
#   tclsh oklab_graphemes.tcl <input.png|input.jpg> [outdir] [options]
#
#   -bins    N     number of L bins            (default 6)
#   -maxdim  N     downscale so max(w,h) <= N  (default 640; 0 = no downscale)
#   -minarea N     ignore graphemes smaller than N px (default auto ~ 0.02%%)
#   -conn    4|8   connectivity for components (default 8)
#   -lrange  lo hi force absolute L window instead of the image's own L range
#
# Reproducible: output is a deterministic function of the input bytes + flags.
# =============================================================================

# -----------------------------------------------------------------------------
# small helpers
# -----------------------------------------------------------------------------
proc clamp {v lo hi} { expr {$v < $lo ? $lo : ($v > $hi ? $hi : $v)} }
proc iceil {a b}     { expr {($a + $b - 1) / $b} }
proc die {msg}       { puts stderr "error: $msg"; exit 1 }

# read whole file as a binary string
proc slurp {path} {
    set f [open $path rb]
    set d [read $f]
    close $f
    return $d
}

# =============================================================================
# PNG DECODER  (pure Tcl, built-in zlib)
# returns: dict  w h  pix   (pix = binary RGB string, 3 bytes/pixel)
# =============================================================================
proc decode_png {data} {
    if {[string range $data 0 7] ne [binary format H* 89504e470d0a1a0a]} {
        die "not a PNG"
    }
    set pos 8
    set n [string length $data]
    set idat ""
    set w 0; set h 0; set depth 0; set ctype 0; set interlace 0
    set plte ""; set trns ""
    while {$pos < $n} {
        binary scan $data @${pos}Iu len
        set type [string range $data [expr {$pos+4}] [expr {$pos+7}]]
        set body [string range $data [expr {$pos+8}] [expr {$pos+8+$len-1}]]
        switch -- $type {
            IHDR {
                binary scan $body IuIucucucucucu w h depth ctype comp filt interlace
            }
            PLTE { set plte $body }
            tRNS { set trns $body }
            IDAT { append idat $body }
            IEND { break }
        }
        set pos [expr {$pos + 12 + $len}]
    }
    if {$depth != 8} { die "PNG bit depth $depth unsupported (need 8)" }
    if {$interlace != 0} { die "interlaced PNG unsupported" }

    # channels per pixel for each colour type
    array set chans {0 1 2 3 3 1 4 2 6 4}
    if {![info exists chans($ctype)]} { die "PNG colour type $ctype unsupported" }
    set cpp $chans($ctype)                 ;# channels (bytes) per pixel in raw
    set stride [expr {$w * $cpp}]

    set raw [zlib decompress $idat]

    # ---- unfilter scanlines ----
    # bpp = bytes per pixel used for the a/c predictors (>=1)
    set bpp $cpp
    set out [string repeat "\x00" [expr {$stride * $h}]]
    set prev [string repeat "\x00" $stride]
    set rp 0
    for {set y 0} {$y < $h} {incr y} {
        set ft [scan [string index $raw $rp] %c]
        incr rp
        set line [string range $raw $rp [expr {$rp + $stride - 1}]]
        incr rp $stride
        binary scan $line cu* cur
        binary scan $prev cu* prv
        for {set i 0} {$i < $stride} {incr i} {
            set x [lindex $cur $i]
            set a [expr {$i >= $bpp ? [lindex $cur [expr {$i-$bpp}]] : 0}]
            set b [lindex $prv $i]
            set c [expr {$i >= $bpp ? [lindex $prv [expr {$i-$bpp}]] : 0}]
            switch -- $ft {
                0 { set v $x }
                1 { set v [expr {($x + $a) & 255}] }
                2 { set v [expr {($x + $b) & 255}] }
                3 { set v [expr {($x + (($a + $b) >> 1)) & 255}] }
                4 {
                    set p  [expr {$a + $b - $c}]
                    set pa [expr {abs($p - $a)}]
                    set pb [expr {abs($p - $b)}]
                    set pc [expr {abs($p - $c)}]
                    if {$pa <= $pb && $pa <= $pc} { set pr $a } \
                    elseif {$pb <= $pc}          { set pr $b } \
                    else                         { set pr $c }
                    set v [expr {($x + $pr) & 255}]
                }
                default { die "bad PNG filter $ft" }
            }
            lset cur $i $v
        }
        set prev [binary format cu* $cur]
        set start [expr {$y * $stride}]
        set out [string replace $out $start [expr {$start + $stride - 1}] $prev]
    }

    # ---- expand to RGB ----
    set pix [expand_to_rgb $out $w $h $ctype $plte]
    return [dict create w $w h $h pix $pix]
}

# convert an unfiltered raw buffer (given colour type) into a packed RGB string
proc expand_to_rgb {raw w h ctype plte} {
    set npx [expr {$w * $h}]
    binary scan $raw cu* B
    set rgb {}
    switch -- $ctype {
        2 { return $raw }
        6 { # RGBA -> drop alpha
            for {set i 0} {$i < $npx} {incr i} {
                set o [expr {$i*4}]
                lappend rgb [lindex $B $o] [lindex $B [expr {$o+1}]] [lindex $B [expr {$o+2}]]
            }
        }
        0 { # grey
            foreach g $B { lappend rgb $g $g $g }
        }
        4 { # grey+alpha
            for {set i 0} {$i < $npx} {incr i} {
                set g [lindex $B [expr {$i*2}]]
                lappend rgb $g $g $g
            }
        }
        3 { # palette index -> PLTE rgb triplet
            binary scan $plte cu* P
            foreach idx $B {
                set o [expr {$idx*3}]
                lappend rgb [lindex $P $o] [lindex $P [expr {$o+1}]] [lindex $P [expr {$o+2}]]
            }
        }
    }
    return [binary format cu* $rgb]
}

# =============================================================================
# JPEG DECODER  (baseline / SOF0)  ->  DC image (1/8 resolution)
# returns: dict  w h  pix   (pix = binary RGB string of the DC image)
#
# We Huffman-decode every coefficient (needed to walk the bitstream) but keep
# only the DC term of each 8x8 block.  The inverse DCT of a DC-only block is a
# flat patch = DC/8 + 128, so the DC image is an exact 8x8 box-downsample of a
# full decode -- fast, and a fine working resolution for binning + graphemes.
# =============================================================================

# fast bit reader over a segment (list of byte ints), MSB first, with a buffer
proc j_init_seg {seg} {
    set ::J(seg)  $seg
    set ::J(sp)   0
    set ::J(slen) [llength $seg]
    set ::J(bb)   0
    set ::J(bn)   0
}
proc j_fill {} {
    while {$::J(bn) <= 24} {
        if {$::J(sp) < $::J(slen)} {
            set byte [lindex $::J(seg) $::J(sp)]
            incr ::J(sp)
        } else { set byte 0 }
        set ::J(bb) [expr {(($::J(bb) << 8) | $byte) & 0xFFFFFFFF}]
        incr ::J(bn) 8
    }
}
proc j_receive {n} {
    if {$n == 0} { return 0 }
    if {$::J(bn) < $n} { j_fill }
    set v [expr {($::J(bb) >> ($::J(bn) - $n)) & ((1 << $n) - 1)}]
    incr ::J(bn) -$n
    return $v
}
# DECODE using a 16-bit lookahead table: lut entry = (symbol<<5)|codelength
proc j_decode {lutName} {
    upvar #0 $lutName lut
    if {$::J(bn) < 16} { j_fill }
    set idx [expr {($::J(bb) >> ($::J(bn) - 16)) & 0xFFFF}]
    set v   [lindex $lut $idx]
    incr ::J(bn) -[expr {$v & 31}]
    return [expr {$v >> 5}]
}
proc j_extend {v t} {
    if {$t == 0} { return 0 }
    if {$v < (1 << ($t - 1))} { return [expr {$v + (-1 << $t) + 1}] }
    return $v
}

# build a 65536-entry lookahead LUT from JPEG DHT counts+symbols
proc j_build_lut {counts symbols} {
    set lut [lrepeat 65536 0]
    set k 0
    set code 0
    for {set len 1} {$len <= 16} {incr len} {
        set c [lindex $counts [expr {$len-1}]]
        for {set i 0} {$i < $c} {incr i} {
            set sym [lindex $symbols $k]
            set entry [expr {($sym << 5) | $len}]
            set shift [expr {16 - $len}]
            set base  [expr {$code << $shift}]
            set span  [expr {1 << $shift}]
            for {set j 0} {$j < $span} {incr j} {
                lset lut [expr {$base + $j}] $entry
            }
            incr code
            incr k
        }
        set code [expr {$code << 1}]
    }
    return $lut
}

proc decode_jpeg {data} {
    set n [string length $data]
    if {[string range $data 0 1] ne [binary format H* ffd8]} { die "not a JPEG" }

    array set qt {}          ;# quant tables: id -> list of 64 (zigzag order)
    array set comp {}        ;# SOF components, index -> {id H V Tq}
    set ncomp 0
    set W 0; set H 0
    set restart 0
    # per-table Huffman LUT variable names live in globals ::LUTDC(id)/::LUTAC(id)

    set pos 2
    set sosData {}
    while {$pos < $n} {
        if {[scan [string index $data $pos] %c] != 255} { incr pos; continue }
        set m [scan [string index $data [expr {$pos+1}]] %c]
        set pos [expr {$pos+2}]
        # standalone markers (no length)
        if {$m == 0xD9} { break }                        ;# EOI
        if {($m >= 0xD0 && $m <= 0xD7) || $m == 0x01} { continue }
        binary scan $data @${pos}Su len
        set seg [string range $data [expr {$pos+2}] [expr {$pos+$len-1}]]
        set segEnd [expr {$pos + $len}]
        switch -- [format %02X $m] {
            DB {  ;# DQT (may hold several tables)
                binary scan $seg cu* q
                set i 0
                while {$i < [llength $q]} {
                    set pqtq [lindex $q $i]; incr i
                    set prec [expr {$pqtq >> 4}]
                    set tid  [expr {$pqtq & 15}]
                    set tbl {}
                    for {set j 0} {$j < 64} {incr j} {
                        if {$prec == 0} {
                            lappend tbl [lindex $q $i]; incr i
                        } else {
                            lappend tbl [expr {([lindex $q $i]<<8)|[lindex $q [expr {$i+1}]]}]
                            incr i 2
                        }
                    }
                    set qt($tid) $tbl
                }
            }
            C0 - C1 {  ;# baseline / extended sequential SOF
                binary scan $seg cuSuSucu prec H W nf
                for {set i 0} {$i < $nf} {incr i} {
                    set o [expr {6 + $i*3}]
                    binary scan $seg @${o}cucucu cid hv tq
                    set comp($i) [list $cid [expr {$hv>>4}] [expr {$hv&15}] $tq]
                }
                set ncomp $nf
            }
            C2 { die "progressive JPEG (SOF2) unsupported; baseline only" }
            C4 {  ;# DHT (may hold several tables)
                binary scan $seg cu* d
                set i 0
                while {$i < [llength $d]} {
                    set tcth [lindex $d $i]; incr i
                    set tc [expr {$tcth >> 4}]  ;# 0=DC 1=AC
                    set th [expr {$tcth & 15}]
                    set counts {}
                    set total 0
                    for {set j 0} {$j < 16} {incr j} {
                        set c [lindex $d $i]; incr i
                        lappend counts $c
                        incr total $c
                    }
                    set syms [lrange $d $i [expr {$i+$total-1}]]
                    incr i $total
                    set lut [j_build_lut $counts $syms]
                    if {$tc == 0} { set ::LUTDC($th) $lut } else { set ::LUTAC($th) $lut }
                }
            }
            DD { binary scan $seg Su restart }              ;# DRI
            DA {  ;# SOS -- read scan header, then entropy data follows
                binary scan $seg cu* s
                set ns [lindex $s 0]
                set scan {}          ;# per scan comp: {compIndex Td Ta}
                for {set i 0} {$i < $ns} {incr i} {
                    set cs [lindex $s [expr {1 + $i*2}]]
                    set td [expr {[lindex $s [expr {2 + $i*2}]] >> 4}]
                    set ta [expr {[lindex $s [expr {2 + $i*2}]] & 15}]
                    # map component selector id -> SOF index
                    set ci -1
                    for {set c 0} {$c < $ncomp} {incr c} {
                        if {[lindex $comp($c) 0] == $cs} { set ci $c; break }
                    }
                    lappend scan [list $ci $td $ta]
                }
                set entropyStart $segEnd
                set sosData [list $ns $scan $entropyStart]
                break
            }
        }
        set pos $segEnd
    }
    if {$sosData eq {}} { die "no SOS found" }
    lassign $sosData ns scan entropyStart

    # ---- split entropy-coded data into segments on restart markers ----
    binary scan [string range $data $entropyStart end] cu* tail
    set tn [llength $tail]
    set segs {}
    set cur {}
    set i 0
    while {$i < $tn} {
        set b [lindex $tail $i]
        if {$b == 0xFF} {
            set b2 [lindex $tail [expr {$i+1}]]
            if {$b2 == 0x00} { lappend cur 255; incr i 2; continue }
            if {$b2 >= 0xD0 && $b2 <= 0xD7} { lappend segs $cur; set cur {}; incr i 2; continue }
            # any other marker (incl. EOI 0xD9) ends the entropy data
            break
        }
        lappend cur $b
        incr i
    }
    lappend segs $cur

    # ---- geometry ----
    set Hmax 1; set Vmax 1
    for {set c 0} {$c < $ncomp} {incr c} {
        lassign $comp($c) cid hh vv tq
        if {$hh > $Hmax} { set Hmax $hh }
        if {$vv > $Vmax} { set Vmax $vv }
    }
    if {$ns == 1} {
        # non-interleaved single-component scan: MCU == one block
        set only [lindex [lindex $scan 0] 0]
        set Hmax 1; set Vmax 1
        for {set c 0} {$c < $ncomp} {incr c} { set comp($c) [lreplace $comp($c) 1 2 1 1] }
        set mcusX [iceil $W 8]
        set mcusY [iceil $H 8]
    } else {
        set mcusX [iceil $W [expr {8*$Hmax}]]
        set mcusY [iceil $H [expr {8*$Vmax}]]
    }

    # DC image storage per component
    array set dcimg {}; array set bw {}; array set bh {}; array set pred {}
    for {set c 0} {$c < $ncomp} {incr c} {
        lassign $comp($c) cid hh vv tq
        set bw($c) [expr {$mcusX*$hh}]
        set bh($c) [expr {$mcusY*$vv}]
        set dcimg($c) [lrepeat [expr {$bw($c)*$bh($c)}] 0]
        set pred($c) 0
    }

    # scan-order -> component info (index, dcLUT name, acLUT name)
    set order {}
    foreach sc $scan {
        lassign $sc ci td ta
        lappend order [list $ci $td $ta]
    }

    # ---- decode MCUs ----
    set segIdx 0
    j_init_seg [lindex $segs 0]
    set mcuCount 0
    for {set my 0} {$my < $mcusY} {incr my} {
        for {set mx 0} {$mx < $mcusX} {incr mx} {
            if {$restart > 0 && $mcuCount > 0 && $mcuCount % $restart == 0} {
                incr segIdx
                if {$segIdx < [llength $segs]} { j_init_seg [lindex $segs $segIdx] }
                for {set c 0} {$c < $ncomp} {incr c} { set pred($c) 0 }
            }
            foreach oc $order {
                lassign $oc ci td ta
                lassign $comp($ci) cid hh vv tq
                set dcName ::LUTDC($td)
                set acName ::LUTAC($ta)
                for {set by 0} {$by < $vv} {incr by} {
                    for {set bx 0} {$bx < $hh} {incr bx} {
                        # DC
                        set t [j_decode $dcName]
                        set diff [j_extend [j_receive $t] $t]
                        set pred($ci) [expr {$pred($ci) + $diff}]
                        # AC (decode to advance the bitstream; values discarded)
                        set k 1
                        while {$k < 64} {
                            set rs [j_decode $acName]
                            set r [expr {$rs >> 4}]
                            set sz [expr {$rs & 15}]
                            if {$sz == 0} {
                                if {$r == 15} { incr k 16; continue } else break
                            }
                            incr k $r
                            j_receive $sz
                            incr k
                        }
                        set col [expr {$mx*$hh + $bx}]
                        set row [expr {$my*$vv + $by}]
                        lset dcimg($ci) [expr {$row*$bw($ci) + $col}] $pred($ci)
                    }
                }
            }
            incr mcuCount
        }
    }

    # ---- reconstruct DC image as RGB ----
    set outW [iceil $W 8]
    set outH [iceil $H 8]
    set rgb {}
    set gray [expr {$ncomp == 1}]
    for {set by 0} {$by < $outH} {incr by} {
        for {set bx 0} {$bx < $outW} {incr bx} {
            set vals {}
            for {set c 0} {$c < $ncomp} {incr c} {
                lassign $comp($c) cid hh vv tq
                set cx [clamp [expr {$bx*$hh/$Hmax}] 0 [expr {$bw($c)-1}]]
                set cy [clamp [expr {$by*$vv/$Vmax}] 0 [expr {$bh($c)-1}]]
                set raw [lindex $dcimg($c) [expr {$cy*$bw($c)+$cx}]]
                set q0  [lindex $qt($tq) 0]
                set v [expr {int(round(double($raw*$q0)/8.0)) + 128}]
                lappend vals [clamp $v 0 255]
            }
            if {$gray} {
                set g [lindex $vals 0]
                lappend rgb $g $g $g
            } else {
                lassign $vals Y Cb Cr
                set R [expr {int(round($Y + 1.402*($Cr-128)))}]
                set G [expr {int(round($Y - 0.344136*($Cb-128) - 0.714136*($Cr-128)))}]
                set B [expr {int(round($Y + 1.772*($Cb-128)))}]
                lappend rgb [clamp $R 0 255] [clamp $G 0 255] [clamp $B 0 255]
            }
        }
    }
    return [dict create w $outW h $outH pix [binary format cu* $rgb]]
}

# =============================================================================
# DOWNSCALE  (box average)  packed-RGB -> smaller packed-RGB
# =============================================================================
proc downscale {pix w h maxdim} {
    if {$maxdim <= 0 || max($w,$h) <= $maxdim} { return [list $w $h $pix] }
    set scale [expr {double($maxdim)/max($w,$h)}]
    set tw [expr {int(round($w*$scale))}]
    set th [expr {int(round($h*$scale))}]
    if {$tw < 1} {set tw 1}; if {$th < 1} {set th 1}
    set npx [expr {$tw*$th}]
    set sumR [lrepeat $npx 0]; set sumG [lrepeat $npx 0]
    set sumB [lrepeat $npx 0]; set cnt  [lrepeat $npx 0]
    set stride [expr {$w*3}]
    for {set y 0} {$y < $h} {incr y} {
        set ty [expr {$y*$th/$h}]
        set rowoff [expr {$y*$stride}]
        binary scan [string range $pix $rowoff [expr {$rowoff+$stride-1}]] cu* row
        set base [expr {$ty*$tw}]
        for {set x 0} {$x < $w} {incr x} {
            set tx [expr {$x*$tw/$w}]
            set ti [expr {$base+$tx}]
            set o [expr {$x*3}]
            lset sumR $ti [expr {[lindex $sumR $ti]+[lindex $row $o]}]
            lset sumG $ti [expr {[lindex $sumG $ti]+[lindex $row [expr {$o+1}]]}]
            lset sumB $ti [expr {[lindex $sumB $ti]+[lindex $row [expr {$o+2}]]}]
            lset cnt  $ti [expr {[lindex $cnt $ti]+1}]
        }
    }
    set out {}
    for {set i 0} {$i < $npx} {incr i} {
        set c [lindex $cnt $i]
        if {$c == 0} { set c 1 }
        lappend out [expr {[lindex $sumR $i]/$c}] \
                    [expr {[lindex $sumG $i]/$c}] \
                    [expr {[lindex $sumB $i]/$c}]
    }
    return [list $tw $th [binary format cu* $out]]
}

# =============================================================================
# sRGB -> OKLAB L    (only the lightness channel is needed for binning)
# =============================================================================
proc build_srgb_lin_lut {} {
    set lut {}
    for {set i 0} {$i < 256} {incr i} {
        set c [expr {$i/255.0}]
        if {$c <= 0.04045} {
            lappend lut [expr {$c/12.92}]
        } else {
            lappend lut [expr {pow(($c+0.055)/1.055, 2.4)}]
        }
    }
    return $lut
}
# L of OKLAB for a linear-RGB triple
proc oklab_L {lr lg lb} {
    set l [expr {0.4122214708*$lr + 0.5363325363*$lg + 0.0514459929*$lb}]
    set m [expr {0.2119034982*$lr + 0.6806995451*$lg + 0.1073969566*$lb}]
    set s [expr {0.0883024619*$lr + 0.2817188376*$lg + 0.6299787005*$lb}]
    set l_ [expr {$l <= 0 ? 0 : pow($l, 1.0/3)}]
    set m_ [expr {$m <= 0 ? 0 : pow($m, 1.0/3)}]
    set s_ [expr {$s <= 0 ? 0 : pow($s, 1.0/3)}]
    return [expr {0.2104542553*$l_ + 0.7936177850*$m_ - 0.0040720468*$s_}]
}

# =============================================================================
# PNG ENCODER  (RGBA, 8-bit)
# =============================================================================
proc png_chunk {type body} {
    set td $type$body
    set crc [zlib crc32 $td]
    return [binary format I [string length $body]]$td[binary format I $crc]
}
proc write_png_rgba {path w h rgba} {
    set stride [expr {$w*4}]
    set raw ""
    for {set y 0} {$y < $h} {incr y} {
        append raw "\x00" [string range $rgba [expr {$y*$stride}] [expr {($y+1)*$stride-1}]]
    }
    set out [binary format H* 89504e470d0a1a0a]
    append out [png_chunk IHDR [binary format IIccccc $w $h 8 6 0 0 0]]
    append out [png_chunk IDAT [zlib compress $raw]]
    append out [png_chunk IEND ""]
    set f [open $path wb]
    puts -nonewline $f $out
    close $f
}

# =============================================================================
# drawing into an RGBA int-list (4 ints/pixel)
# =============================================================================
proc putpx {imgVar w h x y r g b a} {
    upvar 1 $imgVar im
    if {$x < 0 || $y < 0 || $x >= $w || $y >= $h} return
    set i [expr {($y*$w+$x)*4}]
    lset im $i $r
    lset im [expr {$i+1}] $g
    lset im [expr {$i+2}] $b
    lset im [expr {$i+3}] $a
}
proc draw_line {imgVar w h x0 y0 x1 y1 r g b} {
    upvar 1 $imgVar im
    set dx [expr {abs($x1-$x0)}]; set dy [expr {-abs($y1-$y0)}]
    set sx [expr {$x0 < $x1 ? 1 : -1}]; set sy [expr {$y0 < $y1 ? 1 : -1}]
    set err [expr {$dx+$dy}]
    while {1} {
        putpx im $w $h $x0 $y0 $r $g $b 255
        if {$x0 == $x1 && $y0 == $y1} break
        set e2 [expr {2*$err}]
        if {$e2 >= $dy} { set err [expr {$err+$dy}]; set x0 [expr {$x0+$sx}] }
        if {$e2 <= $dx} { set err [expr {$err+$dx}]; set y0 [expr {$y0+$sy}] }
    }
}
proc draw_rect {imgVar w h x0 y0 x1 y1 r g b} {
    upvar 1 $imgVar im
    draw_line im $w $h $x0 $y0 $x1 $y0 $r $g $b
    draw_line im $w $h $x0 $y1 $x1 $y1 $r $g $b
    draw_line im $w $h $x0 $y0 $x0 $y1 $r $g $b
    draw_line im $w $h $x1 $y0 $x1 $y1 $r $g $b
}

# =============================================================================
# MAIN
# =============================================================================
proc main {argv} {
    if {[llength $argv] < 1} {
        puts "usage: tclsh oklab_graphemes.tcl <input.png|jpg> \[outdir\] \[options\]"
        puts "options: -bins N  -maxdim N  -minarea N  -conn 4|8  -lrange lo hi"
        exit 1
    }
    set input [lindex $argv 0]
    set outdir "oklab_out"
    set bins 6; set maxdim 640; set minarea -1; set conn 8
    set lrange {}
    set i 1
    # optional positional outdir
    if {[llength $argv] > 1 && ![string match -* [lindex $argv 1]]} {
        set outdir [lindex $argv 1]; set i 2
    }
    for {} {$i < [llength $argv]} {incr i} {
        switch -- [lindex $argv $i] {
            -bins    { set bins    [lindex $argv [incr i]] }
            -maxdim  { set maxdim  [lindex $argv [incr i]] }
            -minarea { set minarea [lindex $argv [incr i]] }
            -conn    { set conn    [lindex $argv [incr i]] }
            -lrange  { set lrange [list [lindex $argv [incr i]] [lindex $argv [incr i]]] }
            default  { die "unknown option [lindex $argv $i]" }
        }
    }
    file mkdir $outdir

    # ---- load ----
    set data [slurp $input]
    set magic [string range $data 0 1]
    puts "reading $input ..."
    if {$magic eq [binary format H* ffd8]} {
        set img [decode_jpeg $data]
        set kind "JPEG (DC image, 1/8 scale)"
    } elseif {[string range $data 0 7] eq [binary format H* 89504e470d0a1a0a]} {
        set img [decode_png $data]
        set kind "PNG"
    } else {
        die "unrecognised format (need PNG or JPEG)"
    }
    set w [dict get $img w]; set h [dict get $img h]; set pix [dict get $img pix]
    puts "  decoded $kind : ${w}x${h}"

    lassign [downscale $pix $w $h $maxdim] w h pix
    puts "  working size  : ${w}x${h}"
    set npx [expr {$w*$h}]
    binary scan $pix cu* RGB

    # ---- per-pixel OKLAB L ----
    set lut [build_srgb_lin_lut]
    set R {}; set G {}; set B {}; set Lv {}
    set Lmin 1e9; set Lmax -1e9
    for {set p 0} {$p < $npx} {incr p} {
        set o [expr {$p*3}]
        set r [lindex $RGB $o]; set g [lindex $RGB [expr {$o+1}]]; set b [lindex $RGB [expr {$o+2}]]
        lappend R $r; lappend G $g; lappend B $b
        set L [oklab_L [lindex $lut $r] [lindex $lut $g] [lindex $lut $b]]
        lappend Lv $L
        if {$L < $Lmin} {set Lmin $L}
        if {$L > $Lmax} {set Lmax $L}
    }
    if {[llength $lrange] == 2} { lassign $lrange Lmin Lmax }
    if {$Lmax <= $Lmin} { set Lmax [expr {$Lmin+1e-6}] }
    set bw [expr {($Lmax-$Lmin)/double($bins)}]
    puts [format "  OKLAB L range : %.4f .. %.4f  (%d bins, width %.4f)" $Lmin $Lmax $bins $bw]

    # ---- assign bins ----
    set BN {}
    foreach L $Lv {
        set k [expr {int(($L-$Lmin)/$bw)}]
        lappend BN [clamp $k 0 [expr {$bins-1}]]
    }

    if {$minarea < 0} {
        set minarea [expr {int(round($npx*0.0002))}]
        if {$minarea < 6} { set minarea 6 }
    }

    # false-colour preview palette (bin -> RGB), dark->light ramp
    set palette {}
    for {set k 0} {$k < $bins} {incr k} {
        set t [expr {$bins==1 ? 0.0 : double($k)/($bins-1)}]
        lappend palette [list \
            [expr {int(round(40+$t*200))}] \
            [expr {int(round(30+$t*150+($k%2)*30))}] \
            [expr {int(round(80+$t*160))}]]
    }

    # ---- write preview ----
    set prev {}
    foreach bn $BN {
        lassign [lindex $palette $bn] pr pg pb
        lappend prev $pr $pg $pb 255
    }
    write_png_rgba [file join $outdir bins_preview.png] $w $h [binary format cu* $prev]

    # ---- per-bin: emit channel image + grapheme search ----
    set tsv [open [file join $outdir graphemes.tsv] w]
    puts $tsv "bin\tid\tarea\tcx\tcy\tx0\ty0\tx1\ty1\torient_deg\teccentricity\tglyph"
    set totalGraphemes 0
    set summaryLines {}
    set dxs [list 1 -1 0 0 1 1 -1 -1]
    set dys [list 0 0 1 -1 1 -1 1 -1]
    set nNb [expr {$conn == 4 ? 4 : 8}]

    for {set k 0} {$k < $bins} {incr k} {
        # channel RGBA: this bin's pixels in their true colour, rest transparent
        set rgba {}
        for {set p 0} {$p < $npx} {incr p} {
            if {[lindex $BN $p] == $k} {
                lappend rgba [lindex $R $p] [lindex $G $p] [lindex $B $p] 255
            } else {
                lappend rgba 0 0 0 0
            }
        }
        write_png_rgba [file join $outdir [format bin_%d.png $k]] $w $h [binary format cu* $rgba]

        # ---- connected-component grapheme search on this channel ----
        set lab [lrepeat $npx 0]
        set comps {}
        for {set p 0} {$p < $npx} {incr p} {
            if {[lindex $BN $p] != $k || [lindex $lab $p] != 0} continue
            # BFS flood
            set stack [list $p]
            lset lab $p 1
            set head 0
            set area 0; set sx 0; set sy 0; set sxx 0; set syy 0; set sxy 0
            set minx $w; set maxx 0; set miny $h; set maxy 0
            while {$head < [llength $stack]} {
                set q [lindex $stack $head]; incr head
                set qx [expr {$q % $w}]; set qy [expr {$q / $w}]
                incr area
                incr sx $qx; incr sy $qy
                set sxx [expr {$sxx + $qx*$qx}]
                set syy [expr {$syy + $qy*$qy}]
                set sxy [expr {$sxy + $qx*$qy}]
                if {$qx < $minx} {set minx $qx}; if {$qx > $maxx} {set maxx $qx}
                if {$qy < $miny} {set miny $qy}; if {$qy > $maxy} {set maxy $qy}
                for {set d 0} {$d < $nNb} {incr d} {
                    set nx [expr {$qx+[lindex $dxs $d]}]
                    set ny [expr {$qy+[lindex $dys $d]}]
                    if {$nx < 0 || $ny < 0 || $nx >= $w || $ny >= $h} continue
                    set ni [expr {$ny*$w+$nx}]
                    if {[lindex $BN $ni] == $k && [lindex $lab $ni] == 0} {
                        lset lab $ni 1
                        lappend stack $ni
                    }
                }
            }
            if {$area < $minarea} continue
            # central moments -> orientation + eccentricity
            set cx [expr {double($sx)/$area}]
            set cy [expr {double($sy)/$area}]
            set mu20 [expr {double($sxx)/$area - $cx*$cx}]
            set mu02 [expr {double($syy)/$area - $cy*$cy}]
            set mu11 [expr {double($sxy)/$area - $cx*$cy}]
            set theta [expr {0.5*atan2(2*$mu11, $mu20-$mu02)}]
            set deg [expr {$theta*180.0/3.141592653589793}]
            set common [expr {sqrt(($mu20-$mu02)*($mu20-$mu02) + 4*$mu11*$mu11)}]
            set l1 [expr {($mu20+$mu02+$common)/2.0}]
            set l2 [expr {($mu20+$mu02-$common)/2.0}]
            set ecc [expr {$l1 > 0 ? sqrt(1.0 - ($l2 < 0 ? 0 : $l2)/$l1) : 0.0}]
            # glyph by shape+orientation (morphology of the grapheme)
            set glyph [orient_glyph $deg $ecc]
            lappend comps [list $area $cx $cy $minx $miny $maxx $maxy $deg $ecc $glyph]
        }
        # rank graphemes largest first
        set comps [lsort -real -decreasing -index 0 $comps]
        set gid 0
        foreach cmp $comps {
            lassign $cmp area cx cy x0 y0 x1 y1 deg ecc glyph
            puts $tsv [format "%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%.2f\t%.3f\t%s" \
                $k $gid $area [expr {int(round($cx))}] [expr {int(round($cy))}] \
                $x0 $y0 $x1 $y1 $deg $ecc $glyph]
            incr gid
        }
        incr totalGraphemes [llength $comps]
        lappend summaryLines [format "  bin %d  L in \[%.3f,%.3f)  graphemes: %d" \
            $k [expr {$Lmin+$k*$bw}] [expr {$Lmin+($k+1)*$bw}] [llength $comps]]

        # ---- annotated channel: draw bbox + orientation whisker per grapheme ----
        set ann $rgba
        foreach cmp $comps {
            lassign $cmp area cx cy x0 y0 x1 y1 deg ecc glyph
            set icx [expr {int(round($cx))}]; set icy [expr {int(round($cy))}]
            draw_rect ann $w $h $x0 $y0 $x1 $y1 255 60 60
            set len [expr {sqrt($area)/1.5 + 3}]
            set th [expr {$deg*3.141592653589793/180.0}]
            set ex [expr {int(round($icx+cos($th)*$len))}]
            set ey [expr {int(round($icy+sin($th)*$len))}]
            set bx [expr {int(round($icx-cos($th)*$len))}]
            set by [expr {int(round($icy-sin($th)*$len))}]
            draw_line ann $w $h $bx $by $ex $ey 80 220 255
            putpx ann $w $h $icx $icy 255 255 0 255
        }
        write_png_rgba [file join $outdir [format bin_%d_graphemes.png $k]] $w $h [binary format cu* $ann]
    }
    close $tsv

    # ---- summary ----
    set s [open [file join $outdir summary.txt] w]
    puts $s "oklab_graphemes report"
    puts $s "input        : $input"
    puts $s "format       : $kind"
    puts $s "working size : ${w}x${h}  ($npx px)"
    puts $s "bins         : $bins  (equally spaced along OKLAB L)"
    puts $s [format "L range      : %.4f .. %.4f" $Lmin $Lmax]
    puts $s "connectivity : $conn    min grapheme area: $minarea px"
    puts $s "graphemes    : $totalGraphemes total"
    puts $s ""
    foreach l $summaryLines { puts $s $l }
    puts $s ""
    puts $s "glyph legend : | vertical   - horizontal   / \\ diagonal   o round/blob"
    puts $s "orientation follows the note: graphemes encode orientation + meaning."
    close $s

    puts ""
    puts "wrote to $outdir/:"
    puts "  bins_preview.png, bin_0..[expr {$bins-1}].png, bin_*_graphemes.png"
    puts "  graphemes.tsv, summary.txt"
    puts "graphemes found: $totalGraphemes"
    foreach l $summaryLines { puts $l }
}

# map principal-axis angle + eccentricity to a glyph (grapheme morphology)
proc orient_glyph {deg ecc} {
    if {$ecc < 0.6} { return "o" }
    set a [expr {fmod($deg+180.0, 180.0)}]
    if {$a < 22.5 || $a >= 157.5} { return "-" }
    if {$a < 67.5}                { return "\\" }
    if {$a < 112.5}               { return "|" }
    return "/"
}

main $argv
