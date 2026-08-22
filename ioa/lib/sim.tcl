# ioa/lib/sim.tcl -- run the plan against a modelled fabric.
#
# The planner predicts. This disagrees with it, on purpose. It pushes pictures
# through the route one at a time with a deterministic channel: per-fragment
# loss draws, serialisation, and a store-and-forward queue at every relay that
# can and does overflow. When the simulation and the plan disagree, the plan
# was optimistic about something, and that is worth knowing before the install.
#
# A sample of pictures is also run through the real IOAF encoder and
# reassembler, so the wire format is exercised rather than assumed.

package require Tcl 8.6

namespace eval ioa::sim {
    variable defaults {
        seconds       10
        seed          "ioa"
        ring_bytes    4194304
        max_queue_ms  400
        verify        8
        size_jitter   0.25
    }
}

proc ioa::sim::run {plan {opts {}}} {
    variable defaults
    set o [dict merge $defaults $opts]

    set rung  [dict get $plan rung]
    set fps   [dict get $rung fps]
    set gop   [dict get $rung gop]
    set avg   [dict get $plan picture_bytes]
    set keyB  [ioa::codec::keyframeBytes $rung]
    set n     [expr {int(ceil([dict get $o seconds] * $fps))}]
    set hops  [dict get $plan hops]

    set rng [ioa::rng "[dict get $o seed]/[dict get $plan rung_id]/[llength $hops]"]

    # Per-hop state: when the transmitter is next idle, and what is queued.
    set free {}
    set queued {}
    set dropQueue {}
    set dropLoss {}
    foreach e $hops {
        lappend free 0.0
        lappend queued 0
        lappend dropQueue 0
        lappend dropLoss 0
    }

    set delivered 0
    set latencies {}
    set bytesIn 0
    set bytesWire 0
    set peakQueue 0

    for {set k 0} {$k < $n} {incr k} {
        set t [expr {1000.0 * $k / $fps}]
        set isKey [expr {$gop > 1 && $k % $gop == 0}]
        set size [expr {int(($isKey ? $keyB : $avg) * (1.0 - [dict get $o size_jitter] \
                          + 2.0 * [dict get $o size_jitter] * [ioa::draw $rng]))}]
        if {$size < 64} { set size 64 }
        incr bytesIn $size

        set now $t
        set alive 1
        for {set i 0} {$i < [llength $hops] && $alive} {incr i} {
            set e [lindex $hops $i]
            set fec [dict get $e fec]
            set h [ioa::budget::hop $e $size $fec]
            set nsent [dict get $h sent]
            set repair [dict get $h repair]
            incr bytesWire [dict get $h wire_bytes]

            # Store and forward: wait for the transmitter, and for the ring.
            set start [expr {max($now, [lindex $free $i])}]
            set wait [expr {$start - $now}]
            set backlog [expr {int([lindex $queued $i] + $size)}]
            if {$wait > [dict get $o max_queue_ms] || $backlog > [dict get $o ring_bytes]} {
                lset dropQueue $i [expr {[lindex $dropQueue $i] + 1}]
                set alive 0
                break
            }
            if {$backlog > $peakQueue} { set peakQueue $backlog }
            lset queued $i $backlog

            set serial [dict get $h serialization_ms]
            lset free $i [expr {$start + $serial}]
            lset queued $i [expr {max(0, [lindex $queued $i] - $size)}]

            # Fragment-level loss. Below the repair threshold the FEC covers it.
            set lost 0
            set p [dict get $e loss]
            for {set fgi 0} {$fgi < $nsent} {incr fgi} {
                if {[ioa::draw $rng] < $p} { incr lost }
            }
            if {$lost > $repair} {
                lset dropLoss $i [expr {[lindex $dropLoss $i] + 1}]
                set alive 0
                break
            }

            set jit [expr {[dict get $e jitter_ms] * [ioa::draw $rng]}]
            set now [expr {$start + $serial + [dict get $e latency_ms] + $jit}]
        }

        if {$alive} {
            incr delivered
            lappend latencies [expr {$now - $t}]
        }
    }

    set res [dict create \
        pictures $n delivered $delivered \
        delivery [expr {$n > 0 ? double($delivered) / $n : 0.0}] \
        effective_fps [expr {[dict get $o seconds] > 0 ? $delivered / double([dict get $o seconds]) : 0}] \
        bytes_in $bytesIn bytes_wire $bytesWire \
        wire_overhead_pct [expr {$bytesIn > 0 ? 100.0 * ($bytesWire - $bytesIn) / $bytesIn : 0}] \
        peak_queue_bytes $peakQueue \
        seconds [dict get $o seconds] seed [dict get $o seed]]

    dict set res latency [stats $latencies]

    set perHop {}
    for {set i 0} {$i < [llength $hops]} {incr i} {
        set e [lindex $hops $i]
        lappend perHop [dict create \
            hop "[dict get $e from] -> [dict get $e to]" \
            transport [dict get $e transport] \
            lost_to_loss [lindex $dropLoss $i] \
            lost_to_queue [lindex $dropQueue $i]]
    }
    dict set res hops $perHop
    dict set res verify [verifyWire $plan [dict get $o verify] $rng]
    return $res
}

proc ioa::sim::stats {xs} {
    if {![llength $xs]} { return [dict create n 0 min 0 mean 0 p95 0 max 0] }
    set s [lsort -real $xs]
    set sum 0.0
    foreach x $s { set sum [expr {$sum + $x}] }
    dict create \
        n [llength $s] \
        min [lindex $s 0] \
        mean [expr {$sum / [llength $s]}] \
        p95 [lindex $s [expr {int(0.95 * ([llength $s] - 1))}]] \
        max [lindex $s end]
}

# Push real bytes through the real framing code over the narrowest hop on the
# route: fragment, parse, reassemble, compare. This is the part that would
# catch an MTU that cannot hold a header or a fragment count that overflows
# the field. Loss is not injected here -- the simulation above already covers
# that -- but one frame per picture is deliberately corrupted to confirm the
# CRC rejects it instead of handing a torn picture to the sink.
proc ioa::sim::verifyWire {plan count rng} {
    set narrow [lindex [dict get $plan hops] 0]
    foreach e [dict get $plan hops] {
        if {[dict get $e mtu] < [dict get $narrow mtu]} { set narrow $e }
    }
    set size [dict get $plan picture_bytes]
    set r [ioa::frame::reassembler 8]
    set ok 0
    set fragsTotal 0
    set caught 0

    for {set k 0} {$k < $count} {incr k} {
        # A JPEG-shaped payload: SOI, filler, EOI. ioa never inspects it.
        set body [binary format H* ffd8ffe0]
        append body [string repeat [binary format H* [format %02x [expr {int(255*[ioa::draw $rng])}]] ] \
                        [expr {max(1, $size - 6)}]]
        append body [binary format H* ffd9]

        set frames [ioa::frame::fragment \
            [dict create stream 1 seq $k codec [dict get $plan rung codec] flags 1] \
            $body [dict get $narrow mtu]]
        incr fragsTotal [llength $frames]

        set got ""
        foreach f $frames {
            set parsed [ioa::frame::unpack $f]
            set done [ioa::frame::feed $r $parsed]
            if {$done ne ""} { set got $done }
        }
        if {$got ne "" && [dict get $got payload] eq $body} { incr ok }

        # Flip a payload byte and confirm the frame is refused.
        set torn [lindex $frames 0]
        set at [expr {[ioa::frame::overhead] + 1}]
        set torn [string replace $torn $at $at [binary format c             [expr {([scan [string index $torn $at] %c] + 1) & 0xff}]]]
        if {[catch {ioa::frame::unpack $torn} _ eo]
            && [lrange [dict get $eo -errorcode] 0 2] eq {IOA FRAME CRC}} { incr caught }
    }
    set stats [ioa::frame::reasmStats $r]
    ioa::frame::reasmDestroy $r

    dict create attempted $count intact $ok mtu [dict get $narrow mtu] \
        transport [dict get $narrow transport] fragments $fragsTotal \
        corruption_caught $caught reassembler $stats
}

proc ioa::sim::report {plan res} {
    set out [ioa::heading "simulated [dict get $res seconds] s over [join [dict get $plan nodes] { -> }]"]
    append out "\n"
    append out [format "  pictures     %d offered, %d delivered (%.1f%%)\n" \
        [dict get $res pictures] [dict get $res delivered] [expr {100*[dict get $res delivery]}]]
    append out [format "  predicted    %.1f%% -- %s\n" [expr {100*[dict get $plan delivery]}] \
        [verdict [dict get $plan delivery] [dict get $res delivery]]]
    append out [format "  frame rate   %.1f fps sustained (asked for %g)\n" \
        [dict get $res effective_fps] [dict get $plan rung fps]]
    set l [dict get $res latency]
    append out [format "  latency      min %.1f  mean %.1f  p95 %.1f  max %.1f ms\n" \
        [dict get $l min] [dict get $l mean] [dict get $l p95] [dict get $l max]]
    append out [format "  predicted    %.1f ms one way\n" [dict get $plan latency_ms]]
    append out [format "  moved        %s of pictures as %s on the wire (+%.1f%% framing and FEC)\n" \
        [ioa::bytes [dict get $res bytes_in]] [ioa::bytes [dict get $res bytes_wire]] \
        [dict get $res wire_overhead_pct]]
    append out [format "  peak queue   %s\n" [ioa::bytes [dict get $res peak_queue_bytes]]]

    set rows {}
    foreach h [dict get $res hops] {
        lappend rows [list [dict get $h hop] [dict get $h transport] \
            [dict get $h lost_to_loss] [dict get $h lost_to_queue]]
    }
    append out "\n" [ioa::table {hop transport "lost to loss" "lost to backlog"} $rows] "\n"

    set v [dict get $res verify]
    append out [format "\nwire check: %d/%d pictures round-tripped byte-identical through real IOAF framing over %s (mtu %d, %d fragments); %d/%d corrupted frames refused by CRC\n" \
        [dict get $v intact] [dict get $v attempted] [dict get $v transport] \
        [dict get $v mtu] [dict get $v fragments] \
        [dict get $v corruption_caught] [dict get $v attempted]]
    return $out
}

proc ioa::sim::verdict {predicted observed} {
    set d [expr {$observed - $predicted}]
    if {abs($d) < 0.02} { return "plan holds" }
    if {$d < 0} { return [format "plan was optimistic by %.1f points" [expr {-100*$d}]] }
    return [format "plan was pessimistic by %.1f points" [expr {100*$d}]]
}

package provide ioa::sim 0.3.0
