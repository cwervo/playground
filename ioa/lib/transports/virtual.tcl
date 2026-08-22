# ioa/lib/transports/virtual.tcl -- media that are not media.
#
# loopback is how the test suite and `ioa demo` move real IOAF frames without
# hardware. capture writes them to disk so a field failure can be replayed at
# a desk, frame for frame, against the same planner.

package require Tcl 8.6

ioa::transport::define loopback {
    medium virtual
    band "in-process"
    duplex full
    nominal_bps 10000000000
    efficiency 1.0
    mtu 65507
    latency_ms 0.05
    jitter_ms 0.0
    loss 0.0
    range_m 0
    power_mw 0
    platforms {macos linux esp32 fpga any}
    derate ioa::transport::derateFlat
    realize ioa::tx::virtual::realizeLoopback
    notes "Same framing, same planner, no radio. If it does not work here it will not work in the air."
}

ioa::transport::define capture {
    medium virtual
    band "filesystem"
    duplex simplex
    nominal_bps 2000000000
    efficiency 0.9
    mtu 65507
    latency_ms 0.1
    jitter_ms 0.0
    loss 0.0
    range_m 0
    power_mw 0
    platforms {macos linux}
    derate ioa::transport::derateFlat
    realize ioa::tx::virtual::realizeCapture
    notes "An .ioaf file is a sequence of wire frames. Record on site, replay at the bench."
}

namespace eval ioa::tx::virtual {}

proc ioa::tx::virtual::realizeLoopback {dir node link} {
    dict create kind inproc cmd [list ioa::sim::channel $dir]
}

proc ioa::tx::virtual::realizeCapture {dir node link} {
    set path [ioa::dget [dict get $link params] path "ioa-[clock format [clock seconds] -format %Y%m%dT%H%M%S].ioaf"]
    dict create kind exec cmd [list ioa gw $dir --transport capture --path $path]
}

package provide ioa::transports::virtual 0.3.0
