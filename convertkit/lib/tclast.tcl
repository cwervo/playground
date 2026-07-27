# tclast.tcl -- a real Tcl AST for convertkit.
#
# Parses a Tcl script into a structured tree that captures the semantics
# of the program:
#
#   script  := list of command nodes
#   command := {cmd words {<word>...}}
#   word    := {w type T text RAW children {...}}
#     T = bare | brace | quote | cmdsub
#     - brace  : literal, no substitution; children hold a nested script
#                parse when the word plausibly IS a script (proc bodies,
#                control-structure bodies), purely as extra structure
#     - quote  : "..." with $var/[cmd] substitution left as raw text
#     - cmdsub : [...] -- children hold the nested parsed script
#
# fromAst regenerates a semantically equivalent program: word text is
# preserved verbatim inside its original delimiters, so substitution
# behavior is unchanged. Formatting (comments, blank lines, whitespace)
# is normalized, which is why the byte-exact base64 <source> remains the
# authoritative channel; the AST is the *reconstructable semantics*
# channel for the printed page.

namespace eval ::convertkit::tclast {

    # commands whose trailing brace words are themselves scripts
    variable scriptBodies {
        proc while for foreach if else elseif then switch catch try
        namespace apply time after
    }

    # --- tokenizer -------------------------------------------------------

    # Split one complete Tcl command into words, honoring {} "" [] \ nesting.
    proc splitWords {cmd} {
        set words {}
        set i 0
        set n [string length $cmd]
        while {$i < $n} {
            # skip inter-word whitespace (incl. escaped newlines)
            while {$i < $n} {
                set c [string index $cmd $i]
                if {[string is space $c]} { incr i; continue }
                if {$c eq "\\" && [string index $cmd $i+1] eq "\n"} { incr i 2; continue }
                break
            }
            if {$i >= $n} break
            set c [string index $cmd $i]
            if {$c eq "\{"} {
                set j [matchBrace $cmd $i]
                lappend words [list brace [string range $cmd $i+1 $j-1]]
                set i [expr {$j + 1}]
            } elseif {$c eq "\""} {
                set j [matchQuote $cmd $i]
                lappend words [list quote [string range $cmd $i+1 $j-1]]
                set i [expr {$j + 1}]
            } elseif {$c eq "\["} {
                set j [matchBracket $cmd $i]
                lappend words [list cmdsub [string range $cmd $i+1 $j-1]]
                set i [expr {$j + 1}]
            } else {
                set start $i
                while {$i < $n} {
                    set c [string index $cmd $i]
                    if {[string is space $c]} break
                    if {$c eq "\\"} { incr i 2; continue }
                    if {$c eq "\["} { set i [expr {[matchBracket $cmd $i] + 1}]; continue }
                    incr i
                }
                lappend words [list bare [string range $cmd $start [expr {$i-1}]]]
            }
        }
        return $words
    }

    proc matchBrace {s i} {
        set depth 0
        set n [string length $s]
        for {} {$i < $n} {incr i} {
            switch -- [string index $s $i] {
                "\\" { incr i }
                "\{" { incr depth }
                "\}" { incr depth -1; if {$depth == 0} { return $i } }
            }
        }
        error "unbalanced brace"
    }
    proc matchQuote {s i} {
        set n [string length $s]
        for {incr i} {$i < $n} {incr i} {
            switch -- [string index $s $i] {
                "\\" { incr i }
                "\"" { return $i }
                "\[" { set i [matchBracket $s $i] }
            }
        }
        error "unterminated quote"
    }
    proc matchBracket {s i} {
        set depth 0
        set n [string length $s]
        for {} {$i < $n} {incr i} {
            switch -- [string index $s $i] {
                "\\" { incr i }
                "\[" { incr depth }
                "\]" { incr depth -1; if {$depth == 0} { return $i } }
                "\{" { set i [matchBrace $s $i] }
                "\"" { if {$depth > 0} { set i [matchQuote $s $i] } }
            }
        }
        error "unbalanced bracket"
    }

    # --- parser ----------------------------------------------------------

    proc parseScript {script} {
        variable scriptBodies
        set nodes {}
        foreach cmd [::convertkit::tclxml::splitCommands $script] {
            if {[string index $cmd 0] eq "#"} {
                lappend nodes [list comment $cmd]
                continue
            }
            set words {}
            set wlist [splitWords $cmd]
            set head ""
            if {[llength $wlist]} { set head [lindex $wlist 0 1] }
            set idx 0
            foreach w $wlist {
                lassign $w type text
                set children {}
                if {$type eq "cmdsub"} {
                    if {![catch {parseScript $text} sub]} { set children $sub }
                } elseif {$type eq "brace" && $idx > 0 && $head in $scriptBodies
                          && [string first "\n" $text] >= 0} {
                    if {![catch {parseScript $text} sub]} { set children $sub }
                }
                lappend words [list $type $text $children]
                incr idx
            }
            lappend nodes [list command $words]
        }
        return $nodes
    }

    # --- source regeneration ----------------------------------------------

    proc wordToTcl {w} {
        lassign $w type text children
        switch -- $type {
            bare   { return $text }
            brace  { return "\{$text\}" }
            quote  { return "\"$text\"" }
            cmdsub { return "\[$text\]" }
        }
    }

    proc astToTcl {nodes} {
        set lines {}
        foreach node $nodes {
            lassign $node kind payload
            if {$kind eq "comment"} {
                lappend lines $payload
            } else {
                set parts {}
                foreach w $payload { lappend parts [wordToTcl $w] }
                lappend lines [join $parts " "]
            }
        }
        return [join $lines \n]\n
    }

    # --- XML emission ------------------------------------------------------

    proc esc {s} { ::convertkit::tclxml::xmlEscape $s }

    proc astToXml {nodes {indent "    "}} {
        set out ""
        foreach node $nodes {
            lassign $node kind payload
            if {$kind eq "comment"} {
                append out "$indent<comment>[esc $payload]</comment>\n"
            } else {
                append out "$indent<cmd>\n"
                foreach w $payload {
                    lassign $w type text children
                    if {[llength $children]} {
                        append out "$indent  <w t=\"$type\">\n"
                        append out "$indent    <raw>[esc $text]</raw>\n"
                        append out "$indent    <script>\n"
                        append out [astToXml $children "$indent      "]
                        append out "$indent    </script>\n"
                        append out "$indent  </w>\n"
                    } else {
                        append out "$indent  <w t=\"$type\">[esc $text]</w>\n"
                    }
                }
                append out "$indent</cmd>\n"
            }
        }
        return $out
    }
}
