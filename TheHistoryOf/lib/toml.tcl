# toml.tcl -- a small TOML-subset reader for TheHistoryOf sources.
#
# The whitepaper sources are constrained TOML on purpose (they must fit
# on a printed page and survive a camera), so this parser covers exactly
# the subset the sources use:
#
#   [table] and [table.sub]        plain tables
#   [[array-of-table]]             appended table arrays
#   key = "basic string"           with \\ \" \n \t escapes
#   key = """ ... """              multiline basic strings (opening and
#                                  closing delimiters on their own line)
#   key = 123 / true / false       scalars, kept as literal strings
#   # comments and blank lines
#
# Result shape: a dict.  Plain tables become nested dicts; each
# [[name]] appends a dict to the list stored at $name.

namespace eval ::thehistoryof::toml {

    proc unescape {s} {
        string map [list \\\\ \\ \\\" \" \\n \n \\t \t] $s
    }

    proc parseValue {v} {
        set v [string trim $v]
        if {[string index $v 0] eq "\""} {
            if {[string index $v end] ne "\"" || [string length $v] < 2} {
                error "unterminated string: $v"
            }
            return [unescape [string range $v 1 end-1]]
        }
        return $v ;# bare scalar: number / bool / date
    }

    # parse $text -> dict
    proc parse {text} {
        set root [dict create]
        set path {}          ;# current table path (list of keys)
        set inArray 0        ;# is the current table an element of [[...]]?
        set cur [dict create]

        set flush {}
        lappend flush root path inArray cur

        set lines [split $text \n]
        set n [llength $lines]
        for {set i 0} {$i < $n} {incr i} {
            set line [string trim [lindex $lines $i]]
            if {$line eq "" || [string index $line 0] eq "#"} continue

            if {[regexp {^\[\[([A-Za-z0-9_.-]+)\]\]$} $line -> name]} {
                set root [closeTable $root $path $inArray $cur]
                set path [split $name .]
                set inArray 1
                set cur [dict create]
                continue
            }
            if {[regexp {^\[([A-Za-z0-9_.-]+)\]$} $line -> name]} {
                set root [closeTable $root $path $inArray $cur]
                set path [split $name .]
                set inArray 0
                set cur [dict create]
                continue
            }
            if {[regexp {^([A-Za-z0-9_-]+)\s*=\s*(.*)$} $line -> key rhs]} {
                set rhs [string trim $rhs]
                if {$rhs eq "\"\"\"" } {
                    # multiline basic string: gather until a line that is """
                    set buf {}
                    incr i
                    while {$i < $n} {
                        set raw [lindex $lines $i]
                        if {[string trim $raw] eq "\"\"\""} break
                        lappend buf $raw
                        incr i
                    }
                    if {$i >= $n} { error "unterminated multiline string for $key" }
                    dict set cur $key [join $buf \n]
                } else {
                    # strip trailing comment on bare scalars only
                    if {[string index $rhs 0] ne "\""} {
                        regexp {^([^#]*)} $rhs -> rhs
                    }
                    dict set cur $key [parseValue $rhs]
                }
                continue
            }
            error "toml: cannot parse line [expr {$i+1}]: $line"
        }
        return [closeTable $root $path $inArray $cur]
    }

    proc closeTable {root path inArray cur} {
        if {$path eq ""} {
            # top-level bare keys
            return [dict merge $root $cur]
        }
        if {$inArray} {
            set existing {}
            if {[dict exists $root {*}$path]} {
                set existing [dict get $root {*}$path]
            }
            lappend existing $cur
            dict set root {*}$path $existing
        } else {
            dict set root {*}$path $cur
        }
        return $root
    }

    proc load {path} {
        set f [open $path r]
        fconfigure $f -encoding utf-8
        set text [read $f]
        close $f
        return [parse $text]
    }
}
