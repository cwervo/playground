# ioa/lib/device.tcl -- a node in a fabric.
#
# A device is mostly a reference to a product plus where it is standing. What
# it can do comes from the catalog, so the planner is always reasoning about
# hardware that exists rather than a wish list in a config file.

package require Tcl 8.6

namespace eval ioa::device {}

proc ioa::device::resolve {id spec} {
    set sku [ioa::dget $spec product ""]
    set base [dict create \
        id $id product $sku roles {} place "" platform linux \
        transports {} encode {} power_mw 0 params {}]

    if {$sku ne ""} {
        set p [ioa::product::get $sku]
        dict set base platform   [dict get $p platform]
        dict set base transports [ioa::dget $p transports {}]
        dict set base encode     [ioa::dget $p encode {}]
        if {[dict exists $p encoder]} { dict set base encoder [dict get $p encoder] }
        dict set base power_mw   [ioa::dget $p power_mw 0]
        dict set base name       [dict get $p name]
        dict set base class      [dict get $p class]
    }

    # A host product says "any"; the fabric has to pick one.
    set dev [dict merge $base $spec]
    if {[dict get $dev platform] eq "any"} {
        dict set dev platform [ioa::dget $spec platform [hostPlatform]]
    }
    if {[dict get $dev roles] eq ""} {
        dict set dev roles [defaultRoles [ioa::dget $dev class relay]]
    }
    return $dev
}

proc ioa::device::hostPlatform {} {
    switch -glob -- $::tcl_platform(os) {
        Darwin  { return macos }
        Linux*  { return linux }
        default { return linux }
    }
}

proc ioa::device::defaultRoles {class} {
    switch -- $class {
        camera   { return {source} }
        relay    { return {relay} }
        optical  { return {relay} }
        bridge   { return {relay sink} }
        host     { return {sink control} }
        software { return {sink} }
        default  { return {relay} }
    }
}

proc ioa::device::hasRole {dev role} {
    expr {[lsearch -exact [dict get $dev roles] $role] >= 0}
}

# Role this device plays on a given transport: egress, ingress, bidir,
# control, or {} when the hardware simply does not have that interface.
proc ioa::device::transportRole {dev transport} {
    foreach t [dict get $dev transports] {
        if {[lindex $t 0] eq $transport} { return [lindex $t 1] }
    }
    return {}
}

proc ioa::device::canSend {dev transport} {
    expr {[transportRole $dev $transport] in {egress bidir control}}
}

proc ioa::device::canReceive {dev transport} {
    expr {[transportRole $dev $transport] in {ingress bidir control}}
}

# Rungs this device can encode unaided. Relays re-frame but never re-encode,
# so they inherit whatever arrives.
proc ioa::device::rungs {dev} {
    set out {}
    foreach r [ioa::codec::rungNames] {
        if {[ioa::codec::withinCeiling [ioa::codec::rung $r] [dict get $dev encode]]} {
            lappend out $r
        }
    }
    return $out
}

package provide ioa::device 0.3.0
