# tclxml.tcl -- Tcl <-> XML core for PrintablePrograms.png.
#
# The XML document is the canonical interchange format for the whole
# toolkit. It carries two views of a Tcl script:
#   * <source encoding="base64">  -- byte-exact payload, guarantees
#     lossless roundtrips through every carrier format (XML/PNG/JPEG)
#   * <commands>                  -- human-readable structural view,
#     one <command> element per complete Tcl command
#
# Only the base64 <source> element is used when converting back to .tcl,
# so a roundtrip is always byte-identical.

namespace eval ::printable::tclxml {
    variable xmlns "https://github.com/cwervo/playground/PrintablePrograms.png"

    proc xmlEscape {s} {
        string map {& &amp; < &lt; > &gt; \" &quot; ' &apos;} $s
    }

    # Split a Tcl script into complete commands using Tcl's own parser.
    proc splitCommands {script} {
        set cmds {}
        set buf ""
        foreach line [split $script \n] {
            append buf $line \n
            if {[info complete $buf]} {
                set trimmed [string trim $buf]
                if {$trimmed ne ""} { lappend cmds $trimmed }
                set buf ""
            }
        }
        if {[string trim $buf] ne ""} { lappend cmds [string trim $buf] }
        return $cmds
    }

    # Convert Tcl source text into a PrintablePrograms XML document.
    proc tclToXml {source {name "untitled.tcl"}} {
        variable xmlns
        set b64 [binary encode base64 -maxlen 76 [encoding convertto utf-8 $source]]
        set out {<?xml version="1.0" encoding="UTF-8"?>}
        append out \n "<tclprogram xmlns=\"$xmlns\" name=\"[xmlEscape $name]\" generator=\"PrintablePrograms.png\">" \n
        append out "  <source encoding=\"base64\">\n$b64\n  </source>\n"
        append out "  <commands>\n"
        foreach cmd [splitCommands $source] {
            set first [lindex [split [string trim $cmd]] 0]
            append out "    <command name=\"[xmlEscape $first]\">"
            append out [xmlEscape $cmd]
            append out "</command>\n"
        }
        append out "  </commands>\n"
        # structured AST (semantic view; requires tclast.tcl to be loaded)
        if {[namespace exists ::printable::tclast]
            && ![catch {::printable::tclast::parseScript $source} ast]} {
            append out "  <ast>\n"
            append out [::printable::tclast::astToXml $ast]
            append out "  </ast>\n"
        }
        append out "</tclprogram>\n"
        return $out
    }

    # Extract the byte-exact Tcl source from a PrintablePrograms XML document.
    proc xmlToTcl {xml} {
        if {![regexp {<source encoding="base64">(.*?)</source>} $xml -> b64]} {
            error "not a PrintablePrograms XML document: missing <source encoding=\"base64\">"
        }
        return [encoding convertfrom utf-8 [binary decode base64 $b64]]
    }

    # Best-effort program name stored in the document.
    proc xmlName {xml} {
        if {[regexp {<tclprogram[^>]*name="([^"]*)"} $xml -> n]} { return $n }
        return "untitled.tcl"
    }
}
