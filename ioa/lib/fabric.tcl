# ioa/lib/fabric.tcl -- the installation, as a small declarative language.
#
#   fabric "Studio A" { site "Kreuzberg, 3rd floor" }
#   device eye-01  { product IOA-EYE-S3  place "north truss" }
#   device desk    { product IOA-HUB-X   platform macos }
#   link eye-01 relay-a espnow   {distance_m 18}
#   link relay-a desk  wifi_tcp  {distance_m 6 peer 10.0.0.4}
#
# Loaded in a safe interpreter: a fabric file is data, and describing someone
# else's rig should never be able to run code on yours.

package require Tcl 8.6

namespace eval ioa::fabric {
    variable loading {}
}

proc ioa::fabric::new {{name "untitled"}} {
    dict create name $name site "" notes {} devices [dict create] links {}
}

proc ioa::fabric::load {path} {
    if {![file readable $path]} {
        error "cannot read fabric: $path" {} {IOA FABRIC NOFILE}
    }
    parse [read [open $path r]] [file rootname [file tail $path]]
}

proc ioa::fabric::parse {text {name "untitled"}} {
    variable loading
    set saved $loading
    set loading [new $name]

    set i [interp create -safe]
    foreach cmd {fabric site device link note} {
        $i alias $cmd ioa::fabric::_$cmd
    }
    if {[catch {$i eval $text} err opts]} {
        interp delete $i
        set loading $saved
        error "fabric $name: $err" {} {IOA FABRIC PARSE}
    }
    interp delete $i

    set f $loading
    set loading $saved
    validate $f
    return $f
}

proc ioa::fabric::_fabric {name {spec {}}} {
    variable loading
    dict set loading name $name
    foreach {k v} $spec { dict set loading $k $v }
}

proc ioa::fabric::_site {text} {
    variable loading
    dict set loading site $text
}

proc ioa::fabric::_note {text} {
    variable loading
    dict lappend loading notes $text
}

proc ioa::fabric::_device {id spec} {
    variable loading
    if {[dict exists $loading devices $id]} {
        error "duplicate device: $id"
    }
    dict set loading devices $id [ioa::device::resolve $id $spec]
}

proc ioa::fabric::_link {a b transport {params {}}} {
    variable loading
    dict lappend loading links [dict create from $a to $b transport $transport params $params]
}

proc ioa::fabric::validate {f} {
    foreach l [dict get $f links] {
        foreach end {from to} {
            set id [dict get $l $end]
            if {![dict exists $f devices $id]} {
                error "link references unknown device: $id" {} {IOA FABRIC NODEV}
            }
        }
        set t [dict get $l transport]
        if {![ioa::transport::exists $t]} {
            error "link [dict get $l from]->[dict get $l to] uses unknown transport: $t" {} {IOA FABRIC NOTRANSPORT}
        }
        foreach {end check} {from canSend to canReceive} {
            set dev [dict get $f devices [dict get $l $end]]
            if {[dict get $dev product] eq ""} continue
            if {![ioa::device::$check $dev $t]} {
                error "[dict get $dev id] ([dict get $dev product]) has no $t interface for [string range $end 0 end]" \
                    {} {IOA FABRIC NOIFACE}
            }
        }
    }
    return 1
}

proc ioa::fabric::device {f id} {
    if {![dict exists $f devices $id]} {
        error "no such device: $id (have: [join [dict keys [dict get $f devices]] {, }])" {} {IOA FABRIC NODEV}
    }
    dict get $f devices $id
}

proc ioa::fabric::deviceIds {f} { dict keys [dict get $f devices] }

proc ioa::fabric::withRole {f role} {
    set out {}
    dict for {id dev} [dict get $f devices] {
        if {[ioa::device::hasRole $dev $role]} { lappend out $id }
    }
    return $out
}

# Directed, resolved edges. A declared link becomes two edges when both the
# medium and both endpoints are bidirectional, one when it is not.
proc ioa::fabric::edges {f} {
    set out {}
    foreach l [dict get $f links] {
        set t [dict get $l transport]
        set caps [ioa::transport::caps $t]
        set a [device $f [dict get $l from]]
        set b [device $f [dict get $l to]]

        set dirs [list [list $a $b]]
        if {[dict get $caps duplex] ne "simplex"
            && [ioa::device::canSend $b $t] && [ioa::device::canReceive $a $t]} {
            lappend dirs [list $b $a]
        }
        foreach pair $dirs {
            lassign $pair src dst
            if {![ioa::device::canSend $src $t] || ![ioa::device::canReceive $dst $t]} continue
            set e [ioa::transport::link [dict get $src id] [dict get $dst id] $t [dict get $l params]]
            # A control-grade interface (an IR port on a camera, say) can carry
            # commands and thumbnails but must not be planned as a video path.
            dict set e control_only [expr {
                [ioa::device::transportRole $src $t] eq "control"
                || [ioa::device::transportRole $dst $t] eq "control"}]
            lappend out $e
        }
    }
    return $out
}

proc ioa::fabric::summary {f} {
    set rows {}
    dict for {id dev} [dict get $f devices] {
        lappend rows [list $id [ioa::dget $dev product -] [dict get $dev platform] \
            [join [dict get $dev roles] ,] \
            [llength [dict get $dev transports]] \
            [ioa::dget $dev place ""]]
    }
    ioa::table {device product platform roles ifaces place} $rows
}

package provide ioa::fabric 0.3.0

# ------------------------------------------------------- live alteration ---
#
# Installations change under you: a node loses power, somebody parks a van in
# the laser path, the band fills up at 19:00. These let the orchestrator
# re-plan against the fabric as it is now rather than as it was documented.

proc ioa::fabric::removeDevice {f id} {
    dict unset f devices $id
    set keep {}
    foreach l [dict get $f links] {
        if {[dict get $l from] eq $id || [dict get $l to] eq $id} continue
        lappend keep $l
    }
    dict set f links $keep
    return $f
}

proc ioa::fabric::setLinkParams {f from to transport params} {
    set out {}
    set hit 0
    foreach l [dict get $f links] {
        if {[dict get $l from] eq $from && [dict get $l to] eq $to
            && [dict get $l transport] eq $transport} {
            dict set l params [dict merge [dict get $l params] $params]
            set hit 1
        }
        lappend out $l
    }
    if {!$hit} { error "no link $from -> $to over $transport" {} {IOA FABRIC NOLINK}}
    dict set f links $out
    return $f
}

# Degrade every link on a medium at once: what a band going busy, or dusk
# arriving on the optical heads, actually looks like.
proc ioa::fabric::degradeMedium {f medium params} {
    set out {}
    foreach l [dict get $f links] {
        if {[dict get [ioa::transport::caps [dict get $l transport]] medium] eq $medium} {
            dict set l params [dict merge [dict get $l params] $params]
        }
        lappend out $l
    }
    dict set f links $out
    return $f
}
