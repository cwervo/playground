# ioa/lib/transports/wired.tcl -- copper and glass with connectors on the end.
#
# "Over air" is the interesting case, but a fabric that cannot also use the
# HDMI cable already in the wall is a toy. Wired media register identically,
# which is what lets the planner hand a stream from a laser to an HDMI output
# without any special case.

package require Tcl 8.6

ioa::transport::define hdmi {
    medium electrical
    band "TMDS, HDMI 1.4b"
    duplex simplex
    nominal_bps 8160000000
    efficiency 0.55
    mtu 32768
    latency_ms 0.2
    jitter_ms 0.05
    loss 0.0
    range_m 15
    power_mw 500
    platforms {macos linux fpga}
    derate ioa::transport::derateFlat
    realize ioa::tx::wired::realizeHdmi
    notes "Uncompressed 1080p60 is 3 Gb/s; the Frame bridge encodes on the way in so the rest of the fabric survives it."
}

ioa::transport::define uvc {
    medium electrical
    band "USB 2.0 isochronous"
    duplex simplex
    nominal_bps 480000000
    efficiency 0.60
    mtu 3072
    latency_ms 1.5
    jitter_ms 1.0
    loss 0.0
    range_m 5
    power_mw 500
    platforms {macos linux fpga}
    derate ioa::transport::derateFlat
    realize ioa::tx::wired::realizeUvc
    notes "The universal ingress. Every host already has a driver for it."
}

ioa::transport::define ethernet {
    medium electrical
    band "1000BASE-T"
    duplex full
    nominal_bps 1000000000
    efficiency 0.92
    mtu 1500
    latency_ms 0.3
    jitter_ms 0.1
    loss 0.00001
    range_m 100
    power_mw 900
    platforms {macos linux fpga}
    derate ioa::transport::derateFlat
    realize ioa::tx::wired::realizeEthernet
    notes "When it is available it wins on every axis. It is usually not available where the camera is."
}

ioa::transport::define uart {
    medium electrical
    band "TTL serial, 3 Mbaud"
    duplex full
    nominal_bps 3000000
    efficiency 0.80
    mtu 256
    latency_ms 1.0
    jitter_ms 0.5
    loss 0.0005
    range_m 3
    power_mw 40
    platforms {macos linux esp32 fpga}
    derate ioa::transport::derateFlat
    realize ioa::tx::wired::realizeUart
    notes "Bring-up, flashing and the console of last resort. Also a fine 2.4 Mb/s stream link over 30 cm."
}

namespace eval ioa::tx::wired {}

proc ioa::tx::wired::realizeHdmi {dir node link} {
    if {$dir eq "rx"} {
        return [dict create kind exec cmd \
            [list ioa gw rx --transport hdmi --input [ioa::dget [dict get $link params] input hdmi0]]]
    }
    dict create kind exec cmd \
        [list ioa gw tx --transport hdmi --output [ioa::dget [dict get $link params] output hdmi0] \
              --mode [ioa::dget [dict get $link params] mode 1920x1080@60]]
}

proc ioa::tx::wired::realizeUvc {dir node link} {
    set dev [ioa::dget [dict get $link params] dev ""]
    if {$dev eq ""} {
        set dev [expr {[ioa::dget $node platform linux] eq "macos" ? "0" : "/dev/video0"}]
    }
    dict create kind exec cmd [list ioa gw $dir --transport uvc --dev $dev]
}

proc ioa::tx::wired::realizeEthernet {dir node link} {
    set peer [ioa::dget [dict get $link params] peer "10.0.0.2"]
    set port [ioa::dget [dict get $link params] port 9101]
    if {$dir eq "tx"} {
        return [dict create kind exec cmd [list ioa gw tx --transport ethernet --peer $peer:$port]]
    }
    dict create kind exec cmd [list ioa gw rx --transport ethernet --listen 0.0.0.0:$port]
}

proc ioa::tx::wired::realizeUart {dir node link} {
    set dev [ioa::dget [dict get $link params] dev /dev/ttyUSB0]
    set baud [ioa::dget [dict get $link params] baud 3000000]
    dict create kind exec cmd [list ioa gw $dir --transport uart --dev $dev --baud $baud]
}

package provide ioa::transports::wired 0.3.0
