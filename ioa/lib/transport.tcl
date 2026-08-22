# ioa/lib/transport.tcl -- the medium-agnostic driver registry.
#
# Everything ioa can push a picture through -- Wi-Fi, ESP-NOW, BLE, LoRa, IR,
# Li-Fi, laser, HDMI, USB, UART, Ethernet -- registers here with the same
# handful of numbers. The planner never asks "is this a radio?"; it asks for
# goodput, MTU, latency and loss, and every medium has to answer.

package require Tcl 8.6

namespace eval ioa::transport {
    variable drivers [dict create]
    variable order {}
}

# spec keys:
#   medium      rf | optical | electrical | virtual
#   band        human-readable spectrum note
#   duplex      full | half | simplex
#   nominal_bps raw PHY rate before protocol overhead
#   efficiency  fraction of nominal that reaches the application
#   mtu         bytes per packet, header included
#   latency_ms  one-way floor
#   jitter_ms   one-way spread
#   loss        packet loss floor at short range
#   range_m     usable distance; 0 means "cable length, not a limit"
#   los         1 if it needs line of sight
#   power_mw    transmitter draw at full rate
#   platforms   host families that can terminate it
#   derate      proc {caps params} -> {goodput_bps loss} for the actual geometry
#   realize     proc {dir node link} -> shell/firmware invocation on real gear
proc ioa::transport::define {name spec} {
    variable drivers
    variable order
    if {![dict exists $drivers $name]} { lappend order $name }
    dict set drivers $name [dict merge [dict create \
        name $name medium rf duplex full efficiency 0.7 jitter_ms 0 \
        loss 0.0 range_m 0 los 0 power_mw 0 platforms {any} \
        derate ioa::transport::derateFlat realize ioa::transport::realizeStub \
    ] $spec]
}

proc ioa::transport::exists {name} {
    variable drivers
    dict exists $drivers $name
}

proc ioa::transport::caps {name} {
    variable drivers
    if {![dict exists $drivers $name]} {
        error "unknown transport: $name" {} {IOA TRANSPORT UNKNOWN}
    }
    dict get $drivers $name
}

proc ioa::transport::names {} { variable order; return $order }

proc ioa::transport::all {} {
    set out {}
    foreach n [names] { lappend out [caps $n] }
    return $out
}

# ------------------------------------------------------------- derating ---

# Wired and virtual media: geometry does not move the numbers.
proc ioa::transport::derateFlat {caps params} {
    list [expr {int([dict get $caps nominal_bps] * [dict get $caps efficiency])}] \
         [dict get $caps loss]
}

# Radio: usable rate falls off with distance and with how much of the band
# somebody else is already using. Not a propagation model -- a rate-ladder
# approximation of what these chipsets actually negotiate.
proc ioa::transport::derateRf {caps params} {
    set d     [ioa::dget $params distance_m 5]
    set range [dict get $caps range_m]
    set noise [ioa::dget $params interference 0.0]

    set ratio [expr {$range > 0 ? double($d) / $range : 0.0}]
    if {$ratio > 1.0} { return [list 0 1.0] }
    # Flat to 30% of rated range, then a squared roll-off to 15% of rate.
    set f [expr {$ratio <= 0.3 ? 1.0 : 1.0 - 0.85 * (($ratio - 0.3) / 0.7) ** 2}]
    set f [expr {$f * (1.0 - $noise)}]

    set g [expr {int([dict get $caps nominal_bps] * [dict get $caps efficiency] * $f)}]
    set loss [expr {[dict get $caps loss] + 0.05 * $ratio ** 3 + 0.1 * $noise}]
    list $g [expr {min($loss, 1.0)}]
}

# Free-space optical: distance matters less than aim and ambient light. A
# misaligned laser is not a slow link, it is no link.
proc ioa::transport::derateOptical {caps params} {
    set d     [ioa::dget $params distance_m 5]
    set range [dict get $caps range_m]
    set aim   [ioa::dget $params alignment 1.0]
    set lux   [ioa::dget $params ambient_lux 200]

    if {$range > 0 && $d > $range} { return [list 0 1.0] }
    if {$aim < 0.5} { return [list 0 1.0] }

    set spread [expr {$range > 0 ? 1.0 - 0.5 * (double($d) / $range) ** 2 : 1.0}]
    set sun    [expr {1.0 - min(0.6, $lux / 100000.0)}]
    set f      [expr {$spread * $sun * ($aim ** 2)}]

    set g [expr {int([dict get $caps nominal_bps] * [dict get $caps efficiency] * $f)}]
    set loss [expr {[dict get $caps loss] + 0.15 * (1.0 - $aim) + $lux / 500000.0}]
    list $g [expr {min($loss, 1.0)}]
}

# ------------------------------------------------------------------ link ---

# Resolve an abstract edge into the numbers the planner and simulator use.
proc ioa::transport::link {from to name {params {}}} {
    set c [caps $name]
    lassign [{*}[dict get $c derate] $c $params] goodput loss

    # Half-duplex media pay for turnaround on every acknowledged burst.
    set latency [dict get $c latency_ms]
    if {[dict get $c duplex] eq "half"} {
        set latency [expr {$latency * 1.5}]
    }

    dict create \
        from $from to $to transport $name \
        medium [dict get $c medium] duplex [dict get $c duplex] \
        mtu [dict get $c mtu] \
        goodput_bps $goodput \
        nominal_bps [dict get $c nominal_bps] \
        latency_ms $latency jitter_ms [dict get $c jitter_ms] \
        loss $loss los [dict get $c los] \
        power_mw [dict get $c power_mw] \
        params $params \
        distance_m [ioa::dget $params distance_m 5]
}

# Time on the wire for one packet of $bytes, ignoring queueing.
proc ioa::transport::serializationMs {link bytes} {
    set g [dict get $link goodput_bps]
    if {$g <= 0} { return Inf }
    expr {double($bytes) * 8000.0 / $g}
}

proc ioa::transport::realizeStub {dir node link} {
    return [list note "no host-side realization for [dict get $link transport]"]
}

# What to actually run, on real hardware, to stand this link up.
proc ioa::transport::realize {dir node link} {
    set c [caps [dict get $link transport]]
    {*}[dict get $c realize] $dir $node $link
}

package provide ioa::transport 0.3.0
