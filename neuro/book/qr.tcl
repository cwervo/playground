# qr.tcl — a QR encoder, because a citation you cannot follow is decoration.
#
# Byte mode, error-correction levels M and Q, versions 1 through 10, which
# covers every URL in this bibliography with room over. No package, no network,
# no image library: it emits SVG paths, so the code goes into the page as
# geometry and prints at whatever resolution the press has.
#
#   package require qr
#   qr::svg "https://doi.org/10.1093/brain/57.4.355" -level Q -size 22
#
# Correctness is not asserted, it is checked: book/qr-verify.py rebuilds every
# URL in the bibliography with an independent implementation and compares the
# module matrices for all eight masks. See the header of that file.
#
# References: ISO/IEC 18004. The tables below are transcribed from it; the
# placement and masking follow the same reading of the spec as Nayuki's
# reference implementation, which is the clearest one in print.

package provide qr 1.0

namespace eval qr {
    variable EXP {}
    variable LOG {}

    # version -> total codewords, data and error correction together
    variable TOTAL {1 26 2 44 3 70 4 100 5 134 6 172 7 196 8 242 9 292 10 346}

    # level -> version -> {ecPerBlock group1blocks group1data group2blocks group2data}
    variable BLOCKS
    array set BLOCKS {
        M,1  {10 1 16 0 0}   M,2  {16 1 28 0 0}   M,3  {26 1 44 0 0}
        M,4  {18 2 32 0 0}   M,5  {24 2 43 0 0}   M,6  {16 4 27 0 0}
        M,7  {18 4 31 0 0}   M,8  {22 2 38 2 39}  M,9  {22 3 36 2 37}
        M,10 {26 4 43 1 44}
        Q,1  {13 1 13 0 0}   Q,2  {22 1 22 0 0}   Q,3  {18 2 17 0 0}
        Q,4  {26 2 24 0 0}   Q,5  {18 2 15 2 16}  Q,6  {24 4 19 0 0}
        Q,7  {18 2 14 4 15}  Q,8  {22 4 18 2 19}  Q,9  {20 4 16 4 17}
        Q,10 {24 6 19 2 20}
    }

    # centres of the alignment patterns, per version
    variable ALIGN
    array set ALIGN {
        1 {}       2 {6 18}   3 {6 22}   4 {6 26}   5 {6 30}
        6 {6 34}   7 {6 22 38} 8 {6 24 42} 9 {6 26 46} 10 {6 28 50}
    }

    # the two-bit field the format information carries for each level
    variable ECBITS
    array set ECBITS {L 1 M 0 Q 3 H 2}
}

# --- GF(256), the field Reed-Solomon lives in -------------------------------
proc qr::initgf {} {
    variable EXP
    variable LOG
    if {[llength $EXP]} return
    set EXP [lrepeat 512 0]
    set LOG [lrepeat 256 0]
    set x 1
    for {set i 0} {$i < 255} {incr i} {
        lset EXP $i $x
        lset LOG $x $i
        set x [expr {$x << 1}]
        if {$x & 0x100} {set x [expr {$x ^ 0x11d}]}
    }
    for {set i 255} {$i < 512} {incr i} {
        lset EXP $i [lindex $EXP [expr {$i - 255}]]
    }
}

proc qr::mul {a b} {
    variable EXP
    variable LOG
    if {$a == 0 || $b == 0} {return 0}
    return [lindex $EXP [expr {[lindex $LOG $a] + [lindex $LOG $b]}]]
}

# generator polynomial for `n` error-correction codewords, high order first
proc qr::generator {n} {
    variable EXP
    set g {1}
    for {set i 0} {$i < $n} {incr i} {
        set root [lindex $EXP $i]
        set out [lrepeat [expr {[llength $g] + 1}] 0]
        for {set j 0} {$j < [llength $g]} {incr j} {
            set c [lindex $g $j]
            lset out $j [expr {[lindex $out $j] ^ $c}]
            set k [expr {$j + 1}]
            lset out $k [expr {[lindex $out $k] ^ [mul $c $root]}]
        }
        set g $out
    }
    return $g
}

proc qr::ecc {data n} {
    set gen [generator $n]
    set rem [concat $data [lrepeat $n 0]]
    set len [llength $data]
    for {set i 0} {$i < $len} {incr i} {
        set coef [lindex $rem $i]
        if {$coef == 0} continue
        for {set j 0} {$j <= $n} {incr j} {
            set k [expr {$i + $j}]
            lset rem $k [expr {[lindex $rem $k] ^ [mul [lindex $gen $j] $coef]}]
        }
    }
    return [lrange $rem $len end]
}

# --- bit stream -------------------------------------------------------------
proc qr::bits {value width} {
    set out ""
    for {set i [expr {$width - 1}]} {$i >= 0} {incr i -1} {
        append out [expr {($value >> $i) & 1}]
    }
    return $out
}

proc qr::capacity {version level} {
    variable BLOCKS
    lassign $BLOCKS($level,$version) ec g1n g1d g2n g2d
    return [expr {$g1n * $g1d + $g2n * $g2d}]
}

proc qr::pickversion {len level} {
    for {set v 1} {$v <= 10} {incr v} {
        set cc [expr {$v < 10 ? 8 : 16}]
        if {4 + $cc + 8 * $len <= 8 * [capacity $v $level]} {return $v}
    }
    error "qr: $len bytes will not fit in version 10 at level $level"
}

# --- codewords: encode, split into blocks, interleave -----------------------
proc qr::codewords {text version level} {
    variable BLOCKS
    set bytes {}
    foreach c [split $text ""] {
        scan $c %c n
        if {$n > 255} {error "qr: byte mode only, got a character above U+00FF"}
        lappend bytes $n
    }
    set n [llength $bytes]
    set cc [expr {$version < 10 ? 8 : 16}]

    set s "0100"
    append s [bits $n $cc]
    foreach b $bytes {append s [bits $b 8]}

    set total [expr {8 * [capacity $version $level]}]
    append s [string repeat 0 [expr {min(4, $total - [string length $s])}]]
    while {[string length $s] % 8} {append s 0}
    set pads {236 17}
    set p 0
    while {[string length $s] < $total} {
        append s [bits [lindex $pads $p] 8]
        set p [expr {1 - $p}]
    }

    set words {}
    for {set i 0} {$i < $total} {incr i 8} {
        set byte 0
        for {set j 0} {$j < 8} {incr j} {
            set byte [expr {($byte << 1) | [string index $s [expr {$i + $j}]]}]
        }
        lappend words $byte
    }

    lassign $BLOCKS($level,$version) eclen g1n g1d g2n g2d
    set blocks {}
    set eccs {}
    set at 0
    foreach {count size} [list $g1n $g1d $g2n $g2d] {
        for {set i 0} {$i < $count} {incr i} {
            set blk [lrange $words $at [expr {$at + $size - 1}]]
            incr at $size
            lappend blocks $blk
            lappend eccs [ecc $blk $eclen]
        }
    }

    # Interleaved: first codeword of every block, then the second, and so on.
    # A scuff on the paper then damages one codeword in each block rather than
    # destroying one block outright, which is the whole point of the exercise.
    set out {}
    set longest [expr {max($g1d, $g2d)}]
    for {set i 0} {$i < $longest} {incr i} {
        foreach blk $blocks {
            if {$i < [llength $blk]} {lappend out [lindex $blk $i]}
        }
    }
    for {set i 0} {$i < $eclen} {incr i} {
        foreach e $eccs {lappend out [lindex $e $i]}
    }
    return $out
}

# --- the matrix -------------------------------------------------------------
proc qr::newgrid {size fill} {
    set row [lrepeat $size $fill]
    return [lrepeat $size $row]
}

proc qr::at {gridName r c} {
    upvar 1 $gridName g
    return [lindex $g $r $c]
}

proc qr::put {gridName r c v} {
    upvar 1 $gridName g
    lset g $r $c $v
}

proc qr::function_patterns {mName fName version} {
    variable ALIGN
    upvar 1 $mName m $fName f
    set size [expr {17 + 4 * $version}]

    # three finders, with their separators
    foreach {r0 c0} [list 0 0 0 [expr {$size - 7}] [expr {$size - 7}] 0] {
        for {set dr -1} {$dr <= 7} {incr dr} {
            for {set dc -1} {$dc <= 7} {incr dc} {
                set r [expr {$r0 + $dr}]
                set c [expr {$c0 + $dc}]
                if {$r < 0 || $c < 0 || $r >= $size || $c >= $size} continue
                set a [expr {abs($dr - 3)}]
                set b [expr {abs($dc - 3)}]
                set dark [expr {max($a, $b) != 2 && ($a < 4 && $b < 4)}]
                put m $r $c [expr {$dark ? 1 : 0}]
                put f $r $c 1
            }
        }
    }

    # timing
    for {set i 0} {$i < $size} {incr i} {
        if {![at f 6 $i]} {put m 6 $i [expr {1 - $i % 2}]; put f 6 $i 1}
        if {![at f $i 6]} {put m $i 6 [expr {1 - $i % 2}]; put f $i 6 1}
    }

    # alignment
    set cs $ALIGN($version)
    foreach ar $cs {
        foreach ac $cs {
            # not over a finder
            if {($ar < 8 && $ac < 8) || ($ar < 8 && $ac > $size - 9) ||
                ($ar > $size - 9 && $ac < 8)} continue
            for {set dr -2} {$dr <= 2} {incr dr} {
                for {set dc -2} {$dc <= 2} {incr dc} {
                    set dark [expr {max(abs($dr), abs($dc)) != 1}]
                    put m [expr {$ar + $dr}] [expr {$ac + $dc}] [expr {$dark ? 1 : 0}]
                    put f [expr {$ar + $dr}] [expr {$ac + $dc}] 1
                }
            }
        }
    }

    # reserve the format and version areas
    for {set i 0} {$i < 9} {incr i} {
        put f 8 $i 1
        put f $i 8 1
    }
    for {set i 0} {$i < 8} {incr i} {
        put f 8 [expr {$size - 1 - $i}] 1
        put f [expr {$size - 1 - $i}] 8 1
    }
    put m [expr {$size - 8}] 8 1
    put f [expr {$size - 8}] 8 1
    if {$version >= 7} {
        for {set i 0} {$i < 18} {incr i} {
            set a [expr {$size - 11 + $i % 3}]
            set b [expr {$i / 3}]
            put f $b $a 1
            put f $a $b 1
        }
    }
}

proc qr::place_data {mName fName words size} {
    upvar 1 $mName m $fName f
    set stream ""
    foreach w $words {append stream [bits $w 8]}
    set i 0
    set n [string length $stream]
    for {set right [expr {$size - 1}]} {$right >= 1} {incr right -2} {
        if {$right == 6} {set right 5}
        for {set vert 0} {$vert < $size} {incr vert} {
            for {set j 0} {$j < 2} {incr j} {
                set c [expr {$right - $j}]
                set upward [expr {(($right + 1) & 2) == 0}]
                set r [expr {$upward ? $size - 1 - $vert : $vert}]
                if {![at f $r $c] && $i < $n} {
                    put m $r $c [string index $stream $i]
                    incr i
                }
            }
        }
    }
}

proc qr::maskbit {mask r c} {
    switch -- $mask {
        0 {return [expr {($c + $r) % 2 == 0}]}
        1 {return [expr {$r % 2 == 0}]}
        2 {return [expr {$c % 3 == 0}]}
        3 {return [expr {($c + $r) % 3 == 0}]}
        4 {return [expr {($c / 3 + $r / 2) % 2 == 0}]}
        5 {return [expr {$c * $r % 2 + $c * $r % 3 == 0}]}
        6 {return [expr {($c * $r % 2 + $c * $r % 3) % 2 == 0}]}
        7 {return [expr {(($c + $r) % 2 + $c * $r % 3) % 2 == 0}]}
    }
}

proc qr::apply_mask {mName fName mask size} {
    upvar 1 $mName m $fName f
    for {set r 0} {$r < $size} {incr r} {
        for {set c 0} {$c < $size} {incr c} {
            if {[at f $r $c]} continue
            if {[maskbit $mask $r $c]} {put m $r $c [expr {1 - [at m $r $c]}]}
        }
    }
}

proc qr::format_bits {mName level mask size} {
    variable ECBITS
    upvar 1 $mName m
    set data [expr {($ECBITS($level) << 3) | $mask}]
    set rem $data
    for {set i 0} {$i < 10} {incr i} {
        set rem [expr {($rem << 1) ^ (($rem >> 9) * 0x537)}]
    }
    set v [expr {(($data << 10) | ($rem & 0x3ff)) ^ 0x5412}]
    for {set i 0} {$i < 15} {incr i} {
        set b [expr {($v >> $i) & 1}]
        if {$i <= 5} {
            put m $i 8 $b
        } elseif {$i == 6} {
            put m 7 8 $b
        } elseif {$i == 7} {
            put m 8 8 $b
        } elseif {$i == 8} {
            put m 8 7 $b
        } else {
            put m 8 [expr {14 - $i}] $b
        }
        if {$i < 8} {
            put m 8 [expr {$size - 1 - $i}] $b
        } else {
            put m [expr {$size - 15 + $i}] 8 $b
        }
    }
}

proc qr::version_bits {mName version size} {
    upvar 1 $mName m
    if {$version < 7} return
    set rem $version
    for {set i 0} {$i < 12} {incr i} {
        set rem [expr {($rem << 1) ^ (($rem >> 11) * 0x1f25)}]
    }
    set v [expr {($version << 12) | ($rem & 0xfff)}]
    for {set i 0} {$i < 18} {incr i} {
        set b [expr {($v >> $i) & 1}]
        set a [expr {$size - 11 + $i % 3}]
        set d [expr {$i / 3}]
        put m $d $a $b
        put m $a $d $b
    }
}

# --- how ugly is it -- rules 1 to 4 of the spec -----------------------------
proc qr::penalty {mName size} {
    upvar 1 $mName m
    set score 0

    # rule 1: runs of five or more
    for {set r 0} {$r < $size} {incr r} {
        set run 1
        for {set c 1} {$c < $size} {incr c} {
            if {[at m $r $c] == [at m $r [expr {$c - 1}]]} {
                incr run
            } else {
                if {$run >= 5} {incr score [expr {$run - 2}]}
                set run 1
            }
        }
        if {$run >= 5} {incr score [expr {$run - 2}]}
    }
    for {set c 0} {$c < $size} {incr c} {
        set run 1
        for {set r 1} {$r < $size} {incr r} {
            if {[at m $r $c] == [at m [expr {$r - 1}] $c]} {
                incr run
            } else {
                if {$run >= 5} {incr score [expr {$run - 2}]}
                set run 1
            }
        }
        if {$run >= 5} {incr score [expr {$run - 2}]}
    }

    # rule 2: two by two blocks of one colour
    for {set r 0} {$r < $size - 1} {incr r} {
        for {set c 0} {$c < $size - 1} {incr c} {
            set v [at m $r $c]
            if {$v == [at m $r [expr {$c + 1}]] &&
                $v == [at m [expr {$r + 1}] $c] &&
                $v == [at m [expr {$r + 1}] [expr {$c + 1}]]} {incr score 3}
        }
    }

    # rule 3: anything that looks like a finder
    set p1 "10111010000"
    set p2 "00001011101"
    for {set r 0} {$r < $size} {incr r} {
        set row ""
        set col ""
        for {set c 0} {$c < $size} {incr c} {
            append row [at m $r $c]
            append col [at m $c $r]
        }
        foreach line [list $row $col] {
            foreach pat [list $p1 $p2] {
                set from 0
                while {[set k [string first $pat $line $from]] >= 0} {
                    incr score 40
                    set from [expr {$k + 1}]
                }
            }
        }
    }

    # rule 4: how far off half dark it is
    set dark 0
    for {set r 0} {$r < $size} {incr r} {
        foreach v [lindex $m $r] {incr dark $v}
    }
    set pct [expr {100.0 * $dark / ($size * $size)}]
    incr score [expr {int(abs($pct - 50) / 5) * 10}]
    return $score
}

# --- the whole thing --------------------------------------------------------
#
# Returns a dict: version, level, mask, size, and rows, a list of strings of
# 0 and 1, one per row of the symbol, quiet zone not included.
proc qr::encode {text args} {
    initgf
    array set opt {-level Q -mask auto}
    array set opt $args
    set level $opt(-level)
    set version [pickversion [string length $text] $level]
    set size [expr {17 + 4 * $version}]
    set words [codewords $text $version $level]

    set best {}
    set bestscore ""
    set masks [expr {$opt(-mask) eq "auto" ? "0 1 2 3 4 5 6 7" : $opt(-mask)}]
    foreach mask $masks {
        set m [newgrid $size 0]
        set f [newgrid $size 0]
        function_patterns m f $version
        place_data m f $words $size
        apply_mask m f $mask $size
        format_bits m $level $mask $size
        version_bits m $version $size
        set s [penalty m $size]
        if {$bestscore eq "" || $s < $bestscore} {
            set bestscore $s
            set best $m
            set bestmask $mask
        }
    }

    set rows {}
    foreach row $best {lappend rows [join $row ""]}
    return [dict create version $version level $level mask $bestmask \
                        size $size penalty $bestscore rows $rows]
}

# --- SVG --------------------------------------------------------------------
#
# One path, one fill, no image: it stays sharp at any size the press runs at,
# and the file stays small enough to sit inline in the HTML forty-six times.
proc qr::svg {text args} {
    array set opt {-level Q -size 100 -quiet 4 -dark #111111 -light none -class ""}
    array set opt $args
    set enc [encode $text -level $opt(-level)]
    set size [dict get $enc size]
    set span [expr {$size + 2 * $opt(-quiet)}]
    set q $opt(-quiet)

    set d ""
    set r 0
    foreach row [dict get $enc rows] {
        set c 0
        while {$c < $size} {
            if {[string index $row $c] eq "1"} {
                set run 1
                while {$c + $run < $size &&
                       [string index $row [expr {$c + $run}]] eq "1"} {incr run}
                append d "M[expr {$c + $q}] [expr {$r + $q}]h${run}v1h-${run}z"
                incr c $run
            } else {
                incr c
            }
        }
        incr r
    }

    set cls [expr {$opt(-class) eq "" ? "" : " class=\"$opt(-class)\""}]
    set bg ""
    if {$opt(-light) ne "none"} {
        set bg "<rect width=\"$span\" height=\"$span\" fill=\"$opt(-light)\"/>"
    }
    return "<svg$cls viewBox=\"0 0 $span $span\" width=\"$opt(-size)\"\
height=\"$opt(-size)\" shape-rendering=\"crispEdges\"\
role=\"img\" aria-label=\"QR code linking to $text\">$bg<path d=\"$d\"\
fill=\"$opt(-dark)\"/></svg>"
}
