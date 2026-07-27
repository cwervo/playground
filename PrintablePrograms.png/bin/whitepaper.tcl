#!/usr/bin/env tclsh
# whitepaper.tcl -- builds every edition of the PrintablePrograms.png
# white paper from its canonical XML source. The paper is itself a
# printable program: each printed page carries the document in its own
# thin US Letter data frame, and the carrier editions reproduce the
# PDF (images, diagrams, formatting) from constants embedded in their
# own source.
#
#   build:   tclsh whitepaper.tcl build  docs/whitepaper/WhitePaper.xml
#   extract: tclsh whitepaper.tcl extract <any .pp.* artifact>
#
# Build outputs (in docs/whitepaper/build/):
#   WhitePaper.md                    ACM-style Markdown edition
#   WhitePaper.html                  ACM-style HTML, vendored Libertinus
#   WhitePaper.8.5x11.pNN.png        US Letter page frames (absolute
#                                    sizing self-encoded in each frame)
#   WhitePaper.pdf                   the typeset paper
#   WhitePaper.pp.pdf                PDF + embedded canonical XML
#   WhitePaper.pp.xml                canonical XML (the printable program)
#   WhitePaper.pp.md / .pp.html      editions with embedded XML payload
#   WhitePaper.pp.html.folk          folk carrier: reproduces the HTML
#   WhitePaper.pp.html.rust          Rust carrier: reproduces the HTML
#   WhitePaper.pp.go                 Go carrier: reproduces the PDF
#   WhitePaper.pp.cpp                C++ carrier: reproduces the PDF

set libdir [file join [file dirname [file dirname [file normalize [info script]]]] lib]
foreach mod {tclxml tclast pngcodec jpgcodec typeset pageframe} {
    source [file join $libdir $mod.tcl]
}
set ROOT [file dirname $libdir]

# US Letter: 8.5in x 11in = 215.9mm x 279.4mm total, quiet margin included
set QUIET_MM 6.0
set PAGE_W_MM [expr {215.9 - 2*$QUIET_MM}]
set PAGE_H_MM [expr {279.4 - 2*$QUIET_MM}]
set CELL_MM 2.0
set BAND_MM 24.0     ;# thin band: 12 cells
set DPI 150

proc slurp {path} { set f [open $path r]; fconfigure $f -encoding utf-8; set d [read $f]; close $f; return $d }
proc slurpb {path} { set f [open $path rb]; set d [read $f]; close $f; return $d }
proc spit {path data} { set f [open $path w]; fconfigure $f -encoding utf-8; puts -nonewline $f $data; close $f }
proc spitb {path data} { set f [open $path wb]; puts -nonewline $f $data; close $f }

# ---------------------------------------------------------------- parse
proc parsePaper {xml} {
    set p [dict create]
    regexp {<title>(.*?)</title>} $xml -> t; dict set p title $t
    regexp {<date>(.*?)</date>} $xml -> d; dict set p date $d
    regexp {<keywords>(.*?)</keywords>} $xml -> k; dict set p keywords $k
    # NB: in Tcl AREs the first quantifier sets the whole pattern's
    # greediness, so every quantifier here is non-greedy on purpose
    set authors {}
    foreach {- aff name} [regexp -all -inline {<author affiliation="(.*?)">(.*?)</author>} $xml] {
        lappend authors [list $name $aff]
    }
    dict set p authors $authors
    regexp {<abstract>(.*?)</abstract>} $xml -> a
    dict set p abstract [string trim $a]
    set sections {}
    foreach {- st sb} [regexp -all -inline {<section title="(.*?)">(.*?)</section>} $xml] {
        lappend sections [list $st [string trim $sb]]
    }
    dict set p sections $sections
    set refs {}
    foreach {- rid rb} [regexp -all -inline {<ref id="(.*?)">(.*?)</ref>} $xml] {
        lappend refs [list $rid $rb]
    }
    dict set p refs $refs
    return $p
}

proc unescape {s} { string map {&amp; & &lt; < &gt; > &#233; é} $s }

# ---------------------------------------------------------------- markdown
proc emitMarkdown {p} {
    set out "# [unescape [dict get $p title]]\n\n"
    foreach a [dict get $p authors] {
        lassign $a name aff
        append out "**[unescape $name]** — _[unescape $aff]_  \n"
    }
    append out "\n[dict get $p date]\n\n"
    append out "**Keywords:** [dict get $p keywords]\n\n"
    append out "## Abstract\n\n[unescape [dict get $p abstract]]\n\n"
    set n 0
    foreach s [dict get $p sections] {
        lassign $s t b
        incr n
        append out "## $n. $t\n\n[unescape $b]\n\n"
    }
    append out "## References\n\n"
    foreach r [dict get $p refs] {
        lassign $r id body
        append out "- [unescape $body]\n"
    }
    append out "\n---\n\n_Built from WhitePaper.xml by PrintablePrograms.png; the PDF edition's page frames carry this document's canonical XML._\n"
    return $out
}

# ---------------------------------------------------------------- html
proc emitHtml {p} {
    set title [unescape [dict get $p title]]
    set out "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n<title>$title</title>\n<style>\n"
    append out {
@font-face { font-family: 'Libertinus Serif'; src: url('../../fonts/LibertinusSerif-Regular.woff2') format('woff2'); font-weight: 400; }
@font-face { font-family: 'Libertinus Serif'; src: url('../../fonts/LibertinusSerif-Bold.woff2') format('woff2'); font-weight: 700; }
@font-face { font-family: 'Libertinus Serif'; src: url('../../fonts/LibertinusSerif-Italic.woff2') format('woff2'); font-style: italic; }
body { font-family: 'Libertinus Serif', 'Linux Libertine', Georgia, serif;
       max-width: 42em; margin: 2em auto; padding: 0 1.5em;
       font-size: 12pt; line-height: 1.45; color: #111; background: #fff; }
h1 { font-size: 17pt; text-align: center; line-height: 1.25; }
.authors { text-align: center; margin: 0.8em 0; }
.authors .aff { font-style: italic; font-size: 10pt; color: #333; }
.date, .keywords { text-align: center; font-size: 10pt; color: #333; }
h2 { font-size: 12pt; text-transform: uppercase; letter-spacing: 0.04em; margin-top: 1.6em; }
.abstract { margin: 1.4em 2.2em; font-size: 10.5pt; }
.abstract b { text-transform: uppercase; letter-spacing: 0.04em; }
.refs { font-size: 10pt; }
.refs li { margin-bottom: 0.45em; }
p { text-align: justify; hyphens: auto; }
footer { margin-top: 2.5em; font-size: 9pt; color: #555; border-top: 1px solid #ccc; padding-top: 0.8em; }
}
    append out "</style>\n</head>\n<body>\n<h1>$title</h1>\n<div class=\"authors\">"
    foreach a [dict get $p authors] {
        lassign $a name aff
        append out "<div><b>[unescape $name]</b> <span class=\"aff\">[unescape $aff]</span></div>"
    }
    append out "</div>\n<div class=\"date\">[dict get $p date]</div>\n"
    append out "<div class=\"keywords\"><i>Keywords:</i> [dict get $p keywords]</div>\n"
    append out "<div class=\"abstract\"><b>Abstract.</b> [unescape [dict get $p abstract]]</div>\n"
    set n 0
    foreach s [dict get $p sections] {
        lassign $s t b
        incr n
        append out "<h2>$n&nbsp;&nbsp;$t</h2>\n"
        foreach para [split $b \n\n] {
            if {[string trim $para] ne ""} { append out "<p>[unescape $para]</p>\n" }
        }
    }
    append out "<h2>References</h2>\n<ul class=\"refs\">\n"
    foreach r [dict get $p refs] {
        lassign $r id body
        append out "<li>[unescape $body]</li>\n"
    }
    append out "</ul>\n<footer>Built from WhitePaper.xml by PrintablePrograms.png. The PDF edition's US Letter page frames carry this document's canonical XML; decode any printed page with <code>bin/printout.tcl decode</code>.</footer>\n</body>\n</html>\n"
    return $out
}

# ---------------------------------------------------------------- typeset
# Render the whole paper as one tall column image, then slice into pages.
proc paperText {p} {
    set out "[unescape [dict get $p title]]\n\n"
    foreach a [dict get $p authors] {
        lassign $a name aff
        append out "[unescape $name]  ([unescape $aff])\n"
    }
    append out "[dict get $p date]\n\nABSTRACT. [unescape [dict get $p abstract]]\n\nKeywords: [dict get $p keywords]\n"
    set n 0
    foreach s [dict get $p sections] {
        lassign $s t b
        incr n
        append out "\n$n  [string toupper $t]\n\n[unescape $b]\n"
    }
    append out "\nREFERENCES\n\n"
    foreach r [dict get $p refs] {
        lassign $r id body
        append out "[unescape $body]\n\n"
    }
    return $out
}

proc buildPages {p xml outdir base} {
    global QUIET_MM PAGE_W_MM PAGE_H_MM CELL_MM BAND_MM DPI ROOT
    set im [::printable::typeset::magick]
    set serif [file join $ROOT fonts LibertinusSerif-Regular.ttf]

    set cellpx [expr {int(round($CELL_MM/25.4*$DPI))}]
    set T [expr {int(round($BAND_MM/$CELL_MM))}]
    set W [expr {int(round($PAGE_W_MM/$CELL_MM))}]
    set H [expr {int(round($PAGE_H_MM/$CELL_MM))}]
    set innerW [expr {($W-2*$T)*$cellpx - 2*$cellpx}]
    set innerH [expr {($H-2*$T)*$cellpx - 2*$cellpx}]

    # Column of ACM-typeset text (Libertinus, 11pt at $DPI). ImageMagick 6's
    # caption: reader is unreliable for long text (its size estimator errors
    # out) and CLI text arguments are capped around 2.7KB, so we do our own
    # word wrap in Tcl, render short label: chunks, and append them.
    set ptpx [expr {int(round(11.0 * $DPI / 72))}]

    # calibrate average glyph width for the wrap column
    set probe "the quick brown fox jumps over the lazy dog, 0123456789 (and then some)"
    set pw [exec $im -background white -font $serif -pointsize $ptpx \
                label:$probe -format "%w" info:]
    set avgw [expr {double($pw) / [string length $probe]}]
    set wrapcol [expr {int($innerW * 0.97 / $avgw)}]

    # word-wrap the paper text
    set wrapped {}
    foreach line [split [paperText $p] \n] {
        if {$line eq ""} { lappend wrapped ""; continue }
        set cur ""
        foreach word [split $line] {
            if {$word eq ""} continue
            if {$cur eq ""} { set cur $word ; continue }
            if {[string length $cur] + 1 + [string length $word] <= $wrapcol} {
                append cur " " $word
            } else {
                lappend wrapped $cur
                set cur $word
            }
        }
        lappend wrapped $cur
    }

    # render in chunks under the CLI text-argument limit
    set chunkFiles {}
    set ci 0
    for {set i 0} {$i < [llength $wrapped]} {} {
        set chunk ""
        set bytes 0
        while {$i < [llength $wrapped] && $bytes < 1800} {
            set l [lindex $wrapped $i]
            if {$l eq ""} { set l " " }
            append chunk $l \n
            incr bytes [expr {[string length $l] + 1}]
            incr i
        }
        incr ci
        set cf [file join $outdir chunk_[format %02d $ci].png]
        exec $im -background white -fill "#1010FF" -font $serif \
            -pointsize $ptpx label:[string trimright $chunk \n] \
            -gravity NorthWest -extent ${innerW}x png:$cf
        lappend chunkFiles $cf
    }
    set col [file join $outdir column.png]
    exec $im {*}$chunkFiles -background white -append png:$col
    file delete {*}$chunkFiles

    # figure plate: the storyboard printout sample + caption
    set fig [file join $outdir figure.png]
    set figsrc [file join $ROOT samples storyboard.printout.png]
    set figcap [file join $outdir figcap.png]
    set figtext "Figure 1. A printable program page: minimal color-cell frame, code at 12pt, byte-exact recovery from pixels alone."
    exec $im -background white -fill "#1010FF" -font $serif \
        -pointsize [expr {int(round(10.0 * $DPI / 72))}] \
        label:$figtext -gravity NorthWest -extent ${innerW}x png:$figcap
    exec $im \( $figsrc -resize ${innerW}x \) $figcap -background white -append png:$fig

    # append the figure under the text column, then slice into pages
    set full [file join $outdir fullcol.png]
    exec $im $col $fig -background white -append png:$full
    # +repage BEFORE the crop: -append leaves a stale virtual canvas that
    # otherwise confines the tiling to the first image's page geometry
    exec $im $full +repage -background white -crop ${innerW}x${innerH} +repage \
        [file join $outdir slice_%02d.png]

    set slices [lsort [glob [file join $outdir slice_*.png]]]
    set npages [llength $slices]
    set pages {}
    set pn 0
    foreach slice $slices {
        incr pn
        set page [file join $outdir [format "$base.8.5x11.p%02d.png" $pn]]
        ::printable::pageframe::encode -source $xml -out $page \
            -pagewmm $PAGE_W_MM -pagehmm $PAGE_H_MM -cellmm $CELL_MM \
            -bandmm $BAND_MM -quietmm $QUIET_MM -dpi $DPI \
            -id $pn -file "$base.8.5x11.p[format %02d $pn].png" \
            -textpng $slice \
            -extra "doc=$base\npaper=usletter\npage=$pn\npages=$npages"
        # lossless digital channel on every page
        set png [::printable::pngcodec::readFile $page]
        ::printable::pngcodec::writeFile $page [::printable::pngcodec::embed $png $xml]
        lappend pages $page
        file delete $slice
    }
    file delete -force $col $fig $figcap $full
    return $pages
}

# ---------------------------------------------------------------- carriers
proc b64chunks {data width} {
    set b64 [binary encode base64 -maxlen $width $data]
    return [split $b64 \n]
}

proc emitFolkCarrier {html out} {
    set lines [b64chunks [encoding convertto utf-8 $html] 72]
    set o "# WhitePaper.pp.html.folk -- a folk/Tcl carrier of the\n"
    append o "# PrintablePrograms.png white paper. Running it reproduces the\n"
    append o "# HTML edition (formatting and all) from the constant below:\n"
    append o "#     tclsh WhitePaper.pp.html.folk\n"
    append o "# In a Folk room, the claim below lets other programs find it.\n\n"
    append o "set payload \{\n[join $lines \n]\n\}\n\n"
    append o "set html \[encoding convertfrom utf-8 \[binary decode base64 \$payload\]\]\n"
    append o "if \{\[info exists ::argv0\] && \[file tail \$::argv0\] eq \[file tail \[info script\]\]\} \{\n"
    append o "    set f \[open WhitePaper.html w\]; fconfigure \$f -encoding utf-8\n"
    append o "    puts -nonewline \$f \$html; close \$f\n"
    append o "    puts \"reproduced WhitePaper.html (\[string length \$html\] chars)\"\n"
    append o "\} else \{\n"
    append o "    Claim \$this is a printable program named \"WhitePaper\"\n"
    append o "    Wish \$this displays html \$html\n"
    append o "\}\n"
    spit $out $o
}

proc emitRustCarrier {html out} {
    set lines [b64chunks [encoding convertto utf-8 $html] 96]
    set o "// WhitePaper.pp.html.rust -- a Rust carrier of the PrintablePrograms.png\n"
    append o "// white paper. Build & run to reproduce the HTML edition:\n"
    append o "//     rustc -O --crate-name whitepaper -o wp WhitePaper.pp.html.rust && ./wp\n\n"
    append o "const PAYLOAD_B64: &str = concat!(\n"
    foreach l $lines { append o "    \"$l\",\n" }
    append o ");\n\n"
    append o "fn b64_decode(s: &str) -> Vec<u8> \{\n"
    append o "    const T: &\[u8\] = b\"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/\";\n"
    append o "    let idx = |c: u8| T.iter().position(|&t| t == c).unwrap() as u32;\n"
    append o "    let bytes: Vec<u8> = s.bytes().filter(|&c| c != b'=' && c != b'\\n').collect();\n"
    append o "    let mut out = Vec::new();\n"
    append o "    for chunk in bytes.chunks(4) \{\n"
    append o "        let mut acc = 0u32; let mut n = 0;\n"
    append o "        for &c in chunk \{ acc = (acc << 6) | idx(c); n += 1; \}\n"
    append o "        acc <<= 6 * (4 - n);\n"
    append o "        for i in 0..(n * 6 / 8) \{ out.push((acc >> (16 - 8 * i)) as u8); \}\n"
    append o "    \}\n    out\n\}\n\n"
    append o "fn main() \{\n"
    append o "    let html = b64_decode(PAYLOAD_B64);\n"
    append o "    std::fs::write(\"WhitePaper.html\", &html).expect(\"write failed\");\n"
    append o "    println!(\"reproduced WhitePaper.html (\{\} bytes)\", html.len());\n"
    append o "\}\n"
    spit $out $o
}

proc emitGoCarrier {pdf out} {
    set lines [b64chunks $pdf 96]
    set o "// WhitePaper.pp.go -- a Go carrier of the PrintablePrograms.png white\n"
    append o "// paper. Running it reproduces the full PDF edition -- embedded\n"
    append o "// images, diagrams, page frames, and formatting -- from the constant\n"
    append o "// below:\n//     go run WhitePaper.pp.go\n\n"
    append o "package main\n\nimport (\n\t\"encoding/base64\"\n\t\"fmt\"\n\t\"os\"\n)\n\n"
    append o "const payloadB64 = \"\" +\n"
    foreach l $lines { append o "\t\"$l\" +\n" }
    append o "\t\"\"\n\n"
    append o "func main() \{\n"
    append o "\tpdf, err := base64.StdEncoding.DecodeString(payloadB64)\n"
    append o "\tif err != nil \{ panic(err) \}\n"
    append o "\tif err := os.WriteFile(\"WhitePaper.pdf\", pdf, 0o644); err != nil \{ panic(err) \}\n"
    append o "\tfmt.Printf(\"reproduced WhitePaper.pdf (%d bytes)\\n\", len(pdf))\n"
    append o "\}\n"
    spit $out $o
}

proc emitCppCarrier {pdf out} {
    set lines [b64chunks $pdf 96]
    set o "// WhitePaper.pp.cpp -- a C++ carrier of the PrintablePrograms.png white\n"
    append o "// paper. Build & run to reproduce the full PDF edition:\n"
    append o "//     g++ -std=c++17 -o wp WhitePaper.pp.cpp && ./wp\n\n"
    append o "#include <cstdint>\n#include <cstdio>\n#include <string>\n#include <vector>\n\n"
    append o "static const char* PAYLOAD_B64 =\n"
    foreach l $lines { append o "    \"$l\"\n" }
    append o ";\n\n"
    append o "int main() \{\n"
    append o "    static const std::string tbl = \"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/\";\n"
    append o "    std::string s(PAYLOAD_B64);\n"
    append o "    std::vector<uint8_t> out;\n"
    append o "    uint32_t acc = 0; int n = 0;\n"
    append o "    for (char c : s) \{\n"
    append o "        auto p = tbl.find(c);\n"
    append o "        if (p == std::string::npos) continue;\n"
    append o "        acc = (acc << 6) | (uint32_t)p;\n"
    append o "        if (++n == 4) \{ out.push_back(acc >> 16); out.push_back(acc >> 8); out.push_back(acc); acc = 0; n = 0; \}\n"
    append o "    \}\n"
    append o "    if (n == 3) \{ acc <<= 6; out.push_back(acc >> 16); out.push_back(acc >> 8); \}\n"
    append o "    else if (n == 2) \{ acc <<= 12; out.push_back(acc >> 16); \}\n"
    append o "    FILE* f = std::fopen(\"WhitePaper.pdf\", \"wb\");\n"
    append o "    std::fwrite(out.data(), 1, out.size(), f);\n"
    append o "    std::fclose(f);\n"
    append o "    std::printf(\"reproduced WhitePaper.pdf (%zu bytes)\\n\", out.size());\n"
    append o "    return 0;\n\}\n"
    spit $out $o
}

# ---------------------------------------------------------------- pp embeds
set PP_BEGIN "%PrintablePrograms-XML-BEGIN"
set PP_END   "%PrintablePrograms-XML-END"

proc embedInPdf {pdfPath xml outPath} {
    global PP_BEGIN PP_END
    set pdf [slurpb $pdfPath]
    set b64 [binary encode base64 -maxlen 76 [encoding convertto utf-8 $xml]]
    spitb $outPath "$pdf\n$PP_BEGIN\n$b64\n$PP_END\n"
}

proc extract {path} {
    global PP_BEGIN PP_END
    set ext [string tolower [file extension $path]]
    set data [slurpb $path]
    if {[string match "*.png" [string tolower $path]]} {
        return [::printable::pngcodec::extract $data]
    }
    if {$ext in {.jpg .jpeg}} {
        return [::printable::jpgcodec::extract $data]
    }
    # trailer block (pp.pdf) or embedded comment (pp.md/.pp.html) or
    # base64 constant (carriers)
    if {[regexp "[string map {% \\%} $PP_BEGIN]\n(.*?)\n[string map {% \\%} $PP_END]" $data -> b64]} {
        return [encoding convertfrom utf-8 [binary decode base64 $b64]]
    }
    if {[regexp {<!-- pp:xml:base64\n(.*?)\n-->} $data -> b64]} {
        return [encoding convertfrom utf-8 [binary decode base64 $b64]]
    }
    error "no PrintablePrograms payload found in $path"
}

# ---------------------------------------------------------------- main
proc build {xmlPath} {
    global DPI ROOT
    set xml [slurp $xmlPath]
    set p [parsePaper $xml]
    set dir [file dirname $xmlPath]
    set outdir [file join $dir build]
    file mkdir $outdir
    set base WhitePaper

    puts "== editions =="
    set md [emitMarkdown $p]
    spit [file join $outdir $base.md] $md
    puts "  $base.md"
    set html [emitHtml $p]
    spit [file join $outdir $base.html] $html
    puts "  $base.html"

    puts "== US Letter page frames =="
    set pages [buildPages $p $xml $outdir $base]
    puts "  [llength $pages] pages ($base.8.5x11.pNN.png)"

    puts "== PDF =="
    set im [::printable::typeset::magick]
    set pdf [file join $outdir $base.pdf]
    exec $im {*}$pages -units PixelsPerInch -density $DPI $pdf
    puts "  $base.pdf ([file size $pdf] bytes)"

    puts "== pp editions (payload-carrying) =="
    embedInPdf $pdf $xml [file join $outdir $base.pp.pdf]
    puts "  $base.pp.pdf"
    spit [file join $outdir $base.pp.xml] $xml
    puts "  $base.pp.xml"
    set b64 [binary encode base64 -maxlen 76 [encoding convertto utf-8 $xml]]
    spit [file join $outdir $base.pp.md] "$md\n<!-- pp:xml:base64\n$b64\n-->\n"
    puts "  $base.pp.md"
    spit [file join $outdir $base.pp.html] [string map [list </body> "<!-- pp:xml:base64\n$b64\n-->\n</body>"] $html]
    puts "  $base.pp.html"

    puts "== self-reproducing carriers =="
    emitFolkCarrier $html [file join $outdir $base.pp.html.folk]
    puts "  $base.pp.html.folk"
    emitRustCarrier $html [file join $outdir $base.pp.html.rust]
    puts "  $base.pp.html.rust"
    set pdfBytes [slurpb $pdf]
    emitGoCarrier $pdfBytes [file join $outdir $base.pp.go]
    puts "  $base.pp.go"
    emitCppCarrier $pdfBytes [file join $outdir $base.pp.cpp]
    puts "  $base.pp.cpp"
    puts "done: [file normalize $outdir]"
}

if {[llength $argv] < 1} {
    puts stderr "usage: whitepaper.tcl build ?WhitePaper.xml?  |  whitepaper.tcl extract <artifact>"
    exit 2
}
switch -- [lindex $argv 0] {
    build {
        set xmlPath [expr {[llength $argv] > 1 ? [lindex $argv 1]
            : [file join $ROOT docs whitepaper WhitePaper.xml]}]
        build $xmlPath
    }
    extract {
        puts -nonewline [extract [lindex $argv 1]]
    }
    default { puts stderr "unknown mode: [lindex $argv 0]"; exit 2 }
}
