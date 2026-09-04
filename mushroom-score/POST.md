# Post kit — Instagram & TikTok

## Assets

| use | file | spec |
|---|---|---|
| IG feed post | `out/mushroom_score_post_4x5.png` | 1080 × 1350, 4:5 |
| IG story / TikTok cover | `out/mushroom_score_cover_9x16.png` | 1080 × 1920, 9:16 |
| Reel / TikTok video | `out/mushroom_visual_score.mp4` | 720 × 1280, 16.95 s, AAC 192k |
| carousel slides | `out/plates/` | 720 × 1280 each |
| audio only | `out/mushroom_track.m4a` | 18.95 s incl. reverb tail |

**Video note.** 16.95 s sits just under TikTok's and Reels' comfortable minimum for
reach; both platforms favour a loop. The clip loops cleanly — it opens and closes on
a wide framing with a crash on each — so set it to repeat rather than padding it.
Upload the 720 × 1280 master directly; do not let the platform letterbox it.

## Carousel order (IG)

1. `mushroom_score_post_4x5.png` — the score sheet
2. `plates/cue_01_IN_f0213.png` — maximum zoom in, the kick
3. `plates/cue_02_OUT_f0325.png` — maximum zoom out, the crash
4. `plates/stop_WIDE_f0060.png` — the vector field on the weeds
5. `plates/stop_MID_f0110.png` — the cap at 0.1 % of frame, still tracked

## Caption — long (Instagram)

> A mushroom came up at the base of a street tree, so I made it a score.
>
> Three photos of it — tight, mid, wide — are the stopping points. Each one gets
> reduced to two colours in CIELAB: the white of the cap, the green of the weeds.
> Then every frame of the video gets measured against those two colours with ΔE₀₀,
> the cap gets tracked, and the plants' movement gets sampled as a vector field.
>
> Navy is the mushroom. Magenta is the plants moving. Amber is a drum hit.
>
> The camera's zoom is the melody — closer is higher. The two moments it pushes all
> the way in are a kick; the three moments it pulls all the way out are a crash. The
> beat gets denser the closer the camera gets, and the hats follow the weeds moving.
> The tempo isn't a choice: the camera pushes in twice, 7.2 seconds apart, and
> calling that four bars gives 133.2 BPM.
>
> Hardest part was the wide shots. The cap is 0.05% of the frame there, and a sunlit
> sidewalk slab is brighter, bigger and rounder than the mushroom — it beat it on
> every test I tried. Fixed by tracking through time instead of judging each frame
> alone: lock on where the cap fills the frame, then walk outward and never let it
> jump.
>
> Sound is a synth I wrote in numpy, driven by a MIDI file the video generated.
>
> 🍄 Queens, NY

## Caption — short (TikTok)

> I turned a sidewalk mushroom into a song.
>
> Navy = the mushroom. Magenta = the plants moving. Amber = a drum hit.
> Zoom in and the pitch goes up, and the beat gets denser. All the way in is a kick,
> all the way out is a crash.
>
> 133.2 BPM — the camera set that, not me. It pushes in twice, 7.2 s apart.

## Alt text

> A vertical video frame of a white mushroom at the base of a street tree, overlaid
> with computer-vision graphics: a navy blue detector frame and crosshair on the
> mushroom cap, magenta arrows across the surrounding green weeds showing their
> motion, a data readout along the top, and a zoom curve with amber cue markers along
> the bottom.

## Hashtags

```
#visualscore #generativeart #creativecoding #opencv #computervision #cielab
#mushroom #urbannature #sidewalkmushroom #newmediaart #audiovisual #midi
#pythonart #datasonification #experimentalmusic #nycnature #foraging #mycology
```

## First comment

> Full process notes, the timing chart and the MIDI are in the repo — the video
> generates the MIDI, and the MIDI generates the audio, so you can open the .mid,
> change it, and re-render the track.
