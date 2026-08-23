#!/usr/bin/env tclsh
# ============================================================================
#  synth.tcl -- the score.
#
#  Pure Tcl.  No sound library, no external synth, no MIDI file.  Wavetables,
#  envelopes, the arpeggiator, the hi-hat voice, the stereo bus and the RIFF
#  writer are all built here out of expr and binary format.
#
#  It reads the per-frame analysis emitted by pcav and turns it into audio:
#
#     camera velocity  -> arpeggiated "Nickelodeon" keyboard
#                         (octave, density, thickness, loudness)
#     shadow change    -> synth hi-hat (closed / open, accent)
#     plant centroid X -> stereo position of the keyboard
#
#  usage: tclsh synth.tcl metrics.tsv ambience.raw out.wav
# ============================================================================

set SR       44100
set BPM      126.0
set AMB_GAIN 0.13          ;# original location sound, tucked underneath

lassign $argv METRICS AMBIENCE OUTWAV
if {$OUTWAV eq ""} { puts stderr "usage: synth.tcl metrics.tsv ambience.raw out.wav"; exit 1 }

# ---------------------------------------------------------------------------
#  1.  Load the analysis
# ---------------------------------------------------------------------------
set fh [open $METRICS r]
set header [split [string trim [gets $fh]] \t]
set col {}
set ci 0
foreach h $header { dict set col $h $ci; incr ci }
set M {}
while {[gets $fh line] >= 0} {
    if {[string trim $line] eq ""} continue
    lappend M [split $line \t]
}
close $fh
set NFRAMES [llength $M]
proc mv {row name} {
    global col
    lindex $row [dict get $col $name]
}
set DURATION [expr {[mv [lindex $M end] time] + 0.2}]
puts stderr "  synth: $NFRAMES frames, [format %.2f $DURATION]s"

# normalising statistics -- the mapping adapts to this clip, not to constants
proc stats {M name} {
    set n 0; set s 0.0; set mx 0.0; set vals {}
    foreach r $M { set v [expr {double([mv $r $name])}]; lappend vals $v
                   set s [expr {$s+$v}]; incr n; if {$v>$mx} {set mx $v} }
    set mean [expr {$n?$s/$n:0}]
    set q 0.0
    foreach v $vals { set d [expr {$v-$mean}]; set q [expr {$q+$d*$d}] }
    set sd [expr {$n>1?sqrt($q/($n-1)):0}]
    set srt [lsort -real $vals]
    set p90 [lindex $srt [expr {int($n*0.90)}]]
    list $mean $sd $mx $p90
}
lassign [stats $M camMag]       CAM_MEAN CAM_SD CAM_MAX CAM_P90
lassign [stats $M localEnergy]  LOC_MEAN LOC_SD LOC_MAX LOC_P90
lassign [stats $M shadowChange] SHD_MEAN SHD_SD SHD_MAX SHD_P90
puts stderr [format "  synth: cam mean %.2f p90 %.2f | shadow mean %.4f p90 %.4f" \
             $CAM_MEAN $CAM_P90 $SHD_MEAN $SHD_P90]

proc frameAt {t} {
    global M NFRAMES
    set i [expr {int($t*30000.0/1001.0)}]
    if {$i<0} {set i 0}
    if {$i>=$NFRAMES} {set i [expr {$NFRAMES-1}]}
    lindex $M $i
}

# ---------------------------------------------------------------------------
#  2.  Wavetables -- one cycle each, built by hand
# ---------------------------------------------------------------------------
set TL 1024
set TSQ {}; set TSAW {}; set TTRI {}; set TSIN {}
for {set i 0} {$i<$TL} {incr i} {
    set p [expr {double($i)/$TL}]
    lappend TSQ  [expr {$p < 0.44 ? 1.0 : -1.0}]           ;# 44% duty, hollow
    lappend TSAW [expr {2.0*$p - 1.0}]
    lappend TTRI [expr {$p<0.5 ? (4.0*$p-1.0) : (3.0-4.0*$p)}]
    lappend TSIN [expr {sin(6.283185307179586*$p)}]
}
# The "mixed keyboard": a hollow square for the cartoon bite, a saw for body,
# a triangle to round the top.  Band-limited the cheap way -- the triangle
# dominates up high, so aliasing stays under the mix.
set TKEY {}
for {set i 0} {$i<$TL} {incr i} {
    lappend TKEY [expr {0.46*[lindex $TSQ $i] + 0.26*[lindex $TSAW $i]
                        + 0.34*[lindex $TTRI $i]}]
}
# Bell layer for the top octave accents
set TBELL {}
for {set i 0} {$i<$TL} {incr i} {
    set p [expr {double($i)/$TL}]
    lappend TBELL [expr {0.70*sin(6.283185307179586*$p)
                       + 0.22*sin(6.283185307179586*$p*3.0)
                       + 0.10*sin(6.283185307179586*$p*5.0)}]
}

set NSAMP [expr {int($DURATION*$SR)+$SR/2}]
set BUFL [lrepeat $NSAMP 0.0]
set BUFR [lrepeat $NSAMP 0.0]

proc midi2freq {m} { expr {440.0*pow(2.0,($m-69.0)/12.0)} }

# ---------------------------------------------------------------------------
#  3.  Voices
# ---------------------------------------------------------------------------

# Two detuned wavetable oscillators, 4 ms attack, exponential decay, and a
# short downward pitch blip on the attack -- the plastic-keyboard "chirp".
proc keyVoice {tblName t0 dur freq amp panL panR {bellMix 0.0}} {
    global SR TL BUFL BUFR NSAMP TBELL
    upvar #0 $tblName TBL
    set n0 [expr {int($t0*$SR)}]
    set n  [expr {int($dur*$SR)}]
    if {$n0<0} {set n0 0}
    if {$n0+$n > $NSAMP} { set n [expr {$NSAMP-$n0}] }
    if {$n<=0} return

    set inc1 [expr {$freq*double($TL)/$SR}]
    set inc2 [expr {$freq*1.0041*double($TL)/$SR}]   ;# +7 cents detune
    set ph1 0.0
    set ph2 [expr {$TL*0.37}]
    set atk [expr {int(0.004*$SR)+1}]
    set dec [expr {$n-$atk}]
    if {$dec<1} {set dec 1}
    set dk  [expr {pow(0.0016,1.0/$dec)}]            ;# to -56 dB over the note
    set env 0.0
    set blip [expr {int(0.020*$SR)}]
    set useBell [expr {$bellMix>0.001}]
    set fc [expr {$freq*7.5}]
    if {$fc>8200.0} {set fc 8200.0}
    if {$fc<450.0}  {set fc 450.0}
    set lpBase [expr {1.0-exp(-6.283185307179586*$fc/$SR)}]
    set lp 0.0

    for {set i 0} {$i<$n} {incr i} {
        if {$i<$atk} { set env [expr {$env+1.0/$atk}] } else { set env [expr {$env*$dk}] }
        set b1 [expr {int($ph1)}]
        set b2 [expr {int($ph2)}]
        set s [expr {0.62*[lindex $TBL $b1] + 0.38*[lindex $TBL $b2]}]
        if {$useBell} { set s [expr {$s*(1.0-$bellMix) + $bellMix*[lindex $TBELL $b1]}] }
        set k1 [expr {$lpBase*(0.52+0.48*$env)}]      ;# cutoff follows the env
        set lp [expr {$lp+$k1*($s-$lp)}]
        set v [expr {$lp*$env*$amp*1.35}]
        set k [expr {$n0+$i}]
        lset BUFL $k [expr {[lindex $BUFL $k]+$v*$panL}]
        lset BUFR $k [expr {[lindex $BUFR $k]+$v*$panR}]
        # pitch blip: start ~3% sharp, settle within 20 ms
        if {$i<$blip} {
            set bend [expr {1.0+0.030*(1.0-double($i)/$blip)}]
            set ph1 [expr {fmod($ph1+$inc1*$bend,$TL)}]
            set ph2 [expr {fmod($ph2+$inc2*$bend,$TL)}]
        } else {
            set ph1 [expr {fmod($ph1+$inc1,$TL)}]
            set ph2 [expr {fmod($ph2+$inc2,$TL)}]
        }
    }
}

# Synth hi-hat: LCG noise through a one-pole high-pass, plus two inharmonic
# square partials for the metal.  Decay length sets closed vs open.
set HAT_SEED 20250823
proc hatVoice {t0 dur amp {tone 1.0}} {
    global SR BUFL BUFR NSAMP HAT_SEED TSQ TL
    set n0 [expr {int($t0*$SR)}]
    set n  [expr {int($dur*$SR)}]
    if {$n0<0} {set n0 0}
    if {$n0+$n > $NSAMP} { set n [expr {$NSAMP-$n0}] }
    if {$n<=0} return
    set dk [expr {pow(0.0009,1.0/$n)}]
    set env 1.0
    set prevX 0.0
    set y 0.0
    set a 0.86
    set f1 [expr {8300.0*$tone}]; set f2 [expr {11700.0*$tone}]
    set i1 [expr {$f1*double($TL)/$SR}]; set i2 [expr {$f2*double($TL)/$SR}]
    set p1 0.0; set p2 [expr {$TL*0.5}]
    for {set i 0} {$i<$n} {incr i} {
        set HAT_SEED [expr {($HAT_SEED*1103515245+12345) & 0x7fffffff}]
        set x [expr {double($HAT_SEED%20001)/10000.0-1.0}]
        set y [expr {$a*($y+$x-$prevX)}]          ;# one-pole high-pass
        set prevX $x
        set m [expr {0.30*([lindex $TSQ [expr {int($p1)}]]
                         + [lindex $TSQ [expr {int($p2)}]])}]
        set v [expr {(0.76*$y+0.24*$m)*$env*$amp}]
        set k [expr {$n0+$i}]
        lset BUFL $k [expr {[lindex $BUFL $k]+$v*0.62}]
        lset BUFR $k [expr {[lindex $BUFR $k]+$v*0.78}]   ;# hats sit right
        set env [expr {$env*$dk}]
        set p1 [expr {fmod($p1+$i1,$TL)}]
        set p2 [expr {fmod($p2+$i2,$TL)}]
    }
}

# Soft sine root under the chord, so the arp has a floor to sit on
proc bassVoice {t0 dur freq amp} {
    global SR TL TSIN BUFL BUFR NSAMP
    set n0 [expr {int($t0*$SR)}]
    set n  [expr {int($dur*$SR)}]
    if {$n0+$n > $NSAMP} { set n [expr {$NSAMP-$n0}] }
    if {$n<=0} return
    set inc [expr {$freq*double($TL)/$SR}]
    set ph 0.0
    set atk [expr {int(0.012*$SR)+1}]
    set dk [expr {pow(0.02,1.0/$n)}]
    set env 0.0
    for {set i 0} {$i<$n} {incr i} {
        if {$i<$atk} { set env [expr {$env+1.0/$atk}] } else { set env [expr {$env*$dk}] }
        set v [expr {[lindex $TSIN [expr {int($ph)}]]*$env*$amp}]
        set k [expr {$n0+$i}]
        lset BUFL $k [expr {[lindex $BUFL $k]+$v}]
        lset BUFR $k [expr {[lindex $BUFR $k]+$v}]
        set ph [expr {fmod($ph+$inc,$TL)}]
    }
}

# ---------------------------------------------------------------------------
#  4.  Arrangement -- camera velocity drives the keyboard
# ---------------------------------------------------------------------------
# Bright, wide-interval voicings: major 9ths and 6/9s, the harmonic dialect of
# every after-school cartoon bumper.
set CHORDS {
    {62 66 69 71 74 78 81}
    {59 62 66 69 71 74 78}
    {55 59 62 66 69 71 74}
    {57 61 64 66 69 73 76}
}
set PATTERN {0 1 2 3 4 3 2 1 0 2 4 5 6 5 4 2}

set STEP [expr {60.0/$BPM/4.0}]                 ;# one sixteenth
set NSTEPS [expr {int($DURATION/$STEP)}]
set nNotes 0
set eps 0.0001

for {set st 0} {$st<$NSTEPS} {incr st} {
    set t [expr {$st*$STEP}]
    set row [frameAt $t]
    set cam [expr {double([mv $row camMag])}]
    set loc [expr {double([mv $row localEnergy])}]
    set pcx [expr {double([mv $row plantCx])/720.0}]

    set mn [expr {$cam/($CAM_P90+$eps)}]
    if {$mn>1.35} {set mn 1.35}
    set ln [expr {$loc/($LOC_P90+$eps)}]
    if {$ln>1.3} {set ln 1.3}
    set drive [expr {0.62*$mn+0.38*$ln}]

    # density: slow camera -> eighths, fast camera -> every sixteenth
    if {$drive<0.28 && ($st%2)==1} continue

    set ci [expr {($st/8)%[llength $CHORDS]}]
    set chord [lindex $CHORDS $ci]
    set pi [lindex $PATTERN [expr {$st%[llength $PATTERN]}]]
    set note [lindex $chord $pi]

    # octave register climbs with movement in the camera image
    if {$drive<0.30}      { set oct 0 } \
    elseif {$drive<0.72}  { set oct 12 } \
    else                  { set oct 24 }
    set amp  [expr {0.17+0.33*($drive>1.0?1.0:$drive)}]
    set bell [expr {($drive-0.55)/0.75}]
    if {$bell<0} {set bell 0}
    if {$bell>0.75} {set bell 0.75}
    set dur [expr {$STEP*($drive<0.28?1.85:0.92)}]

    set pan [expr {0.30+0.40*$pcx}]
    set panL [expr {sqrt(1.0-$pan)}]
    set panR [expr {sqrt($pan)}]

    keyVoice TKEY $t $dur [midi2freq [expr {$note+$oct}]] $amp $panL $panR $bell
    incr nNotes

    # thicken into a two-hand voicing when the frame is really moving
    if {$drive>0.86} {
        set n2 [lindex $chord [expr {($pi+2)%[llength $chord]}]]
        keyVoice TKEY $t [expr {$dur*0.8}] [midi2freq [expr {$n2+$oct}]] \
                 [expr {$amp*0.55}] $panR $panL $bell
        incr nNotes
        # 32nd-note flam, the frantic top end of the arpeggiator
        keyVoice TKEY [expr {$t+$STEP*0.5}] [expr {$STEP*0.5}] \
                 [midi2freq [expr {$note+$oct+12}]] [expr {$amp*0.42}] \
                 $panL $panR 0.6
        incr nNotes
    }

    # root note under each chord change
    if {($st%8)==0} {
        bassVoice $t [expr {$STEP*4.2}] [midi2freq [expr {[lindex $chord 0]-24}]] 0.052
    }
}

# ---------------------------------------------------------------------------
#  5.  Hi-hats -- shadow movement drives the kit
# ---------------------------------------------------------------------------
# (a) accents on peaks of the shadow-change signal, quantised to 32nds
set HSTEP [expr {$STEP*0.5}]
set fired {}
set nHats 0
for {set i 1} {$i<$NFRAMES-1} {incr i} {
    set p [expr {double([mv [lindex $M [expr {$i-1}]] shadowChange])}]
    set c [expr {double([mv [lindex $M $i]           shadowChange])}]
    set n [expr {double([mv [lindex $M [expr {$i+1}]] shadowChange])}]
    if {!($c>=$p && $c>$n && $c>$SHD_MEAN)} continue
    set t [expr {double([mv [lindex $M $i] time])}]
    set q [expr {int(($t/$HSTEP)+0.5)}]
    if {[dict exists $fired $q]} continue
    dict set fired $q 1
    set norm [expr {($c-$SHD_MEAN)/(($SHD_P90-$SHD_MEAN)+$eps)}]
    if {$norm>1.6} {set norm 1.6}
    set open [expr {$norm>0.95}]
    set dur  [expr {$open?0.20:0.055}]
    set amp  [expr {0.12+0.19*$norm}]
    hatVoice [expr {$q*$HSTEP}] $dur $amp [expr {$open?0.88:1.06}]
    incr nHats
}
# (b) a quiet closed-hat pulse on the offbeat, gated by how much shadow the
#     frame actually contains -- the kit thins out when the shadows do
for {set st 0} {$st<$NSTEPS} {incr st} {
    if {($st%2)!=1} continue
    set t [expr {$st*$STEP}]
    set row [frameAt $t]
    set sf [expr {double([mv $row shadowFrac])}]
    set sc [expr {double([mv $row shadowChange])}]
    if {$sf<0.012} continue
    if {$sc<$SHD_MEAN*0.45} continue
    if {[dict exists $fired [expr {$st*2}]]} continue
    hatVoice $t 0.038 [expr {0.038+0.055*($sf*12.0>1.0?1.0:$sf*12.0)}] 1.10
    incr nHats
}
puts stderr "  synth: $nNotes keyboard notes, $nHats hats"

# ---------------------------------------------------------------------------
#  6.  Mixdown: fold in the location sound, soft-limit, write the RIFF file
# ---------------------------------------------------------------------------
set amb {}
if {[file exists $AMBIENCE] && [file size $AMBIENCE] > 0} {
    set af [open $AMBIENCE rb]
    fconfigure $af -translation binary
    binary scan [read $af] s* amb
    close $af
    puts stderr "  synth: ambience [expr {[llength $amb]/2}] frames"
}
set nAmb [expr {[llength $amb]/2}]

# pass 1 -- sum the busses, apply the head/tail fade, find the true peak
set peak 0.0
for {set i 0} {$i<$NSAMP} {incr i} {
    set l [lindex $BUFL $i]
    set r [lindex $BUFR $i]
    if {$i<$nAmb} {
        set l [expr {$l+[lindex $amb [expr {2*$i}]]/32768.0*$AMB_GAIN}]
        set r [expr {$r+[lindex $amb [expr {2*$i+1}]]/32768.0*$AMB_GAIN}]
    }
    # gentle master fade so nothing clicks at the head or tail
    if {$i<2205}            { set g [expr {$i/2205.0}] } \
    elseif {$i>$NSAMP-4410} { set g [expr {($NSAMP-$i)/4410.0}] } \
    else                    { set g 1.0 }
    set l [expr {$l*$g}]
    set r [expr {$r*$g}]
    lset BUFL $i $l
    lset BUFR $i $r
    set a [expr {abs($l)}]; if {$a>$peak} {set peak $a}
    set a [expr {abs($r)}]; if {$a>$peak} {set peak $a}
}
# pass 2 -- normalise to just under full scale, soft-limit, quantise to s16
set gain [expr {$peak>0.0001 ? 0.92/$peak : 1.0}]
if {$gain>6.0} {set gain 6.0}
set out {}
for {set i 0} {$i<$NSAMP} {incr i} {
    set l [expr {[lindex $BUFL $i]*$gain}]
    set r [expr {[lindex $BUFR $i]*$gain}]
    # soft limiter -- rational saturation, no hard clip
    set l [expr {$l/(1.0+abs($l)*0.32)}]
    set r [expr {$r/(1.0+abs($r)*0.32)}]
    lappend out [expr {int($l*32200)}] [expr {int($r*32200)}]
}
puts stderr [format "  synth: pre-normalise peak %.3f, make-up gain %.2fx" $peak $gain]

set pcm [binary format s* $out]
set bytes [string length $pcm]
set hdr [binary format {a4 i a4 a4 i s s i i s s a4 i} \
    RIFF [expr {36+$bytes}] WAVE fmt\  16 1 2 $SR [expr {$SR*4}] 4 16 data $bytes]
set of [open $OUTWAV wb]
fconfigure $of -translation binary
puts -nonewline $of $hdr
puts -nonewline $of $pcm
close $of
puts stderr "  synth: wrote $OUTWAV ([expr {$bytes/1024}] KiB pcm)"
