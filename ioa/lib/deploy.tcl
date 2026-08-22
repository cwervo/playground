# ioa/lib/deploy.tcl -- a plan, turned into things you can actually run.
#
# The orchestrator's job ends at a manifest: for each box on the route, what
# to execute (macOS, Linux), what to build into firmware (ESP32) or load as a
# bitstream (the FPGA products). ioa deliberately does not implement capture
# or encoding -- it drives whatever already does that on each platform and
# owns only the framing and the routing between them.

package require Tcl 8.6

namespace eval ioa::deploy {}

# ioa quality (50..95, higher better) -> ffmpeg -q:v (2..31, lower better).
proc ioa::deploy::ffQuality {q} {
    expr {int(max(2, min(31, round(2 + (95 - $q) * 0.35))))}
}

# ioa quality -> esp32-camera jpeg_quality (0..63, lower better).
proc ioa::deploy::espQuality {q} {
    expr {int(max(4, min(63, round(63 - ($q - 50) * 0.9))))}
}

proc ioa::deploy::espFramesize {w h} {
    foreach {fw fh name} {1600 1200 FRAMESIZE_UXGA 1280 1024 FRAMESIZE_SXGA
                          1280 720 FRAMESIZE_HD 800 600 FRAMESIZE_SVGA
                          640 480 FRAMESIZE_VGA 400 296 FRAMESIZE_CIF
                          320 240 FRAMESIZE_QVGA 160 120 FRAMESIZE_QQVGA} {
        if {$w >= $fw && $h >= $fh} { return $name }
    }
    return FRAMESIZE_QQVGA
}

# What this node must run to produce pictures at $rung.
proc ioa::deploy::capture {dev rung} {
    set w [dict get $rung w]
    set h [dict get $rung h]
    set fps [dict get $rung fps]
    set codec [dict get $rung codec]

    switch -- [dict get $dev platform] {
        macos {
            set enc [expr {$codec eq "mjpeg"
                ? "-c:v mjpeg -q:v [ffQuality [dict get $rung q]]"
                : "-c:v h264_videotoolbox -realtime 1 -b:v [ioa::codec::bitrate $rung]"}]
            return [dict create kind exec cmd \
                "ffmpeg -hide_banner -f avfoundation -framerate $fps -video_size ${w}x${h}\
 -i [ioa::dget $dev input {0:none}] $enc -f $codec -"]
        }
        linux {
            set enc [expr {$codec eq "mjpeg"
                ? "-c:v mjpeg -q:v [ffQuality [dict get $rung q]]"
                : "-c:v [ioa::dget $dev encoder libx264] -preset ultrafast -tune zerolatency\
 -g [dict get $rung gop] -b:v [ioa::codec::bitrate $rung]"}]
            return [dict create kind exec cmd \
                "ffmpeg -hide_banner -f v4l2 -input_format mjpeg -video_size ${w}x${h}\
 -framerate $fps -i [ioa::dget $dev input /dev/video0] $enc -f $codec -"]
        }
        esp32 {
            return [dict create kind firmware config [dict create \
                IOA_FRAMESIZE [espFramesize $w $h] \
                IOA_JPEG_QUALITY [espQuality [dict get $rung q]] \
                IOA_TARGET_FPS $fps \
                IOA_GRAB_MODE CAMERA_GRAB_LATEST \
                IOA_FB_COUNT 2] \
                flash [list idf.py -p [ioa::dget $dev port /dev/ttyUSB0] -b 921600 flash]]
        }
        fpga {
            return [dict create kind bitstream \
                config [dict create IOA_ENCODE $codec IOA_W $w IOA_H $h IOA_FPS $fps \
                    IOA_BITRATE [ioa::codec::bitrate $rung]] \
                load [list ioa fpga load --target crosslink-nx --bit ioa-frame-h264.bin \
                          --port [ioa::dget $dev port /dev/ttyACM0]]]
        }
    }
    return [dict create kind note text "no capture path for platform [dict get $dev platform]"]
}

# What the far end does with pictures once they arrive.
proc ioa::deploy::sink {dev rung {mode view}} {
    set codec [dict get $rung codec]
    switch -- $mode {
        record {
            return [dict create kind exec cmd \
                "ffmpeg -hide_banner -f $codec -i - -c copy ioa-[dict get $dev id]-%Y%m%dT%H%M%S.mkv"]
        }
        uvc {
            return [dict create kind exec cmd \
                "ffmpeg -hide_banner -f $codec -i - -f v4l2 -pix_fmt yuyv422 /dev/video10"]
        }
        default {
            return [dict create kind exec cmd \
                "ffplay -hide_banner -fflags nobuffer -flags low_delay -f $codec -i -"]
        }
    }
}

# The full per-node manifest for a plan.
proc ioa::deploy::manifest {f plan {opts {}}} {
    set mode [ioa::dget $opts sink view]
    set nodes [dict get $plan nodes]
    set hops [dict get $plan hops]
    set rung [dict get $plan rung]
    set out {}

    for {set i 0} {$i < [llength $nodes]} {incr i} {
        set id [lindex $nodes $i]
        set dev [ioa::fabric::device $f $id]
        set steps {}

        if {$i == 0} {
            lappend steps [list capture [capture $dev $rung]]
        }
        if {$i > 0} {
            set in [lindex $hops [expr {$i - 1}]]
            lappend steps [list ingress [ioa::transport::realize rx $dev $in]]
        }
        if {$i > 0 && $i < [llength $nodes] - 1} {
            lappend steps [list forward [dict create kind config config [dict create \
                IOA_RING_BYTES 4194304 \
                IOA_REFRAME_MTU [dict get [lindex $hops $i] mtu] \
                IOA_FEC [dict get [lindex $hops $i] fec] \
                IOA_DROP_POLICY oldest-first]]]
        }
        if {$i < [llength $nodes] - 1} {
            set eg [lindex $hops $i]
            lappend steps [list egress [ioa::transport::realize tx $dev $eg]]
        }
        if {$i == [llength $nodes] - 1} {
            lappend steps [list sink [sink $dev $rung $mode]]
        }

        set role [expr {$i == 0 ? "source" : ($i == [llength $nodes] - 1 ? "sink" : "relay")}]
        lappend out [dict create node $id role $role \
            platform [dict get $dev platform] product [ioa::dget $dev product -] \
            steps $steps]
    }
    return $out
}

proc ioa::deploy::render {manifest} {
    set out [ioa::heading "deployment"]
    append out "\n"
    foreach n $manifest {
        append out [format "\n%s  \[%s, %s, %s\]\n" \
            [dict get $n node] [dict get $n role] [dict get $n platform] [dict get $n product]]
        foreach s [dict get $n steps] {
            lassign $s stage spec
            append out [format "  %-8s " $stage]
            switch -- [ioa::dget $spec kind note] {
                exec      { append out "$ [string map {\n { }} [dict get $spec cmd]]\n" }
                firmware  { append out "firmware:\n[kv [dict get $spec config] 12]"
                            if {[dict exists $spec flash]} {
                                append out [format "%12s\$ %s\n" "" [dict get $spec flash]] } }
                bitstream { append out "bitstream:\n[kv [dict get $spec config] 12]"
                            if {[dict exists $spec precheck]} {
                                append out [format "%12s\$ %s\n" "" [dict get $spec precheck]] }
                            append out [format "%12s\$ %s\n" "" [dict get $spec load]] }
                config    { append out "\n[kv [dict get $spec config] 12]" }
                inproc    { append out "in-process: [dict get $spec cmd]\n" }
                default   { append out "[ioa::dget $spec text [ioa::dget $spec note {}]]\n" }
            }
        }
    }
    return $out
}

proc ioa::deploy::kv {d indent} {
    set out ""
    dict for {k v} $d {
        append out [format "%*s%-20s %s\n" $indent "" $k $v]
    }
    return $out
}

package provide ioa::deploy 0.3.0
