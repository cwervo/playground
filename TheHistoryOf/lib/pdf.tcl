# pdf.tcl -- minimal pure-Tcl PDF assembler for TheHistoryOf.
#
# Ghostscript-free by design: each page is a JPEG embedded verbatim as a
# /DCTDecode image XObject, so the PDF pipeline needs nothing beyond the
# JPEGs themselves (which ImageMagick already produces for the page
# rasters).  One image = one page; pages keep the physical size given in
# points.

namespace eval ::thehistoryof::pdf {

    # width/height in pixels from a JPEG's SOFn segment
    proc jpegSize {data} {
        set len [string length $data]
        set i 2
        while {$i < $len} {
            binary scan [string range $data $i $i+1] cucu m code
            if {$m != 0xFF} { incr i; continue }
            # SOF0..SOF15 except DHT(C4) DNL? (C8) DAC(CC)
            if {$code >= 0xC0 && $code <= 0xCF
                && $code != 0xC4 && $code != 0xC8 && $code != 0xCC} {
                binary scan [string range $data [expr {$i+5}] [expr {$i+8}]] SuSu h w
                return [list $w $h]
            }
            if {$code == 0xD8 || ($code >= 0xD0 && $code <= 0xD9)} { incr i 2; continue }
            binary scan [string range $data [expr {$i+2}] [expr {$i+3}]] Su seglen
            incr i [expr {2 + $seglen}]
        }
        error "no SOF marker found in JPEG"
    }

    # write a PDF at $out from a list of JPEG paths; every page is
    # $ptw x $pth points (US letter default).
    proc fromJpegs {out jpegPaths {ptw 612} {pth 792}} {
        set objs {}   ;# list of object bodies, index+1 = object number
        set kids {}
        set npages [llength $jpegPaths]

        # objects 1 (catalog) and 2 (pages) are placeholders filled below
        lappend objs "" ""

        foreach jp $jpegPaths {
            set f [open $jp rb]; set jpg [read $f]; close $f
            lassign [jpegSize $jpg] w h

            set imgNum [expr {[llength $objs] + 1}]
            lappend objs [format {<< /Type /XObject /Subtype /Image /Width %d /Height %d /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length %d >>
stream
%s
endstream} $w $h [string length $jpg] $jpg]

            set stream [format "q %s 0 0 %s 0 0 cm /Im%d Do Q" $ptw $pth $imgNum]
            set streamNum [expr {[llength $objs] + 1}]
            lappend objs [format {<< /Length %d >>
stream
%s
endstream} [string length $stream] $stream]

            set pageNum [expr {[llength $objs] + 1}]
            lappend objs [format {<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %s %s] /Resources << /XObject << /Im%d %d 0 R >> >> /Contents %d 0 R >>} \
                              $ptw $pth $imgNum $imgNum $streamNum]
            lappend kids "$pageNum 0 R"
        }

        lset objs 0 "<< /Type /Catalog /Pages 2 0 R >>"
        lset objs 1 "<< /Type /Pages /Count $npages /Kids \[[join $kids { }]\] >>"

        set buf "%PDF-1.4\n%\xE2\xE3\xCF\xD3\n"
        set offsets {}
        set num 0
        foreach body $objs {
            incr num
            lappend offsets [string length $buf]
            append buf "$num 0 obj\n$body\nendobj\n"
        }
        set xrefOff [string length $buf]
        append buf "xref\n0 [expr {$num + 1}]\n"
        append buf "0000000000 65535 f \n"
        foreach off $offsets {
            append buf [format "%010d 00000 n \n" $off]
        }
        append buf "trailer\n<< /Size [expr {$num + 1}] /Root 1 0 R >>\nstartxref\n$xrefOff\n%%EOF\n"

        set f [open $out wb]
        puts -nonewline $f $buf
        close $f
        return $out
    }
}
