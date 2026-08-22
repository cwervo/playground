# ioa/lib/budget.tcl -- will this picture survive the hop?
#
# The interesting failure of low-MTU media is not bandwidth, it is arithmetic:
# a 40 KB JPEG over 250-byte ESP-NOW packets is 170 fragments, and losing any
# one of them loses the whole picture. At 1.2% packet loss that is a 12%
# delivery rate on a link the datasheet calls reliable. This file is the maths
# that makes the planner see that before the install does.

package require Tcl 8.6

namespace eval ioa::budget {}

# log(n!) via Lanczos, so binomial tails stay stable at a few thousand frags.
proc ioa::budget::lgamma {x} {
    set g 7.0
    set c {0.99999999999980993 676.5203681218851 -1259.1392167224028
           771.32342877765313 -176.61502916214059 12.507343278686905
           -0.13857109526572012 9.9843695780195716e-6 1.5056327351493116e-7}
    if {$x < 0.5} {
        return [expr {log(3.141592653589793 / sin(3.141592653589793 * $x)) - [lgamma [expr {1.0 - $x}]]}]
    }
    set x [expr {$x - 1.0}]
    set a [lindex $c 0]
    set t [expr {$x + $g + 0.5}]
    for {set i 1} {$i < 9} {incr i} {
        set a [expr {$a + [lindex $c $i] / ($x + $i)}]
    }
    expr {0.5 * log(2.0 * 3.141592653589793) + ($x + 0.5) * log($t) - $t + log($a)}
}

proc ioa::budget::lchoose {n k} {
    expr {[lgamma [expr {$n + 1.0}]] - [lgamma [expr {$k + 1.0}]] - [lgamma [expr {$n - $k + 1.0}]]}
}

# P(X <= k) for X ~ Binomial(n, p): the chance a picture arrives when the
# transport can repair up to $k lost fragments.
proc ioa::budget::binomCdf {n p k} {
    if {$p <= 0.0} { return 1.0 }
    if {$p >= 1.0} { return [expr {$k >= $n ? 1.0 : 0.0}] }
    if {$k >= $n} { return 1.0 }
    if {$k < 0}   { return 0.0 }
    set sum 0.0
    for {set i 0} {$i <= $k} {incr i} {
        set lp [expr {[lchoose $n $i] + $i * log($p) + ($n - $i) * log(1.0 - $p)}]
        set sum [expr {$sum + exp($lp)}]
    }
    expr {min(1.0, $sum)}
}

# Everything the planner needs to know about pushing $bytes through one hop.
#
#   fec  1.0 = none. 1.25 = a quarter of the packets are repair symbols, so a
#        quarter of them may be lost with the picture still recoverable.
proc ioa::budget::hop {link bytes {fec 1.0}} {
    set mtu     [dict get $link mtu]
    set payload [expr {$mtu - [ioa::frame::overhead]}]
    if {$payload < 16} { error "mtu [dict get $link mtu] cannot carry IOAF" {} {IOA BUDGET MTU} }

    set nfrag  [expr {max(1, int(ceil(double($bytes) / $payload)))}]
    set nsent  [expr {int(ceil($nfrag * $fec))}]
    set repair [expr {$nsent - $nfrag}]
    set loss   [dict get $link loss]

    set delivery [binomCdf $nsent $loss $repair]
    # Data fragments cost the payload plus a header each; repair symbols are
    # always full-width. Counting every packet at MTU would overstate the
    # overhead of small pictures by a factor of two.
    set wire     [expr {$bytes + $nfrag * [ioa::frame::overhead] + $repair * $mtu}]
    set serial   [ioa::transport::serializationMs $link $wire]

    dict create \
        fragments $nfrag sent $nsent repair $repair \
        wire_bytes $wire \
        overhead_pct [expr {$bytes > 0 ? 100.0 * ($wire - $bytes) / $bytes : 0.0}] \
        serialization_ms $serial \
        latency_ms [expr {[dict get $link latency_ms] + $serial}] \
        delivery $delivery \
        loss $loss
}

# Offered load in bits/s once framing and FEC are paid for.
proc ioa::budget::offeredBps {link bytes fps {fec 1.0}} {
    set h [hop $link $bytes $fec]
    expr {[dict get $h wire_bytes] * 8.0 * $fps}
}

# Smallest FEC ratio from $options that gets this hop to $target delivery.
# Returns {} when even the most redundant option cannot save it.
proc ioa::budget::chooseFec {link bytes target {options {1.0 1.1 1.25 1.5 2.0}}} {
    foreach f $options {
        if {[dict get [hop $link $bytes $f] delivery] >= $target} { return $f }
    }
    return {}
}

package provide ioa::budget 0.3.0
