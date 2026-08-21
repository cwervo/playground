#!/usr/bin/env tclsh
# bundle.tcl — inline a .nvm display file into the browser host.
#
# The result is one self-contained HTML file: no fetch, no CORS, no server, and
# no second artefact to lose track of. Open it from a thumb drive on a machine
# with no network and it still works, which for a document that is going to be
# carried into a consulting room is the whole point.
#
#   tclsh web/bundle.tcl web/host.html build/dashboard.nvm build/dashboard.html

proc main {argv} {
    lassign $argv hostPath nvmPath outPath
    if {$hostPath eq "" || $nvmPath eq "" || $outPath eq ""} {
        puts stderr "usage: bundle.tcl <host.html> <in.nvm> <out.html>"
        exit 1
    }
    set f [open $hostPath r] ; fconfigure $f -encoding utf-8
    set html [read $f] ; close $f

    set f [open $nvmPath rb] ; set blob [read $f] ; close $f
    set b64 [binary encode base64 $blob]

    if {![string match "*@@NVM_BASE64@@*" $html]} {
        puts stderr "bundle: host has no @@NVM_BASE64@@ placeholder"
        exit 1
    }
    # A base64 payload can contain characters that string map would not touch,
    # but the replacement is inserted verbatim, so guard the one thing that
    # could break the surrounding <script>: a literal closing tag.
    if {[string match "*</script*" $b64]} {
        puts stderr "bundle: payload contains a script terminator, refusing"
        exit 1
    }
    set html [string map [list @@NVM_BASE64@@ $b64] $html]

    set f [open $outPath w] ; fconfigure $f -encoding utf-8
    puts -nonewline $f $html
    close $f

    puts stderr [format "bundle: wrote %s  (%.0f kB html, %.0f kB payload)" \
        $outPath [expr {[string length $html]/1024.0}] [expr {[string length $blob]/1024.0}]]
}

main $argv
