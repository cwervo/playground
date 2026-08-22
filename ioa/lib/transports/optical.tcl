# ioa/lib/transports/optical.tcl -- photons instead of radio.
#
# Line of sight is the whole story here. These links do not care about a
# crowded 2.4 GHz band, an RF-quiet site, or a spectrum licence; they care
# about aim, glass, and how bright the room is.

package require Tcl 8.6

ioa::transport::define ir {
    medium optical
    band "940 nm infrared, PPM"
    duplex half
    nominal_bps 4800
    efficiency 0.50
    mtu 32
    latency_ms 8.0
    jitter_ms 4.0
    loss 0.03
    range_m 12
    los 1
    power_mw 180
    platforms {esp32 linux}
    derate ioa::transport::derateOptical
    realize ioa::tx::optical::realizeIr
    notes "2.4 kb/s. Not a video link -- a wake, aim and telemetry channel that works when RF is banned."
}

ioa::transport::define lifi {
    medium optical
    band "visible / near-IR diffuse, OOK"
    duplex half
    nominal_bps 24000000
    efficiency 0.50
    mtu 1024
    latency_ms 1.0
    jitter_ms 1.0
    loss 0.004
    range_m 25
    los 1
    power_mw 900
    platforms {fpga esp32 linux}
    derate ioa::transport::derateOptical
    realize ioa::tx::optical::realizeLifi
    notes "Room-scale, no aiming. 12 Mb/s carries 720p30 MJPEG with headroom."
}

ioa::transport::define laser {
    medium optical
    band "650 nm collimated, Class 3R"
    duplex full
    nominal_bps 155000000
    efficiency 0.65
    mtu 4096
    latency_ms 0.5
    jitter_ms 0.5
    loss 0.0008
    range_m 400
    los 1
    power_mw 2100
    platforms {fpga linux}
    derate ioa::transport::derateOptical
    realize ioa::tx::optical::realizeLaser
    notes "100 Mb/s across a car park, if both heads are aimed. Interlocked; drops to zero below 0.5 alignment."
}

namespace eval ioa::tx::optical {}

proc ioa::tx::optical::realizeIr {dir node link} {
    set carrier [ioa::dget [dict get $link params] carrier_hz 38000]
    switch -- [ioa::dget $node platform linux] {
        esp32   { return [dict create kind firmware config [dict create IOA_LINK ir IOA_IR_CARRIER $carrier IOA_DIR $dir]] }
        default { return [dict create kind exec cmd [list ioa gw $dir --transport ir --carrier $carrier --dev [ioa::dget [dict get $link params] dev /dev/lirc0]]] }
    }
}

proc ioa::tx::optical::realizeLifi {dir node link} {
    if {[ioa::dget $node platform linux] ne "fpga"} {
        return [dict create kind exec cmd \
            [list ioa gw $dir --transport lifi --port [ioa::dget $node port /dev/ttyACM0] \
                  --clock [ioa::dget [dict get $link params] clock_hz 24000000]]]
    }
    dict create kind bitstream \
        config [dict create \
            IOA_LINK lifi IOA_DIR $dir \
            IOA_OOK_CLOCK_HZ [ioa::dget [dict get $link params] clock_hz 24000000] \
            IOA_AGC [ioa::dget [dict get $link params] agc 1]] \
        load [list ioa fpga load --target ice40up5k --bit ioa-prism-lifi.bin \
                   --port [ioa::dget $node port /dev/ttyACM0]]
}

proc ioa::tx::optical::realizeLaser {dir node link} {
    if {[ioa::dget $node platform linux] ne "fpga"} {
        return [dict create kind exec cmd \
            [list ioa gw $dir --transport laser --port [ioa::dget $node port /dev/ttyACM0] \
                  --align [ioa::dget [dict get $link params] alignment 1.0] --interlock on]]
    }
    dict create kind bitstream \
        config [dict create \
            IOA_LINK laser IOA_DIR $dir \
            IOA_LASER_MW [ioa::dget [dict get $link params] laser_mw 4] \
            IOA_INTERLOCK 1 \
            IOA_ALIGN_TARGET [ioa::dget [dict get $link params] alignment 1.0]] \
        load [list ioa fpga load --target ice40up5k --bit ioa-prism-laser.bin \
                   --port [ioa::dget $node port /dev/ttyACM0]] \
        precheck [list ioa prism align --port [ioa::dget $node port /dev/ttyACM0] --settle 3s]
}

package provide ioa::transports::optical 0.3.0
