# plant-contour-av

An audio-visual analysis of one 10.7-second clip: a walk down a sidewalk toward a weed
growing out of the crack where a brick wall meets the concrete.

The picture is annotated with navy bounding boxes over bright-green plant contours and
over zones of high and low velocity, the shadows are segmented and mixed with dark
purple, and the whole frame is graded filmic. The score is generated from the analysis —
camera velocity drives an arpeggiated Nickelodeon-style keyboard, shadow movement drives
a synth hi-hat.

Everything is written from scratch in **C++** (the vision engine and colourist) and
**Tcl** (the synthesiser, arranger, mixer and pipeline driver). No computer-vision
library, no audio library, no font. `ffmpeg` is used only to demux, decode and mux —
it touches no pixel and no sample that these two programs did not compute.

**→ [EXPLANATION.md](EXPLANATION.md) is the full write-up: every algorithm, every
mapping, and exactly where the boundary of "no library" is drawn.**

## Layout

```
src/pcav.cpp        vision engine + film grade   (C++, 769 lines)
tcl/synth.tcl       synthesiser + arranger + mixer (Tcl, 394 lines)
tcl/render.tcl      pipeline driver               (Tcl,  98 lines)
out/                rendered results
```

## Run

```bash
g++ -O2 -ffast-math -o build/pcav src/pcav.cpp
tclsh tcl/render.tcl /path/to/IMG_7688.mov out
```

`pcav` is a Unix filter: raw `rgb24` in on stdin, raw `rgb24` out on stdout, per-frame
measurements to two TSV files. `synth.tcl` reads those measurements and writes a WAV.
Neither program knows anything about video containers.

## Output

| File | |
|---|---|
| `out/plant_contour_av.mp4` | the finished piece, 720×1280, picture + score |
| `out/plant_contour_av_frames.zip` | the complete 322-frame still sequence |
| `out/contact_sheet.jpg` | twelve frames across the clip |
| `out/metrics.tsv` | 322 rows × 19 columns of per-frame analysis |
| `out/boxes.tsv` | every bounding box drawn: frame, kind, x, y, w, h, area |
