# jpgcodec.tcl -- pure-Tcl JPEG COM-segment surgery for PrintablePrograms.png.
#
# JPEG compression is lossy, so the payload can't live in pixels; it
# rides in COM (0xFFFE) comment segments instead, which survive any
# JPEG-aware tool that preserves metadata. Payloads longer than one
# segment (max 65531 bytes of data) are split across several COM
# segments, each prefixed with "printable:<i>/<n>:".

namespace eval ::printable::jpgcodec {
    variable prefix "printable"
    variable maxData 60000  ;# per-segment payload budget, under the 65533 limit

    proc readFile {path} {
        set f [open $path rb]; set data [read $f]; close $f
        return $data
    }
    proc writeFile {path data} {
        set f [open $path wb]; puts -nonewline $f $data; close $f
    }

    proc isJpg {data} {
        expr {[string range $data 0 1] eq "\xff\xd8"}
    }

    # Walk marker segments; returns list of {marker start length} where
    # start/length cover the whole segment including the marker bytes.
    # Stops at SOS (entropy-coded data follows).
    proc segments {data} {
        set out {}
        set pos 2
        set len [string length $data]
        while {$pos + 4 <= $len} {
            binary scan [string index $data $pos] c b0
            if {($b0 & 0xff) != 0xff} break
            binary scan [string index $data [expr {$pos+1}]] c m
            set m [expr {$m & 0xff}]
            if {$m == 0xd9 || $m == 0xda} break  ;# EOI / SOS
            binary scan [string range $data [expr {$pos+2}] [expr {$pos+3}]] S slen
            set slen [expr {$slen & 0xffff}]
            lappend out [list $m $pos [expr {2 + $slen}]]
            incr pos [expr {2 + $slen}]
        }
        return $out
    }

    # Insert (or replace) printable COM segments right after SOI.
    proc embed {jpgData text} {
        variable prefix
        variable maxData
        if {![isJpg $jpgData]} { error "not a JPEG file" }
        set stripped [strip $jpgData]
        set b64 [binary encode base64 [encoding convertto utf-8 $text]]
        set total [expr {([string length $b64] + $maxData - 1) / $maxData}]
        if {$total == 0} { set total 1 }
        set coms ""
        for {set i 0} {$i < $total} {incr i} {
            set part [string range $b64 [expr {$i*$maxData}] [expr {($i+1)*$maxData - 1}]]
            set body "$prefix:[expr {$i+1}]/$total:$part"
            append coms [binary format ccS 0xff 0xfe [expr {[string length $body] + 2}]] $body
        }
        return "\xff\xd8$coms[string range $stripped 2 end]"
    }

    # Remove any existing printable COM segments.
    proc strip {jpgData} {
        variable prefix
        set out "\xff\xd8"
        set pos 2
        foreach seg [segments $jpgData] {
            lassign $seg m start slen
            set body [string range $jpgData [expr {$start+4}] [expr {$start+$slen-1}]]
            if {!($m == 0xfe && [string match "$prefix:*" $body])} {
                append out [string range $jpgData $start [expr {$start+$slen-1}]]
            }
            set pos [expr {$start + $slen}]
        }
        append out [string range $jpgData $pos end]
        return $out
    }

    # Reassemble the payload from printable COM segments.
    proc extract {jpgData} {
        variable prefix
        if {![isJpg $jpgData]} { error "not a JPEG file" }
        array set parts {}
        set total -1
        foreach seg [segments $jpgData] {
            lassign $seg m start slen
            if {$m != 0xfe} continue
            set body [string range $jpgData [expr {$start+4}] [expr {$start+$slen-1}]]
            if {[regexp "^$prefix:(\\d+)/(\\d+):(.*)\$" $body -> i n part]} {
                set total $n
                set parts($i) $part
            }
        }
        if {$total < 0} { error "no printable payload found in JPEG" }
        set b64 ""
        for {set i 1} {$i <= $total} {incr i} {
            if {![info exists parts($i)]} { error "printable payload segment $i/$total missing" }
            append b64 $parts($i)
        }
        return [encoding convertfrom utf-8 [binary decode base64 $b64]]
    }
}
