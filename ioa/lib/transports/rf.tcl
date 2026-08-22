# ioa/lib/transports/rf.tcl -- radio media.
#
# Numbers are measured-ish: what these radios deliver to an application with
# real headers and real retries, not what the datasheet prints on the box.

package require Tcl 8.6

ioa::transport::define wifi_tcp {
    medium rf
    band "2.4 / 5 GHz 802.11n/ac"
    duplex full
    nominal_bps 200000000
    efficiency 0.55
    mtu 1472
    latency_ms 4.0
    jitter_ms 6.0
    loss 0.0005
    range_m 60
    power_mw 700
    platforms {macos linux esp32 fpga}
    derate ioa::transport::derateRf
    realize ioa::tx::rf::realizeWifi
    notes "Reliable and everywhere. Retransmits hide loss and spend latency doing it."
}

ioa::transport::define wifi_udp {
    medium rf
    band "2.4 / 5 GHz 802.11n/ac"
    duplex full
    nominal_bps 200000000
    efficiency 0.60
    mtu 1472
    latency_ms 2.0
    jitter_ms 4.0
    loss 0.006
    range_m 60
    power_mw 700
    platforms {macos linux esp32 fpga}
    derate ioa::transport::derateRf
    realize ioa::tx::rf::realizeWifi
    notes "For live video this beats TCP: a late picture is worth less than a missing one."
}

ioa::transport::define espnow {
    medium rf
    band "2.4 GHz connectionless (Espressif)"
    duplex half
    nominal_bps 2000000
    efficiency 0.50
    mtu 250
    latency_ms 3.0
    jitter_ms 2.0
    loss 0.012
    range_m 200
    power_mw 480
    platforms {esp32}
    derate ioa::transport::derateRf
    realize ioa::tx::rf::realizeEspNow
    notes "No association, no DHCP, no AP. 250-byte packets mean a 40 KB picture is 170 fragments."
}

ioa::transport::define ble {
    medium rf
    band "2.4 GHz BLE 5 (2M PHY)"
    duplex full
    nominal_bps 2000000
    efficiency 0.35
    mtu 244
    latency_ms 15.0
    jitter_ms 10.0
    loss 0.002
    range_m 40
    power_mw 90
    platforms {macos linux esp32}
    derate ioa::transport::derateRf
    realize ioa::tx::rf::realizeBle
    notes "Thumbnails and control. Anything above QVGA is wishful thinking."
}

ioa::transport::define lora {
    medium rf
    band "sub-GHz ISM, SF7 BW500"
    duplex half
    nominal_bps 27000
    efficiency 0.40
    mtu 222
    latency_ms 120.0
    jitter_ms 60.0
    loss 0.02
    range_m 4000
    power_mw 450
    platforms {esp32}
    derate ioa::transport::derateRf
    realize ioa::tx::rf::realizeLora
    notes "Kilometres, kilobits. A still every few seconds, or the control plane for a site with no other link."
}

namespace eval ioa::tx::rf {}

proc ioa::tx::rf::realizeWifi {dir node link} {
    set peer [ioa::dget [dict get $link params] peer "10.0.0.2"]
    set port [ioa::dget [dict get $link params] port 9101]
    set t [dict get $link transport]
    switch -- [ioa::dget $node platform linux] {
        esp32 {
            return [dict create kind firmware config [dict create \
                IOA_LINK $t IOA_PEER $peer IOA_PORT $port \
                IOA_MTU [dict get $link mtu] \
                IOA_SSID [ioa::dget [dict get $link params] ssid "ioa-backhaul"]]]
        }
        default {
            if {$dir eq "tx"} {
                return [dict create kind exec cmd \
                    [list ioa gw tx --transport $t --peer $peer:$port --mtu [dict get $link mtu]]]
            }
            return [dict create kind exec cmd \
                [list ioa gw rx --transport $t --listen 0.0.0.0:$port]]
        }
    }
}

proc ioa::tx::rf::realizeEspNow {dir node link} {
    set mac [ioa::dget [dict get $link params] peer_mac "ff:ff:ff:ff:ff:ff"]
    set chan [ioa::dget [dict get $link params] channel 6]
    dict create kind firmware config [dict create \
        IOA_LINK espnow IOA_PEER_MAC $mac IOA_WIFI_CHANNEL $chan \
        IOA_MTU 250 IOA_ESPNOW_LR [ioa::dget [dict get $link params] long_range 1] \
        IOA_DIR $dir]
}

proc ioa::tx::rf::realizeBle {dir node link} {
    set svc [ioa::dget [dict get $link params] service "1ada"]
    switch -- [ioa::dget $node platform linux] {
        esp32   { return [dict create kind firmware config [dict create IOA_LINK ble IOA_GATT_SVC $svc IOA_DIR $dir]] }
        macos   { return [dict create kind exec cmd [list ioa gw $dir --transport ble --service $svc --backend corebluetooth]] }
        default { return [dict create kind exec cmd [list ioa gw $dir --transport ble --service $svc --backend bluez]] }
    }
}

proc ioa::tx::rf::realizeLora {dir node link} {
    dict create kind firmware config [dict create \
        IOA_LINK lora IOA_DIR $dir \
        IOA_LORA_FREQ [ioa::dget [dict get $link params] freq_hz 868100000] \
        IOA_LORA_SF [ioa::dget [dict get $link params] sf 7] \
        IOA_LORA_BW [ioa::dget [dict get $link params] bw_hz 500000]]
}

package provide ioa::transports::rf 0.3.0
