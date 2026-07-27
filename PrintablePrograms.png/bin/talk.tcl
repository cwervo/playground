#!/usr/bin/env tclsh
# talk.tcl -- builds the PrintablePrograms.png talk from Talk.xml.
#
#   build:   tclsh talk.tcl build ?docs/talk/Talk.xml?
#   extract: tclsh talk.tcl extract <talk.landscape.pp.4:3.html.pdf>
#
# Outputs (docs/talk/build/):
#   talk.html                        HTML deck (arrow keys / click to advance)
#   talk.landscape.4x3.sNN.png       landscape 4:3 (10x7.5in) slide frames;
#                                    each slide's band decodes to that
#                                    slide's own text, absolute size and
#                                    slide=N/slides=M self-encoded
#   talk.landscape.pp.4:3.html.pdf   the deck as a PDF of page frames,
#                                    with the HTML edition embedded as an
#                                    extractable payload

set libdir [file join [file dirname [file dirname [file normalize [info script]]]] lib]
foreach mod {tclxml tclast pngcodec jpgcodec typeset pageframe} {
    source [file join $libdir $mod.tcl]
}
set ROOT [file dirname $libdir]

# landscape 4:3 -- 10in x 7.5in = 254 x 190.5 mm, quiet margin included
set QUIET_MM 6.0
set PAGE_W_MM [expr {254.0 - 2*$QUIET_MM}]
set PAGE_H_MM [expr {190.5 - 2*$QUIET_MM}]
set CELL_MM 2.0
set BAND_MM 24.0
set DPI 150

set PP_BEGIN "%PrintablePrograms-XML-BEGIN"
set PP_END   "%PrintablePrograms-XML-END"

proc slurp {p} { set f [open $p r]; fconfigure $f -encoding utf-8; set d [read $f]; close $f; return $d }
proc slurpb {p} { set f [open $p rb]; set d [read $f]; close $f; return $d }
proc spit {p d} { set f [open $p w]; fconfigure $f -encoding utf-8; puts -nonewline $f $d; close $f }
proc spitb {p d} { set f [open $p wb]; puts -nonewline $f $d; close $f }
proc unescape {s} { string map {&amp; & &lt; < &gt; >} $s }

proc parseTalk {xml} {
    set t [dict create]
    regexp {<title>(.*?)</title>} $xml -> v; dict set t title $v
    regexp {<subtitle>(.*?)</subtitle>} $xml -> v; dict set t subtitle $v
    regexp {<date>(.*?)</date>} $xml -> v; dict set t date $v
    set slides {}
    foreach {- st sb} [regexp -all -inline {<slide title="(.*?)">(.*?)</slide>} $xml] {
        lappend slides [list [unescape $st] [unescape [string trim $sb]]]
    }
    dict set t slides $slides
    return $t
}

# ---------------------------------------------------------------- html deck
proc emitHtml {t} {
    set title [dict get $t title]
    set out "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n<title>$title (talk)</title>\n<style>\n"
    append out {
@font-face { font-family: 'Libertinus Serif'; src: url('../../fonts/LibertinusSerif-Regular.woff2') format('woff2'); }
html, body { margin: 0; height: 100%; background: #222; }
.slide { display: none; box-sizing: border-box; width: 100vw; height: 100vh;
         padding: 7vh 9vw; background: #fff; color: #1010FF;
         font-family: 'Libertinus Serif', Georgia, serif; }
.slide.on { display: block; }
.slide h1 { font-size: 6vh; margin: 0 0 4vh 0; border-bottom: 0.6vh solid #1010FF; padding-bottom: 1.5vh; }
.slide pre { font-size: 3.6vh; line-height: 1.5; white-space: pre-wrap;
             font-family: inherit; margin: 0; }
.pgnum { position: fixed; right: 2vw; bottom: 2vh; color: #1010FF; font: 2.5vh Georgia, serif; }
}
    append out "</style>\n</head>\n<body>\n"
    set n 0
    foreach s [dict get $t slides] {
        lassign $s st sb
        incr n
        append out "<div class=\"slide[expr {$n==1 ? " on" : ""}]\"><h1>$st</h1><pre>$sb</pre></div>\n"
    }
    append out "<div class=\"pgnum\"></div>\n<script>\n"
    append out {
let i = 0; const S = document.querySelectorAll('.slide'), P = document.querySelector('.pgnum');
function show(k){ i = (k + S.length) % S.length; S.forEach((s,j)=>s.classList.toggle('on', j===i)); P.textContent = (i+1)+' / '+S.length; }
document.addEventListener('keydown', e=>{ if (e.key==='ArrowRight'||e.key===' ') show(i+1); if (e.key==='ArrowLeft') show(i-1); });
document.addEventListener('click', ()=>show(i+1)); show(0);
}
    append out "</script>\n</body>\n</html>\n"
    return $out
}

# ---------------------------------------------------------------- slides
proc buildSlides {t outdir} {
    global QUIET_MM PAGE_W_MM PAGE_H_MM CELL_MM BAND_MM DPI ROOT
    set im [::printable::typeset::magick]
    set serif [file join $ROOT fonts LibertinusSerif-Regular.ttf]
    set mono  [file join $ROOT fonts IBMPlexMono-Regular.ttf]

    set cellpx [expr {int(round($CELL_MM/25.4*$DPI))}]
    set T [expr {int(round($BAND_MM/$CELL_MM))}]
    set W [expr {int(round($PAGE_W_MM/$CELL_MM))}]
    set H [expr {int(round($PAGE_H_MM/$CELL_MM))}]
    set innerW [expr {($W-2*$T)*$cellpx - 2*$cellpx}]
    set innerH [expr {($H-2*$T)*$cellpx - 2*$cellpx}]

    set slides [dict get $t slides]
    set total [llength $slides]
    set pages {}
    set n 0
    foreach s $slides {
        lassign $s st sb
        incr n
        # title (serif, large) over body (mono keeps ASCII layout intact)
        set tpng [file join $outdir s_title.png]
        set bpng [file join $outdir s_body.png]
        exec $im -background white -fill "#1010FF" -font $serif \
            -pointsize [expr {int(round(26.0*$DPI/72))}] \
            label:$st -gravity NorthWest -extent ${innerW}x png:$tpng
        exec $im -background white -fill "#1010FF" -font $mono \
            -pointsize [expr {int(round(13.5*$DPI/72))}] \
            -interline-spacing 6 label:$sb \
            -gravity NorthWest -extent ${innerW}x png:$bpng
        set panel [file join $outdir s_panel.png]
        exec $im $tpng \( -size ${innerW}x30 xc:white \) $bpng \
            -background white -append png:$panel
        # never taller than the interior: slides are written to fit
        exec $im $panel -resize ${innerW}x${innerH}\> png:$panel

        set page [file join $outdir [format "talk.landscape.4x3.s%02d.png" $n]]
        set slideSource "# $st\n$sb\n"
        ::printable::pageframe::encode -source $slideSource -out $page \
            -pagewmm $PAGE_W_MM -pagehmm $PAGE_H_MM -cellmm $CELL_MM \
            -bandmm $BAND_MM -quietmm $QUIET_MM -dpi $DPI \
            -id $n -file [format "talk.landscape.4x3.s%02d.png" $n] \
            -textpng $panel \
            -extra "doc=talk\npaper=4:3-landscape-10x7.5in\nslide=$n\nslides=$total"
        lappend pages $page
        file delete $tpng $bpng $panel
    }
    return $pages
}

proc build {xmlPath} {
    global DPI PP_BEGIN PP_END
    set xml [slurp $xmlPath]
    set t [parseTalk $xml]
    set outdir [file join [file dirname $xmlPath] build]
    file mkdir $outdir

    set html [emitHtml $t]
    spit [file join $outdir talk.html] $html
    puts "  talk.html"

    set pages [buildSlides $t $outdir]
    puts "  [llength $pages] slides (talk.landscape.4x3.sNN.png)"

    # embed the HTML deck in every slide PNG's tEXt chunk
    foreach page $pages {
        set png [::printable::pngcodec::readFile $page]
        ::printable::pngcodec::writeFile $page [::printable::pngcodec::embed $png $html]
    }

    set im [::printable::typeset::magick]
    set pdf [file join $outdir "talk.landscape.pp.4:3.html.pdf"]
    exec $im {*}$pages -units PixelsPerInch -density $DPI pdf:$pdf
    # append the HTML edition as the PDF's extractable payload
    set b64 [binary encode base64 -maxlen 76 [encoding convertto utf-8 $html]]
    spitb $pdf "[slurpb $pdf]\n$PP_BEGIN\n$b64\n$PP_END\n"
    puts "  talk.landscape.pp.4:3.html.pdf ([file size $pdf] bytes)"
}

proc extract {path} {
    global PP_BEGIN PP_END
    set data [slurpb $path]
    if {[string match "*.png" [string tolower $path]]} {
        return [::printable::pngcodec::extract $data]
    }
    if {[regexp "[string map {% \\%} $PP_BEGIN]\n(.*?)\n[string map {% \\%} $PP_END]" $data -> b64]} {
        return [encoding convertfrom utf-8 [binary decode base64 $b64]]
    }
    error "no PrintablePrograms payload found in $path"
}

if {[llength $argv] < 1} {
    puts stderr "usage: talk.tcl build ?Talk.xml?  |  talk.tcl extract <artifact>"
    exit 2
}
switch -- [lindex $argv 0] {
    build {
        set p [expr {[llength $argv] > 1 ? [lindex $argv 1]
            : [file join $ROOT docs talk Talk.xml]}]
        build $p
    }
    extract { puts -nonewline [extract [lindex $argv 1]] }
    default { puts stderr "unknown mode: [lindex $argv 0]"; exit 2 }
}
