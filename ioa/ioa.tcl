#!/usr/bin/env tclsh
# ioa -- Image Over Air.
#
# Cameras on one side, screens on the other, and whatever will carry bits in
# between: Wi-Fi, ESP-NOW, BLE, LoRa, infrared, Li-Fi, laser, HDMI, USB, UART,
# Ethernet. This program does not move pixels itself. It decides what can be
# moved over what, tells each box on the route how to do its part, and keeps
# deciding as the fabric changes.
#
#   ioa products                        the line
#   ioa transports                      every medium it can plan over
#   ioa plan   --from eye-01 --to desk  what would actually get through
#   ioa run    --from eye-01 --to desk  simulate it and check the plan
#   ioa deploy --from eye-01 --to desk  the commands to make it real
#   ioa demo                            all of the above, plus a failure

package require Tcl 8.6

namespace eval ioa::cli {
    variable root [file normalize [file dirname [info script]]]
}

foreach f {core transport frame codec budget products device fabric plan sim deploy session} {
    source [file join $ioa::cli::root lib $f.tcl]
}
foreach f {rf optical wired virtual} {
    source [file join $ioa::cli::root lib transports $f.tcl]
}

# ------------------------------------------------------------- arg parsing --

proc ioa::cli::args {argv spec} {
    set out $spec
    set rest {}
    for {set i 0} {$i < [llength $argv]} {incr i} {
        set a [lindex $argv $i]
        if {![string match --* $a]} { lappend rest $a; continue }
        set k [string map {- _} [string range $a 2 end]]
        if {[string match no_* $k] && [dict exists $out [string range $k 3 end]]} {
            dict set out [string range $k 3 end] 0
            continue
        }
        if {![dict exists $out $k]} {
            ioa::die "unknown option: $a (try: ioa help)"
        }
        # Boolean options may stand alone: --control, not --control 1.
        set next [lindex $argv [expr {$i + 1}]]
        if {[dict get $out $k] in {0 1} && ($next eq "" || [string match --* $next])} {
            dict set out $k 1
            continue
        }
        dict set out $k [lindex $argv [incr i]]
    }
    dict set out _rest $rest
    return $out
}

proc ioa::cli::fabric {o} {
    variable root
    set path [dict get $o fabric]
    if {![file exists $path]} {
        set alt [file join $root fabric $path]
        if {[file exists $alt]} { set path $alt } elseif {[file exists $alt.ioa]} { set path $alt.ioa }
    }
    ioa::fabric::load $path
}

proc ioa::cli::planOpts {o} {
    set p [dict create want [dict get $o want]]
    if {[dict get $o forbid] ne ""}  { dict set p forbid [split [dict get $o forbid] ,] }
    if {[dict get $o require] ne ""} { dict set p require [split [dict get $o require] ,] }
    if {[dict get $o budget_ms] ne ""} { dict set p budget_ms [dict get $o budget_ms] }
    if {[dict get $o target] ne ""}  { dict set p target_delivery [dict get $o target] }
    if {![dict get $o fec]}          { dict set p allow_fec 0 }
    if {[dict get $o control]}       { dict set p control 1 }
    if {[dict get $o sink] ne ""}    { dict set p sink [dict get $o sink] }
    return $p
}

variable ioa::cli::routeSpec {
    fabric studio.ioa from "" to "" want webcam
    forbid "" require "" budget_ms "" target "" fec 1 control 0 sink view
    seconds 10 seed ioa
}

proc ioa::cli::needRoute {o} {
    if {[dict get $o from] eq "" || [dict get $o to] eq ""} {
        ioa::die "need --from and --to (devices in [dict get $o fabric])"
    }
}

# ------------------------------------------------------------- subcommands --

proc ioa::cli::cmd_products {argv} {
    set o [args $argv {class "" sku ""}]
    if {[dict get $o sku] ne ""} {
        set p [ioa::product::get [dict get $o sku]]
        puts [ioa::heading "[dict get $p sku] -- [dict get $p name]"]
        puts "\n[dict get $p tagline]\n"
        foreach k {class status platform soc sensor encode encoder power_mw supply formfactor price_usd} {
            if {[dict exists $p $k] && [dict get $p $k] ne ""} {
                puts [format "  %-11s %s" $k [dict get $p $k]]
            }
        }
        if {[llength [ioa::dget $p transports {}]]} {
            puts "\n  interfaces"
            foreach t [dict get $p transports] {
                set c [ioa::transport::caps [lindex $t 0]]
                puts [format "    %-9s %-8s %-11s %s" [lindex $t 0] [lindex $t 1] \
                    [dict get $c medium] [ioa::bps [expr {int([dict get $c nominal_bps]*[dict get $c efficiency])}]]]
            }
        }
        if {[dict exists $p contains]} { puts "\n  contains     [join [dict get $p contains] {, }]" }
        puts "\n  [dict get $p notes]"
        return
    }

    set rows {}
    foreach p [ioa::product::all] {
        if {[dict get $o class] ne "" && [dict get $p class] ne [dict get $o class]} continue
        lappend rows [list [dict get $p sku] [dict get $p name] [dict get $p class] \
            [dict get $p status] [dict get $p platform] \
            [expr {[dict get $p price_usd] > 0 ? "\$[dict get $p price_usd]" : "-"}] \
            [dict get $p tagline]]
    }
    puts [ioa::heading "the ioa line"]
    puts "\n[ioa::table {sku name class status platform price what} $rows]"
    puts "\nioa products --sku IOA-EYE-S3   for one in full"
}

proc ioa::cli::cmd_transports {argv} {
    set o [args $argv {medium ""}]
    set rows {}
    foreach c [ioa::transport::all] {
        if {[dict get $o medium] ne "" && [dict get $c medium] ne [dict get $o medium]} continue
        lappend rows [list [dict get $c name] [dict get $c medium] [dict get $c duplex] \
            [ioa::bps [expr {int([dict get $c nominal_bps] * [dict get $c efficiency])}]] \
            [dict get $c mtu] \
            [format "%.1f" [dict get $c latency_ms]] \
            [format "%.2f%%" [expr {100*[dict get $c loss]}]] \
            [expr {[dict get $c range_m] > 0 ? "[dict get $c range_m] m" : "cable"}] \
            [expr {[dict get $c los] ? "yes" : "no"}] \
            "[dict get $c power_mw] mW"]
    }
    puts [ioa::heading "media ioa can plan over"]
    puts "\n[ioa::table {transport medium duplex goodput mtu ms loss range los tx} $rows]"
    puts "\nGoodput is application-visible throughput at short range, before IOAF framing."
}

proc ioa::cli::cmd_codecs {argv} {
    set rows {}
    foreach id [ioa::codec::rungNames] {
        set r [ioa::codec::rung $id]
        lappend rows [list $id [dict get $r codec] \
            "[dict get $r w]x[dict get $r h]" [dict get $r fps] [dict get $r q] \
            [ioa::bps [ioa::codec::bitrate $r]] \
            [ioa::bytes [ioa::codec::pictureBytes $r]] \
            [ioa::bytes [ioa::codec::keyframeBytes $r]]]
    }
    puts [ioa::heading "the ladder"]
    puts "\n[ioa::table {rung codec size fps q bitrate picture keyframe} $rows]"
    puts "\nnamed asks: [join [ioa::codec::profileNames] {, }]"
    puts "The planner starts at what you asked for and walks down until the fabric agrees."
}

proc ioa::cli::cmd_fabric {argv} {
    variable routeSpec
    set o [args $argv $routeSpec]
    if {[llength [dict get $o _rest]]} { dict set o fabric [lindex [dict get $o _rest] 0] }
    set f [fabric $o]
    puts [ioa::heading "[dict get $f name] -- [dict get $f site]"]
    puts "\n[ioa::fabric::summary $f]"
    set rows {}
    foreach e [ioa::fabric::edges $f] {
        lappend rows [list "[dict get $e from] -> [dict get $e to]" [dict get $e transport] \
            [dict get $e medium] [format "%.0f m" [dict get $e distance_m]] \
            [ioa::bps [dict get $e goodput_bps]] [dict get $e mtu] \
            [format "%.2f%%" [expr {100*[dict get $e loss]}]] \
            [expr {[dict get $e control_only] ? "control" : "media"}]]
    }
    puts "\n[ioa::table {edge transport medium distance capacity mtu loss grade} $rows]"
    foreach n [ioa::dget $f notes {}] { puts "\nnote: $n" }
}

proc ioa::cli::cmd_plan {argv} {
    variable routeSpec
    set o [args $argv $routeSpec]
    needRoute $o
    set f [fabric $o]
    puts [ioa::plan::explain [ioa::plan::route $f [dict get $o from] [dict get $o to] [planOpts $o]]]
}

proc ioa::cli::cmd_run {argv} {
    variable routeSpec
    set o [args $argv $routeSpec]
    needRoute $o
    set f [fabric $o]
    set p [ioa::plan::route $f [dict get $o from] [dict get $o to] [planOpts $o]]
    if {![dict get $p ok]} { puts [ioa::plan::explain $p]; exit 2 }
    puts [ioa::plan::explain $p]
    puts [ioa::sim::report $p [ioa::sim::run $p \
        [dict create seconds [dict get $o seconds] seed [dict get $o seed]]]]
}

proc ioa::cli::cmd_deploy {argv} {
    variable routeSpec
    set o [args $argv $routeSpec]
    needRoute $o
    set f [fabric $o]
    set p [ioa::plan::route $f [dict get $o from] [dict get $o to] [planOpts $o]]
    if {![dict get $p ok]} { puts [ioa::plan::explain $p]; exit 2 }
    puts [ioa::deploy::render [ioa::deploy::manifest $f $p [dict create sink [dict get $o sink]]]]
    puts "\nNothing above was executed. ioa plans and configures; the boxes do the moving."
}

proc ioa::cli::cmd_session {argv} {
    variable routeSpec
    # --event is repeatable, and each value is itself a list, so it cannot go
    # through the ordinary option parser without being flattened into five
    # separate events.
    set events {}
    set rest {}
    for {set i 0} {$i < [llength $argv]} {incr i} {
        if {[lindex $argv $i] eq "--event"} {
            lappend events [lindex $argv [incr i]]
        } else {
            lappend rest [lindex $argv $i]
        }
    }
    set o [args $rest $routeSpec]
    dict set o event $events
    needRoute $o
    set f [fabric $o]
    set s [ioa::session::open $f [dict get $o from] [dict get $o to] [planOpts $o]]
    set s [ioa::session::supervise $s [dict get $o event]]
    puts [ioa::session::report $s]
}

proc ioa::cli::cmd_selftest {argv} {
    variable root
    puts [exec [info nameofexecutable] [file join $root tests all.tcl] {*}$argv]
}

proc ioa::cli::cmd_demo {argv} {
    set studio    [fabric {fabric studio.ioa}]
    set darkroom  [fabric {fabric darkroom.ioa}]
    set backcount [fabric {fabric backcountry.ioa}]

    puts [ioa::heading "1. a room with cameras in it"]
    puts "\n[ioa::fabric::summary $studio]"

    puts [ioa::heading "2. a \$59 camera, asked for a webcam stream"]
    puts [ioa::plan::explain [ioa::plan::route $studio eye-01 desk {want webcam}]]
    puts "It cannot do 30 fps -- the sensor tops out at 25 -- so it offers 15 and says so."

    puts [ioa::heading "3. now take away the medium it depends on"]
    puts [ioa::plan::explain [ioa::plan::route $studio eye-01 desk \
        {want webcam forbid {wifi_tcp wifi_udp}}]]
    puts "That refusal is the useful part: this camera has exactly one way home,"
    puts "and now you know before the day you need the other one."

    puts [ioa::heading "4. a site that bans radio altogether"]
    puts [ioa::plan::explain [ioa::plan::route $darkroom eye-pro host {want hd forbid rf}]]
    puts "Same planner, same frames, no spectrum: Li-Fi across the room, a laser"
    puts "across the courtyard, copper for the last twenty metres."

    puts [ioa::heading "5. three kilometres from anything, on solar"]
    set far [ioa::plan::route $backcount eye-01 base {want webcam}]
    puts [ioa::plan::explain $far]
    puts [ioa::sim::report $far [ioa::sim::run $far {seconds 120 seed demo}]]

    puts [ioa::heading "6. and at the other end of the range: 1080p60 on a laser"]
    set fast [ioa::plan::route $studio eye-pro desk {want broadcast}]
    puts [ioa::plan::explain $fast]
    puts [ioa::sim::report $fast [ioa::sim::run $fast {seconds 20 seed demo}]]
    puts [ioa::deploy::render [ioa::deploy::manifest $studio $fast]]

    puts [ioa::heading "7. then somebody parks a van in the beam"]
    set s [ioa::session::open $studio eye-pro desk {want broadcast}]
    set s [ioa::session::supervise $s {
        {link eye-pro prism-near laser {alignment 0.3}}
        {medium rf {interference 0.8}}
        {want glance}
    }]
    puts [ioa::session::report $s]
    puts "\nNothing above touched any hardware. Section 6 printed what would."
}

proc ioa::cli::cmd_help {argv} {
    puts [ioa::heading "ioa $ioa::version -- Image Over Air"]
    puts {
  ioa products [--class camera|relay|optical|bridge|host|software|service|kit]
  ioa products --sku IOA-EYE-S3
  ioa transports [--medium rf|optical|electrical|virtual]
  ioa codecs
  ioa fabric [<file>]
  ioa plan    --from <device> --to <device> [options]
  ioa run     --from <device> --to <device> [--seconds N] [--seed S] [options]
  ioa deploy  --from <device> --to <device> [--sink view|record|uvc]
  ioa session --from <device> --to <device> --event 'link a b laser {alignment 0.3}'
              events: 'node-down <id>' | 'medium rf {interference 0.8}'
                      'link <a> <b> <transport> {<param> <value>}' | 'want <profile>'
  ioa demo
  ioa selftest

plan options
  --fabric <file>     default fabric/studio.ioa
  --want <profile>    cinema broadcast hd webcam machine glance trickle, or a rung id
  --forbid a,b        media the route may not use
  --require a,b       media the route must stick to
  --budget-ms N       reject routes slower than this one way
  --target 0.95       fraction of pictures that must arrive whole
  --no-fec            refuse forward error correction; see what survives without it

Everything is a model unless you run the commands ioa deploy prints. Nothing
here touches hardware on its own.}
}

# --------------------------------------------------------------- dispatch --

proc ioa::cli::main {argv} {
    set cmd [lindex $argv 0]
    if {$cmd in {"" -h --help help}} { cmd_help {}; return 0 }
    if {$cmd in {-v --version version}} { puts "ioa $ioa::version"; return 0 }
    if {[info commands ::ioa::cli::cmd_$cmd] eq ""} {
        ioa::die "no such command: $cmd (try: ioa help)"
    }
    # Being piped into head is not an error worth a stack trace.
    if {[catch {cmd_$cmd [lrange $argv 1 end]} err opts]} {
        if {[string match "*broken pipe*" $err]} { return 0 }
        if {[lindex [dict get $opts -errorcode] 0] eq "IOA"} { ioa::die $err }
        return -options $opts $err
    }
    return 0
}

if {[info exists argv0] && [file normalize $argv0] eq [file normalize [info script]]} {
    exit [ioa::cli::main $argv]
}
