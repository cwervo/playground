# ioa/lib/plan.tcl -- route selection.
#
# The planner answers one question: given this fabric, what is the best
# picture that can actually get from A to B, by which path, and at what cost?
#
# It works by descending the codec ladder. For each rung it asks every edge
# whether it could carry that rung -- with forward error correction if the
# fragment count demands it -- then runs a shortest-path over the edges that
# survive. The first rung with a viable path wins. Everything rejected on the
# way down is kept, because "why is my camera at 320x240" is the question
# operators actually ask.

package require Tcl 8.6

namespace eval ioa::plan {
    variable defaults {
        want            webcam
        target_delivery 0.95
        utilization     0.80
        allow_fec       1
        budget_ms       Inf
        max_hops        6
        hop_penalty_ms  0.5
        control         0
        forbid          {}
        require         {}
    }
}

proc ioa::plan::route {f src dst {opts {}}} {
    variable defaults
    set o [dict merge $defaults $opts]

    set srcDev [ioa::fabric::device $f $src]
    set dstDev [ioa::fabric::device $f $dst]
    set edges [ioa::fabric::edges $f]

    set startRung [dict get [ioa::codec::resolve [dict get $o want]] id]
    set tried {}

    foreach rung [ioa::codec::descent $startRung] {
        set rid [dict get $rung id]

        if {![ioa::codec::withinCeiling $rung [dict get $srcDev encode]]} {
            lappend tried [list $rid "beyond [dict get $srcDev id] encoder ceiling ([dict get $srcDev encode])"]
            continue
        }

        lassign [feasibleEdges $edges $rung $o] usable rejects
        if {![llength $usable]} {
            lappend tried [list $rid "no edge can carry [ioa::bps [ioa::codec::bitrate $rung]] ([lindex $rejects 0])"]
            continue
        }

        set path [dijkstra $usable $src $dst [dict get $o max_hops] [dict get $o hop_penalty_ms]]
        if {$path eq ""} {
            lappend tried [list $rid "no path within [dict get $o max_hops] hops over the edges that can carry it"]
            continue
        }

        set plan [assemble $f $rung $path $o]
        if {[dict get $plan latency_ms] > [dict get $o budget_ms]} {
            lappend tried [list $rid [format "latency %.1f ms exceeds budget %s ms" \
                [dict get $plan latency_ms] [dict get $o budget_ms]]]
            continue
        }
        if {[dict get $plan delivery] < [dict get $o target_delivery]} {
            lappend tried [list $rid [format "end-to-end delivery %.1f%% below target %.0f%%" \
                [expr {100 * [dict get $plan delivery]}] [expr {100 * [dict get $o target_delivery]}]]]
            continue
        }

        return [dict merge $plan [dict create ok 1 tried $tried src $src dst $dst opts $o]]
    }

    dict create ok 0 src $src dst $dst tried $tried opts $o \
        reason "no rung from $startRung down to [lindex [ioa::codec::rungNames] end] survives this fabric"
}

# Which edges can carry $rung, and what FEC each one needs to do it.
proc ioa::plan::feasibleEdges {edges rung o} {
    set bytes [ioa::codec::pictureBytes $rung]
    set key   [ioa::codec::keyframeBytes $rung]
    set fps   [dict get $rung fps]
    set usable {}
    set rejects {}

    foreach e $edges {
        set t [dict get $e transport]
        set m [dict get $e medium]
        # forbid/require accept a transport name or a whole medium, so
        # "--forbid rf" is a thing you can say on a site that bans radio.
        if {$t in [dict get $o forbid] || $m in [dict get $o forbid]} {
            lappend rejects "$t forbidden"; continue
        }
        if {[llength [dict get $o require]]
            && $t ni [dict get $o require] && $m ni [dict get $o require]} {
            lappend rejects "$t not in required set"; continue
        }
        if {[dict get $e control_only] && ![dict get $o control]} {
            lappend rejects "$t is a control-grade interface here"; continue
        }
        if {[dict get $e goodput_bps] <= 0} {
            lappend rejects "$t out of range at [dict get $e distance_m] m"; continue
        }

        set fec 1.0
        set h [ioa::budget::hop $e $bytes]
        if {[dict get $h delivery] < [dict get $o target_delivery]} {
            if {![dict get $o allow_fec]} {
                lappend rejects [format "%s delivers %.0f%% of pictures unaided" $t [expr {100*[dict get $h delivery]}]]
                continue
            }
            set fec [ioa::budget::chooseFec $e $bytes [dict get $o target_delivery]]
            if {$fec eq ""} {
                lappend rejects [format "%s: %d fragments at %.1f%% loss is unrecoverable" \
                    $t [dict get $h fragments] [expr {100*[dict get $h loss]}]]
                continue
            }
            set h [ioa::budget::hop $e $bytes $fec]
        }

        # Sustained load, and the keyframe burst, must both fit the budget.
        set offered [ioa::budget::offeredBps $e $bytes $fps $fec]
        set ceiling [expr {[dict get $e goodput_bps] * [dict get $o utilization]}]
        if {$offered > $ceiling} {
            lappend rejects [format "%s offers %s into %s of usable capacity" \
                $t [ioa::bps $offered] [ioa::bps $ceiling]]
            continue
        }
        set keyMs [dict get [ioa::budget::hop $e $key $fec] serialization_ms]

        dict set e fec $fec
        dict set e hop $h
        dict set e offered_bps $offered
        dict set e keyframe_ms $keyMs
        dict set e cost [expr {[dict get $h latency_ms] + [dict get $e jitter_ms]}]
        lappend usable $e
    }
    list $usable $rejects
}

# Plain Dijkstra over device ids, minimising predicted one-way latency.
proc ioa::plan::dijkstra {edges src dst maxHops hopPenalty} {
    set adj [dict create]
    foreach e $edges {
        dict lappend adj [dict get $e from] $e
    }

    set dist [dict create $src 0.0]
    set hops [dict create $src 0]
    set prev [dict create]
    set queue [list $src]
    set done [dict create]

    while {[llength $queue]} {
        # Small graphs: a linear scan for the nearest node is cheaper than a heap.
        set best ""
        set bestd Inf
        foreach n $queue {
            if {[dict get $dist $n] < $bestd} { set bestd [dict get $dist $n]; set best $n }
        }
        set queue [lsearch -all -inline -not -exact $queue $best]
        dict set done $best 1
        if {$best eq $dst} break
        if {[dict get $hops $best] >= $maxHops} continue

        foreach e [ioa::dget $adj $best {}] {
            set to [dict get $e to]
            if {[dict exists $done $to]} continue
            set nd [expr {$bestd + [dict get $e cost] + $hopPenalty}]
            if {![dict exists $dist $to] || $nd < [dict get $dist $to]} {
                dict set dist $to $nd
                dict set hops $to [expr {[dict get $hops $best] + 1}]
                dict set prev $to $e
                if {$to ni $queue} { lappend queue $to }
            }
        }
    }

    if {![dict exists $prev $dst]} { return {} }
    set path {}
    set at $dst
    while {$at ne $src} {
        set e [dict get $prev $at]
        set path [linsert $path 0 $e]
        set at [dict get $e from]
    }
    return $path
}

# Turn a path into the numbers an operator has to live with.
proc ioa::plan::assemble {f rung path o} {
    set latency 0.0
    set delivery 1.0
    set power 0
    set worst 0.0
    set nodes [list [dict get [lindex $path 0] from]]

    foreach e $path {
        set h [dict get $e hop]
        set latency [expr {$latency + [dict get $h latency_ms] + [dict get $e jitter_ms] \
                           + [dict get $o hop_penalty_ms]}]
        set delivery [expr {$delivery * [dict get $h delivery]}]
        set power [expr {$power + [dict get $e power_mw]}]
        if {[dict get $e keyframe_ms] > $worst} { set worst [dict get $e keyframe_ms] }
        lappend nodes [dict get $e to]
    }

    # The slowest hop sets the sustainable frame rate, no matter how fast the
    # rest of the chain is.
    set bottleneck [lindex $path 0]
    foreach e $path {
        if {[dict get $e goodput_bps] < [dict get $bottleneck goodput_bps]} { set bottleneck $e }
    }

    dict create \
        rung $rung rung_id [dict get $rung id] \
        bitrate_bps [ioa::codec::bitrate $rung] \
        picture_bytes [ioa::codec::pictureBytes $rung] \
        hops $path nodes $nodes \
        latency_ms $latency delivery $delivery \
        keyframe_stall_ms $worst \
        power_mw $power \
        bottleneck [dict get $bottleneck transport] \
        bottleneck_bps [dict get $bottleneck goodput_bps] \
        headroom [expr {double([dict get $bottleneck goodput_bps]) / max(1,[dict get $bottleneck offered_bps])}]
}

# A second, disjoint path to fail over to, avoiding the transports the
# primary leans on. Returns {} when the fabric has no independent route.
proc ioa::plan::alternate {f plan} {
    set used {}
    foreach e [dict get $plan hops] { lappend used [dict get $e transport] }
    set o [dict merge [dict get $plan opts] [dict create forbid $used]]
    set alt [route $f [dict get $plan src] [dict get $plan dst] $o]
    if {![dict get $alt ok]} { return {} }
    return $alt
}

proc ioa::plan::explain {plan} {
    if {![dict get $plan ok]} {
        set out [ioa::heading "no route: [dict get $plan src] -> [dict get $plan dst]"]
        append out "\n[dict get $plan reason]\n\ntried:\n"
        foreach t [dict get $plan tried] {
            append out [format "  %-12s %s\n" [lindex $t 0] [lindex $t 1]]
        }
        return $out
    }

    set out [ioa::heading "route: [join [dict get $plan nodes] { -> }]"]
    append out "\n"
    append out [format "  carrying     %s\n" [ioa::codec::describe [dict get $plan rung]]]
    append out [format "  picture      %s per frame, %s keyframe stall worst hop\n" \
        [ioa::bytes [dict get $plan picture_bytes]] [ioa::ms [dict get $plan keyframe_stall_ms]]]
    append out [format "  latency      %s one way\n" [ioa::ms [dict get $plan latency_ms]]]
    append out [format "  delivery     %.2f%% of pictures arrive whole\n" [expr {100*[dict get $plan delivery]}]]
    append out [format "  bottleneck   %s at %s (%.1fx headroom)\n" \
        [dict get $plan bottleneck] [ioa::bps [dict get $plan bottleneck_bps]] [dict get $plan headroom]]
    append out [format "  radiated     %d mW across %d hop(s)\n" \
        [dict get $plan power_mw] [llength [dict get $plan hops]]]

    set rows {}
    foreach e [dict get $plan hops] {
        set h [dict get $e hop]
        lappend rows [list \
            "[dict get $e from] -> [dict get $e to]" \
            [dict get $e transport] \
            [dict get $e medium] \
            [format "%.0f m" [dict get $e distance_m]] \
            [ioa::bps [dict get $e goodput_bps]] \
            [ioa::bps [dict get $e offered_bps]] \
            [dict get $h fragments] \
            [format "%.2fx" [dict get $e fec]] \
            [format "%.2f%%" [expr {100*[dict get $h loss]}]] \
            [format "%.1f%%" [expr {100*[dict get $h delivery]}]] \
            [format "%.1f" [dict get $h latency_ms]]]
    }
    append out "\n" [ioa::table \
        {hop transport medium dist capacity offered frags fec loss delivered ms} $rows] "\n"

    if {[llength [dict get $plan tried]]} {
        append out "\nrungs refused on the way down:\n"
        foreach t [dict get $plan tried] {
            append out [format "  %-12s %s\n" [lindex $t 0] [lindex $t 1]]
        }
    }
    return $out
}

package provide ioa::plan 0.3.0
