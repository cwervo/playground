# ioa/lib/products.tcl -- the ioa product line, as data.
#
# The catalog is executable rather than prose: a device in a fabric names a
# SKU, and inherits that SKU's transports, encoder ceiling and power envelope.
# Planning a route is therefore planning against real hardware limits, and
# adding a product to the line is adding a stanza here.

package require Tcl 8.6

namespace eval ioa::product {
    variable catalog [dict create]
    variable order {}
}

proc ioa::product::define {sku spec} {
    variable catalog
    variable order
    if {![dict exists $catalog $sku]} { lappend order $sku }
    dict set catalog $sku [dict merge [dict create sku $sku status concept] $spec]
}

proc ioa::product::get {sku} {
    variable catalog
    if {![dict exists $catalog $sku]} {
        error "no such product: $sku (try: [join [names] {, }])" {} {IOA PRODUCT UNKNOWN}
    }
    dict get $catalog $sku
}

proc ioa::product::exists {sku} {
    variable catalog
    dict exists $catalog $sku
}

proc ioa::product::names {} { variable order; return $order }

proc ioa::product::all {} {
    variable catalog
    variable order
    set out {}
    foreach sku $order { lappend out [dict get $catalog $sku] }
    return $out
}

proc ioa::product::byClass {class} {
    set out {}
    foreach p [all] { if {[dict get $p class] eq $class} { lappend out $p } }
    return $out
}

# Transports a SKU can terminate, as bare names.
proc ioa::product::transports {sku} {
    set out {}
    foreach t [ioa::dget [get $sku] transports {}] { lappend out [lindex $t 0] }
    return $out
}

# What this SKU can produce on its own: {codec width height fps} ceiling.
proc ioa::product::encodeCeiling {sku} {
    ioa::dget [get $sku] encode {}
}

# =========================================================================
#  THE LINE
#
#  class:      camera | relay | optical | bridge | host | software | service | kit
#  platform:   macos | linux | esp32 | fpga | any  -- what the orchestrator
#              must speak to drive the thing
#  transports: {name role}, role in {ingress egress bidir control}
#  encode:     best it can emit unaided
#  power_mw:   steady-state at full rate, for battery/PoE budgeting
# =========================================================================

# ---- capture -------------------------------------------------------------

ioa::product::define IOA-EYE-S3 {
    name      "ioa Eye"
    tagline   "Palm-sized RF camera node. Sees, encodes, and throws JPEGs at anything listening."
    class     camera
    status    shipping
    platform  esp32
    soc       "ESP32-S3 (240 MHz, 8 MB PSRAM)"
    sensor    "OV5640 5 MP rolling shutter, M12 mount"
    encode    {mjpeg 1600 1200 25}
    transports {
        {wifi_tcp egress}
        {wifi_udp egress}
        {espnow  bidir}
        {ble     control}
        {ir      control}
        {uart    bidir}
    }
    power_mw  820
    supply    "USB-C or 1S LiPo, 18650 sled optional"
    formfactor "38 x 38 x 16 mm"
    price_usd 59
    notes     "Hardware JPEG out of the sensor pipeline; the SoC never touches pixels, only packets."
}

ioa::product::define IOA-EYE-PRO {
    name      "ioa Eye Pro"
    tagline   "Global-shutter head with a real encoder. For fast motion and long links."
    class     camera
    status    beta
    platform  linux
    soc       "RK3588S, 4x A76 + 4x A55, 8 GB"
    sensor    "IMX296 global shutter 1.6 MP, C-mount"
    encode    {h265 1920 1080 60}
    encoder   h264_rkmpp
    transports {
        {ethernet egress}
        {wifi_tcp egress}
        {uvc      egress}
        {lifi     egress}
        {laser    egress}
        {uart     control}
    }
    power_mw  6400
    supply    "PoE+ or 12 V barrel"
    formfactor "92 x 62 x 40 mm, 1/4-20 and M6"
    price_usd 329
    notes     "Carries a Prism-compatible optical port, so it can drive a laser head with no relay in between."
}

# ---- moving the bits -----------------------------------------------------

ioa::product::define IOA-RELAY-24 {
    name      "ioa Relay"
    tagline   "The repeater. Takes a stream in on one medium and puts it out on another."
    class     relay
    status    shipping
    platform  esp32
    soc       "ESP32-S3 + nRF52840 + SX1262"
    encode    {}
    transports {
        {wifi_tcp bidir}
        {wifi_udp bidir}
        {espnow   bidir}
        {ble      bidir}
        {lora     bidir}
        {uart     bidir}
        {ir       control}
    }
    power_mw  1900
    supply    "PoE or USB-C PD"
    formfactor "70 x 70 x 22 mm, magnet + truss clamp"
    price_usd 89
    notes     "Store-and-forward with a 4 MB frame ring: survives a 300 ms outage on the uplink without losing a picture."
}

ioa::product::define IOA-PRISM-L1 {
    name      "ioa Prism"
    tagline   "Photonic head. Free-space optical link where RF is illegal, jammed, or full."
    class     optical
    status    beta
    platform  fpga
    soc       "Lattice iCE40UP5K + 650 nm laser diode + APD front end"
    encode    {}
    transports {
        {lifi     bidir}
        {laser    bidir}
        {ethernet bidir}
        {uart     control}
    }
    power_mw  2300
    supply    "12 V, 2 A"
    formfactor "Ø60 x 110 mm tube, tripod boss"
    price_usd 249
    notes     "Two modes: diffuse Li-Fi at 12 Mb/s across a room, or collimated 100 Mb/s to another Prism you have aimed at. Class 3R, interlocked."
}

ioa::product::define IOA-BEAM-IR {
    name      "ioa Beam"
    tagline   "Infrared side channel. Wakes nodes, aims heads, carries telemetry when nothing else can."
    class     optical
    status    shipping
    platform  esp32
    soc       "ESP32-C3 + 940 nm array + TSOP receiver"
    encode    {}
    transports {
        {ir   bidir}
        {ble  control}
        {uart control}
    }
    power_mw  240
    supply    "USB-C or 2xAA"
    formfactor "48 x 24 x 14 mm"
    price_usd 29
    notes     "Too slow for video by three orders of magnitude, and that is fine: it is the channel that still works when the video channel does not."
}

ioa::product::define IOA-FRAME-HD {
    name      "ioa Frame"
    tagline   "HDMI in one side, ioa out the other. And back again."
    class     bridge
    status    shipping
    platform  fpga
    soc       "Lattice CrossLink-NX + Hantro H.264 encoder"
    encode    {h264 1920 1080 60}
    transports {
        {hdmi     bidir}
        {ethernet bidir}
        {wifi_tcp bidir}
        {uvc      egress}
        {uart     control}
    }
    power_mw  5100
    supply    "PoE+ or USB-C PD"
    formfactor "104 x 66 x 24 mm"
    price_usd 199
    notes     "Egress side enumerates as a plain UVC webcam, so any host app sees an ioa stream as /dev/video0 with no driver."
}

# ---- hosts and software --------------------------------------------------

ioa::product::define IOA-HUB-X {
    name      "ioa Hub"
    tagline   "The orchestrator daemon. Runs the fabric, plans routes, owns the clock."
    class     host
    status    shipping
    platform  any
    soc       "macOS 13+ (arm64/x86_64) or Linux 5.15+"
    encode    {h264 3840 2160 60}
    transports {
        {ethernet bidir}
        {wifi_tcp bidir}
        {wifi_udp bidir}
        {uvc      ingress}
        {hdmi     ingress}
        {ble      bidir}
        {uart     bidir}
        {loopback bidir}
    }
    power_mw  0
    supply    "host"
    formfactor "software"
    price_usd 0
    notes     "This repository. Tcl 8.6, no compiled dependencies; shells out to ffmpeg only when a real stream is being moved."
}

ioa::product::define IOA-SIGHT-1 {
    name      "ioa Sight"
    tagline   "Viewer and recorder. Any ioa stream, any medium, one window."
    class     software
    status    beta
    platform  any
    soc       "macOS / Linux"
    encode    {}
    transports {{loopback ingress} {wifi_tcp ingress} {uvc ingress}}
    power_mw  0
    supply    "host"
    formfactor "software"
    price_usd 0
    notes     "Decodes IOAF directly, so it shows fragment loss and per-hop latency alongside the picture instead of hiding them."
}

ioa::product::define IOA-LOOM {
    name      "ioa Loom"
    tagline   "Fleet service. Inventory, firmware, and route history for installations you cannot visit."
    class     service
    status    concept
    platform  any
    soc       "hosted"
    encode    {}
    transports {{ethernet bidir}}
    power_mw  0
    supply    "n/a"
    formfactor "subscription"
    price_usd 12
    notes     "Per node per month. Optional: the fabric runs headless without it."
}

ioa::product::define IOA-DK-1 {
    name      "ioa Dev Kit"
    tagline   "One of each of the interesting ones, in a foam case."
    class     kit
    status    shipping
    platform  any
    soc       "n/a"
    encode    {}
    transports {}
    contains  {IOA-EYE-S3 IOA-EYE-S3 IOA-RELAY-24 IOA-PRISM-L1 IOA-PRISM-L1 IOA-BEAM-IR IOA-HUB-X}
    power_mw  0
    supply    "n/a"
    formfactor "case, 300 x 220 x 90 mm"
    price_usd 549
    notes     "Two Eyes and two Prisms on purpose: a one-ended optical link is not a link."
}

package provide ioa::product 0.3.0
