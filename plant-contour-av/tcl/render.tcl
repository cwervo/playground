#!/usr/bin/env tclsh
# ============================================================================
#  render.tcl -- pipeline driver.
#
#  Tcl is the conductor: it probes the source, runs the C++ vision engine as a
#  raw-pixel filter between a demuxer and a muxer, runs the Tcl synthesiser
#  over the analysis the engine emitted, then muxes the result and exports the
#  still sequence.
#
#  usage: tclsh render.tcl <input.mov> <outdir>
# ============================================================================

lassign $argv SRC OUT
if {$OUT eq ""} { puts stderr "usage: render.tcl <input.mov> <outdir>"; exit 1 }
set ROOT [file normalize [file join [file dirname [info script]] ..]]
set PCAV [file join $ROOT build pcav]
set WORK [file join $ROOT work]
file mkdir $OUT $WORK [file join $OUT frames]

proc note {m} { puts stderr "\[render\] $m" }

# ---- probe -----------------------------------------------------------------
proc probe {src key {stream v:0}} {
    string trim [exec ffprobe -v error -select_streams $stream \
        -show_entries stream=$key -of default=nw=1:nk=1 $src]
}
set w [probe $SRC width]
set h [probe $SRC height]
set rot 0
catch {
    set rot [string trim [exec ffprobe -v error -select_streams v:0 \
        -show_entries stream_side_data=rotation -of default=nw=1:nk=1 $SRC]]
}
if {$rot eq ""} { set rot 0 }
# ffmpeg auto-rotates on decode, so the raw stream we receive is already upright
if {abs($rot) == 90 || abs($rot) == 270} { lassign [list $h $w] w h }
set fps [string trim [probe $SRC r_frame_rate]]
note "source ${w}x${h} @ $fps  (rotation $rot)"

set METRICS [file join $OUT metrics.tsv]
set BOXES   [file join $OUT boxes.tsv]
set VID     [file join $WORK graded.mp4]
set AMB     [file join $WORK ambience.raw]
set WAV     [file join $WORK score.wav]
set FINAL   [file join $OUT plant_contour_av.mp4]

# ---- 1. vision pass: demux -> pcav -> mux -----------------------------------
note "vision pass (contours, velocity zones, shadows, grade)"
exec ffmpeg -v error -i $SRC -f rawvideo -pix_fmt rgb24 - \
   | $PCAV $w $h $METRICS $BOXES \
   | ffmpeg -v error -f rawvideo -pix_fmt rgb24 -s ${w}x${h} -r $fps -i - \
       -c:v libx264 -preset slow -crf 17 -pix_fmt yuv420p -movflags +faststart \
       -y $VID >@ stderr 2>@ stderr

# ---- 2. location sound out to raw PCM for the Tcl mixer ---------------------
note "decoding location sound to raw PCM"
exec ffmpeg -v error -i $SRC -vn -ac 2 -ar 44100 -f s16le -acodec pcm_s16le \
    -y $AMB 2>@ stderr

# ---- 3. score -------------------------------------------------------------
note "synthesising score in Tcl"
exec tclsh [file join $ROOT tcl synth.tcl] $METRICS $AMB $WAV >@ stderr 2>@ stderr

# ---- 4. mux ---------------------------------------------------------------
note "muxing picture + score"
exec ffmpeg -v error -i $VID -i $WAV -map 0:v:0 -map 1:a:0 \
    -c:v copy -c:a aac -b:a 224k -shortest -movflags +faststart \
    -y $FINAL 2>@ stderr

# ---- 5. still sequences ----------------------------------------------------
# Two exports: the full-resolution working sequence, and a 480-wide sequence
# small enough to travel with the repository.
note "exporting still sequence (full resolution)"
exec ffmpeg -v error -i $VID -q:v 2 -y [file join $OUT frames frame_%04d.jpg] 2>@ stderr

file mkdir [file join $OUT sequence_480]
note "exporting still sequence (480 wide)"
exec ffmpeg -v error -i $VID -vf scale=400:-2 -q:v 7 \
    -y [file join $OUT sequence_480 pcav_%04d.jpg] 2>@ stderr

note "building contact sheet"
exec ffmpeg -v error -i $VID -vf "select=not(mod(n\\,27)),scale=240:-1,tile=4x3" \
    -frames:v 1 -q:v 2 -y [file join $OUT contact_sheet.jpg] 2>@ stderr

note "zipping the sequence"
set cwd [pwd]
cd $OUT
catch { file delete plant_contour_av_frames.zip }
exec zip -q -r plant_contour_av_frames.zip sequence_480
cd $cwd

set n  [llength [glob -nocomplain [file join $OUT frames frame_*.jpg]]]
set n2 [llength [glob -nocomplain [file join $OUT sequence_480 pcav_*.jpg]]]
note "done"
note "  video     : $FINAL"
note "  stills    : $n full-res in [file join $OUT frames]"
note "              $n2 web-res in [file join $OUT sequence_480] (+ .zip)"
note "  analysis  : $METRICS / $BOXES"
