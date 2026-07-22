#!/usr/bin/env wish
# ---------------------------------------------------------------------------
# Broiderspiel — Tcl/Tk port
#
# A faithful port of the WebGL toy: a symmetric "broider" embroidery stitched
# into the outer 4% frame, with a "sandspiel" falling-sand cellular automaton
# (sand, water, wood, plant, fire, smoke, stone) in the central 84% box.
#
# Tk has no shader / GPU pipeline, so this port is deliberately IMMEDIATE MODE
# on the CPU: every frame we recompute the whole framebuffer and blit it into a
# single Tk `photo` image with one `$img put`. That is exactly the retained-vs-
# immediate contrast the accompanying book essay draws out — here the "widget"
# is a raw pixel buffer we repaint from scratch, HyperCard-style, every tick.
#
#   drag           paint the current element
#   1..6           choose element (sand water wood plant fire stone)
#   space          pause / resume
#   d              toggle the debug FPS sparkline (bottom 10% overlay)
#   double-click   pause + save a PNG ("share") to the working directory
#   q              quit
#
# Headless capture (used by the build to make book figures):
#   xvfb-run -a wish broiderspiel.tcl --frames 400 --debug --out shot.png
# ---------------------------------------------------------------------------
package require Tk

# ---- config / cli ---------------------------------------------------------
set CFG(win_w)      720
set CFG(win_h)      480
set CFG(target_long) 120       ;# cells on the longer axis
set CFG(border_frac) 0.04
set CFG(inner_frac)  0.84
set CFG(batch_frames) 0        ;# >0 => run headless then write --out and exit
set CFG(out)        "broiderspiel.png"
set DBG 0
for {set a 0} {$a < [llength $argv]} {incr a} {
    switch -- [lindex $argv $a] {
        --frames { set CFG(batch_frames) [lindex $argv [incr a]] }
        --out    { set CFG(out) [lindex $argv [incr a]] }
        --debug  { set DBG 1 }
        --size   { set CFG(win_w) [lindex $argv [incr a]]; set CFG(win_h) [lindex $argv [incr a]] }
    }
}

# ---- element ids ----------------------------------------------------------
set EMPTY 0; set WALL 1; set SAND 2; set WATER 3
set WOOD 4;  set PLANT 5; set FIRE 6; set SMOKE 7; set STONE 8
set BRUSHES [list $SAND $WATER $WOOD $PLANT $FIRE $STONE]
set brush 0

# ---- grid geometry --------------------------------------------------------
set cell [expr {int(ceil(double(max($CFG(win_w),$CFG(win_h)))/$CFG(target_long)))}]
if {$cell < 1} {set cell 1}
set W [expr {$CFG(win_w)/$cell}]
set H [expr {$CFG(win_h)/$cell}]
set N [expr {$W*$H}]
set bandX [expr {max(1,int(round($CFG(border_frac)*$W)))}]
set bandY [expr {max(1,int(round($CFG(border_frac)*$H)))}]
set mx [expr {int(round((1.0-$CFG(inner_frac))/2.0*$W))}]
set my [expr {int(round((1.0-$CFG(inner_frac))/2.0*$H))}]
set ix0 $mx; set ix1 [expr {$W-1-$mx}]
set iy0 $my; set iy1 [expr {$H-1-$my}]

# ---- state buffers (flat lists, row-major) --------------------------------
set type  [lrepeat $N 0]
set life  [lrepeat $N 0]
set noise [lrepeat $N 0]
for {set i 0} {$i < $N} {incr i} { lset noise $i [expr {int(rand()*256)}] }

# persistent broider colours, one hex per cell (only border cells are used)
set BG "#0c0c14"
set bcol [lrepeat $N $BG]

proc idx {x y} { global W; return [expr {$y*$W+$x}] }
proc inbox {x y} { global ix0 ix1 iy0 iy1; expr {$x>=$ix0 && $x<=$ix1 && $y>=$iy0 && $y<=$iy1} }
proc isborder {x y} { global W H bandX bandY; expr {$x<$bandX || $x>=$W-$bandX || $y<$bandY || $y>=$H-$bandY} }

# ---- colour lookup --------------------------------------------------------
# precompute 4 shade variants per element so the sand/wood/etc. get texture
# without per-frame math. fire & smoke are gradient-by-life, computed inline.
proc hx {r g b} {
    if {$r<0} {set r 0}; if {$r>255} {set r 255}
    if {$g<0} {set g 0}; if {$g>255} {set g 255}
    if {$b<0} {set b 0}; if {$b>255} {set b 255}
    format "#%02x%02x%02x" [expr {int($r)}] [expr {int($g)}] [expr {int($b)}]
}
set LUT [dict create]
foreach {t base} [list \
        $EMPTY {12 12 20} $WALL {80 84 96} $STONE {104 104 112} \
        $SAND {198 176 88} $WATER {40 96 200} $WOOD {110 66 38} \
        $PLANT {46 150 60}] {
    lassign $base r g b
    for {set k 0} {$k < 4} {incr k} {
        set d [expr {($k-1)*10}]
        dict set LUT $t,$k [hx [expr {$r+$d}] [expr {$g+$d}] [expr {$b+$d}]]
    }
}
proc cellhex {i} {
    global type life noise LUT BG
    set t [lindex $type $i]
    if {$t==0} { return $BG }
    switch -- $t {
        6 { set f [expr {min(1.0,[lindex $life $i]/40.0)}]
            return [hx 255 [expr {90+$f*150}] [expr {20+$f*60}]] }   ;# FIRE
        7 { set f [expr {min(1.0,[lindex $life $i]/30.0)}]
            set c [expr {60+$f*45}]; return [hx $c $c [expr {$c+6}]] } ;# SMOKE
        default {
            set k [expr {[lindex $noise $i]&3}]
            return [dict get $LUT $t,$k]
        }
    }
}

# ---- seeding --------------------------------------------------------------
proc seed {} {
    global type ix0 ix1 iy1 iy0 PLANT bcol W H bandX bandY isb walkers
    for {set x $ix0} {$x <= $ix1} {incr x} {
        if {rand() < 0.55} { lset type [idx $x $iy1] $PLANT
            if {rand() < 0.4 && $iy1-1 >= $iy0} { lset type [idx $x [expr {$iy1-1}]] $PLANT } }
    }
    # broider walkers: top-edge (roam x) + left-edge (roam y); 4-fold mirrored
    set walkers {}
    for {set i 0} {$i < 3} {incr i} {
        lappend walkers [dict create edge top x [expr {rand()*$W}] y [expr {rand()*$bandY}] \
            vx [expr {(rand()<0.5?-1:1)*(0.6+rand())}] hue [expr {rand()}] dh [expr {0.002+rand()*0.004}]]
        lappend walkers [dict create edge left x [expr {rand()*$bandX}] y [expr {rand()*$H}] \
            vy [expr {(rand()<0.5?-1:1)*(0.6+rand())}] hue [expr {rand()}] dh [expr {0.002+rand()*0.004}]]
    }
}

# hsv->hex for broider
proc hsvhex {h s v} {
    set h [expr {fmod(fmod($h,1.0)+1.0,1.0)}]
    set i [expr {int($h*6)}]; set f [expr {$h*6-$i}]
    set p [expr {$v*(1-$s)}]; set q [expr {$v*(1-$f*$s)}]; set t [expr {$v*(1-(1-$f)*$s)}]
    switch [expr {$i%6}] {
        0 {set r $v; set g $t; set b $p}
        1 {set r $q; set g $v; set b $p}
        2 {set r $p; set g $v; set b $t}
        3 {set r $p; set g $q; set b $v}
        4 {set r $t; set g $p; set b $v}
        default {set r $v; set g $p; set b $q}
    }
    hx [expr {$r*255}] [expr {$g*255}] [expr {$b*255}]
}

# ---- sandspiel step -------------------------------------------------------
proc swap {a b} { global type life
    set t [lindex $type $a]; lset type $a [lindex $type $b]; lset type $b $t
    set l [lindex $life $a]; lset life $a [lindex $life $b]; lset life $b $l
}
proc emit {x y t} { global type; if {[inbox $x $y]} { set i [idx $x $y]
    if {[lindex $type $i]==0} { lset type $i $t } } }

proc stepSand {} {
    global type life W H ix0 ix1 iy0 iy1 frame EMPTY SAND WATER WOOD PLANT FIRE SMOKE STONE
    set bw [expr {$ix1-$ix0}]
    if {$frame%2==0}  { emit [expr {$ix0+int($bw*0.32)}] [expr {$iy0+1}] $SAND }
    if {$frame%3==0}  { emit [expr {$ix0+int($bw*0.68)}] [expr {$iy0+1}] $WATER }
    if {$frame%220==0} { set i [idx [expr {$ix0+int($bw*0.5)}] [expr {$iy0+1}]]
                         lset type $i $FIRE; lset life $i 40 }
    for {set y $iy1} {$y >= $iy0} {incr y -1} {
        set l2r [expr {(($frame+$y)&1)==0}]
        for {set k 0} {$k <= $ix1-$ix0} {incr k} {
            set x [expr {$l2r ? $ix0+$k : $ix1-$k}]
            set i [expr {$y*$W+$x}]
            set t [lindex $type $i]
            if {$t==0 || $t==1 || $t==$STONE || $t==$WOOD} continue
            if {$t==$SAND} {
                set d [expr {$i+$W}]
                if {$y<$iy1} { set td [lindex $type $d]
                    if {$td==0||$td==$WATER} { swap $i $d; continue } }
                set dir [expr {rand()<0.5?1:-1}]
                if {$y<$iy1} {
                    if {[inbox [expr {$x+$dir}] [expr {$y+1}]]} { set td [lindex $type [expr {$d+$dir}]]
                        if {$td==0||$td==$WATER} { swap $i [expr {$d+$dir}]; continue } }
                    if {[inbox [expr {$x-$dir}] [expr {$y+1}]]} { set td [lindex $type [expr {$d-$dir}]]
                        if {$td==0||$td==$WATER} { swap $i [expr {$d-$dir}]; continue } }
                }
            } elseif {$t==$WATER} {
                set d [expr {$i+$W}]
                if {$y<$iy1 && [lindex $type $d]==0} { swap $i $d; continue }
                set dir [expr {rand()<0.5?1:-1}]
                if {$y<$iy1} {
                    if {[inbox [expr {$x+$dir}] [expr {$y+1}]] && [lindex $type [expr {$d+$dir}]]==0} { swap $i [expr {$d+$dir}]; continue }
                    if {[inbox [expr {$x-$dir}] [expr {$y+1}]] && [lindex $type [expr {$d-$dir}]]==0} { swap $i [expr {$d-$dir}]; continue }
                }
                if {[inbox [expr {$x+$dir}] $y] && [lindex $type [expr {$i+$dir}]]==0} { swap $i [expr {$i+$dir}]; continue }
                if {[inbox [expr {$x-$dir}] $y] && [lindex $type [expr {$i-$dir}]]==0} { swap $i [expr {$i-$dir}]; continue }
            } elseif {$t==$FIRE} {
                lset life $i [expr {[lindex $life $i]-1}]
                set ext 0
                foreach {nx ny nb} [list $x [expr {$y-1}] [expr {$i-$W}] $x [expr {$y+1}] [expr {$i+$W}] \
                                        [expr {$x-1}] $y [expr {$i-1}] [expr {$x+1}] $y [expr {$i+1}]] {
                    if {![inbox $nx $ny]} continue
                    set nt [lindex $type $nb]
                    if {($nt==$WOOD||$nt==$PLANT) && rand()<0.28} { lset type $nb $FIRE; lset life $nb [expr {22+int(rand()*22)}] } \
                    elseif {$nt==$WATER} { set ext 1 }
                }
                if {$ext} { lset type $i $SMOKE; lset life $i 26; continue }
                if {[lindex $life $i] <= 0} { lset type $i [expr {rand()<0.5?$SMOKE:$EMPTY}]; lset life $i 30; continue }
                set u [expr {$i-$W}]
                if {$y>$iy0 && [lindex $type $u]==0 && rand()<0.4} { swap $i $u; continue }
            } elseif {$t==$SMOKE} {
                lset life $i [expr {[lindex $life $i]-1}]
                if {[lindex $life $i] <= 0} { lset type $i $EMPTY; lset life $i 0; continue }
                set u [expr {$i-$W}]; set dir [expr {rand()<0.5?1:-1}]
                if {$y>$iy0} {
                    if {[lindex $type $u]==0} { swap $i $u; continue }
                    if {[inbox [expr {$x+$dir}] [expr {$y-1}]] && [lindex $type [expr {$u+$dir}]]==0} { swap $i [expr {$u+$dir}]; continue }
                    if {[inbox [expr {$x-$dir}] [expr {$y-1}]] && [lindex $type [expr {$u-$dir}]]==0} { swap $i [expr {$u-$dir}]; continue }
                }
            } elseif {$t==$PLANT} {
                if {rand()<0.12} {
                    set wated -1; set empt -1
                    foreach {nx ny nb} [list $x [expr {$y-1}] [expr {$i-$W}] $x [expr {$y+1}] [expr {$i+$W}] \
                                            [expr {$x-1}] $y [expr {$i-1}] [expr {$x+1}] $y [expr {$i+1}]] {
                        if {![inbox $nx $ny]} continue
                        set nt [lindex $type $nb]
                        if {$nt==$WATER} { set wated $nb } elseif {$nt==$EMPTY} { set empt $nb }
                    }
                    if {$wated>=0 && $empt>=0} { lset type $empt $PLANT
                        if {rand()<0.5} { lset type $wated $EMPTY } }
                }
            }
        }
    }
}

# ---- broider step ---------------------------------------------------------
proc stepBroider {} {
    global walkers bcol W H bandX bandY frame BG
    if {$frame%4==0} {
        # gentle fade of border cells toward BG (parse hex, lerp, reformat)
        for {set y 0} {$y < $H} {incr y} {
            for {set x 0} {$x < $W} {incr x} {
                if {![isborder $x $y]} continue
                set i [idx $x $y]; set c [lindex $bcol $i]
                if {$c eq $BG} continue
                scan $c "#%02x%02x%02x" r g b
                lset bcol $i [hx [expr {$r+(12-$r)*0.05}] [expr {$g+(12-$g)*0.05}] [expr {$b+(20-$b)*0.05}]]
            }
        }
    }
    set new {}
    foreach w $walkers {
        dict set w hue [expr {fmod([dict get $w hue]+[dict get $w dh],1.0)}]
        set col [hsvhex [dict get $w hue] [expr {0.65+rand()*0.25}] 0.95]
        if {[dict get $w edge] eq "top"} {
            dict set w x [expr {[dict get $w x]+[dict get $w vx]}]
            dict set w y [expr {[dict get $w y]+(rand()-0.5)*0.9}]
            if {[dict get $w x]<0} { dict set w x 0; dict set w vx [expr {abs([dict get $w vx])}] }
            if {[dict get $w x]>$W-1} { dict set w x [expr {$W-1}]; dict set w vx [expr {-abs([dict get $w vx])}] }
            if {[dict get $w y]<0} { dict set w y 0 }
            if {[dict get $w y]>$bandY-1} { dict set w y [expr {$bandY-1}] }
        } else {
            dict set w y [expr {[dict get $w y]+[dict get $w vy]}]
            dict set w x [expr {[dict get $w x]+(rand()-0.5)*0.9}]
            if {[dict get $w y]<0} { dict set w y 0; dict set w vy [expr {abs([dict get $w vy])}] }
            if {[dict get $w y]>$H-1} { dict set w y [expr {$H-1}]; dict set w vy [expr {-abs([dict get $w vy])}] }
            if {[dict get $w x]<0} { dict set w x 0 }
            if {[dict get $w x]>$bandX-1} { dict set w x [expr {$bandX-1}] }
        }
        stitch [expr {int([dict get $w x])}] [expr {int([dict get $w y])}] $col
        lappend new $w
    }
    set walkers $new
}
proc stitch {x y col} {
    global bcol W H
    foreach {px py} [list $x $y [expr {$W-1-$x}] $y $x [expr {$H-1-$y}] [expr {$W-1-$x}] [expr {$H-1-$y}]] {
        for {set o -1} {$o <= 1} {incr o} {
            set a [expr {$px+$o}]
            if {$a>=0 && $a<$W && $py>=0 && $py<$H && [isborder $a $py]} { lset bcol [idx $a $py] $col }
            set b2 [expr {$py+$o}]
            if {$px>=0 && $px<$W && $b2>=0 && $b2<$H && [isborder $px $b2]} { lset bcol [idx $px $b2] $col }
        }
    }
}

# ---- fps history + sparkline ----------------------------------------------
set fps_hist {}
set FPS_CAP 4096
set last_ms [clock milliseconds]
proc recordFps {} {
    global fps_hist FPS_CAP last_ms
    set now [clock milliseconds]; set dt [expr {$now-$last_ms}]; set last_ms $now
    if {$dt<=0} return
    lappend fps_hist [expr {min(1000.0, 1000.0/$dt)}]
    if {[llength $fps_hist] >= $FPS_CAP*2} {
        set half {}
        for {set i 0} {$i < $FPS_CAP} {incr i} {
            lappend half [expr {([lindex $fps_hist [expr {$i*2}]]+[lindex $fps_hist [expr {$i*2+1}]])*0.5}]
        }
        set fps_hist $half
    }
}
# blend an overlay colour into a base hex at alpha a -> hex
proc blendhex {base r g b a} {
    scan $base "#%02x%02x%02x" br bg bb
    set ia [expr {1.0-$a}]
    hx [expr {$br*$ia+$r*$a}] [expr {$bg*$ia+$g*$a}] [expr {$bb*$ia+$b*$a}]
}

# ---- assemble one frame of hex rows and blit ------------------------------
proc renderRows {} {
    global W H type ix0 ix1 iy0 iy1 bcol BG DBG fps_hist
    set bandH [expr {max(3,int(round($H*0.10)))}]
    set y0 [expr {$H-$bandH}]
    # precompute sparkline column heights (compress entire history to W cols)
    set spark {}
    if {$DBG} {
        set n [llength $fps_hist]
        set mxv 60.0
        foreach v $fps_hist { if {$v>$mxv} {set mxv $v} }
        for {set x 0} {$x < $W} {incr x} {
            if {$n==0} { lappend spark $H; continue }
            set a [expr {int($x*$n/$W)}]; set bb [expr {max($a+1,int(($x+1)*$n/$W))}]
            set s 0.0; set c 0
            for {set j $a} {$j < $bb && $j < $n} {incr j} { set s [expr {$s+[lindex $fps_hist $j]}]; incr c }
            set avg [expr {$c? $s/$c : [lindex $fps_hist end]}]
            lappend spark [expr {int(round(($H-1)-($bandH-1)*($avg<$mxv?$avg/$mxv:1.0)))}]
        }
    }
    set rows {}
    for {set y 0} {$y < $H} {incr y} {
        set r {}
        set inbandrow [expr {$DBG && $y>=$y0}]
        for {set x 0} {$x < $W} {incr x} {
            set i [expr {$y*$W+$x}]
            if {$x>=$ix0 && $x<=$ix1 && $y>=$iy0 && $y<=$iy1} {
                set hexc [cellhex $i]
            } else {
                set hexc [lindex $bcol $i]
            }
            if {$inbandrow} {
                set hexc [blendhex $hexc 0 0 0 0.35]
                set top [lindex $spark $x]
                if {$y>=$top} { set hexc [blendhex $hexc 40 230 120 0.5] }
            }
            lappend r $hexc
        }
        lappend rows $r
    }
    return $rows
}

# ---- UI / main loop -------------------------------------------------------
set frame 0
set paused 0
set running 1

if {$CFG(batch_frames) > 0} {
    # headless: no widgets needed, just churn frames into an offscreen photo
    set img [image create photo -width $W -height $H]
    seed
    # render every frame so the recorded FPS reflects true per-frame cost
    for {set f 0} {$f < $CFG(batch_frames)} {incr f} {
        recordFps; stepSand; stepBroider; incr frame
        if {$f % 3 == 0 || $f >= $CFG(batch_frames)-1} { $img put [renderRows] }
    }
    $img put [renderRows]
    # upscale x4 for a crisper figure
    set big [image create photo -width [expr {$W*4}] -height [expr {$H*4}]]
    $big copy $img -zoom 4
    $big write $CFG(out) -format png
    puts "wrote $CFG(out) (${W}x${H} grid, [llength $fps_hist] fps samples)"
    exit 0
}

wm title . "Broiderspiel — Tcl/Tk"
set img [image create photo -width $W -height $H]
label .c -image $img -bd 0
pack .c -fill both -expand 1
# scale the label's photo to the window via a zoomed display photo
set disp [image create photo -width $CFG(win_w) -height $CFG(win_h)]
.c configure -image $disp
set ZOOM $cell

proc paintAt {sx sy} {
    global disp img cell type life W H brush BRUSHES FIRE
    set gx [expr {int($sx/$cell)}]; set gy [expr {int($sy/$cell)}]
    set t [lindex $BRUSHES $brush]
    set rr [expr {$t==$FIRE?1:2}]
    for {set dy [expr {-$rr}]} {$dy<=$rr} {incr dy} {
        for {set dx [expr {-$rr}]} {$dx<=$rr} {incr dx} {
            set x [expr {$gx+$dx}]; set y [expr {$gy+$dy}]
            if {[inbox $x $y]} { set i [idx $x $y]; lset type $i $t; if {$t==$FIRE} { lset life $i 40 } }
        }
    }
}
bind . <B1-Motion>   {paintAt %x %y}
bind . <ButtonPress-1> {paintAt %x %y}
bind . <Double-1>    {savePng}
bind . <KeyPress-space> {set ::paused [expr {!$::paused}]}
bind . <KeyPress-d>  {set ::DBG [expr {!$::DBG}]}
bind . <KeyPress-q>  {set ::running 0; destroy .}
foreach n {1 2 3 4 5 6} { bind . <KeyPress-$n> "set ::brush [expr {$n-1}]" }

proc savePng {} {
    global img disp
    set ::paused 1
    set fn "broiderspiel-[clock seconds].png"
    $disp write $fn -format png
    wm title . "Broiderspiel — saved $fn (paused)"
    # A desktop build could hand $fn to xdg-open / a share sheet here.
}

seed
proc tick {} {
    global running paused DBG frame img disp cell
    if {!$running} return
    recordFps
    if {!$paused} { stepSand; stepBroider; incr frame }
    $img put [renderRows]
    $disp copy $img -zoom $cell
    after 16 tick
}
tick
