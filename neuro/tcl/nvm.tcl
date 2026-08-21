# nvm.tcl — NeuroVM loader, disassembler and interpreter, in pure Tcl 8.6.
#
# This is the reference implementation of the instruction set defined in
# src/nvm.hpp. When a host disagrees with another host about what a .nvm file
# means, this file is the tie-breaker: it is the shortest complete reading of
# the spec, and it is the one used to generate the plotter and 3D-print output.
#
# The interpreter does no drawing itself. It calls into a *backend* namespace
# whose procs are named after the graphics opcodes, so the same 400 lines drive
# a Tk canvas, an SVG file and an OpenSCAD solid without a single conditional.
# That separation is the whole reason the bytecode exists.
#
#   package require nvm
#   set bc [nvm::load build/dashboard.nvm]
#   nvm::run $bc ::backend::tk
#
# A backend must provide these procs (all coordinates already transformed):
#   clear                          rgba r g b a          linew w
#   font name size                 text x y str anchor
#   path                           moveto x y            lineto x y
#   close                          stroke                fill
#   rect x y w h                   circle x y r          arc x y r a0 a1
#   panel id title                 endpanel
#   anchor id                      note plain full       edge a b hyp w sign
#   flag severity                  cite text
# Any of the semantic ones may be a no-op; the plotter backend ignores note/cite
# because paper has no hover state, and that is a legitimate reading of the file.

package provide nvm 1.0
package require Tcl 8.6

namespace eval nvm {
    variable OPNAME
    array set OPNAME {
        0x00 HALT   0x01 PUSHF  0x02 PUSHI  0x03 PUSHS  0x04 DUP    0x05 DROP
        0x06 SWAP   0x07 OVER
        0x10 ADD    0x11 SUB    0x12 MUL    0x13 DIV    0x14 NEG    0x15 ABS
        0x16 MIN    0x17 MAX    0x18 CLAMP  0x19 LERP   0x1a MAP
        0x20 LOADV  0x21 LOADZ  0x22 LOADD
        0x30 RGBA   0x31 LINEW  0x32 FONT   0x33 PUSHMAT 0x34 POPMAT
        0x35 TRANS  0x36 SCALE  0x37 ROT
        0x40 CLEAR  0x41 MOVETO 0x42 LINETO 0x43 PATH   0x44 CLOSE
        0x45 STROKE 0x46 FILL   0x47 RECT   0x48 CIRCLE 0x49 ARC   0x4a TEXT
        0x50 PANEL  0x51 ENDPANEL 0x52 ANCHOR 0x53 NOTE 0x54 EDGE
        0x55 FLAG   0x56 CITE
        0x60 JMP    0x61 JZ     0x62 CALL   0x63 RET
    }

    # Operand width in bytes. A host that meets an opcode it does not implement
    # can still skip it cleanly, which is what makes the format extensible
    # without a version bump for every new primitive.
    variable OPERAND
    array set OPERAND {
        0x01 4  0x02 4  0x03 2
        0x20 2  0x21 2  0x22 2
        0x30 4  0x31 4  0x32 6  0x4a 3
        0x50 4  0x52 2  0x53 4  0x54 11 0x55 1  0x56 2
        0x60 2  0x61 2  0x62 2
    }
}

# ---------------------------------------------------------------------------
# Loading
# ---------------------------------------------------------------------------
proc nvm::load {path} {
    set f [open $path rb]
    set blob [read $f]
    close $f
    return [parse $blob]
}

proc nvm::parse {blob} {
    if {[string range $blob 0 3] ne "NVM1"} {
        error "nvm: bad magic, not a NeuroVM display file"
    }
    binary scan $blob "@4 su su iu iu iu iu iu iu iu iu iu iu iu iu iu" \
        version flags strOff strCount strLen symOff symCount \
        codeOff codeLen metaOff metaLen crc entry canvasW canvasH

    set bc [dict create \
        version $version flags $flags entry $entry \
        canvasW $canvasW canvasH $canvasH crc $crc]

    # -- string pool --------------------------------------------------------
    set strings {}
    set p $strOff
    for {set i 0} {$i < $strCount} {incr i} {
        binary scan $blob "@$p su" n
        incr p 2
        lappend strings [encoding convertfrom utf-8 [string range $blob $p [expr {$p + $n - 1}]]]
        incr p $n
    }
    dict set bc strings $strings

    # -- symbol table -------------------------------------------------------
    set symbols {}
    set byName [dict create]
    set p $symOff
    for {set i 0} {$i < $symCount} {incr i} {
        binary scan $blob "@$p su su su su r r r r r" \
            nameIdx labelIdx sflags pad value z dist refLo refHi
        incr p 28
        set name [lindex $strings $nameIdx]
        set sym [dict create \
            name     $name \
            label    [expr {$labelIdx == 0xFFFF ? $name : [lindex $strings $labelIdx]}] \
            severity [expr {$sflags & 0x3}] \
            valid    [expr {($sflags >> 2) & 0x1}] \
            domain   [expr {($sflags >> 3) & 0x7}] \
            hasRef   [expr {($sflags >> 6) & 0x1}] \
            refLo    $refLo refHi $refHi \
            value    $value z $z dist $dist]
        lappend symbols $sym
        dict set byName $name $i
    }
    dict set bc symbols $symbols
    dict set bc symIndex $byName

    dict set bc code [string range $blob $codeOff [expr {$codeOff + $codeLen - 1}]]
    dict set bc meta [encoding convertfrom utf-8 \
        [string range $blob $metaOff [expr {$metaOff + $metaLen - 1}]]]

    # CRC is over the code section only. A mismatch means the drawing program is
    # damaged even if the numbers survived, which is worth telling apart.
    set actual [crc32 [dict get $bc code]]
    dict set bc crcOk [expr {$actual == $crc}]
    if {!([dict get $bc crcOk])} {
        puts stderr "nvm: WARNING code CRC mismatch (want $crc got $actual)"
    }
    return $bc
}

proc nvm::crc32 {data} {
    variable crcTable
    if {![info exists crcTable]} {
        for {set i 0} {$i < 256} {incr i} {
            set c $i
            for {set k 0} {$k < 8} {incr k} {
                set c [expr {($c & 1) ? (0xEDB88320 ^ ($c >> 1)) : ($c >> 1)}]
            }
            lappend crcTable $c
        }
    }
    set c 0xFFFFFFFF
    binary scan $data cu* bytes
    foreach b $bytes {
        set c [expr {[lindex $crcTable [expr {($c ^ $b) & 0xFF}]] ^ (($c >> 8) & 0x00FFFFFF)}]
    }
    return [expr {($c ^ 0xFFFFFFFF) & 0xFFFFFFFF}]
}

# ---------------------------------------------------------------------------
# Disassembly
# ---------------------------------------------------------------------------
proc nvm::disasm {bc {from 0} {to -1}} {
    variable OPNAME
    variable OPERAND
    set code [dict get $bc code]
    set strings [dict get $bc strings]
    set symbols [dict get $bc symbols]
    set n [string length $code]
    if {$to < 0} {set to $n}
    set out {}
    set pc $from
    while {$pc < $to} {
        binary scan $code "@$pc cu" op
        set key [format 0x%02x $op]
        set name [expr {[info exists OPNAME($key)] ? $OPNAME($key) : "???"}]
        set nb   [expr {[info exists OPERAND($key)] ? $OPERAND($key) : 0}]
        set arg ""
        switch -- $key {
            0x01 { binary scan $code "@[expr {$pc+1}] r" v ; set arg [format "%.4g" $v] }
            0x02 { binary scan $code "@[expr {$pc+1}] i" v ; set arg $v }
            0x03 - 0x52 - 0x56 {
                binary scan $code "@[expr {$pc+1}] su" v
                set arg "\"[string range [lindex $strings $v] 0 44]\""
            }
            0x20 - 0x21 - 0x22 {
                binary scan $code "@[expr {$pc+1}] su" v
                set arg [dict get [lindex $symbols $v] name]
            }
            0x30 { binary scan $code "@[expr {$pc+1}] cucucucu" r g b a ; set arg "$r $g $b $a" }
            0x31 { binary scan $code "@[expr {$pc+1}] r" v ; set arg [format "%.3g" $v] }
            0x32 {
                binary scan $code "@[expr {$pc+1}] su" s
                binary scan $code "@[expr {$pc+3}] r" sz
                set arg "[lindex $strings $s] [format %.3g $sz]"
            }
            0x4a {
                binary scan $code "@[expr {$pc+1}] su cu" s an
                set arg "\"[string range [lindex $strings $s] 0 40]\" anchor=$an"
            }
            0x50 - 0x53 {
                binary scan $code "@[expr {$pc+1}] su su" a b
                set arg "\"[string range [lindex $strings $a] 0 26]\" \"[string range [lindex $strings $b] 0 26]\""
            }
            0x54 {
                binary scan $code "@[expr {$pc+1}] su su su" a b hy
                binary scan $code "@[expr {$pc+7}] r" w
                binary scan $code "@[expr {$pc+11}] c" sg
                set arg "[lindex $strings $hy]: [lindex $strings $a] -> [lindex $strings $b] w=[format %.2f $w] sign=$sg"
            }
            0x55 { binary scan $code "@[expr {$pc+1}] cu" v
                   set arg [lindex {ok borderline deviant no-data} $v] }
            0x60 - 0x61 { binary scan $code "@[expr {$pc+1}] s" v
                          set arg "$v -> [expr {$pc + 3 + $v}]" }
            0x62 { binary scan $code "@[expr {$pc+1}] su" v ; set arg "-> $v" }
        }
        lappend out [format "%6d  %-9s %s" $pc $name $arg]
        incr pc [expr {1 + $nb}]
    }
    return [join $out \n]
}

# ---------------------------------------------------------------------------
# Interpreter
# ---------------------------------------------------------------------------
# A 3x2 affine matrix as {a b c d e f}, mapping (x,y) -> (a*x + c*y + e,
# b*x + d*y + f). Only translate and scale are emitted today but rotate is
# implemented so the plotter can lay panels out at an angle on a sheet.
proc nvm::matIdentity {} { return {1 0 0 1 0 0} }

proc nvm::matMul {m n} {
    lassign $m a b c d e f
    lassign $n A B C D E F
    return [list \
        [expr {$a*$A + $c*$B}] [expr {$b*$A + $d*$B}] \
        [expr {$a*$C + $c*$D}] [expr {$b*$C + $d*$D}] \
        [expr {$a*$E + $c*$F + $e}] [expr {$b*$E + $d*$F + $f}]]
}

proc nvm::matApply {m x y} {
    lassign $m a b c d e f
    return [list [expr {$a*$x + $c*$y + $e}] [expr {$b*$x + $d*$y + $f}]]
}

# Uniform scale factor, for radii and line widths that cannot be transformed
# component-wise. Emitted content never uses anisotropic scale, so the
# geometric mean is exact rather than an approximation here.
proc nvm::matScale {m} {
    lassign $m a b c d
    return [expr {sqrt(abs($a*$d - $b*$c))}]
}

# `m0` seeds the transform stack, so a host can zoom by handing the VM a scale
# matrix instead of post-scaling the output. That distinction matters: post-
# scaling a Tk canvas moves the geometry but leaves every font at its authored
# size, which silently breaks the layout the emitter computed. Zooming through
# the matrix keeps type and geometry locked together, as the design intends.
proc nvm::run {bc backend {m0 {}}} {
    variable OPNAME
    variable OPERAND

    set code    [dict get $bc code]
    set strings [dict get $bc strings]
    set symbols [dict get $bc symbols]
    set n [string length $code]

    set S {}                       ;# operand stack (floats)
    set R {}                       ;# return-address stack
    set M [expr {[llength $m0] == 6 ? $m0 : [matIdentity]}]  ;# current transform
    set MS {}                      ;# transform stack
    set pc [dict get $bc entry]

    # Path accumulation. RECT/CIRCLE/ARC also fill this so that a single
    # STROKE or FILL closes whatever the last primitive was, which is what
    # makes the emitted code so compact.
    set pathKind ""
    set pathPts {}
    set pathArgs {}

    set push {}
    set steps 0
    set maxSteps 4000000

    while {$pc < $n} {
        if {[incr steps] > $maxSteps} { error "nvm: step limit exceeded, runaway bytecode" }
        binary scan $code "@$pc cu" op
        set key [format 0x%02x $op]
        set nb [expr {[info exists OPERAND($key)] ? $OPERAND($key) : 0}]
        set next [expr {$pc + 1 + $nb}]

        # An opcode with no arm falls through to the bottom of the switch and
        # the pc still advances by 1 + its declared operand width, so an
        # unrecognised instruction is skipped cleanly rather than
        # desynchronising the stream.
        switch -- $key {
            0x00 { return }
            0x01 { binary scan $code "@[expr {$pc+1}] r" v ; lappend S $v }
            0x02 { binary scan $code "@[expr {$pc+1}] i" v ; lappend S [expr {double($v)}] }
            0x03 { binary scan $code "@[expr {$pc+1}] su" v ; lappend S [expr {double($v)}] }
            0x04 { lappend S [lindex $S end] }
            0x05 { set S [lrange $S 0 end-1] }
            0x06 { set a [lindex $S end-1] ; set b [lindex $S end]
                   set S [lreplace $S end-1 end $b $a] }
            0x07 { lappend S [lindex $S end-1] }

            0x10 { set b [pop S] ; set a [pop S] ; lappend S [expr {$a + $b}] }
            0x11 { set b [pop S] ; set a [pop S] ; lappend S [expr {$a - $b}] }
            0x12 { set b [pop S] ; set a [pop S] ; lappend S [expr {$a * $b}] }
            0x13 { set b [pop S] ; set a [pop S]
                   lappend S [expr {$b == 0 ? 0.0 : $a / $b}] }
            0x14 { set a [pop S] ; lappend S [expr {-$a}] }
            0x15 { set a [pop S] ; lappend S [expr {abs($a)}] }
            0x16 { set b [pop S] ; set a [pop S] ; lappend S [expr {min($a,$b)}] }
            0x17 { set b [pop S] ; set a [pop S] ; lappend S [expr {max($a,$b)}] }
            0x18 { set hi [pop S] ; set lo [pop S] ; set v [pop S]
                   lappend S [expr {max($lo, min($hi, $v))}] }
            0x19 { set t [pop S] ; set b [pop S] ; set a [pop S]
                   lappend S [expr {$a + ($b - $a) * $t}] }
            0x1a { set o1 [pop S] ; set o0 [pop S] ; set i1 [pop S] ; set i0 [pop S]
                   set v [pop S]
                   lappend S [expr {($i1 == $i0) ? $o0 : $o0 + ($v - $i0) * ($o1 - $o0) / ($i1 - $i0)}] }

            0x20 - 0x21 - 0x22 {
                binary scan $code "@[expr {$pc+1}] su" si
                set sym [lindex $symbols $si]
                set fld [dict get {0x20 value 0x21 z 0x22 dist} $key]
                lappend S [dict get $sym $fld]
            }

            0x30 { binary scan $code "@[expr {$pc+1}] cucucucu" r g b a
                   ${backend}::rgba $r $g $b $a }
            0x31 { binary scan $code "@[expr {$pc+1}] r" w
                   ${backend}::linew [expr {$w * [matScale $M]}] }
            0x32 { binary scan $code "@[expr {$pc+1}] su" s
                   binary scan $code "@[expr {$pc+3}] r" sz
                   ${backend}::font [lindex $strings $s] [expr {$sz * [matScale $M]}] }
            0x33 { lappend MS $M }
            0x34 { set M [lindex $MS end] ; set MS [lrange $MS 0 end-1] }
            0x35 { set y [pop S] ; set x [pop S]
                   set M [matMul $M [list 1 0 0 1 $x $y]] }
            0x36 { set sy [pop S] ; set sx [pop S]
                   set M [matMul $M [list $sx 0 0 $sy 0 0]] }
            0x37 { set a [pop S]
                   set M [matMul $M [list [expr {cos($a)}] [expr {sin($a)}] \
                                          [expr {-sin($a)}] [expr {cos($a)}] 0 0]] }

            0x40 { ${backend}::clear }
            0x41 { set y [pop S] ; set x [pop S]
                   set pathKind line ; set pathPts [matApply $M $x $y] }
            0x42 { set y [pop S] ; set x [pop S]
                   lappend pathPts {*}[matApply $M $x $y] }
            0x43 { set pathKind line ; set pathPts {} }
            0x44 { if {[llength $pathPts] >= 4} {
                       lappend pathPts [lindex $pathPts 0] [lindex $pathPts 1]
                   } }
            0x45 { emit $backend stroke $pathKind $pathPts $pathArgs }
            0x46 { emit $backend fill   $pathKind $pathPts $pathArgs }
            0x47 { set h [pop S] ; set w [pop S] ; set y [pop S] ; set x [pop S]
                   # Negative extents are legal and mean "grow the other way";
                   # the ladder panel relies on it for leftward bars.
                   if {$w < 0} { set x [expr {$x + $w}] ; set w [expr {-$w}] }
                   if {$h < 0} { set y [expr {$y + $h}] ; set h [expr {-$h}] }
                   lassign [matApply $M $x $y] X0 Y0
                   lassign [matApply $M [expr {$x+$w}] [expr {$y+$h}]] X1 Y1
                   set pathKind rect ; set pathPts [list $X0 $Y0 $X1 $Y1] ; set pathArgs {} }
            0x48 { set r [pop S] ; set y [pop S] ; set x [pop S]
                   lassign [matApply $M $x $y] X Y
                   set pathKind circle ; set pathPts [list $X $Y]
                   set pathArgs [list [expr {$r * [matScale $M]}]] }
            0x49 { set a1 [pop S] ; set a0 [pop S] ; set r [pop S]
                   set y [pop S] ; set x [pop S]
                   lassign [matApply $M $x $y] X Y
                   set pathKind arc ; set pathPts [list $X $Y]
                   set pathArgs [list [expr {$r * [matScale $M]}] $a0 $a1] }
            0x4a { binary scan $code "@[expr {$pc+1}] su cu" s an
                   set y [pop S] ; set x [pop S]
                   lassign [matApply $M $x $y] X Y
                   ${backend}::text $X $Y [lindex $strings $s] $an }

            0x50 { binary scan $code "@[expr {$pc+1}] su su" a b
                   ${backend}::panel [lindex $strings $a] [lindex $strings $b] }
            0x51 { ${backend}::endpanel }
            0x52 { binary scan $code "@[expr {$pc+1}] su" a
                   ${backend}::anchor [lindex $strings $a] }
            0x53 { binary scan $code "@[expr {$pc+1}] su su" a b
                   ${backend}::note [lindex $strings $a] [lindex $strings $b] }
            0x54 { binary scan $code "@[expr {$pc+1}] su su su" a b hy
                   binary scan $code "@[expr {$pc+7}] r" w
                   binary scan $code "@[expr {$pc+11}] c" sg
                   ${backend}::edge [lindex $strings $a] [lindex $strings $b] \
                       [lindex $strings $hy] $w $sg }
            0x55 { binary scan $code "@[expr {$pc+1}] cu" v ; ${backend}::flag $v }
            0x56 { binary scan $code "@[expr {$pc+1}] su" a
                   ${backend}::cite [lindex $strings $a] }

            0x60 { binary scan $code "@[expr {$pc+1}] s" d ; set next [expr {$pc + 3 + $d}] }
            0x61 { binary scan $code "@[expr {$pc+1}] s" d
                   if {[pop S] == 0} { set next [expr {$pc + 3 + $d}] } }
            0x62 { binary scan $code "@[expr {$pc+1}] su" tgt
                   lappend R $next ; set next $tgt }
            0x63 { if {[llength $R] == 0} { return }
                   set next [lindex $R end] ; set R [lrange $R 0 end-1] }
        }
        set pc $next
    }
}

proc nvm::pop {name} {
    upvar 1 $name S
    set v [lindex $S end]
    set S [lrange $S 0 end-1]
    if {$v eq ""} { return 0.0 }
    return $v
}

proc nvm::emit {backend how kind pts args_} {
    switch -- $kind {
        rect   { lassign $pts x0 y0 x1 y1
                 ${backend}::rect $how $x0 $y0 [expr {$x1-$x0}] [expr {$y1-$y0}] }
        circle { lassign $pts x y ; ${backend}::circle $how $x $y [lindex $args_ 0] }
        arc    { lassign $pts x y
                 ${backend}::arc $how $x $y {*}$args_ }
        line   { if {[llength $pts] >= 4} { ${backend}::polyline $how $pts } }
    }
}

# ---------------------------------------------------------------------------
# Convenience accessors
# ---------------------------------------------------------------------------
proc nvm::sym {bc name} {
    set idx [dict get $bc symIndex]
    if {![dict exists $idx $name]} { return "" }
    return [lindex [dict get $bc symbols] [dict get $idx $name]]
}

proc nvm::symbolsBySeverity {bc severity} {
    set out {}
    foreach s [dict get $bc symbols] {
        if {[dict get $s severity] == $severity} { lappend out $s }
    }
    return $out
}
