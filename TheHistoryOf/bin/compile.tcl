#!/usr/bin/env tclsh
# compile.tcl -- TheHistoryOf whitepaper compiler.
#
# Compiles .toml chapter sources into printable whitepapers using the
# PrintablePrograms.png framework (../../PrintablePrograms.png):
#
#   build/<id>/page-NNN.png     the PNG page sequence.  Every page
#                               carries the chapter's full .toml source
#                               in a PNG tEXt chunk (lossless digital
#                               channel), and the final page is a
#                               PrintablePrograms page-frame printout of
#                               the .toml itself -- print it, photograph
#                               it, and the chapter source decodes back
#                               from the pixels.
#   build/<id>.pdf              the same pages bound as a PDF
#                               (pure-Tcl assembler, JPEG/DCTDecode).
#   build/firstpages-4k/        first page of each chapter re-rendered
#                               natively at 4K (3840 px tall).
#
#   usage: tclsh bin/compile.tcl ?src/chapter.toml ...?
#          (defaults to every .toml in src/)

set here      [file dirname [file normalize [info script]]]
set projdir   [file dirname $here]
set repodir   [file dirname $projdir]
set framework [file join $repodir PrintablePrograms.png]

foreach mod {tclxml tclast pngcodec jpgcodec typeset pageframe} {
    source [file join $framework lib $mod.tcl]
}
source [file join $projdir lib toml.tcl]
source [file join $projdir lib pdf.tcl]

# ---------------------------------------------------------------- layout
set COLS      64      ;# mono columns per line
set PAGELINES 38      ;# text lines per page (footer excluded)
set DPI       300     ;# page raster density
set PAGEW     2550    ;# 8.5in * 300
set PAGEH     3300    ;# 11in  * 300
set MARGIN    300     ;# 1in
set INK       "#1010FF"
set FONT      [file join $framework fonts IBMPlexMono-Regular.ttf]

proc im {} {
    set c [::printable::render::magick]
    if {$c eq ""} { error "ImageMagick (convert/magick) is required" }
    return $c
}

# word-wrap a paragraph to $width columns
proc wrapPara {para width} {
    set out {}
    set line ""
    foreach word [split [string trim $para]] {
        if {$word eq ""} continue
        if {$line eq ""} {
            set line $word
        } elseif {[string length $line] + 1 + [string length $word] <= $width} {
            append line " " $word
        } else {
            lappend out $line
            set line $word
        }
    }
    if {$line ne ""} { lappend out $line }
    if {![llength $out]} { lappend out "" }
    return $out
}

# wrap body text: paragraphs separated by blank lines; lines beginning
# with "  " (two spaces) are preformatted and pass through untouched
proc wrapBody {text width} {
    set out {}
    set para {}
    foreach raw [split $text \n] {
        if {[string trim $raw] eq ""} {
            if {[llength $para]} {
                foreach l [wrapPara [join $para " "] $width] { lappend out $l }
                set para {}
            }
            lappend out ""
        } elseif {[string range $raw 0 1] eq "  "} {
            if {[llength $para]} {
                foreach l [wrapPara [join $para " "] $width] { lappend out $l }
                set para {}
            }
            lappend out $raw
        } else {
            lappend para [string trim $raw]
        }
    }
    if {[llength $para]} {
        foreach l [wrapPara [join $para " "] $width] { lappend out $l }
    }
    # trim trailing blanks
    while {[llength $out] && [lindex $out end] eq ""} {
        set out [lrange $out 0 end-1]
    }
    return $out
}

proc rule {ch} { global COLS; string repeat $ch $COLS }

# flow a parsed chapter into a flat list of lines
proc flowChapter {doc} {
    global COLS
    set meta [dict get $doc meta]
    set lines {}

    lappend lines [rule =]
    lappend lines "THE HISTORY OF"
    lappend lines [rule =]
    lappend lines ""
    foreach l [wrapPara [string toupper [dict get $meta title]] $COLS] {
        lappend lines $l
    }
    if {[dict exists $meta subtitle]} {
        lappend lines ""
        foreach l [wrapBody [dict get $meta subtitle] $COLS] { lappend lines $l }
    }
    lappend lines ""
    lappend lines [rule -]
    set byline "a whitepaper in the TheHistoryOf series"
    if {[dict exists $meta date]} { append byline " · " [dict get $meta date] }
    lappend lines $byline
    lappend lines "source: src/[dict get $meta id].toml (also embedded in"
    lappend lines "every page's tEXt chunk; final page is a scannable"
    lappend lines "PrintablePrograms page-frame carrying this source)"
    lappend lines [rule -]

    foreach sec [dict get $doc section] {
        lappend lines "" ""
        foreach l [wrapPara [string toupper [dict get $sec heading]] $COLS] {
            lappend lines $l
        }
        lappend lines [rule =]
        lappend lines ""
        foreach l [wrapBody [dict get $sec body] $COLS] { lappend lines $l }
    }

    if {[dict exists $doc citations]} {
        lappend lines "" ""
        lappend lines "SOURCES & CITATIONS"
        lappend lines [rule =]
        lappend lines ""
        set n 0
        foreach c [dict get $doc citations] {
            incr n
            set tag [format "\[%d\]" $n]
            foreach l [wrapPara [dict get $c label] [expr {$COLS - 5}]] {
                lappend lines [format "%-4s %s" $tag $l]
                set tag ""
            }
            if {[dict exists $c url]} {
                lappend lines "     [dict get $c url]"
            }
            if {[dict exists $c note]} {
                foreach l [wrapPara [dict get $c note] [expr {$COLS - 5}]] {
                    lappend lines "     $l"
                }
            }
            lappend lines ""
        }
        while {[llength $lines] && [lindex $lines end] eq ""} {
            set lines [lrange $lines 0 end-1]
        }
    }
    return $lines
}

# split flowed lines into pages of PAGELINES, avoiding a heading stranded
# at a page bottom
proc paginate {lines} {
    global PAGELINES
    set pages {}
    set i 0
    set n [llength $lines]
    while {$i < $n} {
        set take [expr {min($PAGELINES, $n - $i)}]
        # don't strand a heading (line followed by a ==== rule) at the bottom
        if {$i + $take < $n} {
            set last [lindex $lines [expr {$i + $take - 1}]]
            set next [lindex $lines [expr {$i + $take}]]
            if {[string match "=*" $next] && ![string match "=*" $last]} {
                incr take -1
            }
        }
        set page [lrange $lines $i [expr {$i + $take - 1}]]
        # drop leading blanks on a fresh page
        while {[llength $page] && [lindex $page 0] eq ""} {
            set page [lrange $page 1 end]
        }
        lappend pages $page
        incr i $take
    }
    return $pages
}

# render one text page to PNG; $scale != 1.0 renders the same physical
# page at a proportionally higher density (used for the 4K firstpages)
proc renderPage {pageLines footer out {scale 1.0}} {
    global DPI PAGEW PAGEH MARGIN PAGELINES INK FONT
    set dpi    [expr {$DPI * $scale}]
    set pw     [expr {round($PAGEW  * $scale)}]
    set ph     [expr {round($PAGEH  * $scale)}]
    set margin [expr {round($MARGIN * $scale)}]

    # pad to fixed height so the footer sits at the same physical spot
    while {[llength $pageLines] < $PAGELINES} { lappend pageLines "" }
    lappend pageLines "" $footer
    set text [join $pageLines \n]

    # png8 + few colors: the pages are two-tone text, so a small palette
    # halves the file with no visible change
    exec [im] -density $dpi -units PixelsPerInch \
        -background white -fill $INK -font $FONT -pointsize 12 \
        -interline-spacing 2 label:$text \
        -gravity northwest -splice ${margin}x${margin} \
        -background white -extent ${pw}x${ph} \
        -dither None -colors 32 png8:$out
}

proc embedSource {pngPath toml} {
    set png [::printable::pngcodec::readFile $pngPath]
    ::printable::pngcodec::writeFile $pngPath [::printable::pngcodec::embed $png $toml]
}

proc compileChapter {srcPath builddir} {
    global PAGEW PAGEH
    set f [open $srcPath r]; fconfigure $f -encoding utf-8
    set toml [read $f]; close $f
    set doc [::thehistoryof::toml::parse $toml]
    set id  [dict get $doc meta id]

    set pagedir [file join $builddir $id]
    file delete -force $pagedir
    file mkdir $pagedir

    set pages [paginate [flowChapter $doc]]
    set total [expr {[llength $pages] + 1}] ;# + page-frame page
    set pngs {}
    set pno 0
    foreach page $pages {
        incr pno
        set out [file join $pagedir [format "page-%03d.png" $pno]]
        set footer [format "%-40s %22s" "thehistoryof/$id" \
                        "page $pno of $total"]
        renderPage $page $footer $out
        embedSource $out $toml
        lappend pngs $out
    }

    # final page: the chapter source itself as a print-survivable
    # PrintablePrograms page frame, with a title panel in the interior
    incr pno
    set bandtmp [file join $pagedir band-tmp.png]
    set paneltmp [file join $pagedir panel-tmp.png]
    set panel [join [list \
        "THE HISTORY OF" \
        [string toupper [dict get $doc meta title]] \
        "" \
        "This page's color band carries the" \
        "complete chapter source:" \
        "  src/[file tail $srcPath]" \
        "" \
        "Print, photograph, then decode with" \
        "  PrintablePrograms.png/bin/printout.tcl:" \
        "  tclsh printout.tcl decode <photo>"] \n]
    ::printable::render::codePng $panel $paneltmp 300 18
    ::printable::dataframe::encode -source $toml -out $bandtmp \
        -file [file tail $srcPath] -dpi 150 -textpng $paneltmp
    file delete -force $paneltmp
    set out [file join $pagedir [format "page-%03d.png" $pno]]
    exec [im] $bandtmp -resize ${PAGEW}x${PAGEH}\> \
        -background white -gravity center -extent ${PAGEW}x${PAGEH} png:$out
    file delete -force $bandtmp
    embedSource $out $toml
    lappend pngs $out

    # PDF: JPEG rasters bound by the pure-Tcl assembler
    set jpgs {}
    # ~200dpi rasters keep the PDFs comfortably readable at a third of
    # the 300dpi weight; the PNG sequence remains the archival copy
    foreach p $pngs {
        set j [file rootname $p].tmp.jpg
        exec [im] $p -resize 66.67% -quality 85 jpg:$j
        lappend jpgs $j
    }
    set pdf [file join $builddir $id.pdf]
    ::thehistoryof::pdf::fromJpegs $pdf $jpgs
    foreach j $jpgs { file delete -force $j }

    # native-4K first page (3840 px tall: scale 3840/PAGEH)
    set k4dir [file join $builddir firstpages-4k]
    file mkdir $k4dir
    set k4 [file join $k4dir $id-page-001-4k.png]
    set footer [format "%-40s %22s" "thehistoryof/$id" "page 1 of $total"]
    renderPage [lindex $pages 0] $footer $k4 [expr {3840.0 / $PAGEH}]
    embedSource $k4 $toml

    puts [format "  %-28s %2d pages  ->  %s.pdf, %s/, 4K first page" \
              [file tail $srcPath] $total $id $id]
    return [list $id $total]
}

# ------------------------------------------------------------------ main
set srcdir   [file join $projdir src]
set builddir [file join $projdir build]
file mkdir $builddir

set sources $argv
if {![llength $sources]} {
    set sources [lsort [glob -nocomplain [file join $srcdir *.toml]]]
}
if {![llength $sources]} {
    puts stderr "no .toml sources found in $srcdir"
    exit 1
}

puts "TheHistoryOf compiler · [llength $sources] chapter(s)"
foreach s $sources { compileChapter $s $builddir }
puts "done: outputs in $builddir"
