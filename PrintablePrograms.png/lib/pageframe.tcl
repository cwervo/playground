# dataframe.tcl -- print-survivable pixel-domain data frame for PrintablePrograms.png.
#
# Encodes program metadata + as much of the program as fits into a band
# of saturated color cells around the page edge, designed to survive a
# color inkjet print-and-rescan or a screenshot:
#
#   * white quiet margin (printing comfort only, not needed by CV)
#   * ~6cm (parameterized) data band of large color cells, 3 bits/cell,
#     8-color palette at the RGB cube corners (max print separation)
#   * QR-style 7x7 finder fiducials in all four corners -> cell pitch,
#     no external knowledge of scale needed
#   * calibration strip (all 8 palette colors in order) inside the
#     top-left corner block -> per-print color correction
#   * band thickness self-encoded next to the calibration strip
#   * header: hostname, IP, program id, filename
#     (YYYYMMDD-HHMMSS-mmmZ.ext, UTC), physical page + cell dimensions
#     (so the artifact encodes its own scale), created timestamp
#   * payload: the beginning of the program source, as much as fits
#   * the whole packet is CRC32-guarded and repeated to fill the band;
#     the decoder accepts the first copy whose CRC verifies
#
# If the program doesn't fit, the full version can be pulled from the
# origin: http://<ip>/folk-data/program/<filename>
#
# Decoder assumptions: axis-aligned raster (screenshot, or a scan that
# has been deskewed); arbitrary uniform or anisotropic scale is fine.

namespace eval ::printable::pageframe {
    variable MAGIC   "FKF1"
    variable VERSION 1
    variable FID     7      ;# fiducial is FID x FID cells
    variable palette {
        {0 0 0} {255 0 0} {0 255 0} {0 0 255}
        {0 255 255} {255 0 255} {255 255 0} {255 255 255}
    }

    # ---------------------------------------------------------------- bits
    proc bytesToSymbols {bytes} {
        binary scan $bytes B* bits
        while {[string length $bits] % 3} { append bits 0 }
        set syms {}
        foreach {a b c} [split $bits ""] {
            lappend syms [expr {$a*4 + $b*2 + $c}]
        }
        return $syms
    }
    proc symbolsToBytes {syms} {
        set bits ""
        foreach s $syms {
            append bits [expr {($s>>2)&1}][expr {($s>>1)&1}][expr {$s&1}]
        }
        set bits [string range $bits 0 [expr {([string length $bits]/8)*8 - 1}]]
        return [binary format B* $bits]
    }

    # ------------------------------------------------------------- geometry
    # Data-cell walk order shared by encoder and decoder.
    # W,H: grid size in cells; T: band thickness in cells.
    proc dataCells {W H T} {
        set cells {}
        for {set r 0} {$r < $T} {incr r} {              ;# top strip
            for {set c $T} {$c < $W-$T} {incr c} { lappend cells [list $c $r] }
        }
        for {set c [expr {$W-$T}]} {$c < $W} {incr c} { ;# right strip
            for {set r $T} {$r < $H-$T} {incr r} { lappend cells [list $c $r] }
        }
        for {set r [expr {$H-$T}]} {$r < $H} {incr r} { ;# bottom strip
            for {set c $T} {$c < $W-$T} {incr c} { lappend cells [list $c $r] }
        }
        for {set c 0} {$c < $T} {incr c} {              ;# left strip
            for {set r $T} {$r < $H-$T} {incr r} { lappend cells [list $c $r] }
        }
        return $cells
    }

    # ---------------------------------------------------------------- packet
    proc buildPacket {header payload} {
        variable MAGIC
        variable VERSION
        set h [encoding convertto utf-8 $header]
        set p [encoding convertto utf-8 $payload]
        set crc [zlib crc32 $h$p]
        return $MAGIC[binary format cS $VERSION [string length $h]]$h[binary format I [string length $p]]$p[binary format I $crc]
    }

    proc parsePacket {bytes} {
        variable MAGIC
        if {[string range $bytes 0 3] ne $MAGIC} { error "bad magic" }
        binary scan $bytes @4cS ver hlen
        set hlen [expr {$hlen & 0xffff}]
        set h [string range $bytes 7 [expr {6 + $hlen}]]
        binary scan $bytes @[expr {7 + $hlen}]I plen
        set plen [expr {$plen & 0xffffffff}]
        set p [string range $bytes [expr {11 + $hlen}] [expr {10 + $hlen + $plen}]]
        binary scan $bytes @[expr {11 + $hlen + $plen}]I crc
        if {($crc & 0xffffffff) != [zlib crc32 $h$p]} { error "CRC mismatch" }
        return [list [encoding convertfrom utf-8 $h] [encoding convertfrom utf-8 $p]]
    }

    # ---------------------------------------------------------------- encode
    # opts: -source text -out path (required)
    #       -host -ip -id -file -pagewmm -pagehmm -cellmm -bandmm
    #       -quietmm -dpi -textpng (pre-rendered code image to composite)
    proc encode {args} {
        variable FID
        variable palette
        # -pagewmm/-pagehmm/-bandmm of 0 mean "minimal": the page grows
        # just enough to hold the text panel, and the band grows just
        # enough (up to -maxbandmm) to hold the packet.
        array set o {
            -pagewmm 0 -pagehmm 0 -cellmm 2.0 -bandmm 0 -maxbandmm 60.0
            -quietmm 8.0 -dpi 150 -id 1 -textpng "" -host "" -ip "" -file ""
            -extra ""
        }
        array set o $args
        if {$o(-host) eq ""} { set o(-host) [info hostname] }
        if {$o(-ip) eq ""}   { set o(-ip) [guessIp] }
        if {$o(-file) eq ""} {
            set ms [clock milliseconds]
            set o(-file) [clock format [expr {$ms/1000}] -gmt 1 \
                -format %Y%m%d-%H%M%S]-[format %03d [expr {$ms%1000}]]Z.folk.png
        }

        # header size estimate for band sizing (real header is built after
        # geometry is fixed; the 48-byte slack in needBytes absorbs digit
        # count differences)
        set header_estimate "complete=0\nhost=$o(-host)\nip=$o(-ip)\nid=$o(-id)\nfile=$o(-file)\npage_mm=0000.0 0000.0\ncell_mm=$o(-cellmm)\nband_mm=000.0\ncreated=0000-00-00T00:00:00Z\norigin=http://$o(-ip)/folk-data/program/$o(-file)\n$o(-extra)"

        set cellpx [expr {max(2, int(round($o(-cellmm) / 25.4 * $o(-dpi))))}]
        set minimal [expr {$o(-bandmm) == 0 || $o(-pagewmm) == 0 || $o(-pagehmm) == 0}]
        if {$minimal} {
            # interior sized to the text panel at its native (>=12pt) size
            set tw 0; set th 0
            if {$o(-textpng) ne "" && [::printable::typeset::magick] ne ""} {
                lassign [exec [::printable::typeset::magick] $o(-textpng) \
                             -format "%w %h" info:] tw th
            }
            set iw [expr {max(6, ($tw + 2*$cellpx + $cellpx - 1) / $cellpx)}]
            set ih [expr {max(6, ($th + 2*$cellpx + $cellpx - 1) / $cellpx)}]
            # keep the band as thin as the format allows and grow the
            # perimeter (interior) to fit one full packet; only deepen
            # the band (up to -maxbandmm) if the text panel already
            # provides more perimeter than needed can't happen -- deeper
            # bands are the fallback when the interior must stay small
            set needBytes [expr {4 + 4 + 3
                + [string length [encoding convertto utf-8 $header_estimate]]
                + [string length [encoding convertto utf-8 $o(-source)]] + 4 + 4 + 48}]
            set needCells [expr {($needBytes*8 + 2) / 3}]
            set T [expr {$FID + 5}]
            set needSum [expr {($needCells + 2*$T - 1) / (2*$T)}]   ;# min iw+ih
            if {$iw + $ih < $needSum} {
                set extra [expr {$needSum - $iw - $ih}]
                incr iw [expr {($extra + 1) / 2}]
                incr ih [expr {$extra / 2}]
            }
            # cap runaway pages: past ~2x A4 perimeter, deepen the band
            # instead, then truncate at -maxbandmm (prefix + origin URL)
            set maxT [expr {int(round($o(-maxbandmm) / $o(-cellmm)))}]
            while {2*$T*($iw+$ih) < $needCells && $T < $maxT} { incr T }
            set W [expr {$iw + 2*$T}]
            set H [expr {$ih + 2*$T}]
            set o(-pagewmm) [format %.1f [expr {$W * $o(-cellmm)}]]
            set o(-pagehmm) [format %.1f [expr {$H * $o(-cellmm)}]]
            set o(-bandmm)  [format %.1f [expr {$T * $o(-cellmm)}]]
        } else {
            set W [expr {int(round($o(-pagewmm) / $o(-cellmm)))}]
            set H [expr {int(round($o(-pagehmm) / $o(-cellmm)))}]
            set T [expr {int(round($o(-bandmm) / $o(-cellmm)))}]
        }
        if {$T < $FID + 5} { error "band too thin: need >= [expr {$FID+5}] cells, got $T" }
        if {$W <= 2*$T + 2 || $H <= 2*$T + 2} { error "page too small for band" }

        set cells [dataCells $W $H $T]
        set capBytes [expr {(3 * [llength $cells]) / 8}]

        set header "host=$o(-host)\nip=$o(-ip)\nid=$o(-id)\nfile=$o(-file)\n"
        append header "page_mm=$o(-pagewmm) $o(-pagehmm)\ncell_mm=$o(-cellmm)\n"
        append header "band_mm=$o(-bandmm)\ncreated=[clock format [clock seconds] -gmt 1 -format %Y-%m-%dT%H:%M:%SZ]\n"
        append header "origin=http://$o(-ip)/folk-data/program/$o(-file)\n"
        # caller-supplied extra header lines (key=value, newline separated)
        if {$o(-extra) ne ""} { append header [string trimright $o(-extra) \n] \n }

        # fit as much of the program as the packet budget allows
        # 4 len prefix + 4 magic + 3 ver/hlen + header (incl. the
        # "complete=X\n" line added below) + 4 payload len + 4 crc
        set overhead [expr {4 + 4 + 3 + [string length [encoding convertto utf-8 $header]]
                            + [string length "complete=0\n"] + 4 + 4}]
        set room [expr {$capBytes - $overhead}]
        if {$room < 0} { error "band capacity ($capBytes B) can't even fit the header" }
        set srcBytes [encoding convertto utf-8 $o(-source)]
        set complete 1
        if {[string length $srcBytes] > $room} {
            set srcBytes [string range $srcBytes 0 [expr {$room - 1}]]
            set complete 0
        }
        set header "complete=$complete\n$header"
        set payload [encoding convertfrom utf-8 $srcBytes]

        set packet [buildPacket $header $payload]
        set unit [binary format I [string length $packet]]$packet
        set syms [bytesToSymbols $unit]
        set unitLen [llength $syms]

        # repeat the packet to fill every data cell
        set stream {}
        while {[llength $stream] < [llength $cells]} {
            set stream [concat $stream $syms]
        }
        set stream [lrange $stream 0 [llength $cells]-1]

        # ---- paint the cell grid -----------------------------------------
        # grid(c,r) = palette index; -1 = white background
        for {set r 0} {$r < $H} {incr r} {
            for {set c 0} {$c < $W} {incr c} { set grid($c,$r) 7 }
        }
        set i 0
        foreach cell $cells {
            lassign $cell c r
            set grid($c,$r) [lindex $stream $i]
            incr i
        }
        # fiducials in all four corners
        foreach {cx cy} [list 0 0 [expr {$W-$FID}] 0 0 [expr {$H-$FID}] [expr {$W-$FID}] [expr {$H-$FID}]] {
            paintFiducial grid $cx $cy
        }
        # top-left corner block, rows below the fiducial:
        #   FID+1: calibration strip (palette 0..7 in order)
        #   FID+2: band thickness T   (24 bits in 8 cells)
        #   FID+3: grid width  W      (24 bits in 8 cells)
        #   FID+4: grid height H      (24 bits in 8 cells)
        for {set k 0} {$k < 8} {incr k} { set grid($k,[expr {$FID+1}]) $k }
        set row [expr {$FID + 2}]
        foreach val [list $T $W $H] {
            set bits [format %024b $val]
            for {set k 0} {$k < 8} {incr k} {
                set grid($k,$row) [scan [string range $bits [expr {$k*3}] [expr {$k*3+2}]] %b]
            }
            incr row
        }

        # ---- rasterize ----------------------------------------------------
        set quietpx [expr {int(round($o(-quietmm) / 25.4 * $o(-dpi)))}]
        set imgW [expr {$W*$cellpx + 2*$quietpx}]
        set imgH [expr {$H*$cellpx + 2*$quietpx}]

        set white [binary format ccc 255 255 255]
        set blankRow [string repeat $white $imgW]
        set raw ""
        for {set q 0} {$q < $quietpx} {incr q} { append raw \x00$blankRow }
        for {set r 0} {$r < $H} {incr r} {
            set rowline [string repeat $white $quietpx]
            for {set c 0} {$c < $W} {incr c} {
                lassign [lindex $palette $grid($c,$r)] R G B
                append rowline [string repeat [binary format ccc $R $G $B] $cellpx]
            }
            append rowline [string repeat $white [expr {$imgW - $quietpx - $W*$cellpx}]]
            set scan \x00$rowline
            for {set y 0} {$y < $cellpx} {incr y} { append raw $scan }
        }
        for {set q 0} {$q < $quietpx} {incr q} { append raw \x00$blankRow }

        set ihdr [binary format IIccccc $imgW $imgH 8 2 0 0 0]
        set png "\x89PNG\r\n\x1a\n"
        append png [::printable::pngcodec::buildChunk IHDR $ihdr]
        append png [::printable::pngcodec::buildChunk IDAT [zlib compress $raw]]
        append png [::printable::pngcodec::buildChunk IEND ""]
        ::printable::pngcodec::writeFile $o(-out) $png

        # composite the human-readable code into the interior, centered.
        # The text is never scaled down: 12pt is a floor, and in minimal
        # mode the interior was sized to the text, not the other way round.
        if {$o(-textpng) ne "" && [::printable::typeset::magick] ne ""} {
            set im [::printable::typeset::magick]
            lassign [exec $im $o(-textpng) -format "%w %h" info:] tw th
            set iwpx [expr {($W - 2*$T)*$cellpx}]
            set ihpx [expr {($H - 2*$T)*$cellpx}]
            set ix [expr {$quietpx + $T*$cellpx + max(0, ($iwpx - $tw)/2)}]
            set iy [expr {$quietpx + $T*$cellpx + max(0, ($ihpx - $th)/2)}]
            catch {
                exec $im $o(-out) $o(-textpng) \
                    -gravity NorthWest -geometry +$ix+$iy -composite $o(-out)
            }
        }
        return [dict create file $o(-file) capacity $capBytes \
                    packet [string length $packet] copies \
                    [expr {[llength $cells] / max(1,$unitLen)}] complete $complete \
                    grid "${W}x${H} cells, band $T" px "${imgW}x${imgH}"]
    }

    proc paintFiducial {gridVar cx cy} {
        variable FID
        upvar 1 $gridVar grid
        for {set r 0} {$r < $FID} {incr r} {
            for {set c 0} {$c < $FID} {incr c} {
                set ring [expr {min(min($c, $FID-1-$c), min($r, $FID-1-$r))}]
                set grid([expr {$cx+$c}],[expr {$cy+$r}]) [expr {$ring == 1 ? 7 : 0}]
            }
        }
    }

    proc guessIp {} {
        if {![catch {exec hostname -I} out] && [llength $out]} {
            return [lindex $out 0]
        }
        return "127.0.0.1"
    }

    # ---------------------------------------------------------------- decode
    proc decode {path} {
        variable FID
        variable palette
        set im [::printable::typeset::magick]
        if {$im eq ""} { error "ImageMagick required to decode rasters" }

        # locate the frame: trim the white margin
        set info [exec $im $path -fuzz 35% -format "%w %h %@" info:]
        lassign $info fullW fullH crop
        if {![regexp {(\d+)x(\d+)\+(\d+)\+(\d+)} $crop -> bw bh bx by]} {
            error "could not locate frame bounding box"
        }

        # raw RGB pixels of the full image
        set f [open [list | {*}$im $path -depth 8 rgb:-] rb]
        set raw [read $f]
        close $f

        # cell pitch from the top-left fiducial's solid 7-cell top edge;
        # probe several rows into the fiducial so resampled/blurred edges
        # (screenshots, scans) don't fool the run measurement
        set run 0
        set maxDy [expr {max(4, $bh / 25)}]
        for {set dy 1} {$dy <= $maxDy} {incr dy} {
            set y [expr {$by + $dy}]
            # skip antialiased light pixels at the bbox edge, then count
            set x $bx
            set limit [expr {$bx + $bw/4}]
            while {$x < $limit && [lum $raw $fullW $x $y] >= 128} { incr x }
            set r 0
            while {$x < $bx + $bw && [lum $raw $fullW $x $y] < 128} { incr r; incr x }
            if {$r > $run} { set run $r }
        }
        if {$run < 4} { error "no fiducial found at frame corner" }
        set pitch0 [expr {double($run) / $FID}]

        # sampler: average 3x3 around a cell center
        set sample {{c r} {
            upvar 1 raw raw fullW fullW bx bx by by px px py py
            set x [expr {int($bx + ($c + 0.5) * $px)}]
            set y [expr {int($by + ($r + 0.5) * $py)}]
            set R 0; set G 0; set B 0
            foreach dy {-1 0 1} { foreach dx {-1 0 1} {
                set o [expr {(($y+$dy)*$fullW + $x+$dx) * 3}]
                binary scan $raw @${o}cu3 v
                lassign $v r_ g_ b_
                incr R $r_; incr G $g_; incr B $b_
            }}
            list [expr {$R/9}] [expr {$G/9}] [expr {$B/9}]
        }}

        # bootstrap with the fiducial-run pitch: good enough near the
        # top-left corner, where all the self-description rows live
        set px $pitch0
        set py $pitch0

        # calibration strip -> measured palette
        set measured {}
        for {set k 0} {$k < 8} {incr k} {
            lappend measured [apply $sample $k [expr {$FID+1}]]
        }
        set classify {{rgb measured} {
            lassign $rgb r g b
            set best 0; set bd 1e18
            set i 0
            foreach m $measured {
                lassign $m mr mg mb
                set d [expr {($r-$mr)**2 + ($g-$mg)**2 + ($b-$mb)**2}]
                if {$d < $bd} { set bd $d; set best $i }
                incr i
            }
            return $best
        }}

        # self-description rows: T, then grid W and H (exact cell counts,
        # immune to pitch measurement error over a wide grid)
        set vals {}
        for {set row [expr {$FID+2}]} {$row <= $FID+4} {incr row} {
            set bits ""
            for {set k 0} {$k < 8} {incr k} {
                append bits [format %03b [apply $classify [apply $sample $k $row] $measured]]
            }
            lappend vals [scan $bits %b]
        }
        lassign $vals T W H
        if {$W < 2*$FID || $W > 8192 || $H < 2*$FID || $H > 8192} {
            error "implausible grid ${W}x${H}"
        }
        if {$T < $FID || $T > min($W,$H)/2} { error "implausible band thickness: $T" }
        if {abs($bw/double($W) - $pitch0) > $pitch0/2 || abs($bh/double($H) - $pitch0) > $pitch0/2} {
            error "self-encoded grid ${W}x${H} disagrees with measured pitch"
        }

        # exact pitches now that the true cell counts are known
        set px [expr {double($bw) / $W}]
        set py [expr {double($bh) / $H}]

        # read every data cell
        set syms {}
        foreach cell [dataCells $W $H $T] {
            lassign $cell c r
            lappend syms [apply $classify [apply $sample $c $r] $measured]
        }
        set bytes [symbolsToBytes $syms]

        # first CRC-valid packet copy wins
        binary scan $bytes I plen
        set plen [expr {$plen & 0xffffffff}]
        if {$plen < 12 || $plen > [string length $bytes]} {
            error "corrupt length prefix ($plen); frame unreadable"
        }
        set stride [expr {4 + $plen}]
        set n [string length $bytes]
        for {set off 0} {$off + $stride <= $n} {incr off $stride} {
            if {![catch {parsePacket [string range $bytes [expr {$off+4}] [expr {$off+$stride-1}]]} res]} {
                lassign $res header payload
                set meta [dict create]
                foreach line [split $header \n] {
                    if {[regexp {^([^=]+)=(.*)$} $line -> k v]} { dict set meta $k $v }
                }
                # self-encoded scale: px per mm as seen in this raster
                if {[dict exists $meta cell_mm]} {
                    dict set meta scale_px_per_mm [format %.3f [expr {$px / [dict get $meta cell_mm]}]]
                }
                return [dict create meta $meta source $payload \
                            grid "${W}x${H} cells, band $T" copyOffset $off]
            }
        }
        error "no packet copy passed CRC; frame too damaged"
    }

    proc lum {raw fullW x y} {
        set o [expr {($y*$fullW + $x) * 3}]
        binary scan $raw @${o}cu3 v
        lassign $v r g b
        expr {($r + $g + $b) / 3}
    }
}
