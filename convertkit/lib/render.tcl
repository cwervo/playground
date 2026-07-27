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
        # vendored IBM Plex Mono wins (fonts/ sits next to lib/)
        set vendored [file join [file dirname [file dirname [file normalize \
                          [dict get [info frame 0] file]]]] fonts IBMPlexMono-Regular.ttf]
        if {[file exists $vendored]} { return $vendored }
        if {![catch {exec $im -list font} fonts]} {
            foreach want {IBM-Plex-Mono IBMPlexMono DejaVu-Sans-Mono Liberation-Mono Courier} {
                if {[string first $want $fonts] >= 0} { return $want }
            }
        }
        return ""
    }

    # Render source text to a PNG at $path: #1010FF on white (maximum
    # non-black contrast), minimum 12pt regardless of output size --
    # -density makes -pointsize a physical size, so 12pt stays 12pt at
    # any DPI. Returns 1 if ImageMagick did the rendering, 0 if the
    # blank fallback was used.
    proc codePng {text path {dpi 96} {pointsize 12}} {
        if {$pointsize < 12} { set pointsize 12 }
        set im [magick]
        if {$im ne ""} {
            set font [pickFont]
            set args [list -density $dpi -background white -fill "#1010FF" \
                          -pointsize $pointsize]
            if {$font ne ""} { lappend args -font $font }
            # label:<text> inline: default IM security policy forbids @file reads
            set ok [expr {![catch {
                exec $im {*}$args label:$text \
                    -bordercolor white -border 12 \
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
