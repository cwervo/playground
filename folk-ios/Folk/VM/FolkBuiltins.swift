// FolkBuiltins.swift
// Built-in Folk programs, embedded as source strings (the VM has no file
// I/O). The metaball clock mirrors the app icon: four gold metaballs whose
// positions encode HH / MM / SS / milliseconds.

import Foundation

enum FolkBuiltins {

    static let programs: [(String, String)] = [
        ("background", background),
        ("metaball-clock", metaballClock),
        ("comet", comet),
        ("welcome", welcome),
    ]

    static let background = """
    Wish the surface is cleared with color {0.06 0.06 0.08 1}
    """

    static let metaballClock = """
    # Four gold metaballs on concentric rings: hours, minutes, seconds,
    # milliseconds — the same figure the app icon freezes at build time.
    When the surface has size /w/ /h/ {
        When the wall clock is /hh/ /mm/ /ss/ /ms/ {
            set pi 3.141592653589793
            set cx [expr {$w / 2.0}]
            set cy [expr {$h / 2.0}]
            set dim [expr {$w < $h ? $w : $h}]

            set balls {}
            foreach spec [list [list $hh 24 0.10] \\
                               [list $mm 60 0.17] \\
                               [list $ss 60 0.24] \\
                               [list $ms 1000 0.31]] {
                lassign $spec v max frac
                set a [expr {2 * $pi * $v / $max - $pi / 2}]
                set r [expr {$dim * $frac}]
                lappend balls [list [expr {$cx + $r * cos($a)}] [expr {$cy + $r * sin($a)}]]
                Wish to draw a circle at [list $cx $cy] radius $r color {0.83 0.68 0.21 0.18} thickness 1
            }

            Wish to draw metaballs at [lindex $balls 0] [lindex $balls 1] \\
                [lindex $balls 2] [lindex $balls 3] \\
                radius [expr {$dim * 0.085}] color gold

            Wish to draw text [format "%02d:%02d:%02d.%03d" $hh $mm $ss $ms] \\
                at [list $cx [expr {$cy + $dim * 0.40}]] size 15 color {0.9 0.85 0.6 0.8}
        }
    }
    """

    static let comet = """
    # A small gold comet on a Lissajous orbit, to show continuous animation
    # driven by "the clock time" claims.
    When the surface has size /w/ /h/ {
        When the clock time is /t/ {
            set x [expr {$w * (0.5 + 0.40 * sin($t * 1.3))}]
            set y [expr {$h * (0.5 + 0.36 * sin($t * 2.1))}]
            Wish to draw a circle at [list $x $y] radius 7 color {1.0 0.85 0.4 0.9}
            set px [expr {$w * (0.5 + 0.40 * sin(($t - 0.08) * 1.3))}]
            set py [expr {$h * (0.5 + 0.36 * sin(($t - 0.08) * 2.1))}]
            Wish to draw a line from [list $px $py] to [list $x $y] color {1.0 0.85 0.4 0.35} thickness 3
        }
    }
    """

    static let welcome = """
    Wish $this is labelled "the folk vm is alive"
    When /someone/ claims the clock time is /t/ {
        if {$t < 6} {
            Wish to draw text "folk" at {70 60} size 30 color gold
        }
    }
    """

    /// Starter code shown in the input box.
    static let sampleUserProgram = """
    # Edit me and press Run.
    When the surface has size /w/ /h/ {
        When the clock time is /t/ {
            set r [expr {40 + 18 * sin($t * 2.0)}]
            Wish to draw a circle at [list [expr {$w * 0.25}] [expr {$h * 0.7}]] \\
                radius $r color cyan thickness 3
        }
    }
    """
}
