#!/usr/bin/env tclsh
# nvmdump.tcl — inspect a NeuroVM display file.
#
#   tclsh tcl/nvmdump.tcl build/dashboard.nvm            header + symbols
#   tclsh tcl/nvmdump.tcl build/dashboard.nvm --disasm   full disassembly
#   tclsh tcl/nvmdump.tcl build/dashboard.nvm --strings
#   tclsh tcl/nvmdump.tcl build/dashboard.nvm --meta
#
# The disassembly is the point of this tool. A dashboard you cannot read the
# source of is a dashboard you have to trust; one whose entire drawing program
# prints in a few hundred lines of assembly is one you can audit. Every bar in
# the ladder panel is visible here as a CALL into the same four-instruction
# subroutine, which is exactly the claim the README makes.

set here [file dirname [file normalize [info script]]]
lappend auto_path $here
package require nvm

if {$argc < 1} {
    puts stderr "usage: nvmdump.tcl <file.nvm> \[--disasm|--strings|--meta|--symbols\]"
    exit 1
}
set path [lindex $argv 0]
set mode [expr {$argc > 1 ? [lindex $argv 1] : "--summary"}]
set bc [nvm::load $path]

# Piping this into head is the normal way to use it, so a closed stdout is an
# expected outcome rather than an error worth a stack trace.
proc emit {line} {
    if {[catch {puts $line}]} { exit 0 }
}
proc hr {} { emit [string repeat - 74] }

switch -- $mode {
    --disasm {
        emit [nvm::disasm $bc]
    }
    --strings {
        set i 0
        foreach s [dict get $bc strings] {
            emit [format "%4d  %s" $i $s]
            incr i
        }
    }
    --meta {
        emit [dict get $bc meta]
    }
    default {
        hr
        emit "NeuroVM display file: $path"
        hr
        emit [format "  version   %d" [dict get $bc version]]
        emit [format "  canvas    %d x %d" [dict get $bc canvasW] [dict get $bc canvasH]]
        emit [format "  entry     %d" [dict get $bc entry]]
        emit [format "  code      %d bytes" [string length [dict get $bc code]]]
        emit [format "  strings   %d" [llength [dict get $bc strings]]]
        emit [format "  symbols   %d" [llength [dict get $bc symbols]]]
        emit [format "  code CRC  %s" [expr {[dict get $bc crcOk] ? "ok" : "MISMATCH"}]]
        hr
        emit "  id                             value    sdev   margin  flag        label"
        hr
        set names {ok borderline deviant no-data}
        # Sorted by how far past threshold, because that is the only ordering
        # that puts the three findings that matter at the top.
        set rows {}
        foreach s [dict get $bc symbols] {
            lappend rows [list [dict get $s dist] $s]
        }
        foreach row [lsort -real -decreasing -index 0 $rows] {
            set s [lindex $row 1]
            emit [format "  %-26s %9.3f %7.2f %+7.1f%%  %-11s %s" \
                [dict get $s name] [dict get $s value] [dict get $s z] \
                [expr {[dict get $s dist]*100}] [lindex $names [dict get $s severity]] \
                [dict get $s label]]
        }
        hr
        emit "  run with --disasm to read the drawing program itself"
    }
}
