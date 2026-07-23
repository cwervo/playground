#!/usr/bin/env tclsh
# =====================================================================
#  provenance/extract.tcl
#
#  A dependency-free feature-extraction + deliverable pipeline, written
#  from scratch in pure Tcl (no packages, no external tools, no network).
#
#  Stages:
#    1. INGEST   read each note JPEG as raw bytes; parse the real image
#                dimensions straight out of the JPEG SOF marker.
#    2. MODEL    load the extracted feature manifest (salient shapes +
#                text tokens with normalized 1:1 placement).
#    3. RASTER   render every salient shape as a "platonic" RGBA raster
#                and encode it to a PNG with hand-rolled DEFLATE(stored)
#                + Adler-32 + CRC-32 + a from-scratch Base64 encoder.
#    4. COMPOSE  emit a single self-contained index.html: calcium-blurred
#                CSS-3D backgrounds, selectable SVG text laid 1:1 over the
#                handwriting, and copyable base64-PNG chips underneath.
#
#  Output: provenance/index.html  (self-contained, zero network requests)
# =====================================================================

set HERE [file dirname [file normalize [info script]]]

# ---------------------------------------------------------------------
# 1. Base64 encoder  (from scratch, RFC 4648)
# ---------------------------------------------------------------------
proc b64enc {data} {
    set map "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    binary scan $data cu* B
    set n [llength $B]
    set out {}
    for {set i 0} {$i < $n} {incr i 3} {
        set b0 [lindex $B $i]
        set rem [expr {$n - $i}]
        set b1 [expr {$rem > 1 ? [lindex $B [expr {$i+1}]] : 0}]
        set b2 [expr {$rem > 2 ? [lindex $B [expr {$i+2}]] : 0}]
        set t [expr {($b0 << 16) | ($b1 << 8) | $b2}]
        append out [string index $map [expr {($t >> 18) & 63}]]
        append out [string index $map [expr {($t >> 12) & 63}]]
        append out [expr {$rem > 1 ? [string index $map [expr {($t >> 6) & 63}]] : "="}]
        append out [expr {$rem > 2 ? [string index $map [expr {$t & 63}]] : "="}]
    }
    return $out
}

# ---------------------------------------------------------------------
# 2. CRC-32  (from scratch, IEEE 802.3, table driven)
# ---------------------------------------------------------------------
set ::CRCTBL {}
proc crc_init {} {
    for {set n 0} {$n < 256} {incr n} {
        set c $n
        for {set k 0} {$k < 8} {incr k} {
            set c [expr {($c & 1) ? (0xEDB88320 ^ ($c >> 1)) : ($c >> 1)}]
        }
        lappend ::CRCTBL [expr {$c & 0xFFFFFFFF}]
    }
}
proc crc32 {data} {
    set c 0xFFFFFFFF
    binary scan $data cu* B
    foreach b $B {
        set c [expr {[lindex $::CRCTBL [expr {($c ^ $b) & 0xFF}]] ^ ($c >> 8)}]
    }
    return [expr {($c ^ 0xFFFFFFFF) & 0xFFFFFFFF}]
}

# ---------------------------------------------------------------------
# 3. Adler-32  (from scratch, used by the zlib wrapper)
# ---------------------------------------------------------------------
proc adler32 {data} {
    set a 1; set b 0
    binary scan $data cu* B
    foreach byte $B {
        set a [expr {($a + $byte) % 65521}]
        set b [expr {($b + $a) % 65521}]
    }
    return [expr {(($b << 16) | $a) & 0xFFFFFFFF}]
}

# ---------------------------------------------------------------------
# 4. DEFLATE — stored (uncompressed) blocks, from scratch, + zlib frame
# ---------------------------------------------------------------------
proc zlib_stored {raw} {
    set out [binary format cc 0x78 0x01]        ;# CMF=0x78 FLG=0x01 (check%31==0)
    set len [string length $raw]
    set pos 0
    while {1} {
        set take [expr {min(65535, $len - $pos)}]
        set final [expr {($pos + $take) >= $len ? 1 : 0}]
        append out [binary format c $final]      ;# BFINAL bit, BTYPE=00 (stored)
        append out [binary format s $take]       ;# LEN  (little endian)
        append out [binary format s [expr {~$take & 0xFFFF}]]  ;# NLEN
        append out [string range $raw $pos [expr {$pos + $take - 1}]]
        incr pos $take
        if {$final} break
        if {$len == 0} break
    }
    append out [binary format I [adler32 $raw]]  ;# Adler-32, big endian
    return $out
}

# ---------------------------------------------------------------------
# 5. PNG encoder  (from scratch: signature + IHDR + IDAT + IEND)
#    px is a flat list of RGBA bytes, length = w*h*4
# ---------------------------------------------------------------------
proc png_chunk {type data} {
    set body $type$data
    return [binary format I [string length $data]]$body[binary format I [crc32 $body]]
}
proc png_encode {w h px} {
    # filter each scanline with filter type 0 (None)
    set raw {}
    set stride [expr {$w * 4}]
    for {set y 0} {$y < $h} {incr y} {
        append raw [binary format c 0]
        set off [expr {$y * $stride}]
        append raw [binary format cu* [lrange $px $off [expr {$off + $stride - 1}]]]
    }
    set sig [binary format cccccccc 137 80 78 71 13 10 26 10]
    set ihdr [binary format IIccccc $w $h 8 6 0 0 0]   ;# 8-bit, RGBA, no interlace
    set idat [zlib_stored $raw]
    return $sig[png_chunk IHDR $ihdr][png_chunk IDAT $idat][png_chunk IEND ""]
}

# ---------------------------------------------------------------------
# JPEG dimension reader — genuine extraction from the real file bytes.
# Scans for a Start-Of-Frame marker and reads height/width.
# ---------------------------------------------------------------------
proc jpeg_dims {data} {
    set len [string length $data]
    set i 2                                   ;# skip SOI (FFD8)
    while {$i < $len - 1} {
        binary scan [string range $data $i [expr {$i+1}]] cucu m0 m1
        if {$m0 != 0xFF} { incr i; continue }
        # SOF markers carry the frame size (exclude C4/C8/CC + RST/standalone)
        if {($m1 >= 0xC0 && $m1 <= 0xCF) && $m1 ni {0xC4 0xC8 0xCC}} {
            binary scan [string range $data [expr {$i+5}] [expr {$i+8}]] SuSu H W
            return [list $W $H]
        }
        binary scan [string range $data [expr {$i+2}] [expr {$i+3}]] Su seg
        incr i [expr {2 + $seg}]
    }
    return [list 0 0]
}

# =====================================================================
#  RASTER CANVAS  — a tiny from-scratch RGBA drawing surface
# =====================================================================
proc cnew {w h} {
    set ::bw $w; set ::bh $h
    set ::px [lrepeat [expr {$w * $h * 4}] 0]
}
proc hex2rgb {hex} {
    scan [string range $hex 1 6] "%2x%2x%2x" r g b
    return [list $r $g $b]
}
proc setpx {x y rgb {a 255}} {
    if {$x < 0 || $y < 0 || $x >= $::bw || $y >= $::bh} return
    lassign $rgb r g b
    set i [expr {($y * $::bw + $x) * 4}]
    if {$a >= 255} {
        lset ::px $i $r; lset ::px [expr {$i+1}] $g
        lset ::px [expr {$i+2}] $b; lset ::px [expr {$i+3}] 255
    } else {
        # source-over blend onto existing pixel
        set da [lindex $::px [expr {$i+3}]]
        set na [expr {$a + $da * (255 - $a) / 255}]
        if {$na == 0} return
        for {set k 0} {$k < 3} {incr k} {
            set dc [lindex $::px [expr {$i+$k}]]
            set sc [lindex $rgb $k]
            set oc [expr {($sc*$a + $dc*$da*(255-$a)/255) / $na}]
            lset ::px [expr {$i+$k}] [expr {$oc > 255 ? 255 : $oc}]
        }
        lset ::px [expr {$i+3}] $na
    }
}
proc dot {cx cy rad rgb} {
    set r2 [expr {$rad * $rad}]
    for {set y [expr {int($cy-$rad-1)}]} {$y <= $cy+$rad+1} {incr y} {
        for {set x [expr {int($cx-$rad-1)}]} {$x <= $cx+$rad+1} {incr x} {
            set d [expr {($x-$cx)*($x-$cx) + ($y-$cy)*($y-$cy)}]
            if {$d <= $r2} { setpx $x $y $rgb }
        }
    }
}
proc ring {cx cy rad th rgb} {
    set ro [expr {$rad + $th/2.0}]; set ri [expr {$rad - $th/2.0}]
    set ro2 [expr {$ro*$ro}]; set ri2 [expr {$ri*$ri}]
    for {set y [expr {int($cy-$ro-1)}]} {$y <= $cy+$ro+1} {incr y} {
        for {set x [expr {int($cx-$ro-1)}]} {$x <= $cx+$ro+1} {incr x} {
            set d [expr {($x-$cx)*($x-$cx) + ($y-$cy)*($y-$cy)}]
            if {$d <= $ro2 && $d >= $ri2} { setpx $x $y $rgb }
        }
    }
}
proc thline {x0 y0 x1 y1 th rgb} {
    set x0 [expr {int($x0)}]; set y0 [expr {int($y0)}]
    set x1 [expr {int($x1)}]; set y1 [expr {int($y1)}]
    set dx [expr {abs($x1-$x0)}]; set dy [expr {-abs($y1-$y0)}]
    set sx [expr {$x0 < $x1 ? 1 : -1}]; set sy [expr {$y0 < $y1 ? 1 : -1}]
    set err [expr {$dx + $dy}]
    set h [expr {$th/2}]
    while {1} {
        for {set yy [expr {-$h}]} {$yy <= $h} {incr yy} {
            for {set xx [expr {-$h}]} {$xx <= $h} {incr xx} { setpx [expr {$x0+$xx}] [expr {$y0+$yy}] $rgb }
        }
        if {$x0 == $x1 && $y0 == $y1} break
        set e2 [expr {2*$err}]
        if {$e2 >= $dy} { set err [expr {$err+$dy}]; incr x0 $sx }
        if {$e2 <= $dx} { set err [expr {$err+$dx}]; incr y0 $sy }
    }
}
proc rectout {x0 y0 x1 y1 th rgb} {
    thline $x0 $y0 $x1 $y0 $th $rgb
    thline $x1 $y0 $x1 $y1 $th $rgb
    thline $x1 $y1 $x0 $y1 $th $rgb
    thline $x0 $y1 $x0 $y0 $th $rgb
}

# ---- platonic shape icons: each returns a base64 PNG data payload -----
# All draw into a fresh transparent canvas sized `S` and use ink `rgb`.
proc icon_render {type rgb {S 120}} {
    cnew $S $S
    set c [expr {$S/2.0}]; set m [expr {$S*0.16}]
    set a $m; set b [expr {$S-$m}]
    switch -- $type {
        box      { rectout $a $a $b $b 3 $rgb }
        ring     { ring $c $c [expr {$c-$m}] 4 $rgb }
        blob     { ring $c $c [expr {$c-$m}] 6 $rgb; ring $c $c [expr {$c-$m*1.9}] 3 $rgb }
        concentric {
            rectout $a $a $b $b 3 $rgb
            rectout [expr {$a+$S*0.12}] [expr {$a+$S*0.12}] [expr {$b-$S*0.12}] [expr {$b-$S*0.12}] 3 $rgb
            dot $c $c [expr {$S*0.07}] $rgb
        }
        grid {
            rectout $a $a $b $b 2 $rgb
            for {set k 1} {$k < 5} {incr k} {
                set gx [expr {$a + ($b-$a)*$k/5.0}]
                thline $gx $a $gx $b 1 $rgb
                set gy [expr {$a + ($b-$a)*$k/5.0}]
                thline $a $gy $b $gy 1 $rgb
            }
        }
        arrow {
            thline $a [expr {$S*0.62}] $b [expr {$S*0.38}] 4 $rgb
            thline $b [expr {$S*0.38}] [expr {$b-$S*0.16}] [expr {$S*0.40}] 4 $rgb
            thline $b [expr {$S*0.38}] [expr {$b-$S*0.10}] [expr {$S*0.56}] 4 $rgb
        }
        wave {
            set prev {}
            for {set t 0} {$t <= 40} {incr t} {
                set yy [expr {$a + ($b-$a)*$t/40.0}]
                set xx [expr {$c + ($S*0.26)*sin($t/40.0*6.2831*1.5)}]
                if {$prev ne {}} { thline [lindex $prev 0] [lindex $prev 1] $xx $yy 3 $rgb }
                set prev [list $xx $yy]
            }
        }
        face {
            ring $c $c [expr {$c-$m}] 3 $rgb
            dot [expr {$c-$S*0.14}] [expr {$c-$S*0.06}] [expr {$S*0.03}] $rgb
            dot [expr {$c+$S*0.14}] [expr {$c-$S*0.06}] [expr {$S*0.03}] $rgb
            for {set t 0} {$t <= 20} {incr t} {
                set ang [expr {0.35 + $t/20.0*2.44}]
                setpx [expr {int($c+$S*0.20*cos($ang))}] [expr {int($c+$S*0.10+$S*0.14*sin($ang))}] $rgb
                setpx [expr {int($c+$S*0.20*cos($ang))}] [expr {int($c+$S*0.10+$S*0.14*sin($ang))+1}] $rgb
            }
        }
        default  { rectout $a $a $b $b 3 $rgb }
    }
    return [png_encode $::bw $::bh $::px]
}

# =====================================================================
#  2. FEATURE MANIFEST — the extracted model of each note.
#     text  token:  {string nx ny nw nh rot "#hex"}   (normalized 0..1)
#     shape token:  {type nx ny nw nh "#hex" label}
# =====================================================================
set NOTES {
    {
        file  "assets/note1.jpg"
        title "Note I · CIELAB circle-brush"
        text {
            {"A"                    0.412 0.150 0.020 0.045 0   "#d81f6f"}
            {"B"                    0.470 0.150 0.020 0.045 0   "#e08a2a"}
            {"C"                    0.530 0.150 0.020 0.045 0   "#d81f6f"}
            {"CAB"                  0.440 0.300 0.070 0.060 0   "#e0561f"}
            {"Above target"         0.578 0.185 0.100 0.040 0   "#d81f6f"}
            {"separate in"          0.582 0.235 0.090 0.038 0   "#d81f6f"}
            {"{channel A}"          0.690 0.220 0.090 0.032 -60 "#d81f6f"}
            {"B gold"               0.712 0.285 0.070 0.032 -60 "#d81f6f"}
            {"red on/off"           0.700 0.330 0.080 0.030 -60 "#d81f6f"}
            {"CIELAB"               0.478 0.470 0.090 0.055 0   "#c81e63"}
            {"'circle brush'"       0.478 0.520 0.095 0.034 0   "#c81e63"}
            {"paint tool"           0.482 0.552 0.080 0.034 0   "#c81e63"}
            {"take a 2inch/12inch"  0.240 0.500 0.230 0.034 -90 "#e0207a"}
            {"30mm"                 0.262 0.610 0.090 0.034 -90 "#e0207a"}
            {"1\"=mm (3 say 30mm)"  0.335 0.300 0.190 0.030 -90 "#e0207a"}
            {"via OKLAB, filter to just red" 0.610 0.560 0.230 0.030 -70 "#c81e63"}
            {"motion amplification" 0.740 0.470 0.170 0.030 -70 "#c81e63"}
            {"via differencing"     0.782 0.520 0.130 0.030 -70 "#c81e63"}
            {"8-frame-past"         0.812 0.560 0.110 0.030 -70 "#c81e63"}
        }
        shapes {
            {box        0.402 0.130 0.036 0.055 "#d81f6f" "box A"}
            {box        0.460 0.130 0.036 0.055 "#e08a2a" "box B"}
            {box        0.520 0.130 0.036 0.055 "#d81f6f" "box C"}
            {concentric 0.422 0.240 0.100 0.100 "#e0561f" "CAB frame"}
            {box        0.568 0.170 0.130 0.100 "#d81f6f" "separate-in panel"}
            {blob       0.470 0.430 0.120 0.150 "#c81e63" "circle-brush blob"}
            {face       0.505 0.560 0.050 0.070 "#c81e63" "brush smiley"}
            {arrow      0.560 0.230 0.080 0.070 "#d81f6f" "A/B/C feed"}
            {ring       0.150 0.720 0.070 0.110 "#e0207a" "thumb arch"}
        }
    }
    {
        file  "assets/note2.jpg"
        title "Note II · amplify \$color pixels"
        text {
            {"identify"                     0.430 0.290 0.100 0.048 0   "#2b3ba0"}
            {"red pixels"                   0.445 0.360 0.120 0.048 0   "#2b3ba0"}
            {"above"                        0.445 0.420 0.090 0.048 0   "#2b3ba0"}
            {"amplify \$color"              0.435 0.600 0.170 0.050 0   "#2b3ba0"}
            {"pixels"                       0.470 0.675 0.090 0.050 0   "#2b3ba0"}
            {"a weighted avg of"            0.690 0.300 0.150 0.034 -22 "#c02020"}
            {"first 16 pixels,"             0.705 0.375 0.130 0.034 -22 "#c02020"}
            {"end with-claim a color"       0.735 0.400 0.180 0.032 -22 "#c02020"}
            {"called 0xFCED22"             0.800 0.380 0.130 0.030 -25 "#c02020"}
            {"#Nobody"                      0.752 0.500 0.090 0.036 0   "#2b3ba0"}
            {"wishes to \$color pixels"     0.760 0.560 0.180 0.032 -20 "#2b3ba0"}
            {"#This is left-margined"       0.770 0.660 0.180 0.030 -30 "#2b3ba0"}
            {"3 In order to do my job"      0.780 0.780 0.180 0.030 -55 "#2b3ba0"}
            {"I need someone to"            0.822 0.820 0.150 0.028 -55 "#2b3ba0"}
            {"define #color with a claim"   0.855 0.860 0.190 0.028 -55 "#2b3ba0"}
        }
        shapes {
            {box   0.350 0.255 0.230 0.270 "#2b3ba0" "identify box"}
            {box   0.400 0.535 0.270 0.280 "#2b3ba0" "amplify box"}
            {box   0.628 0.165 0.060 0.090 "#c02020" "target square"}
            {arrow 0.610 0.230 0.090 0.110 "#c02020" "weighted-avg arrow"}
            {wave  0.150 0.180 0.045 0.560 "#2b3ba0" "margin wave"}
            {wave  0.230 0.200 0.045 0.520 "#2b3ba0" "margin wave"}
        }
    }
    {
        file  "assets/note3.jpg"
        title "Note III · Provenance"
        text {
            {"Provenance"               0.245 0.300 0.460 0.090 0   "#b0603a"}
            {"Prov"                     0.230 0.540 0.055 0.045 0   "#8a3a8a"}
            {"ena"                      0.238 0.590 0.045 0.040 0   "#8a3a8a"}
            {"nce"                      0.240 0.635 0.045 0.040 0   "#c05a1a"}
            {"provenance"               0.402 0.548 0.075 0.030 0   "#c81e63"}
            {"D"                        0.612 0.545 0.030 0.050 0   "#c81e63"}
            {"Provence"                 0.245 0.830 0.360 0.075 0   "#e0207a"}
            {"PNG"                      0.720 0.815 0.055 0.045 0   "#c81e63"}
            {"1"                        0.640 0.735 0.020 0.040 0   "#c81e63"}
            {"6"                        0.668 0.840 0.020 0.040 0   "#c81e63"}
            {"7"                        0.748 0.712 0.020 0.040 0   "#c81e63"}
            {"#finish #sketchpad"       0.795 0.270 0.170 0.030 -68 "#c02020"}
            {"is a+ image gula"         0.828 0.320 0.130 0.030 -68 "#c02020"}
            {"this deliberately excluded" 0.878 0.560 0.210 0.028 -80 "#c02020"}
            {"it has slick history"     0.905 0.520 0.150 0.028 -80 "#c02020"}
        }
        shapes {
            {ring       0.395 0.470 0.130 0.230 "#e0207a" "P/O bowl"}
            {ring       0.520 0.470 0.120 0.220 "#c81e63" "P/O bowl"}
            {concentric 0.560 0.460 0.110 0.200 "#c81e63" "D-in-squares"}
            {grid       0.700 0.500 0.120 0.160 "#c81e63" "PNG pixel grid"}
            {grid       0.590 0.740 0.100 0.150 "#c81e63" "PNG pixel grid"}
            {arrow      0.660 0.700 0.090 0.090 "#c81e63" "encode arrow"}
            {face       0.500 0.180 0.055 0.080 "#e0207a" "corner smiley"}
        }
    }
}

# =====================================================================
#  3+4. RUN THE PIPELINE
# =====================================================================
crc_init
proc slurp {path} {
    set fh [open $path rb]; set d [read $fh]; close $fh; return $d
}
proc esc {s} { string map {& &amp; < &lt; > &gt; \" &quot;} $s }

set panels {}      ;# HTML for each note panel
set totalShapes 0

foreach note $NOTES {
    array set N $note
    set jpg [slurp [file join $HERE $N(file)]]
    lassign [jpeg_dims $jpg] JW JH
    set aspect [expr {$JW>0 ? double($JW)/$JH : 16.0/9}]
    set bgb64 [b64enc $jpg]
    puts stderr "  \[ingest\] $N(file)  ${JW}x${JH}  jpeg=[string length $jpg]B"

    # ---- SVG selectable text, placed 1:1 over the handwriting ----
    set VW 1000.0
    set VH [expr {$VW / $aspect}]
    set svg "<svg class=\"ovl\" viewBox=\"0 0 [expr {int($VW)}] [expr {int($VH)}]\" preserveAspectRatio=\"none\" xmlns=\"http://www.w3.org/2000/svg\">"
    foreach t $N(text) {
        lassign $t str nx ny nw nh rot col
        set x [expr {$nx*$VW}]; set y [expr {$ny*$VH}]
        set fs [expr {$nh*$VH}]
        set tr ""
        if {$rot != 0} { set tr " transform=\"rotate($rot [format %.1f $x] [format %.1f $y])\"" }
        append svg "<text x=\"[format %.1f $x]\" y=\"[format %.1f $y]\" font-size=\"[format %.1f $fs]\" fill=\"$col\"$tr>[esc $str]</text>"
    }
    append svg "</svg>"

    # ---- platonic-shape PNG chips (from-scratch encoded) ----
    set chips ""
    foreach s $N(shapes) {
        lassign $s type nx ny nw nh col label
        set png [icon_render $type [hex2rgb $col]]
        set b64 [b64enc $png]
        incr totalShapes
        puts stderr "    \[raster\] $type ($label)  png=[string length $png]B"
        append chips \
          "<figure class=\"chip\">\
           <img alt=\"[esc $label]\" src=\"data:image/png;base64,$b64\">\
           <figcaption>[esc $label] · <span class=\"tag\">$type</span></figcaption>\
           <textarea readonly rows=\"2\" spellcheck=\"false\">data:image/png;base64,$b64</textarea>\
           <button class=\"copy\" onclick=\"cp(this)\">copy PNG</button>\
           </figure>"
    }

    append panels \
      "<section class=\"note\">\
         <header><h2>[esc $N(title)]</h2>\
           <span class=\"dim\">source ${JW}&times;${JH}px · [llength $N(shapes)] shapes · [llength $N(text)] tokens</span>\
         </header>\
         <div class=\"stage\" style=\"aspect-ratio:[format %.4f $aspect]\">\
            <div class=\"bg\" style=\"background-image:url('data:image/jpeg;base64,$bgb64')\"></div>\
            <div class=\"calcium\"></div>\
            $svg\
         </div>\
         <div class=\"tray\"><div class=\"tray-h\">salient platonic shapes · base64 PNG (click to copy)</div>\
            <div class=\"chips\">$chips</div></div>\
       </section>"
}

# ---------------------------------------------------------------------
#  HTML shell — calcium-blur CSS-3D, everything inlined, no network.
# ---------------------------------------------------------------------
set html "<!DOCTYPE html>
<html lang=\"en\">
<head>
<meta charset=\"UTF-8\">
<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
<title>Provenance · platonic-shape feature extraction</title>
<style>
  :root{
    --calcium: 0.5;                 /* Calcium Blur strength, default 50% */
    --bone: #efeade;
    --ink: #1a1622;
  }
  *{box-sizing:border-box}
  html,body{margin:0}
  body{
    background:
      radial-gradient(1200px 600px at 70% -10%, #fff, transparent),
      linear-gradient(160deg,#f6f3ec,#e7e1d3 60%,#d8d2c4);
    color:var(--ink);
    font:14px/1.5 ui-monospace,\"SF Mono\",Menlo,Consolas,monospace;
    padding:28px clamp(12px,4vw,60px) 80px;
  }
  header.top{max-width:1100px;margin:0 auto 22px}
  header.top h1{font-size:clamp(22px,4vw,40px);letter-spacing:-0.02em;margin:0 0 6px}
  header.top p{margin:2px 0;opacity:.75;max-width:70ch}
  .pill{display:inline-block;border:1px solid rgba(0,0,0,.25);border-radius:999px;
        padding:2px 10px;font-size:11px;margin-right:6px;background:rgba(255,255,255,.5)}
  .controls{max-width:1100px;margin:12px auto 26px;display:flex;gap:14px;align-items:center;flex-wrap:wrap}
  .controls label{font-size:12px;text-transform:uppercase;letter-spacing:.08em;opacity:.8}
  input\[type=range\]{accent-color:#c81e63}

  .note{max-width:1100px;margin:0 auto 46px}
  .note header{display:flex;justify-content:space-between;align-items:baseline;gap:12px;margin:0 0 10px;flex-wrap:wrap}
  .note h2{margin:0;font-size:clamp(16px,2.4vw,22px)}
  .note .dim{font-size:11px;opacity:.6}

  /* ---- CSS-3D stage: the note lives on a plane in perspective ---- */
  .stage{
    position:relative;width:100%;
    perspective:1400px;perspective-origin:50% 30%;
    border:1px solid rgba(0,0,0,.15);border-radius:10px;overflow:hidden;
    box-shadow:0 26px 60px -30px rgba(0,0,0,.55);
    transform-style:preserve-3d;background:#000;
  }
  /* the background image, pushed back in Z and Calcium-blurred */
  .stage .bg{
    position:absolute;inset:-6%;
    background-size:cover;background-position:center;
    transform:translateZ(-160px) scale(1.16) rotateX(3.5deg);
    transform-origin:50% 40%;
    filter:blur(calc(var(--calcium) * 12px)) saturate(.82) brightness(1.06) contrast(.96);
    will-change:filter,transform;
  }
  /* the \"calcium\" bloom — a bone-white deposit at 50% over the blur */
  .stage .calcium{
    position:absolute;inset:0;pointer-events:none;
    background:
      radial-gradient(120% 90% at 50% 20%, rgba(255,255,255,.9), rgba(239,234,222,.35) 45%, rgba(210,205,190,.05) 70%),
      linear-gradient(0deg, rgba(239,234,222,.5), rgba(239,234,222,.5));
    mix-blend-mode:soft-light;
    opacity:var(--calcium);
    transform:translateZ(-80px) scale(1.08);
  }
  /* SVG text overlay — the plane at Z=0, sitting 1:1 on the handwriting */
  .stage .ovl{
    position:absolute;inset:0;width:100%;height:100%;
    transform:translateZ(2px);
  }
  .stage .ovl text{
    font-family:ui-monospace,Menlo,Consolas,monospace;
    font-weight:600;
    dominant-baseline:text-before-edge;
    paint-order:stroke fill;
    stroke:rgba(255,255,255,.85);stroke-width:2.4px;
    -webkit-user-select:text;user-select:text;
    opacity:.92;
  }
  .stage .ovl text::selection{background:#c81e63;fill:#fff;color:#fff}

  /* ---- shape tray ---- */
  .tray{margin-top:14px}
  .tray-h{font-size:11px;text-transform:uppercase;letter-spacing:.08em;opacity:.6;margin-bottom:8px}
  .chips{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:12px}
  .chip{margin:0;background:rgba(255,255,255,.62);border:1px solid rgba(0,0,0,.14);
        border-radius:8px;padding:10px;display:flex;flex-direction:column;gap:7px}
  .chip img{width:100%;height:96px;object-fit:contain;image-rendering:auto;
            background:
              conic-gradient(#0000 90deg,#00000008 0 180deg,#0000 0 270deg,#00000008 0) 0 0/16px 16px;
            border-radius:5px}
  .chip figcaption{font-size:11px;line-height:1.3}
  .chip .tag{opacity:.6}
  .chip textarea{width:100%;font:10px/1.3 ui-monospace,monospace;resize:vertical;
                 border:1px solid rgba(0,0,0,.16);border-radius:5px;padding:5px;background:#fbfaf7;color:#333}
  .chip .copy{border:1px solid rgba(0,0,0,.25);background:#fff;border-radius:5px;padding:6px;
              cursor:pointer;font:inherit;font-size:11px;text-transform:uppercase;letter-spacing:.05em}
  .chip .copy:hover{background:var(--ink);color:#fff}
  footer{max-width:1100px;margin:40px auto 0;font-size:11px;opacity:.55}
  code{background:rgba(0,0,0,.06);padding:1px 5px;border-radius:4px}
</style>
</head>
<body>
  <header class=\"top\">
    <h1>Provenance — platonic-shape feature extraction</h1>
    <p><span class=\"pill\">pure Tcl pipeline</span><span class=\"pill\">no dependencies</span><span class=\"pill\">no network</span><span class=\"pill\">$totalShapes shapes rasterized</span></p>
    <p>Three field notes run through a from-scratch Tcl pipeline: real JPEG dimensions parsed from file bytes, salient shapes re-drawn as <em>platonic</em> RGBA rasters and hand-encoded to base64 PNG (from-scratch DEFLATE / Adler-32 / CRC-32 / Base64), and selectable SVG text laid 1:1 over the ink. Backgrounds wear a <b>Calcium&nbsp;Blur</b> on a CSS-3D plane.</p>
  </header>
  <div class=\"controls\">
    <label for=\"cal\">Calcium&nbsp;Blur</label>
    <input id=\"cal\" type=\"range\" min=\"0\" max=\"100\" value=\"50\">
    <output id=\"calv\">50%</output>
  </div>
  $panels
  <footer>
    Generated by <code>provenance/extract.tcl</code> · Calcium&nbsp;Blur = Gaussian blur + bone-white bloom, driven in CSS 3D · select the SVG text, or click any chip to copy its base64 PNG.
  </footer>
<script>
  // click-to-copy for the base64 PNG chips
  function cp(btn){
    var ta = btn.parentNode.querySelector('textarea');
    ta.focus(); ta.select();
    var done = function(){ btn.textContent='copied ✓'; setTimeout(function(){btn.textContent='copy PNG';},1000); };
    if(navigator.clipboard && navigator.clipboard.writeText){
      navigator.clipboard.writeText(ta.value).then(done, function(){ document.execCommand('copy'); done(); });
    } else { document.execCommand('copy'); done(); }
  }
  // Calcium Blur strength -> CSS var (blur px + bloom opacity scale together)
  var cal = document.getElementById('cal'), calv = document.getElementById('calv');
  cal.addEventListener('input', function(){
    var v = cal.value/100;
    document.documentElement.style.setProperty('--calcium', v);
    calv.textContent = cal.value + '%';
  });
</script>
</body>
</html>"

set outp [file join $HERE index.html]
set fh [open $outp w]; puts -nonewline $fh $html; close $fh
puts stderr "\[compose\] wrote $outp  ([string length $html] bytes, $totalShapes shape PNGs)"
