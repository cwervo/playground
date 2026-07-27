# render.tcl -- visible raster generation for convertkit.
#
# The sketch calls for "a PNG with code set in IBM Plex Mono & a border
# around the frame". We approximate that with ImageMagick when it's on
# PATH (IBM Plex Mono if installed, else any mono font), and fall back
# to a pure-Tcl solid PNG so the pipeline never breaks. The raster is
# purely cosmetic -- the authoritative payload lives in metadata chunks.

namespace eval ::convertkit::render {

    proc magick {} {
        foreach c {magick convert} {
            if {[llength [auto_execok $c]]} { return $c }
        }
        return ""
    }

    proc pickFont {} {
        set im [magick]
        if {$im eq ""} { return "" }
        if {![catch {exec $im -list font} fonts]} {
            foreach want {IBM-Plex-Mono IBMPlexMono DejaVu-Sans-Mono Liberation-Mono Courier} {
                if {[string first $want $fonts] >= 0} { return $want }
            }
        }
        return ""
    }

    # Render source text to a bordered PNG at $path. Returns 1 if
    # ImageMagick did the rendering, 0 if the blank fallback was used.
    proc codePng {text path {title ""}} {
        set im [magick]
        if {$im ne ""} {
            set font [pickFont]
            set args [list -background "#16161e" -fill "#c8d3f5" -pointsize 14]
            if {$font ne ""} { lappend args -font $font }
            # label:<text> inline: default IM security policy forbids @file reads
            set ok [expr {![catch {
                exec $im {*}$args label:$text \
                    -bordercolor "#ff9e64" -border 6 \
                    -bordercolor "#16161e" -border 18 \
                    png:$path
            } err]}]
            if {$ok} { return 1 }
        }
        ::convertkit::pngcodec::writeFile $path [::convertkit::pngcodec::blankPng]
        return 0
    }

    # PNG -> JPEG raster transcode (payload re-embedding handled by caller).
    proc pngToJpgRaster {pngPath jpgPath} {
        set im [magick]
        if {$im eq ""} { error "ImageMagick required for PNG<->JPEG raster transcode" }
        exec $im $pngPath -quality 92 jpg:$jpgPath
    }

    proc jpgToPngRaster {jpgPath pngPath} {
        set im [magick]
        if {$im eq ""} { error "ImageMagick required for PNG<->JPEG raster transcode" }
        exec $im $jpgPath png:$pngPath
    }
}
