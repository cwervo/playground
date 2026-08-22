# ioa/lib/session.tcl -- the orchestrator.
#
# A session is one camera reaching one screen, held open across a fabric that
# keeps changing. Everything below is the loop: plan, deploy, watch, re-plan.
# The interesting behaviour is what it does when a link degrades -- it does
# not simply fail, it renegotiates down the ladder or reroutes onto another
# medium, and it records why, because the record is what an operator debugs.

package require Tcl 8.6

namespace eval ioa::session {
    variable counter 0
}

proc ioa::session::open {f src dst {opts {}}} {
    variable counter
    set s [dict create \
        id "s[incr counter]" \
        fabric $f src $src dst $dst opts $opts \
        state planning history {} plan {} alternate {}]
    return [replan $s "session opened"]
}

proc ioa::session::replan {s why} {
    set f [dict get $s fabric]
    set plan [ioa::plan::route $f [dict get $s src] [dict get $s dst] [dict get $s opts]]
    set prev [dict get $s plan]

    if {![dict get $plan ok]} {
        dict set s state dark
        dict set s plan {}
        dict lappend s history [dict create why $why state dark \
            detail [dict get $plan reason] rung - path -]
        dict set s last $plan
        return $s
    }

    dict set s plan $plan
    dict set s last $plan
    dict set s alternate [ioa::plan::alternate $f $plan]
    dict set s state running
    dict set s manifest [ioa::deploy::manifest $f $plan [dict get $s opts]]

    set detail [transition $prev $plan]
    dict lappend s history [dict create why $why state running detail $detail \
        rung [dict get $plan rung_id] path [join [dict get $plan nodes] "->"]]
    return $s
}

proc ioa::session::transition {prev plan} {
    if {$prev eq ""} {
        return [format "%s over %s, %.1f%% delivery" \
            [dict get $plan rung_id] [dict get $plan bottleneck] \
            [expr {100*[dict get $plan delivery]}]]
    }
    set bits {}
    if {[dict get $prev rung_id] ne [dict get $plan rung_id]} {
        lappend bits "quality [dict get $prev rung_id] -> [dict get $plan rung_id]"
    }
    if {[dict get $prev nodes] ne [dict get $plan nodes]} {
        lappend bits "rerouted via [join [dict get $plan nodes] { -> }]"
    }
    if {[dict get $prev bottleneck] ne [dict get $plan bottleneck]} {
        lappend bits "bottleneck now [dict get $plan bottleneck]"
    }
    if {![llength $bits]} { lappend bits "unchanged" }
    join $bits "; "
}

# Apply a change to the world, then let the session cope with it.
#
#   {node-down eye-01}
#   {medium rf {interference 0.85}}
#   {link eye-pro prism-near laser {alignment 0.3}}
proc ioa::session::event {s ev} {
    set f [dict get $s fabric]
    switch -- [lindex $ev 0] {
        node-down {
            set id [lindex $ev 1]
            set f [ioa::fabric::removeDevice $f $id]
            set why "$id went down"
        }
        medium {
            set f [ioa::fabric::degradeMedium $f [lindex $ev 1] [lindex $ev 2]]
            set why "[lindex $ev 1] medium degraded ([lindex $ev 2])"
        }
        link {
            set f [ioa::fabric::setLinkParams $f [lindex $ev 1] [lindex $ev 2] \
                       [lindex $ev 3] [lindex $ev 4]]
            set why "[lindex $ev 1] -> [lindex $ev 2] over [lindex $ev 3] changed ([lindex $ev 4])"
        }
        want {
            dict set s opts [dict merge [dict get $s opts] [dict create want [lindex $ev 1]]]
            set why "operator asked for [lindex $ev 1]"
        }
        default { error "unknown session event: [lindex $ev 0]" {} {IOA SESSION EVENT} }
    }
    dict set s fabric $f
    replan $s $why
}

proc ioa::session::supervise {s events} {
    foreach ev $events { set s [event $s $ev] }
    return $s
}

proc ioa::session::report {s} {
    set out [ioa::heading "session [dict get $s id]: [dict get $s src] -> [dict get $s dst] ([dict get $s state])"]
    append out "\n"
    set rows {}
    set n 0
    foreach h [dict get $s history] {
        lappend rows [list [incr n] [dict get $h why] [dict get $h state] \
            [dict get $h rung] [dict get $h path] [dict get $h detail]]
    }
    append out [ioa::table {# event state carrying path outcome} $rows] "\n"

    if {[dict get $s state] eq "running"} {
        set alt [dict get $s alternate]
        if {$alt eq ""} {
            append out "\nno independent fallback route: every path shares a medium with the primary.\n"
        } else {
            append out [format "\nfallback ready: %s at %s (%s), %.1f ms\n" \
                [join [dict get $alt nodes] " -> "] [dict get $alt rung_id] \
                [dict get $alt bottleneck] [dict get $alt latency_ms]]
        }
    } else {
        append out "\ndark: [dict get [dict get $s last] reason]\n"
    }
    return $out
}

package provide ioa::session 0.3.0
