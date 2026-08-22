# ioa/lib/frame.tcl -- the IOAF/1 wire frame.
#
# One frame format crosses every medium. Wi-Fi, ESP-NOW, BLE, UART, IR and the
# optical heads all carry the same 28-byte header; only the MTU changes, and
# fragmentation absorbs that difference. This is the whole reason a 240-byte
# ESP-NOW packet and a 1500-byte TCP segment can appear on the same route.

package require Tcl 8.6

namespace eval ioa::frame {
    variable MAGIC "IOAF"
    variable VERSION 1
    variable HEADER 28

    # Frame types.
    variable types {hello 0 media 1 ctrl 2 ack 3 telemetry 4 bye 5 fec 6}

    # Codec identifiers carried in the header. The payload is opaque to ioa;
    # these exist so a sink knows which decoder to hand the bytes to.
    variable codecs {raw 0 mjpeg 1 h264 2 h265 3 av1 4 rgb565 5 gray8 6 jpegxl 7}

    variable flagKeyframe  0x01
    variable flagFragment  0x02
    variable flagFinal     0x04
    variable flagFec       0x08
    variable flagEncrypted 0x10
}

proc ioa::frame::typeId {name} {
    variable types
    if {![dict exists $types $name]} { error "unknown frame type: $name" }
    dict get $types $name
}

proc ioa::frame::typeName {id} {
    variable types
    dict for {k v} $types { if {$v == $id} { return $k } }
    return "type$id"
}

proc ioa::frame::codecId {name} {
    variable codecs
    if {![dict exists $codecs $name]} { error "unknown codec: $name" }
    dict get $codecs $name
}

proc ioa::frame::codecName {id} {
    variable codecs
    dict for {k v} $codecs { if {$v == $id} { return $k } }
    return "codec$id"
}

proc ioa::frame::overhead {} { variable HEADER; return $HEADER }

# Build a wire frame. $hdr is a dict; every field has a sane default so that
# callers only state what they mean.
proc ioa::frame::pack {hdr payload} {
    variable MAGIC
    variable VERSION

    set type   [ioa::dget $hdr type media]
    set codec  [ioa::dget $hdr codec mjpeg]
    set flags  [ioa::dget $hdr flags 0]
    set stream [ioa::dget $hdr stream 0]
    set seq    [ioa::dget $hdr seq 0]
    set frag   [ioa::dget $hdr frag 0]
    set nfrag  [ioa::dget $hdr nfrag 1]
    set ts     [ioa::dget $hdr ts [expr {[clock milliseconds] & 0xffffffff}]]

    set len [string length $payload]
    if {$len > 65535} {
        error "payload $len exceeds frame limit; fragment first" {} {IOA FRAME TOOBIG}
    }
    set crc [ioa::crc32 $payload]

    return [binary format "a4ccccSISSISI" \
        $MAGIC $VERSION [typeId $type] $flags [codecId $codec] \
        $stream $seq $frag $nfrag $ts $len $crc]$payload
}

# Parse a wire frame, validating magic, version, declared length and CRC.
# Errors carry a -errorcode so a transport can distinguish "corrupt, drop it"
# from "not one of ours".
proc ioa::frame::unpack {bin} {
    variable MAGIC
    variable VERSION
    variable HEADER

    if {[string length $bin] < $HEADER} {
        error "runt frame: [string length $bin] bytes" {} {IOA FRAME RUNT}
    }
    binary scan $bin "a4cucucucuSuIuSuSuIuSuIu" \
        magic ver type flags codec stream seq frag nfrag ts len crc
    if {$magic ne $MAGIC} { error "bad magic: $magic" {} {IOA FRAME MAGIC} }
    if {$ver != $VERSION} { error "unsupported IOAF version $ver" {} {IOA FRAME VERSION} }

    set payload [string range $bin $HEADER [expr {$HEADER + $len - 1}]]
    if {[string length $payload] != $len} {
        error "truncated payload: want $len got [string length $payload]" {} {IOA FRAME TRUNC}
    }
    if {[ioa::crc32 $payload] != $crc} {
        error "crc mismatch on seq $seq frag $frag" {} {IOA FRAME CRC}
    }

    return [dict create \
        type [typeName $type] flags $flags codec [codecName $codec] \
        stream $stream seq $seq frag $frag nfrag $nfrag ts $ts \
        len $len crc $crc payload $payload]
}

proc ioa::frame::isSet {hdr flag} {
    variable flag$flag
    expr {[ioa::dget $hdr flags 0] & [set ioa::frame::flag$flag]}
}

# Split one logical picture into MTU-sized frames. $mtu is the transport's
# whole-packet budget, so the header comes out of it, not on top of it.
proc ioa::frame::fragment {hdr payload mtu} {
    variable HEADER
    variable flagFragment
    variable flagFinal

    set room [expr {$mtu - $HEADER}]
    if {$room < 16} {
        error "mtu $mtu too small for IOAF (need > [expr {$HEADER + 16}])" {} {IOA FRAME MTU}
    }
    set total [string length $payload]
    set nfrag [expr {max(1, int(ceil(double($total) / $room)))}]
    if {$nfrag > 65535} {
        error "picture needs $nfrag fragments; raise mtu or lower bitrate" {} {IOA FRAME FRAGS}
    }

    set out {}
    for {set i 0} {$i < $nfrag} {incr i} {
        set chunk [string range $payload [expr {$i * $room}] [expr {($i + 1) * $room - 1}]]
        set flags [ioa::dget $hdr flags 0]
        if {$nfrag > 1} {
            set flags [expr {$flags | $flagFragment}]
            if {$i == $nfrag - 1} { set flags [expr {$flags | $flagFinal}] }
        }
        lappend out [pack [ioa::dmerge $hdr [dict create \
            frag $i nfrag $nfrag flags $flags]] $chunk]
    }
    return $out
}

# ------------------------------------------------------------ reassembly ---
#
# Lossy links deliver fragments out of order and lose some outright. The
# reassembler holds partial pictures, emits them when complete, and drops
# whatever is still incomplete once newer sequence numbers have moved on --
# a stalled picture is worse than a missing one for live video.

namespace eval ioa::frame::reasm { variable n 0 }

proc ioa::frame::reassembler {{window 4}} {
    variable reasm::n
    set h "::ioa::frame::reasm::r[incr reasm::n]"
    namespace eval $h {}
    set ${h}::window $window
    set ${h}::parts [dict create]
    set ${h}::stats [dict create completed 0 dropped 0 duplicates 0]
    return $h
}

# Feed one parsed frame. Returns a completed picture dict, or {} if the
# picture is still missing fragments.
proc ioa::frame::feed {h fr} {
    upvar #0 ${h}::parts parts ${h}::stats stats ${h}::window window

    set seq [dict get $fr seq]
    set nfrag [dict get $fr nfrag]

    if {$nfrag <= 1} {
        dict incr stats completed
        return [dict merge $fr [dict create complete 1]]
    }

    if {[dict exists $parts $seq [dict get $fr frag]]} {
        dict incr stats duplicates
        return {}
    }
    dict set parts $seq [dict get $fr frag] $fr

    if {[dict size [dict get $parts $seq]] == $nfrag} {
        set payload ""
        for {set i 0} {$i < $nfrag} {incr i} {
            append payload [dict get $parts $seq $i payload]
        }
        set first [dict get $parts $seq 0]
        dict unset parts $seq
        dict incr stats completed
        return [dict merge $first [dict create \
            payload $payload len [string length $payload] \
            frag 0 nfrag 1 complete 1]]
    }

    # Evict pictures older than the window; they will never finish.
    foreach old [dict keys $parts] {
        if {$old < $seq - $window} {
            dict unset parts $old
            dict incr stats dropped
        }
    }
    return {}
}

proc ioa::frame::reasmStats {h} {
    upvar #0 ${h}::stats stats ${h}::parts parts
    return [dict merge $stats [dict create pending [dict size $parts]]]
}

proc ioa::frame::reasmDestroy {h} { namespace delete $h }

package provide ioa::frame 0.3.0
