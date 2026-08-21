#!/usr/bin/env wish
# explore.tcl — the interactive host. Tk canvas, immediate mode, one window.
#
# ---------------------------------------------------------------------------
# WHAT THIS IS TRYING TO BE
# ---------------------------------------------------------------------------
# Sutherland: the drawing and the model are the same object, and the way you
#   ask a question is to grab the drawing and pull. Select a metric, hold a
#   direction key, and the value moves; the composites, the severities, the
#   concordance scores and the permutation p-values all re-derive from the C++
#   engine and the picture redraws. Nothing is precomputed for the states you
#   might visit. That is the constraint drag, with a process boundary in the
#   middle of it.
#
# Engelbart: every element is a link, the view is restructurable without
#   leaving it, and the chord keys are always live. Lens keys 1-5 add and
#   remove hypothesis overlays; they compose, so 1+4 shows the arousal and
#   inflammation stories at once and lets you see which edges they share.
#   A status line reports what just happened, always, in words.
#
# Kay: the host knows nothing about EEG. It executes a bytecode. Everything
#   domain-specific arrived in the file, including the explanations, so a
#   second modality would need a new emitter and not a new viewer.
#
#   wish tcl/explore.tcl build/dashboard.nvm
#
# Keys:  1-5 lenses   p/f/b explanation register   arrows nudge   r re-derive
#        0 reset view   / search   ? help   q quit
# ---------------------------------------------------------------------------

set here [file dirname [file normalize [info script]]]
lappend auto_path $here
package require Tcl 8.6
package require Tk
package require nvm

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
namespace eval app {
    variable path      ""
    variable bc        {}
    variable root      ""
    variable canvas    ""
    variable zoom      1.0
    variable panX      0
    variable panY      0
    variable selected  ""
    variable hovered   ""
    variable register  both        ;# plain | full | both
    variable lenses    {}
    variable overrides {}
    variable status    "ready"
    variable notes             ;# anchor id -> {plain full}
    variable flags             ;# anchor id -> severity
    variable cites             ;# anchor id -> text
    variable edges     {}
    variable panels    {}
    variable busy      0
    array set notes {}
    array set flags {}
    array set cites {}
}

# The design tokens live in the bytecode for anything data-driven; these are
# only the chrome. Dark by default because the canvas ink was authored at mid
# lightness precisely so it would survive both grounds.
namespace eval ui {
    variable bg      "#16181d"
    variable panelBg "#1d2027"
    variable ink     "#e8eaf0"
    variable muted   "#8b91a3"
    variable rule    "#2b2f39"
    variable accent  "#5b8cff"
    variable warn    "#e0a33a"
    variable bad     "#e06a60"
    variable good    "#4bbf9a"
    variable mono    {"IBM Plex Mono" 10}
    variable sans    {"Inter" 10}
}

# ---------------------------------------------------------------------------
# Backend: draw the bytecode onto a Tk canvas
# ---------------------------------------------------------------------------
namespace eval bk::tk {
    variable c ""
    variable fill "#000000"
    variable alpha 255
    variable width 1.0
    variable fontSpec {Helvetica 10}
    variable anchorId ""
    variable panelId ""
    variable instance ""
    variable instances {}
    variable items {}
}

proc bk::tk::begin {canvas} {
    variable c ; set c $canvas
    variable anchorId ; set anchorId ""
    variable panelId  ; set panelId ""
    variable instance ; set instance ""
    variable instances ; set instances {}
    $c delete all
}

# The bytecode palette is authored as light-theme ink. Rendering it on a dark
# ground means inverting LIGHTNESS ONLY -- naive 255-x inversion rotates hue by
# 180 degrees and turns the deviant red into a cyan, which is exactly the kind
# of silent semantic corruption a shared display file is supposed to prevent.
# So: convert to HSL, reflect L about 0.5, convert back, then composite the
# alpha against the window ground because Tk canvas items have no alpha.
proc bk::tk::invertLightness {r g b} {
    set R [expr {$r/255.0}] ; set G [expr {$g/255.0}] ; set B [expr {$b/255.0}]
    set mx [expr {max($R,$G,$B)}] ; set mn [expr {min($R,$G,$B)}]
    set L [expr {($mx+$mn)/2.0}]
    set d [expr {$mx-$mn}]
    if {$d < 1e-9} {
        set H 0.0 ; set S 0.0
    } else {
        set S [expr {$L > 0.5 ? $d/(2.0-$mx-$mn) : $d/($mx+$mn)}]
        if {$mx == $R} {
            set H [expr {fmod((($G-$B)/$d) + ($G < $B ? 6.0 : 0.0), 6.0)}]
        } elseif {$mx == $G} {
            set H [expr {(($B-$R)/$d) + 2.0}]
        } else {
            set H [expr {(($R-$G)/$d) + 4.0}]
        }
        set H [expr {$H/6.0}]
    }
    # Reflect, but keep a floor so near-black ink does not become pure white and
    # blow out against the dark ground.
    set L [expr {0.06 + 0.88*(1.0-$L)}]
    if {$S < 1e-9} {
        set R $L ; set G $L ; set B $L
    } else {
        set q [expr {$L < 0.5 ? $L*(1.0+$S) : $L+$S-$L*$S}]
        set p [expr {2.0*$L-$q}]
        foreach {var off} {R 1 G 0 B -1} {
            set t [expr {$H + $off/3.0}]
            if {$t < 0} {set t [expr {$t+1.0}]}
            if {$t > 1} {set t [expr {$t-1.0}]}
            if {$t < 1/6.0} {
                set v [expr {$p + ($q-$p)*6.0*$t}]
            } elseif {$t < 0.5} {
                set v $q
            } elseif {$t < 2/3.0} {
                set v [expr {$p + ($q-$p)*(2/3.0-$t)*6.0}]
            } else {
                set v $p
            }
            set $var $v
        }
    }
    return [list [expr {int(round($R*255))}] [expr {int(round($G*255))}] [expr {int(round($B*255))}]]
}

proc bk::tk::rgba {r g b a} {
    variable fill
    variable alpha
    set alpha $a
    set t [expr {$a / 255.0}]
    lassign [winfo rgb . $::ui::bg] br bg_ bb
    set br [expr {$br / 257}] ; set bg_ [expr {$bg_ / 257}] ; set bb [expr {$bb / 257}]
    lassign [invertLightness $r $g $b] r g b
    set fill [format "#%02x%02x%02x" \
        [expr {int($r*$t + $br*(1-$t))}] \
        [expr {int($g*$t + $bg_*(1-$t))}] \
        [expr {int($b*$t + $bb*(1-$t))}]]
}

proc bk::tk::linew {w} { variable width ; set width [expr {max(1.0, $w)}] }

proc bk::tk::font {name size} {
    variable fontSpec
    set fam [expr {[string match *mono* $name] ? "TkFixedFont" : "TkDefaultFont"}]
    set weight [expr {[string match *bold* $name] ? "bold" : "normal"}]
    set fontSpec [list [::font actual $fam -family] [expr {int(round($size))}] $weight]
}

# A metric drawn in two panels gets two tags: one shared by every instance
# ("an:<id>", so selecting it lights all of them) and one per instance
# ("in:<id>#<n>", so a hit test and a highlight box refer to the instance under
# the pointer instead of to a rectangle spanning both panels.
proc bk::tk::tags {} {
    variable anchorId
    variable panelId
    variable instance
    set t {bc}
    if {$anchorId ne ""} { lappend t "an:$anchorId" "in:$instance" }
    if {$panelId  ne ""} { lappend t "pn:$panelId" }
    return $t
}

proc bk::tk::clear {} {}

proc bk::tk::rect {how x y w h} {
    variable c ; variable fill ; variable width
    set x1 [expr {$x + $w}] ; set y1 [expr {$y + $h}]
    if {$how eq "fill"} {
        $c create rectangle $x $y $x1 $y1 -fill $fill -outline "" -tags [tags]
    } else {
        $c create rectangle $x $y $x1 $y1 -outline $fill -width $width -tags [tags]
    }
}

proc bk::tk::circle {how x y r} {
    variable c ; variable fill ; variable width
    if {$how eq "fill"} {
        $c create oval [expr {$x-$r}] [expr {$y-$r}] [expr {$x+$r}] [expr {$y+$r}] \
            -fill $fill -outline "" -tags [tags]
    } else {
        $c create oval [expr {$x-$r}] [expr {$y-$r}] [expr {$x+$r}] [expr {$y+$r}] \
            -outline $fill -width $width -tags [tags]
    }
}

proc bk::tk::arc {how x y r a0 a1} {
    variable c ; variable fill ; variable width
    set start [expr {-$a0 * 180.0 / 3.14159265358979}]
    set extent [expr {-($a1 - $a0) * 180.0 / 3.14159265358979}]
    $c create arc [expr {$x-$r}] [expr {$y-$r}] [expr {$x+$r}] [expr {$y+$r}] \
        -start $start -extent $extent -style arc -outline $fill -width $width -tags [tags]
}

proc bk::tk::polyline {how pts} {
    variable c ; variable fill ; variable width
    if {[llength $pts] < 4} return
    if {$how eq "fill" && [llength $pts] >= 6} {
        $c create polygon {*}$pts -fill $fill -outline "" -tags [tags]
    } else {
        $c create line {*}$pts -fill $fill -width $width -tags [tags]
    }
}

proc bk::tk::text {x y str anchorMode} {
    variable c ; variable fill ; variable fontSpec
    set a [lindex {w center e} $anchorMode]
    $c create text $x $y -text $str -fill $fill -font $fontSpec -anchor $a -tags [tags]
}

proc bk::tk::panel {id title} {
    variable panelId ; set panelId $id
    lappend ::app::panels [list $id $title]
}
proc bk::tk::endpanel {} { variable panelId ; set panelId "" }
proc bk::tk::anchor {id} {
    variable anchorId ; variable instance ; variable instances
    set anchorId $id
    set n 0
    foreach i $instances { if {[string match "$id#*" $i]} { incr n } }
    set instance "$id#$n"
    lappend instances $instance
}
proc bk::tk::note {plain full} {
    variable anchorId
    if {$anchorId ne ""} { set ::app::notes($anchorId) [list $plain $full] }
}
proc bk::tk::flag {sev} {
    variable anchorId
    if {$anchorId ne ""} { set ::app::flags($anchorId) $sev }
}
proc bk::tk::cite {t} {
    variable anchorId
    if {$anchorId ne ""} { set ::app::cites($anchorId) $t }
}
proc bk::tk::edge {a b hyp w sign} { lappend ::app::edges [list $a $b $hyp $w $sign] }

# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------
proc app::render {} {
    variable bc ; variable canvas ; variable zoom ; variable panels ; variable edges
    set panels {} ; set edges {}
    array unset ::app::notes ; array set ::app::notes {}
    array unset ::app::flags ; array set ::app::flags {}
    array unset ::app::cites ; array set ::app::cites {}

    bk::tk::begin $canvas
    # Zoom goes in as the seed transform, not as a post-scale, so text scales
    # with the geometry it was laid out against.
    nvm::run $bc ::bk::tk [list $zoom 0 0 $zoom 0 0]
    $canvas configure -scrollregion [$canvas bbox all]
    highlight
}

# Selection and hover are drawn as an overlay rather than by re-emitting the
# panel, so the bytecode never has to know a pointer exists.
proc app::highlight {} {
    variable canvas ; variable selected ; variable hovered
    $canvas delete hl
    foreach {id colour w} [list $hovered $::ui::muted 1 $selected $::ui::accent 2] {
        if {$id eq ""} continue
        foreach inst $::bk::tk::instances {
            if {![string match "$id#*" $inst]} continue
            set bb [$canvas bbox "in:$inst"]
            if {$bb eq ""} continue
            lassign $bb x0 y0 x1 y1
            $canvas create rectangle [expr {$x0-4}] [expr {$y0-3}] [expr {$x1+4}] [expr {$y1+3}] \
                -outline $colour -width $w -tags hl
        }
    }
    # When a metric is selected, light every prior-graph edge that touches it.
    if {$selected ne ""} {
        foreach e $::app::edges {
            lassign $e a b hyp w sign
            if {$a ne $selected && $b ne $selected} continue
            set ba [$canvas bbox "in:$a#0"] ; set bb2 [$canvas bbox "in:$b#0"]
            if {$ba eq "" || $bb2 eq ""} continue
            lassign $ba ax0 ay0 ax1 ay1
            lassign $bb2 bx0 by0 bx1 by1
            $canvas create line \
                [expr {($ax0+$ax1)/2}] [expr {($ay0+$ay1)/2}] \
                [expr {($bx0+$bx1)/2}] [expr {($by0+$by1)/2}] \
                -fill [expr {$sign > 0 ? $::ui::accent : $::ui::bad}] \
                -width 1 -dash {3 3} -tags hl
        }
    }
}

# ---------------------------------------------------------------------------
# Inspector
# ---------------------------------------------------------------------------
proc app::inspect {id} {
    variable bc ; variable register
    set t .right.txt
    $t configure -state normal
    $t delete 1.0 end

    if {$id eq ""} {
        $t insert end "Nothing selected.\n\n" muted
        $t insert end "Hover to read. Click to select. Arrow keys nudge a selected\nmetric and re-derive the whole argument from the engine.\n" muted
        $t configure -state disabled
        return
    }

    set sym [nvm::sym $bc $id]
    $t insert end "$id\n" head
    if {$sym ne ""} {
        set sevNames {within reference  borderline  deviant  not measured}
        set sev [dict get $sym severity]
        set tagname [lindex {good warn bad muted} $sev]
        $t insert end [format "%s\n" [lindex {"within reference" "borderline" "deviant" "not measured"} $sev]] $tagname
        $t insert end [format "value  %.4g\n" [dict get $sym value]] mono
        if {[dict get $sym hasRef]} {
            $t insert end [format "ref    %.4g to %.4g\n" \
                [dict get $sym refLo] [dict get $sym refHi]] mono
        }
        $t insert end [format "sdev   %+.2f half-bands\n" [dict get $sym z]] mono
        $t insert end [format "margin %+.1f%% of threshold\n" [expr {100*[dict get $sym dist]}]] mono
    }
    $t insert end "\n"

    # Only about half the metrics carry a hand-written note. The rest get a
    # generated sentence rather than an empty pane, using the same wording the
    # browser host uses so the two do not describe the same metric differently.
    if {![info exists ::app::notes($id)] && $sym ne "" && [dict get $sym valid]} {
        set d [dict get $sym dist]
        set pct [format "%.0f" [expr {abs($d)*100}]]
        set line "[dict get $sym label] measured [format %.4g [dict get $sym value]]"
        if {[dict get $sym hasRef]} {
            append line [format ", against a reference of %.4g to %.4g. " \
                [dict get $sym refLo] [dict get $sym refHi]]
        } else { append line ". " }
        append line [expr {$d <= 0 ? "That is inside reference with $pct% of margin left."
                                   : "That is $pct% past the nearer edge."}]
        $t insert end "PLAIN\n" label
        $t insert end "$line\n\n"
        if {$register ne "plain"} {
            $t insert end "FULL FAT\n" label
            $t insert end "No hand-written note for this metric. It contributes to the ranking and, where the prior graph names it, to the concordance scores.\n\n" muted
        }
    }

    if {[info exists ::app::notes($id)]} {
        lassign $::app::notes($id) plain full
        if {$register in {plain both}} {
            $t insert end "PLAIN\n" label
            $t insert end "$plain\n\n"
        }
        if {$register in {full both}} {
            $t insert end "FULL FAT\n" label
            $t insert end "$full\n\n"
        }
    }
    if {[info exists ::app::cites($id)]} {
        $t insert end "[set ::app::cites($id)]\n" muted
    }

    # Every element is a link: list the prior-graph edges that touch this one,
    # each clickable.
    set rel {}
    foreach e $::app::edges {
        lassign $e a b hyp w sign
        if {$a eq $id} { lappend rel [list $b $hyp $w $sign] }
        if {$b eq $id} { lappend rel [list $a $hyp $w $sign] }
    }
    if {[llength $rel]} {
        $t insert end "\nLINKED BY THE PRIOR GRAPH\n" label
        foreach r $rel {
            lassign $r other hyp w sign
            set arrow [expr {$sign > 0 ? "moves with" : "moves against"}]
            $t insert end "  $arrow  " muted
            $t insert end "$other" [list link "lnk:$other"]
            $t insert end [format "  %s w=%.1f\n" $hyp $w] muted
            $t tag bind "lnk:$other" <Button-1> [list app::select $other]
            $t tag bind "lnk:$other" <Enter> {%W configure -cursor hand2}
            $t tag bind "lnk:$other" <Leave> {%W configure -cursor ""}
        }
    }
    $t configure -state disabled
}

proc app::select {id} {
    variable selected
    set selected $id
    highlight
    inspect $id
    say "selected $id"
}

proc app::say {msg} {
    variable status
    set status $msg
}

# ---------------------------------------------------------------------------
# The constraint drag: nudge a value, re-derive everything
# ---------------------------------------------------------------------------
proc app::nudge {direction} {
    variable selected ; variable bc ; variable overrides
    if {$selected eq ""} { say "select a metric first" ; return }
    set sym [nvm::sym $bc $selected]
    if {$sym eq ""} { say "$selected is not a measured metric" ; return }
    set v [dict get $sym value]
    # Step by 2% of the current magnitude, so one key press means the same
    # thing on a 588 ms latency and on a 0.38 amplitude ratio.
    set step [expr {abs($v) > 1e-9 ? abs($v) * 0.02 : 0.02}]
    set new [expr {$v + $direction * $step}]
    dict set overrides $selected $new
    say [format "%s -> %.4g   (re-deriving)" $selected $new]
    rederive
}

proc app::clearOverrides {} {
    variable overrides
    set overrides {}
    say "overrides cleared, re-deriving from source"
    rederive
}

proc app::rederive {} {
    variable overrides ; variable path ; variable bc ; variable busy
    if {$busy} return
    set busy 1
    set root [file dirname [file dirname [file normalize [info script]]]]
    set exe [file join $root build analyze]
    if {![file executable $exe]} {
        say "build/analyze not found -- run make first"
        set busy 0
        return
    }
    set tmp [file join $root build explore.nvm]
    set cmd [list $exe --session [file join $root data session-2026-08-18.json] \
                       --prior   [file join $root data prior-graph.json] \
                       --out     $tmp \
                       --json    [file join $root build explore.json] \
                       --perm    4000]
    dict for {k v} $overrides { lappend cmd --override "$k=$v" }
    if {[catch {exec {*}$cmd 2>@1} out]} {
        say "engine failed: [string range $out 0 90]"
        set busy 0
        return
    }
    set bc [nvm::load $tmp]
    render
    inspect $::app::selected
    set n [dict size $overrides]
    say [expr {$n ? "re-derived with $n override(s) -- press R to reset" : "re-derived from source"}]
    set busy 0
}

# ---------------------------------------------------------------------------
# Lenses
# ---------------------------------------------------------------------------
proc app::toggleLens {n} {
    variable lenses
    set id "H$n"
    set i [lsearch -exact $lenses $id]
    if {$i >= 0} { set lenses [lreplace $lenses $i $i] } else { lappend lenses $id }
    updateLensChrome
    dimToLenses
    say [expr {[llength $lenses] ? "lenses: $lenses" : "all lenses off"}]
}

proc app::updateLensChrome {} {
    variable lenses
    for {set i 1} {$i <= 5} {incr i} {
        set w .top.l$i
        if {![winfo exists $w]} continue
        if {"H$i" in $lenses} {
            $w configure -background $::ui::accent -foreground "#ffffff"
        } else {
            $w configure -background $::ui::panelBg -foreground $::ui::muted
        }
    }
}

# With a lens active, metrics that no hypothesis in the lens set touches are
# pushed back rather than hidden. Removing them would change what the page
# claims; dimming them keeps the denominator visible, which matters when the
# whole point of the panel is how far past a line something sits.
proc app::dimToLenses {} {
    variable lenses ; variable canvas ; variable bc
    $canvas delete lensmask
    if {![llength $lenses]} return
    # Each EDGE record names the hypothesis that emitted it, so a lens set is
    # resolved from the bytecode alone with no sidecar lookup.
    set keep {}
    foreach e $::app::edges {
        lassign $e a b hyp w sign
        if {$hyp in $lenses} { lappend keep $a $b }
    }
    foreach inst $::bk::tk::instances {
        set id [lindex [split $inst "#"] 0]
        if {$id in $keep} continue
        set bb [$canvas bbox "in:$inst"]
        if {$bb eq ""} continue
        lassign $bb x0 y0 x1 y1
        $canvas create rectangle [expr {$x0-3}] [expr {$y0-2}] [expr {$x1+3}] [expr {$y1+2}] \
            -fill $::ui::bg -outline "" -stipple gray50 -tags lensmask
    }
}

# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------
proc app::build {} {
    variable canvas

    wm title . "NeuroVM Explorer"
    wm geometry . 1500x950
    . configure -background $::ui::bg

    # -- lens strip ---------------------------------------------------------
    frame .top -background $::ui::panelBg -padx 10 -pady 8
    pack .top -side top -fill x

    label .top.title -text "NeuroVM" -background $::ui::panelBg -foreground $::ui::ink \
        -font {TkDefaultFont 12 bold}
    pack .top.title -side left -padx {0 16}

    for {set i 1} {$i <= 5} {incr i} {
        set lbl [lindex {"" "1 arousal" "2 timing" "3 affect" "4 immune" "5 ADHD"} $i]
        label .top.l$i -text " $lbl " -background $::ui::panelBg -foreground $::ui::muted \
            -padx 10 -pady 4 -font {TkDefaultFont 10}
        pack .top.l$i -side left -padx 3
        bind .top.l$i <Button-1> [list app::toggleLens $i]
    }

    label .top.reg -text "  explanation " -background $::ui::panelBg -foreground $::ui::muted
    pack .top.reg -side left -padx {24 0}
    foreach {key lbl} {plain "p plain" full "f full-fat" both "b both"} {
        radiobutton .top.r$key -text $lbl -value $key -variable ::app::register \
            -command {app::inspect $::app::selected} \
            -background $::ui::panelBg -foreground $::ui::ink \
            -selectcolor $::ui::accent -activebackground $::ui::panelBg \
            -highlightthickness 0 -font {TkDefaultFont 9}
        pack .top.r$key -side left
    }

    label .top.help -text "?  help" -background $::ui::panelBg -foreground $::ui::muted
    pack .top.help -side right
    bind .top.help <Button-1> app::help

    # -- status line (Engelbart: always say what just happened) -------------
    frame .bot -background $::ui::panelBg -padx 10 -pady 5
    pack .bot -side bottom -fill x
    label .bot.s -textvariable ::app::status -background $::ui::panelBg \
        -foreground $::ui::muted -anchor w -font {TkFixedFont 9}
    pack .bot.s -side left -fill x -expand 1

    # -- inspector ----------------------------------------------------------
    frame .right -background $::ui::panelBg -width 380
    pack .right -side right -fill y
    pack propagate .right 0
    text .right.txt -background $::ui::panelBg -foreground $::ui::ink -width 46 \
        -wrap word -padx 14 -pady 14 -relief flat -highlightthickness 0 \
        -font {TkDefaultFont 10} -state disabled
    pack .right.txt -fill both -expand 1
    .right.txt tag configure head  -font {TkDefaultFont 12 bold} -foreground $::ui::ink -spacing3 4
    .right.txt tag configure label -font {TkDefaultFont 8 bold} -foreground $::ui::muted -spacing1 6 -spacing3 3
    .right.txt tag configure muted -foreground $::ui::muted
    .right.txt tag configure mono  -font {TkFixedFont 9} -foreground $::ui::ink
    .right.txt tag configure good  -foreground $::ui::good
    .right.txt tag configure warn  -foreground $::ui::warn
    .right.txt tag configure bad   -foreground $::ui::bad
    .right.txt tag configure link  -foreground $::ui::accent -underline 1

    # -- canvas -------------------------------------------------------------
    set canvas [canvas .cv -background $::ui::bg -highlightthickness 0 \
        -xscrollincrement 1 -yscrollincrement 1]
    pack .cv -side left -fill both -expand 1

    bind .cv <Motion>          {app::onMotion %x %y}
    bind .cv <Button-1>        {app::onClick %x %y}
    bind .cv <ButtonPress-2>   {%W scan mark %x %y}
    bind .cv <B2-Motion>       {%W scan dragto %x %y 1}
    bind .cv <Button-4>        {app::zoomBy 1.1}
    bind .cv <Button-5>        {app::zoomBy 0.9}
    bind .cv <MouseWheel>      {app::zoomBy [expr {%D > 0 ? 1.1 : 0.9}]}

    bind . <Key-1> {app::toggleLens 1}
    bind . <Key-2> {app::toggleLens 2}
    bind . <Key-3> {app::toggleLens 3}
    bind . <Key-4> {app::toggleLens 4}
    bind . <Key-5> {app::toggleLens 5}
    bind . <Key-p> {set ::app::register plain ; app::inspect $::app::selected}
    bind . <Key-f> {set ::app::register full  ; app::inspect $::app::selected}
    bind . <Key-b> {set ::app::register both  ; app::inspect $::app::selected}
    bind . <Key-Up>    {app::nudge  1}
    bind . <Key-Right> {app::nudge  1}
    bind . <Key-Down>  {app::nudge -1}
    bind . <Key-Left>  {app::nudge -1}
    bind . <Key-r> {app::rederive}
    bind . <Key-R> {app::clearOverrides}
    bind . <Key-0> {set ::app::zoom 1.0 ; app::render ; app::say "view reset to 100%"}
    bind . <Key-equal> {app::zoomBy 1.15}
    bind . <Key-plus>  {app::zoomBy 1.15}
    bind . <Key-minus> {app::zoomBy 0.87}
    bind . <Key-i> {app::toggleInspector}
    bind . <Key-question> app::help
    bind . <Key-slash>    app::search
    bind . <Key-q> {exit}
    focus .
}

# The inspector is the only chrome that competes with the canvas for width, so
# it collapses to nothing on one key rather than resizing by drag. Reading a
# wide panel and reading an explanation are different tasks; the UI should let
# you switch between them, not force a compromise width on both.
proc app::toggleInspector {} {
    if {[winfo manager .right] eq ""} {
        pack .right -side right -fill y -before .cv
        say "inspector shown"
    } else {
        pack forget .right
        say "inspector hidden -- press i to bring it back"
    }
    update idletasks
    render
}

proc app::zoomBy {f} {
    variable zoom
    set zoom [expr {max(0.25, min(4.0, $zoom * $f))}]
    render
    say [format "zoom %.0f%%" [expr {$zoom * 100}]]
}

proc app::anchorAt {x y} {
    variable canvas
    set cx [$canvas canvasx $x] ; set cy [$canvas canvasy $y]
    foreach item [$canvas find overlapping [expr {$cx-2}] [expr {$cy-2}] \
                                            [expr {$cx+2}] [expr {$cy+2}]] {
        foreach t [$canvas gettags $item] {
            if {[string match "an:*" $t]} { return [string range $t 3 end] }
        }
    }
    return ""
}

proc app::onMotion {x y} {
    variable hovered
    set id [anchorAt $x $y]
    if {$id eq $hovered} return
    set hovered $id
    highlight
    if {$id ne "" && $::app::selected eq ""} { inspect $id }
    if {$id ne "" && [info exists ::app::notes($id)]} {
        say [lindex $::app::notes($id) 0]
    }
}

proc app::onClick {x y} {
    set id [anchorAt $x $y]
    if {$id eq ""} { say "" ; return }
    select $id
}

proc app::search {} {
    variable bc
    toplevel .find -background $::ui::panelBg
    wm title .find "jump to metric"
    entry .find.e -background $::ui::bg -foreground $::ui::ink -insertbackground $::ui::ink \
        -width 40 -relief flat
    listbox .find.l -background $::ui::bg -foreground $::ui::ink -height 14 -relief flat \
        -highlightthickness 0
    pack .find.e -fill x -padx 8 -pady 8
    pack .find.l -fill both -expand 1 -padx 8 -pady {0 8}
    foreach s [dict get $bc symbols] { .find.l insert end [dict get $s name] }
    bind .find.e <KeyRelease> {
        .find.l delete 0 end
        set q [string tolower [.find.e get]]
        foreach s [dict get $::app::bc symbols] {
            set n [dict get $s name]
            if {$q eq "" || [string match "*$q*" [string tolower $n]]} { .find.l insert end $n }
        }
    }
    bind .find.l <Double-Button-1> {
        set sel [.find.l get [.find.l curselection]]
        destroy .find
        app::select $sel
    }
    bind .find <Escape> {destroy .find}
    focus .find.e
}

proc app::help {} {
    if {[winfo exists .help]} { destroy .help ; return }
    toplevel .help -background $::ui::panelBg
    wm title .help "keys"
    text .help.t -background $::ui::panelBg -foreground $::ui::ink -width 62 -height 22 \
        -relief flat -padx 16 -pady 14 -wrap word -font {TkFixedFont 10}
    pack .help.t -fill both -expand 1
    .help.t insert end {
  1..5     toggle a hypothesis lens; they compose
  p f b    explanation register: plain, full-fat, both
  click    select. every selected element lights its prior-graph edges
  arrows   nudge the selected metric by 2% and re-derive everything
  r        re-derive now
  R        drop all overrides and re-derive from source
  /        jump to a metric by name
  0        reset zoom to 100%      = / -   zoom in / out
  i        collapse or restore the inspector
  wheel    zoom      middle-drag  pan
  q        quit

  Nudging shells out to build/analyze with --override, so the numbers
  you see after a nudge came from the same engine that produced the
  file, not from an approximation living in the viewer.
}
    .help.t configure -state disabled
    bind .help <Escape> {destroy .help}
    bind .help <Key-question> {destroy .help}
}

# ---------------------------------------------------------------------------
proc app::main {argv} {
    variable path ; variable bc
    set path [expr {[llength $argv] ? [lindex $argv 0] : \
        [file join [file dirname [file dirname [file normalize [info script]]]] build dashboard.nvm]}]
    if {![file exists $path]} {
        puts stderr "explore: $path not found. Run 'make' in neuro/ first."
        exit 1
    }
    set bc [nvm::load $path]
    build
    update idletasks
    # Open at fit-to-width rather than 100%. A dashboard whose first frame is
    # cropped has already failed; the reader should not have to discover a
    # scrollbar to learn that panels exist off-screen.
    variable zoom
    set avail [expr {[winfo width .cv] - 24}]
    if {$avail > 200} {
        set zoom [expr {max(0.62, min(1.0, double($avail) / [dict get $bc canvasW]))}]
    }
    render
    inspect ""
    say "[llength [dict get $bc symbols]] metrics loaded from [file tail $path] -- press ? for keys"
}

if {[catch {app::main $argv} err]} {
    puts stderr "explore: $err\n$::errorInfo"
    exit 1
}
