# ioa/lib/codec.tcl -- how many bits a picture costs, and the ladder of
# retreats available when the link cannot carry that many.
#
# ioa does not implement codecs. It models their bitrate well enough to decide
# what to ask the encoder for, then tells the encoder in its own language.

package require Tcl 8.6

namespace eval ioa::codec {
    # Bits per pixel per frame, by codec and quality knob. Rough field numbers
    # for natural scenes; a static shot beats these, a confetti cannon does not.
    variable bppTable {
        mjpeg  {95 1.10 90 0.80 85 0.65 80 0.53 75 0.44 70 0.38 65 0.30 60 0.24 55 0.19 50 0.15}
        h264   {95 0.30 90 0.20 85 0.14 80 0.10 75 0.08 70 0.06 65 0.05 60 0.04 55 0.03 50 0.025}
        h265   {95 0.20 90 0.13 85 0.09 80 0.065 75 0.05 70 0.04 65 0.032 60 0.026 55 0.02 50 0.016}
        av1    {95 0.16 90 0.10 85 0.07 80 0.05 75 0.04 70 0.032 65 0.026 60 0.021 55 0.017 50 0.013}
        rgb565 {95 16.0 90 16.0 85 16.0 80 16.0 75 16.0 70 16.0 65 16.0 60 16.0 55 16.0 50 16.0}
        gray8  {95 8.0  90 8.0  85 8.0  80 8.0  75 8.0  70 8.0  65 8.0  60 8.0  55 8.0  50 8.0}
        raw    {95 24.0 90 24.0 85 24.0 80 24.0 75 24.0 70 24.0 65 24.0 60 24.0 55 24.0 50 24.0}
    }

    # The retreat ladder, richest first. The planner walks down this until the
    # fabric can carry a rung; the rung it stops on is the honest answer to
    # "what can this camera actually deliver over that medium?"
    variable ladder {
        {id uhd2160p60 codec h265  w 3840 h 2160 fps 60  q 75 gop 60}
        {id uhd2160p30 codec h265  w 3840 h 2160 fps 30  q 75 gop 30}
        {id hd1080p60  codec h264  w 1920 h 1080 fps 60  q 80 gop 60}
        {id hd1080p30  codec h264  w 1920 h 1080 fps 30  q 80 gop 30}
        {id mj1080p30  codec mjpeg w 1920 h 1080 fps 30  q 80 gop 1}
        {id mj1080p15  codec mjpeg w 1920 h 1080 fps 15  q 75 gop 1}
        {id mj720p30   codec mjpeg w 1280 h 720  fps 30  q 80 gop 1}
        {id mj720p15   codec mjpeg w 1280 h 720  fps 15  q 75 gop 1}
        {id mj480p30   codec mjpeg w 854  h 480  fps 30  q 75 gop 1}
        {id mj480p10   codec mjpeg w 854  h 480  fps 10  q 70 gop 1}
        {id mj360p10   codec mjpeg w 640  h 360  fps 10  q 70 gop 1}
        {id mjqvga15   codec mjpeg w 320  h 240  fps 15  q 65 gop 1}
        {id mjqvga5    codec mjpeg w 320  h 240  fps 5   q 60 gop 1}
        {id mjqqvga2   codec mjpeg w 160  h 120  fps 2   q 55 gop 1}
        {id mjthumb05  codec mjpeg w 160  h 120  fps 0.5 q 55 gop 1}
        {id mjcrawl    codec mjpeg w 80   h 60   fps 0.2 q 50 gop 1}
    }

    # Named asks, so a caller says what it wants rather than a rung id.
    variable profiles {
        cinema    uhd2160p60
        broadcast hd1080p60
        hd        hd1080p30
        webcam    mj720p30
        machine   mj480p10
        glance    mjqvga5
        trickle   mjthumb05
    }
}

proc ioa::codec::bpp {codec q} {
    variable bppTable
    if {![dict exists $bppTable $codec]} { error "unknown codec: $codec" {} {IOA CODEC UNKNOWN} }
    set t [dict get $bppTable $codec]
    set best 0.5
    set bestd 1e9
    dict for {qq v} $t {
        set d [expr {abs($qq - $q)}]
        if {$d < $bestd} { set bestd $d; set best $v }
    }
    return $best
}

# Average bits per second for a rung.
proc ioa::codec::bitrate {rung} {
    set b [bpp [dict get $rung codec] [dict get $rung q]]
    expr {int([dict get $rung w] * [dict get $rung h] * [dict get $rung fps] * $b)}
}

# Average bytes in one coded picture.
proc ioa::codec::pictureBytes {rung} {
    expr {int(ceil(double([bitrate $rung]) / [dict get $rung fps] / 8.0))}
}

# Keyframes are far bigger than the pictures between them; a fabric that can
# carry the average but not the keyframe will stutter once per GOP.
proc ioa::codec::keyframeBytes {rung} {
    if {[dict get $rung gop] <= 1} { return [pictureBytes $rung] }
    expr {int([pictureBytes $rung] * 6)}
}

proc ioa::codec::rung {id} {
    variable ladder
    foreach r $ladder { if {[dict get $r id] eq $id} { return $r } }
    error "unknown rung: $id" {} {IOA CODEC RUNG}
}

proc ioa::codec::resolve {want} {
    variable profiles
    if {[dict exists $profiles $want]} { return [rung [dict get $profiles $want]] }
    return [rung $want]
}

proc ioa::codec::profileNames {} {
    variable profiles
    dict keys $profiles
}

proc ioa::codec::rungNames {} {
    variable ladder
    set out {}
    foreach r $ladder { lappend out [dict get $r id] }
    return $out
}

# The descent order from $startId.
#
# The ladder is curated by usefulness, not by cost -- MJPEG at 1080p30 is a
# better picture than H.264 at 1080p30 and five times the bitrate. So the
# descent skips any rung that would cost more than the one just refused:
# retreating must always be cheaper, or the planner is just guessing.
proc ioa::codec::descent {startId} {
    variable ladder
    set out {}
    set cap Inf
    set seen 0
    foreach r $ladder {
        if {[dict get $r id] eq $startId} {
            set seen 1
            set cap [bitrate $r]
            lappend out $r
            continue
        }
        if {!$seen} continue
        set b [bitrate $r]
        if {$b > $cap} continue
        set cap $b
        lappend out $r
    }
    if {!$seen} { error "unknown rung: $startId" {} {IOA CODEC RUNG} }
    return $out
}

# Rungs a given SKU can actually produce, given its encoder ceiling.
proc ioa::codec::withinCeiling {rung ceiling} {
    if {$ceiling eq ""} { return 1 }
    lassign $ceiling c w h fps
    variable bppTable
    # A device that can do h265 can do the cheaper intra codecs too.
    set rank {gray8 0 rgb565 0 raw 0 mjpeg 1 h264 2 h265 3 av1 3 jpegxl 1}
    set need [ioa::dget $rank [dict get $rung codec] 1]
    set have [ioa::dget $rank $c 1]
    expr {$need <= $have
          && [dict get $rung w] <= $w
          && [dict get $rung h] <= $h
          && [dict get $rung fps] <= $fps}
}

proc ioa::codec::describe {rung} {
    format "%s %dx%d@%g %s q%d (%s)" \
        [dict get $rung id] [dict get $rung w] [dict get $rung h] \
        [dict get $rung fps] [dict get $rung codec] [dict get $rung q] \
        [ioa::bps [bitrate $rung]]
}

package provide ioa::codec 0.3.0
