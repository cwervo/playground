# folk-engine.tcl — a miniature folk engine for folkOS simulators.
#
# Runs on Jim Tcl (bootstrap build: no namespaces, no Tcl 8.6-isms).
# Implements the folklang subset described in folkOS/folklang.bnf.tcl:
#   Layer 1 forms:   Claim, Wish, When (batch semantics, see below)
#   Layer 2 patterns: /var/ capture, /...rest/ capture, non-capturing
#                     wildcards (any anyone someone something anything),
#                     $bound substitution in patterns, claimize sugar
#   Layer 3 vocab:   the decorations family (outlined / labelled /
#                    titled / highlighted / filled), draws text,
#                    draws a circle
#
# Batch semantics: each folk-eval-program call resets the world,
# evaluates the program, then runs When bodies to a fixpoint. There is
# no incremental retraction (no Hold!, no On unmatch, no negation) —
# per the capability matrix this is core-syntax=partial,
# reactive-db=partial. Output is a display list serialized as JSON.

set __folk_statements {}
set __folk_whens {}
set __folk_whenId 0
set __folk_fired {}
set __folk_display {}
set __folk_error ""

proc __folk_reset {} {
    set ::__folk_statements {}
    set ::__folk_whens {}
    set ::__folk_whenId 0
    set ::__folk_fired {}
    set ::__folk_display {}
    set ::__folk_error ""
}

proc __folk_say {stmt} {
    if {[lsearch -exact $::__folk_statements $stmt] == -1} {
        lappend ::__folk_statements $stmt
    }
}

proc Claim {args} {
    upvar this this
    __folk_say [list [expr {[info exists this] ? $this : "<unknown>"}] claims {*}$args]
}

proc Wish {args} {
    upvar this this
    __folk_say [list [expr {[info exists this] ? $this : "<unknown>"}] wishes {*}$args]
}

# When ?-modifiers...? pattern... body
# Modifier flags from full folk are accepted and ignored.
proc When {args} {
    set body [lindex $args end]
    set rawPattern [lrange $args 0 end-1]

    set pattern {}
    set skipNext 0
    foreach t $rawPattern {
        if {$skipNext} { set skipNext 0; continue }
        if {$t eq "-atomicallyWithKey"} { set skipNext 1; continue }
        if {[string index $t 0] eq "-"} { continue }
        if {[string index $t 0] eq "\$"} {
            # Bound reference: substitute from the enclosing scope now.
            lappend pattern [uplevel 1 [list subst -nocommands -nobackslashes $t]]
        } else {
            lappend pattern $t
        }
    }

    # Capture the lexical environment (locals of the enclosing body).
    # At toplevel (level 1 = this proc called from global scope) there
    # is nothing worth capturing; globals are reachable anyway.
    set env {}
    if {[info level] > 1} {
        foreach name [uplevel 1 {info locals}] {
            if {[string match __* $name]} { continue }
            upvar 1 $name v
            if {[info exists v]} { dict set env $name $v }
        }
    }
    set owner [uplevel 1 {expr {[info exists this] ? $this : "system"}}]

    incr ::__folk_whenId
    lappend ::__folk_whens [list $::__folk_whenId $pattern $body $env $owner]
}

# Match a pattern against a statement.
# Returns {1 bindings} on match, {0 {}} otherwise.
proc __folk_match {pattern stmt} {
    set bindings {}
    set np [llength $pattern]
    set ns [llength $stmt]
    for {set i 0} {$i < $np} {incr i} {
        set t [lindex $pattern $i]
        if {[string length $t] > 2 &&
            [string index $t 0] eq "/" && [string index $t end] eq "/"} {
            set name [string range $t 1 end-1]
            if {[string range $name 0 2] eq "..."} {
                # Rest variable: swallows all remaining terms.
                set name [string range $name 3 end]
                if {$name ni {any anyone someone something anything}} {
                    dict set bindings $name [lrange $stmt $i end]
                }
                return [list 1 $bindings]
            }
            if {$i >= $ns} { return {0 {}} }
            if {$name in {any anyone someone something anything}} { continue }
            if {$name in {nobody nothing}} {
                # Negation is unsupported in the batch engine; a
                # nobody/nothing pattern never fires rather than firing
                # wrongly.
                return {0 {}}
            }
            dict set bindings $name [lindex $stmt $i]
        } else {
            if {$i >= $ns || $t ne [lindex $stmt $i]} { return {0 {}} }
        }
    }
    if {$np != $ns} { return {0 {}} }
    return [list 1 $bindings]
}

proc __folk_fire {when stmt bindings} {
    lassign $when id pattern body env owner
    # bindings shadow captured env; `this` is the When's owner.
    set frame $env
    dict for {k v} $bindings { dict set frame $k $v }
    dict set frame this $owner
    set names {}
    set vals {}
    dict for {k v} $frame { lappend names $k; lappend vals $v }
    if {[catch {apply [list $names $body] {*}$vals} err]} {
        set ::__folk_error $err
        __display error text $err color red
    }
}

proc __folk_run {} {
    set changed 1
    set safety 0
    while {$changed && $safety < 100} {
        set changed 0
        incr safety
        foreach when $::__folk_whens {
            lassign $when id pattern body env owner
            foreach stmt $::__folk_statements {
                set res [__folk_match $pattern $stmt]
                if {![lindex $res 0] &&
                    [lindex $pattern 1] ni {claims wishes} &&
                    [lindex $stmt 1] eq "claims"} {
                    # Claimize sugar: (When X ...) also matches
                    # (/someone/ claims X ...), as in full folk.
                    set res [__folk_match $pattern [lrange $stmt 2 end]]
                }
                if {[lindex $res 0]} {
                    set key [list $id $stmt]
                    if {![dict exists $::__folk_fired $key]} {
                        dict set ::__folk_fired $key 1
                        __folk_fire $when $stmt [lindex $res 1]
                        set changed 1
                    }
                }
            }
        }
    }
}

# Display list: each entry is {op key value key value ...}
proc __display {op args} {
    lappend ::__folk_display [list $op {*}$args]
}

# The standard-library vocabulary slice this simulator implements
# (feature ids from folklang.bnf.tcl: decorations, draw2d partial).
proc __folk_stdlib {} {
    When /someone/ wishes /thing/ is outlined /color/ {
        __display outline color $color thickness 3
    }
    When /someone/ wishes /thing/ is outlined thick /color/ {
        __display outline color $color thickness 7
    }
    When /someone/ wishes /thing/ is labelled /text/ {
        __display label text $text color white
    }
    When /someone/ wishes /thing/ is labelled /text/ with color /color/ {
        __display label text $text color $color
    }
    When /someone/ wishes /thing/ is titled /text/ {
        __display title text $text color white
    }
    When /someone/ wishes /thing/ is highlighted /color/ {
        __display highlight color $color
    }
    When /someone/ wishes /thing/ is filled with color /color/ {
        __display fill color $color
    }
    When /someone/ wishes /thing/ draws text /text/ {
        __display drawtext text $text color white
    }
    When /someone/ wishes /thing/ draws a circle {
        __display circle color white radius 40 x 0 y 0 filled false
    }
    When /someone/ wishes /thing/ draws a circle with /...options/ {
        set d [dict create color white radius 40 x 0 y 0 filled false]
        foreach {k v} $options { dict set d $k $v }
        __display circle color [dict get $d color] radius [dict get $d radius] \
            x [dict get $d x] y [dict get $d y] \
            filled [expr {[dict get $d filled] in {true yes on 1} ? "true" : "false"}]
    }
    # Errors surface as statements (per prelude.tcl) and as display ops.
    When /p/ has error /err/ with info /info/ {
        __display error text $err color red
    }
}

# ---------------------------------------------------------------------
# JSON serialization
# ---------------------------------------------------------------------

proc __folk_json_str {s} {
    set out ""
    foreach ch [split $s ""] {
        switch -exact -- $ch {
            "\"" { append out "\\\"" }
            "\\" { append out "\\\\" }
            "\n" { append out "\\n" }
            "\r" { append out "\\r" }
            "\t" { append out "\\t" }
            default {
                scan $ch %c code
                if {$code < 32} {
                    append out [format "\\u%04x" $code]
                } else {
                    append out $ch
                }
            }
        }
    }
    return "\"$out\""
}

# Keys with numeric JSON values; everything else is emitted as string
# (keeps the Swift Codable model simple and predictable).
set __folk_numeric_keys {thickness radius x y}
set __folk_bool_keys {filled}

proc __folk_json_val {key val} {
    if {$key in $::__folk_bool_keys && $val in {true false}} { return $val }
    if {$key in $::__folk_numeric_keys && [string is double -strict $val]} {
        return $val
    }
    return [__folk_json_str $val]
}

proc __folk_json {} {
    set items {}
    foreach d $::__folk_display {
        set pairs [list "\"op\":[__folk_json_str [lindex $d 0]]"]
        foreach {k v} [lrange $d 1 end] {
            lappend pairs "[__folk_json_str $k]:[__folk_json_val $k $v]"
        }
        lappend items "{[join $pairs ,]}"
    }
    set err [expr {$::__folk_error eq "" ? "null" : [__folk_json_str $::__folk_error]}]
    set ok [expr {$::__folk_error eq "" ? "true" : "false"}]
    return "{\"ok\":$ok,\"error\":$err,\"statementCount\":[llength $::__folk_statements],\"display\":\[[join $items ,]\]}"
}

# ---------------------------------------------------------------------
# Entry point called from the host (folk_jim.c)
# ---------------------------------------------------------------------

proc folk-eval-program {code} {
    __folk_reset
    # Tolerate smart quotes from iOS keyboards / pasted text.
    set code [string map [list \u201c \" \u201d \" \u2018 ' \u2019 ' \u00a0 " "] $code]
    __folk_stdlib
    set ::this "editor"
    if {[catch {uplevel #0 $code} err]} {
        set ::__folk_error $err
        __display error text $err color red
    }
    __folk_run
    return [__folk_json]
}
