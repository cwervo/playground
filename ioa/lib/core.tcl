# ioa/lib/core.tcl -- Image Over Air: primitives shared by every subsystem.
#
# Nothing in here knows about cameras, radios or lasers. It is units, logging,
# deterministic randomness and small dict helpers, so that the rest of the
# runtime can be written as plain data transformations.

package require Tcl 8.6

namespace eval ioa {
    variable version 0.3.0
    variable logLevel [expr {[info exists ::env(IOA_LOG)] ? $::env(IOA_LOG) : "info"}]
}

namespace eval ioa::core {
    variable levels {trace 0 debug 1 info 2 warn 3 error 4 silent 5}
}

# ---------------------------------------------------------------- logging ---

proc ioa::log {level args} {
    variable logLevel
    set l $ioa::core::levels
    if {![dict exists $l $level]} { set level info }
    if {[dict get $l $level] < [dict get $l $logLevel]} { return }
    set tag [format %-5s [string toupper $level]]
    puts stderr "[ioa::stamp] $tag [join $args " "]"
}

proc ioa::stamp {} {
    set ms [clock milliseconds]
    format "%s.%03d" [clock format [expr {$ms / 1000}] -format %H:%M:%S] [expr {$ms % 1000}]
}

proc ioa::die {args} {
    puts stderr "ioa: [join $args " "]"
    exit 1
}

# ------------------------------------------------------------ dict sugar ---

# Read $key from $d, falling back to $default rather than erroring.
proc ioa::dget {d key {default {}}} {
    if {[dict exists $d $key]} { return [dict get $d $key] }
    return $default
}

# Right-biased merge: later dicts win, one level deep.
proc ioa::dmerge {args} {
    set out [dict create]
    foreach d $args {
        dict for {k v} $d { dict set out $k $v }
    }
    return $out
}

# --------------------------------------------------------------- units -----

proc ioa::bps {n} {
    foreach {scale suffix} {1000000000 Gb/s 1000000 Mb/s 1000 kb/s 1 b/s} {
        if {$n >= $scale} {
            return [format "%.3g %s" [expr {double($n) / $scale}] $suffix]
        }
    }
    return "0 b/s"
}

proc ioa::bytes {n} {
    foreach {scale suffix} {1048576 MiB 1024 KiB 1 B} {
        if {$n >= $scale} {
            return [format "%.3g %s" [expr {double($n) / $scale}] $suffix]
        }
    }
    return "0 B"
}

proc ioa::ms {x} { format "%.2f ms" $x }

# CRC32 over binary payloads. Tcl 8.6 ships zlib; keep a slow path so the
# runtime still loads on a stripped interpreter (some ESP32 side-loaders).
proc ioa::crc32 {data} {
    if {![catch {zlib crc32 $data} c]} { return [expr {$c & 0xffffffff}] }
    variable crcTable
    if {![info exists crcTable]} {
        set crcTable {}
        for {set n 0} {$n < 256} {incr n} {
            set c $n
            for {set k 0} {$k < 8} {incr k} {
                set c [expr {($c & 1) ? (0xedb88320 ^ ($c >> 1)) : ($c >> 1)}]
            }
            lappend crcTable $c
        }
    }
    set crc 0xffffffff
    binary scan $data cu* octets
    foreach b $octets {
        set idx [expr {($crc ^ $b) & 0xff}]
        set crc [expr {[lindex $crcTable $idx] ^ (($crc >> 8) & 0x00ffffff)}]
    }
    return [expr {($crc ^ 0xffffffff) & 0xffffffff}]
}

# ------------------------------------------------- deterministic entropy ---
#
# Channel simulation must be reproducible: the same fabric plus the same seed
# must always produce the same loss pattern, or the test suite is worthless.

proc ioa::rng {seed} {
    set var ::ioa::core::state([incr ::ioa::core::rngCount])
    # Seed from the caller's string alone. Anything else in here -- a counter,
    # a clock, the variable's own name -- and two runs of the same simulation
    # stop agreeing, which quietly makes the test suite meaningless.
    set $var [expr {[ioa::crc32 $seed] | 1}]
    return [list ioa::core::xorshift $var]
}

proc ioa::core::xorshift {var} {
    upvar #0 $var s
    if {![info exists s]} {
        set s [expr {[ioa::crc32 $var] | 1}]
    }
    set s [expr {($s ^ ($s << 13)) & 0xffffffff}]
    set s [expr {$s ^ ($s >> 17)}]
    set s [expr {($s ^ ($s << 5)) & 0xffffffff}]
    return [expr {double($s) / 4294967296.0}]
}

# Draw a uniform [0,1) from a handle produced by ioa::rng.
proc ioa::draw {handle} { return [{*}$handle] }

# ---------------------------------------------------------------- tables ---

# Render rows (list of lists) under $headers as an aligned text table.
proc ioa::table {headers rows} {
    set widths {}
    foreach h $headers { lappend widths [string length $h] }
    foreach row $rows {
        for {set i 0} {$i < [llength $headers]} {incr i} {
            set cell [lindex $row $i]
            if {[string length $cell] > [lindex $widths $i]} {
                lset widths $i [string length $cell]
            }
        }
    }
    set out {}
    set line {}
    for {set i 0} {$i < [llength $headers]} {incr i} {
        lappend line [format "%-*s" [lindex $widths $i] [lindex $headers $i]]
    }
    lappend out [string trimright [join $line "  "]]
    set line {}
    foreach w $widths { lappend line [string repeat - $w] }
    lappend out [join $line "  "]
    foreach row $rows {
        set line {}
        for {set i 0} {$i < [llength $headers]} {incr i} {
            lappend line [format "%-*s" [lindex $widths $i] [lindex $row $i]]
        }
        lappend out [string trimright [join $line "  "]]
    }
    return [join $out \n]
}

proc ioa::heading {text} {
    return "\n$text\n[string repeat = [string length $text]]"
}

package provide ioa::core $ioa::version
