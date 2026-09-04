#!/usr/bin/env python3
"""
Stage 08 - the published post kit page.

Builds out/post_kit.html: the cut assets, caption copy, cue sheet and process
notes as one page, for publishing as an Artifact. Self-contained - it derives
the zoom-curve geometry from work/analysis.npz and embeds the poster and plate
images as data URIs, because a published artifact may only load images that
ship with the page.
"""
import base64
import html
import io
import json
import pathlib

import numpy as np
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
WORK = ROOT / "work"
OUT = ROOT / "out"

# ---- derive the curve geometry and embed the assets ----------------------
_d = np.load(WORK / "analysis.npz")
_a = json.loads((WORK / "analysis.json").read_text())
_z = _d["zoom"]
_n = len(_z)

_idx = np.linspace(0, _n - 1, 160).astype(int)
_cues = ([{"f": e["frame"], "t": e["t"], "k": "IN"} for e in _a["zoom_in_extrema"]]
         + [{"f": e["frame"], "t": e["t"], "k": "OUT"} for e in _a["zoom_out_extrema"]])
_cues.sort(key=lambda q: q["f"])
for _q in _cues:
    _q["x"] = _q["f"] / (_n - 1)
c = {
    "cues": _cues,
    "segs": [{"s": s["stop"], "a": s["start_frame"] / (_n - 1),
              "b": s["end_frame"] / (_n - 1), "t0": s["start_s"], "t1": s["end_s"]}
             for s in _a["stop_segments"]],
}

# Curve path in a 1000-wide viewBox, y=0..1 mapped to 238..26.
path = " ".join(
    ("M" if k == 0 else "L") + f"{i / (_n - 1) * 1000:.2f} {238 - 212 * float(_z[i]):.2f}"
    for k, i in enumerate(_idx))


def _b64(rel, width, quality=82):
    im = Image.open(OUT / rel).convert("RGB")
    im = im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)
    buf = io.BytesIO()
    im.save(buf, "JPEG", quality=quality, optimize=True)
    return "data:image/jpeg;base64," + base64.b64encode(buf.getvalue()).decode()


imgs = {
    "post": _b64("mushroom_score_post_4x5.png", 520),
    "cover": _b64("mushroom_score_cover_9x16.png", 380),
    "cue_in": _b64("plates/cue_01_IN_f0213.png", 300),
    "cue_out": _b64("plates/cue_02_OUT_f0325.png", 300),
    "wide": _b64("plates/stop_WIDE_f0060.png", 300),
}

HERE = OUT

W = 1000
SEG_TONE = {"WIDE": "var(--wide)", "MID": "var(--mid)", "TIGHT": "var(--tight)"}

CAP_LONG = """A mushroom came up at the base of a street tree, so I made it a score.

Three photos of it — tight, mid, wide — are the stopping points. Each one gets reduced to two colours in CIELAB: the white of the cap, the green of the weeds. Then every frame of the video gets measured against those two colours with ΔE₀₀, the cap gets tracked, and the plants' movement gets sampled as a vector field.

Navy is the mushroom. Magenta is the plants moving. Amber is a drum hit.

The camera's zoom is the melody — closer is higher. The two moments it pushes all the way in are a kick; the three moments it pulls all the way out are a crash. The beat gets denser the closer the camera gets, and the hats follow the weeds moving. The tempo isn't a choice: the camera pushes in twice, 7.2 seconds apart, and calling that four bars gives 133.2 BPM.

Hardest part was the wide shots. The cap is 0.05% of the frame there, and a sunlit sidewalk slab is brighter, bigger and rounder than the mushroom — it beat it on every test I tried. Fixed by tracking through time instead of judging each frame alone: lock on where the cap fills the frame, then walk outward and never let it jump.

Sound is a synth I wrote in numpy, driven by a MIDI file the video generated.

🍄 Queens, NY"""

CAP_SHORT = """I turned a sidewalk mushroom into a song.

Navy = the mushroom. Magenta = the plants moving. Amber = a drum hit.
Zoom in and the pitch goes up, and the beat gets denser.
All the way in is a kick, all the way out is a crash.

133.2 BPM — the camera set that, not me. It pushes in twice, 7.2 s apart."""

ALT = ("A vertical video frame of a white mushroom at the base of a street tree, "
       "overlaid with computer-vision graphics: a navy blue detector frame and crosshair "
       "on the mushroom cap, magenta arrows across the surrounding green weeds showing "
       "their motion, a data readout along the top, and a zoom curve with amber cue "
       "markers along the bottom.")

TAGS = ("#visualscore #generativeart #creativecoding #opencv #computervision #cielab "
        "#mushroom #urbannature #sidewalkmushroom #newmediaart #audiovisual #midi "
        "#pythonart #datasonification #experimentalmusic #nycnature #foraging #mycology")

FIRST = ("Full process notes, the timing chart and the MIDI are in the repo — the video "
         "generates the MIDI, and the MIDI generates the audio, so you can open the .mid, "
         "change it, and re-render the track.")

_ev = json.loads((WORK / "midi_events.json").read_text())
_spb, _bar = _ev["seconds_per_beat"], _ev["bar_seconds"]


def _bb(t):
    return (f"{int(t // _bar) + 1}.{int((t % _bar) / _spb) + 1}."
            f"{int(round(((t % _bar) % _spb) / _spb * 480)):03d}")


CUE_ROWS = [
    (i, q["frame"], f"{int(q['t'] // 60):02d}:{q['t'] % 60:06.3f}", _bb(q["t"]),
     "MAX ZOOM IN" if q["k"] == "IN" else "MAX ZOOM OUT",
     "kick 36 + low tom 41" if q["k"] == "IN" else "crash 49 + snare 38",
     f"{q['zoom']:.3f}")
    for i, q in enumerate(
        sorted(([{**e, "k": "IN"} for e in _a["zoom_in_extrema"]]
                + [{**e, "k": "OUT"} for e in _a["zoom_out_extrema"]]),
               key=lambda q: q["frame"]), 1)
]


def esc(s):
    return html.escape(s)


def copyblock(cid, label, meta, body, mono=False):
    cls = " mono" if mono else ""
    return f"""<article class="copy" id="{cid}">
  <header class="copy-h">
    <div>
      <h3>{esc(label)}</h3>
      <p class="meta">{esc(meta)}</p>
    </div>
    <button class="btn" type="button" data-copy="{cid}">Copy</button>
  </header>
  <pre class="copy-b{cls}">{esc(body)}</pre>
</article>"""


# --- hero curve ------------------------------------------------------------
ribbon = "".join(
    f'<rect x="{s["a"] * W:.1f}" y="252" width="{max(2, (s["b"] - s["a"]) * W):.1f}" '
    f'height="10" fill="{SEG_TONE[s["s"]]}"><title>{s["s"]} · '
    f'{s["t0"]:.2f}–{s["t1"]:.2f}s</title></rect>'
    for s in c["segs"])

cue_marks = []
for i, cu in enumerate(c["cues"], 1):
    x = cu["x"] * W
    up = cu["k"] == "IN"
    tri = (f'{x:.1f},14 {x - 8:.1f},0 {x + 8:.1f},0' if up
           else f'{x:.1f},0 {x - 8:.1f},14 {x + 8:.1f},14')
    cue_marks.append(
        f'<g class="cue" tabindex="0" role="button" data-cue="{i}" '
        f'aria-label="Cue {i}, {"maximum zoom in" if up else "maximum zoom out"} '
        f'at {cu["t"]:.2f} seconds">'
        f'<rect x="{x - 14:.1f}" y="0" width="28" height="264" fill="transparent"/>'
        f'<line x1="{x:.1f}" y1="16" x2="{x:.1f}" y2="244" stroke="var(--amber)" '
        f'stroke-width="1.5" opacity=".75"/>'
        f'<polygon points="{tri}" fill="var(--amber)"/>'
        f'<text x="{x:.1f}" y="-8" text-anchor="middle" class="cue-t">{cu["t"]:.2f}s</text>'
        f'</g>')

cue_table = "".join(
    f'<tr id="cue-{n}"><td class="num">{n}</td><td class="num">{f}</td>'
    f'<td class="mono">{tc}</td><td class="mono">{bb}</td>'
    f'<td><span class="pill {"in" if "IN" in k else "out"}">{k}</span></td>'
    f'<td class="mono dim">{dr}</td><td class="num mono">{z}</td></tr>'
    for n, f, tc, bb, k, dr, z in CUE_ROWS)

CAROUSEL = [
    ("The score sheet", "mushroom_score_post_4x5.png", "the whole piece in one frame"),
    ("Maximum zoom in", "plates/cue_01_IN_f0213.png", "07.107 s — the kick"),
    ("Maximum zoom out", "plates/cue_02_OUT_f0325.png", "10.844 s — the crash"),
    ("The vector field", "plates/stop_WIDE_f0060.png", "plant motion, ego-compensated"),
    ("Still tracking", "plates/stop_MID_f0110.png", "the cap at 0.1 % of frame"),
]
carousel = "".join(
    f'<li><span class="ord">{i}</span><div><h4>{esc(t)}</h4>'
    f'<p class="mono dim">{esc(f)}</p><p class="note">{esc(d)}</p></div></li>'
    for i, (t, f, d) in enumerate(CAROUSEL, 1))

HTML = f"""<title>Mushroom Score Post Kit</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Big+Shoulders+Display:wght@400;600;700&family=IBM+Plex+Mono:wght@400;600&family=Instrument+Sans:ital,wght@0,400;0,500;1,400&display=swap">
<style>
:root {{
  --ground:#0B1020; --panel:#121A31; --panel-2:#17224A; --line:#22305C;
  --navy:#1E3A8A; --navy-lit:#6E9BFF; --magenta:#FF00AA; --amber:#FFB020;
  --paper:#EEF0F5; --dim:#8B94AE; --dimmer:#5E688A;
  --wide:#2B3A6B; --mid:#3E56A8; --tight:#6E9BFF;
  --display:"Big Shoulders Display","Oswald","Arial Narrow","Helvetica Neue Condensed",
    "Liberation Sans Narrow",Impact,system-ui,sans-serif;
  --body:"Instrument Sans",system-ui,-apple-system,"Segoe UI",sans-serif;
  --mono:"IBM Plex Mono",ui-monospace,"SF Mono",Menlo,monospace;
  --maxw:1080px;
}}
* {{ box-sizing:border-box; }}
body {{
  margin:0; background:var(--ground); color:var(--paper);
  font-family:var(--body); font-size:16px; line-height:1.62;
  -webkit-font-smoothing:antialiased;
}}
.wrap {{ max-width:var(--maxw); margin:0 auto; padding:0 28px 96px; }}
.mono {{ font-family:var(--mono); font-variant-numeric:tabular-nums; }}
.dim {{ color:var(--dim); }}
.num {{ text-align:right; font-variant-numeric:tabular-nums; font-family:var(--mono); }}
a {{ color:var(--navy-lit); }}
:focus-visible {{ outline:2px solid var(--amber); outline-offset:3px; border-radius:2px; }}

/* ---- masthead ---- */
.mast {{ padding:56px 0 30px; }}
.eyebrow {{
  font-family:var(--mono); font-size:12.5px; font-weight:600; letter-spacing:.22em;
  color:var(--magenta); margin:0 0 14px;
}}
h1 {{
  font-family:var(--display); font-weight:700; font-size:clamp(58px,10vw,116px);
  line-height:.82; letter-spacing:-.005em; margin:0; text-wrap:balance;
}}
h1 .b {{ display:block; color:var(--navy-lit); }}
.lede {{ max-width:60ch; margin:22px 0 0; color:var(--dim); font-size:17.5px; }}
.lede em {{ color:var(--paper); font-style:italic; }}
.facts {{
  display:flex; flex-wrap:wrap; gap:0; margin:30px 0 0;
  border-top:1px solid var(--line); border-bottom:1px solid var(--line);
}}
.facts div {{ flex:1 1 130px; padding:13px 16px 13px 0; }}
.facts dt {{
  font-family:var(--mono); font-size:11px; letter-spacing:.16em;
  color:var(--dimmer); margin:0 0 3px;
}}
.facts dd {{ margin:0; font-family:var(--mono); font-size:19px; color:var(--paper); }}

/* ---- hero curve ---- */
.score {{ margin:44px 0 0; }}
.score-svg {{ width:100%; height:auto; overflow:visible; display:block; }}
.grid-l {{ stroke:var(--line); stroke-width:1; }}
.curve-under {{ fill:none; stroke:var(--navy); stroke-width:8; stroke-linejoin:round; }}
.curve {{ fill:none; stroke:var(--navy-lit); stroke-width:3; stroke-linejoin:round; }}
.cue {{ cursor:pointer; }}
.cue polygon, .cue line {{ transition:opacity .15s ease; }}
.cue:hover polygon, .cue:focus polygon {{ filter:brightness(1.25); }}
.cue:hover line, .cue:focus line {{ opacity:1; }}
.cue-t {{
  font-family:var(--mono); font-size:12px; fill:var(--amber);
}}
.ax {{ font-family:var(--mono); font-size:12px; fill:var(--dimmer); }}
.score-cap {{
  display:flex; flex-wrap:wrap; gap:8px 26px; margin:38px 0 0;
  font-family:var(--mono); font-size:12.5px; color:var(--dim);
}}
.key {{ display:inline-flex; align-items:center; gap:8px; }}
.sw {{ width:13px; height:13px; border-radius:2px; flex:none; }}

/* ---- sections ---- */
section {{ margin:74px 0 0; }}
h2 {{
  font-family:var(--display); font-weight:700; font-size:34px; letter-spacing:.01em;
  margin:0 0 6px; color:var(--paper);
}}
.sub {{ margin:0 0 24px; color:var(--dim); max-width:64ch; }}
h3 {{ font-family:var(--body); font-weight:500; font-size:16px; margin:0; }}
h4 {{ font-family:var(--body); font-weight:500; font-size:15.5px; margin:0 0 2px; }}

/* ---- assets ---- */
.assets {{ display:grid; grid-template-columns:repeat(auto-fit,minmax(232px,1fr)); gap:20px; align-items:start; }}
.asset {{ display:flex; flex-direction:column; gap:12px; }}
/* The cut assets are 4:5 and 9:16. A shared frame with the image contained
   inside keeps every tile the same height, so the captions share a baseline
   and each asset is still shown whole. */
.frame {{
  aspect-ratio:4/5; display:grid; place-items:center; padding:10px;
  border:1px solid var(--line); background:var(--panel);
}}
.frame img {{ max-width:100%; max-height:100%; width:auto; height:auto; display:block; }}
.asset .fn {{ font-family:var(--mono); font-size:12px; color:var(--navy-lit); word-break:break-all; }}
.asset .sp {{ font-family:var(--mono); font-size:12px; color:var(--dimmer); }}
.filelist {{
  border-top:1px solid var(--line); margin:26px 0 0; padding:0; list-style:none;
}}
.filelist li {{
  display:flex; flex-wrap:wrap; gap:4px 18px; align-items:baseline;
  padding:11px 0; border-bottom:1px solid var(--line);
}}
.filelist .fn {{ font-family:var(--mono); font-size:13px; color:var(--navy-lit); flex:1 1 260px; }}
.filelist .sp {{ font-family:var(--mono); font-size:12.5px; color:var(--dimmer); }}

/* ---- carousel order ---- */
.order {{ list-style:none; margin:0; padding:0; display:grid; gap:2px; }}
.order li {{ display:flex; gap:18px; align-items:baseline; padding:13px 0; border-bottom:1px solid var(--line); }}
.order .ord {{
  font-family:var(--mono); font-size:12px; color:var(--amber);
  min-width:22px; font-weight:600;
}}
.order .note {{ margin:1px 0 0; color:var(--dim); font-size:14.5px; }}
.order p {{ margin:0; font-size:12.5px; }}

/* ---- copy blocks ---- */
.copies {{ display:grid; gap:18px; }}
.copy {{ background:var(--panel); border:1px solid var(--line); }}
.copy-h {{
  display:flex; gap:16px; align-items:flex-start; justify-content:space-between;
  padding:15px 18px; border-bottom:1px solid var(--line);
}}
.copy-h .meta {{ margin:2px 0 0; font-family:var(--mono); font-size:11.5px; color:var(--dimmer); }}
.copy-b {{
  margin:0; padding:18px; font-family:var(--body); font-size:15px; line-height:1.66;
  white-space:pre-wrap; word-wrap:break-word; color:var(--paper);
  max-height:none;
}}
.copy-b.mono {{ font-family:var(--mono); font-size:13px; line-height:1.72; color:var(--dim); }}
.btn {{
  flex:none; font-family:var(--mono); font-size:12px; letter-spacing:.08em;
  color:var(--paper); background:var(--navy); border:1px solid var(--navy-lit);
  padding:7px 15px; cursor:pointer; transition:background .15s ease;
}}
.btn:hover {{ background:var(--navy-lit); color:var(--ground); }}
.btn[data-state="ok"] {{ background:var(--amber); border-color:var(--amber); color:var(--ground); }}
.btn[data-state="sel"] {{ background:var(--magenta); border-color:var(--magenta); color:#fff; }}

/* ---- table ---- */
.tw {{ overflow-x:auto; border:1px solid var(--line); }}
table {{ border-collapse:collapse; width:100%; min-width:620px; }}
th, td {{ padding:11px 14px; text-align:left; border-bottom:1px solid var(--line); font-size:13.5px; }}
th {{
  font-family:var(--mono); font-size:11px; letter-spacing:.15em; color:var(--dimmer);
  font-weight:600; background:var(--panel); white-space:nowrap;
}}
tbody tr {{ transition:background .2s ease; }}
tbody tr:last-child td {{ border-bottom:none; }}
tbody tr.lit {{ background:var(--panel-2); }}
.pill {{
  font-family:var(--mono); font-size:11px; letter-spacing:.08em; padding:3px 9px;
  white-space:nowrap; border:1px solid;
}}
.pill.in {{ color:var(--amber); border-color:var(--amber); }}
.pill.out {{ color:var(--navy-lit); border-color:var(--navy-lit); }}

/* ---- process notes ---- */
.notes {{ display:grid; gap:26px; max-width:70ch; }}
.note-b {{ border-left:2px solid var(--navy); padding:2px 0 2px 22px; }}
.note-b h3 {{
  font-family:var(--display); font-size:25px; font-weight:600; margin:0 0 8px;
  color:var(--paper);
}}
.note-b p {{ margin:0 0 11px; color:var(--dim); }}
.note-b p:last-child {{ margin-bottom:0; }}
.note-b strong {{ color:var(--paper); font-weight:500; }}
.note-b .r {{ font-family:var(--mono); color:var(--amber); }}
.fails {{ margin:0 0 11px; padding-left:20px; color:var(--dim); }}
.fails li {{ margin:0 0 5px; }}

footer {{
  margin:80px 0 0; padding:24px 0 0; border-top:1px solid var(--line);
  font-family:var(--mono); font-size:12px; color:var(--dimmer);
  display:flex; flex-wrap:wrap; gap:6px 24px;
}}
@media (prefers-reduced-motion:reduce) {{
  * {{ transition:none !important; animation:none !important; }}
}}
@media (max-width:620px) {{
  .facts div {{ flex-basis:44%; }}
  .copy-h {{ flex-direction:column; }}
}}
</style>

<div class="wrap">

<header class="mast">
  <p class="eyebrow">VISUAL SCORE / NO. 01 — POST KIT</p>
  <h1>Mushroom<span class="b">Score</span></h1>
  <p class="lede">Everything needed to post the piece: the two cut images, the caption
  copy, the cue sheet and the process notes. The score was made from
  <em>16.95 seconds</em> of a white mushroom at the base of a street tree in Queens —
  three photographs set the colour, and the camera's own zoom set the tempo.</p>
  <dl class="facts">
    <div><dt>DURATION</dt><dd>16.95 s</dd></div>
    <div><dt>FRAMES</dt><dd>508</dd></div>
    <div><dt>TEMPO</dt><dd>133.20</dd></div>
    <div><dt>KEY</dt><dd>D min pent</dd></div>
    <div><dt>DRUM CUES</dt><dd>5</dd></div>
  </dl>
</header>

<div class="score">
  <svg class="score-svg" viewBox="-6 -26 1012 316" role="img"
       aria-label="Zoom curve across the 16.95 second clip, showing two arches with five amber drum cues.">
    <line class="grid-l" x1="0" y1="26" x2="1000" y2="26"/>
    <line class="grid-l" x1="0" y1="132" x2="1000" y2="132"/>
    <line class="grid-l" x1="0" y1="238" x2="1000" y2="238"/>
    <text class="ax" x="1006" y="30">in</text>
    <text class="ax" x="1006" y="242">out</text>
    <path class="curve-under" d="{path}"/>
    <path class="curve" d="{path}"/>
    {ribbon}
    {"".join(cue_marks)}
    <text class="ax" x="0" y="284">0.00 s</text>
    <text class="ax" x="1000" y="284" text-anchor="end">16.95 s</text>
  </svg>
  <div class="score-cap">
    <span class="key"><i class="sw" style="background:var(--navy-lit)"></i>zoom curve — apparent cap scale</span>
    <span class="key"><i class="sw" style="background:var(--amber)"></i>drum cue — select one</span>
    <span class="key"><i class="sw" style="background:var(--tight)"></i>tight</span>
    <span class="key"><i class="sw" style="background:var(--mid)"></i>mid</span>
    <span class="key"><i class="sw" style="background:var(--wide)"></i>wide</span>
  </div>
</div>

<section>
  <h2>Cue sheet</h2>
  <p class="sub">Every drum hit in the piece is a turning point of the camera's zoom —
  nothing else is scored to a fixed position. Bar positions are from the derived
  133.20&nbsp;BPM grid.</p>
  <div class="tw">
    <table>
      <thead><tr>
        <th>#</th><th>FRAME</th><th>TIMECODE</th><th>BAR.BEAT.TICK</th>
        <th>CUE</th><th>DRUMS</th><th>ZOOM</th>
      </tr></thead>
      <tbody>{cue_table}</tbody>
    </table>
  </div>
</section>

<section>
  <h2>Cut assets</h2>
  <p class="sub">Both images are laid out from the same data the score is, so the post
  and the video read as one object.</p>
  <div class="assets">
    <figure class="asset" style="margin:0">
      <span class="frame"><img src="{imgs['post']}" alt="The 4:5 Instagram feed image: title, the three stopping-point frames, and the zoom curve."></span>
      <div><p class="fn">mushroom_score_post_4x5.png</p>
      <p class="sp">1080 × 1350 · Instagram feed</p></div>
    </figure>
    <figure class="asset" style="margin:0">
      <span class="frame"><img src="{imgs['cover']}" alt="The 9:16 story and TikTok cover: a full-bleed close-up of the cap above the title and zoom curve."></span>
      <div><p class="fn">mushroom_score_cover_9x16.png</p>
      <p class="sp">1080 × 1920 · story / TikTok cover</p></div>
    </figure>
    <figure class="asset" style="margin:0">
      <span class="frame"><img src="{imgs['cue_in']}" alt="Score frame at maximum zoom in: the cap fills the frame inside a navy detector bracket."></span>
      <div><p class="fn">plates/cue_01_IN_f0213.png</p>
      <p class="sp">720 × 1280 · carousel slide</p></div>
    </figure>
    <figure class="asset" style="margin:0">
      <span class="frame"><img src="{imgs['wide']}" alt="Score frame in a wide framing: magenta arrows across the weeds, small navy box on the distant cap."></span>
      <div><p class="fn">plates/stop_WIDE_f0060.png</p>
      <p class="sp">720 × 1280 · carousel slide</p></div>
    </figure>
  </div>
  <ul class="filelist">
    <li><span class="fn">mushroom_visual_score.mp4</span>
        <span class="sp">720 × 1280 · 16.95 s · H.264 + AAC 192k · 21 MB</span></li>
    <li><span class="fn">mushroom_track.m4a</span>
        <span class="sp">18.95 s incl. ~2 s reverb tail · AAC 256k</span></li>
    <li><span class="fn">mushroom_score.mid</span>
        <span class="sp">5 tracks · 133.20 BPM · PPQ 480</span></li>
    <li><span class="fn">score_seq/ · 40 frames</span>
        <span class="sp">540 × 960 PNG · the score as a filmstrip</span></li>
  </ul>
  <p class="sub" style="margin-top:22px">The clip runs 16.95&nbsp;s, just under the length
  both platforms reward, and it loops cleanly — it opens and closes wide, with a crash on
  each. Set it to repeat rather than padding it, and upload the 720 × 1280 master directly
  so neither platform letterboxes it.</p>
</section>

<section>
  <h2>Carousel order</h2>
  <p class="sub">Sequenced so the first two slides carry the whole idea, in case nobody
  swipes past them.</p>
  <ol class="order">{carousel}</ol>
</section>

<section>
  <h2>Caption copy</h2>
  <p class="sub">Written to be pasted as-is.</p>
  <div class="copies">
    {copyblock("cap-ig", "Instagram — long", "feed post + carousel", CAP_LONG)}
    {copyblock("cap-tt", "TikTok — short", "reads in one screen", CAP_SHORT)}
    {copyblock("cap-alt", "Alt text", "both platforms · accessibility", ALT)}
    {copyblock("cap-tag", "Hashtags", "18 tags · trim to taste", TAGS, mono=True)}
    {copyblock("cap-fc", "First comment", "post immediately after", FIRST)}
  </div>
</section>

<section>
  <h2>Process notes</h2>
  <p class="sub">Three things shaped the implementation. Two of them were failures worth
  keeping in the record.</p>
  <div class="notes">

    <div class="note-b">
      <h3>The photographs are the colour space</h3>
      <p>The three plates aren't a mood board. Each is reduced to two anchors — the median
      Lab of the cap, the median Lab of the weeds — and the per-channel median across all
      three is what every video frame is measured against: mushroom
      <span class="r">L*95.02 a*−1.22 b*+4.22</span>, plant
      <span class="r">L*43.57 a*−15.63 b*+24.13</span>.</p>
      <p>Distance is full <strong>CIEDE2000</strong>, hue-rotation term included, not the
      cheap Euclidean CIE76. If the premise is that perceived colour drives the piece, the
      metric has to be the perceptual one.</p>
    </div>

    <div class="note-b">
      <h3>The hardest problem was a sidewalk slab</h3>
      <p>In the wide framings the cap is about <strong>0.05 % of the picture</strong>. A
      sunlit sidewalk slab is brighter, bigger, near-neutral and convex, and it beats the
      mushroom on every static cue. Three attempts failed:</p>
      <ol class="fails">
        <li>Largest bright, low-chroma blob — picked the sidewalk.</li>
        <li>Cap-shaped blob, roundness × box-fill — still the sidewalk; a concrete slab is
        also a filled convex quadrilateral.</li>
        <li>Bright-against-a-dark-surround — nearly worked, then failed subtly: the
        comparison ring was sized proportionally to the blob, so the huge slab got a 68 px
        ring that reached out into dark road and scored <em>higher</em> contrast than the
        mushroom.</li>
      </ol>
      <p>What works is temporal. Frame-local scoring is thrown out; the track is
      <strong>seeded</strong> where the cap is unambiguous — deep in a tight framing, where
      it fills half the picture — then propagated outward in both directions, each step
      preferring the candidate that continues the current position <em>and</em> scale.
      Jumping cap → sidewalk means a large positional leap and a hundred-fold area jump,
      and continuity rejects it. The cap then holds on all 508 frames.</p>
      <p>The check that this is right: apparent cap scale and the radial divergence of the
      optical-flow field are two independent estimates of the same zoom, and after the fix
      they correlate at <span class="r">r = +0.855</span> — before it, +0.59.</p>
    </div>

    <div class="note-b">
      <h3>The camera set the tempo</h3>
      <p>The clip pushes in to maximum zoom twice, 7.207 s apart. Treating that as one
      four-bar phrase gives <strong>133.20 BPM</strong> — measured, not chosen. It falls
      out neatly: the two zoom-in cues land at <span class="r">4.4.373</span> and
      <span class="r">8.4.373</span>, exactly four bars apart.</p>
      <p>Finding both peaks took a second fix. The first peak-finder measured prominence
      over a fixed ±27-frame window, and the camera <em>holds</em> at maximum zoom for over
      a second — so the first arch scored a prominence of 0.04 and was discarded. True
      topographic prominence, descending from each peak until the signal rises above it
      again, recovers both.</p>
    </div>

    <div class="note-b">
      <h3>The groove is tiered by the zoom</h3>
      <p>The first cut had only the five cue hits and a sparse hat, which left the
      track flat between arches. The kit now runs a backbeat on the derived grid with
      its density <strong>tiered by the zoom curve</strong> — wide framings get a spare
      two-and-four, the pushes in unlock sixteenth kicks, ghost snares and an open hat
      — so the beat builds and releases with the camera rather than running flat
      underneath it.</p>
      <p>Punch is mostly mix, not notes: every kick ducks the pad, lead and bass
      through a short sidechain dip, the kit gets its own bus compressor, and the
      plate is fed from the tuned voices only so reverb never smears the transients.
      That took the track from <span class="r">−16.2</span> to
      <span class="r">−13.8 dBFS</span> RMS while keeping a
      <span class="r">12.8 dB</span> crest factor. The hats now ride the
      ego-compensated plant motion, so the weeds thicken the kit and the camera
      doesn't.</p>
    </div>

    <div class="note-b">
      <h3>The vector field shows plants, not camera</h3>
      <p>Drawn from raw optical flow the magenta field is meaningless: during a whip-zoom
      it's a full-frame starburst of camera motion that buries the picture. Subtracting each
      frame's median flow vector — a robust estimate of global ego-motion — leaves the
      plants moving relative to the shot, which is what the field claims to show.</p>
      <p>Smaller lesson in the same pass: confidence was first encoded by scaling the
      magenta toward black. That isn't transparency, it's just dark purple, and it vanished
      into the bark. Magenta now stays magenta and confidence rides on line weight.</p>
    </div>

  </div>
</section>

<footer>
  <span>IMG_5823 · iPhone 16 Pro · 2026-09-04</span>
  <span>40.7184 N 73.9496 W</span>
  <span>CIELAB ΔE₀₀ → optical flow → MIDI → synthesis</span>
</footer>

</div>

<script>
(function () {{
  document.querySelectorAll(".btn[data-copy]").forEach(function (btn) {{
    btn.addEventListener("click", function () {{
      var pre = document.getElementById(btn.dataset.copy).querySelector(".copy-b");
      var text = pre.textContent;
      var done = function (state, label) {{
        btn.dataset.state = state;
        btn.textContent = label;
        setTimeout(function () {{ btn.removeAttribute("data-state"); btn.textContent = "Copy"; }}, 2600);
      }};
      var fallback = function () {{
        // Clipboard access can be refused in an embedded frame. Select the text
        // instead so the keyboard shortcut still works, and say so.
        try {{
          var r = document.createRange();
          r.selectNodeContents(pre);
          var s = window.getSelection();
          s.removeAllRanges();
          s.addRange(r);
          done("sel", "Selected — press \\u2318C");
        }} catch (e) {{
          done("sel", "Select manually");
        }}
      }};
      if (navigator.clipboard && navigator.clipboard.writeText) {{
        navigator.clipboard.writeText(text).then(function () {{
          done("ok", "Copied");
        }}, fallback);
      }} else {{
        fallback();
      }}
    }});
  }});

  function lightCue(n) {{
    var row = document.getElementById("cue-" + n);
    if (!row) return;
    document.querySelectorAll("tbody tr.lit").forEach(function (r) {{ r.classList.remove("lit"); }});
    row.classList.add("lit");
    row.scrollIntoView({{ block: "center", behavior: "smooth" }});
  }}
  document.querySelectorAll(".cue").forEach(function (g) {{
    g.addEventListener("click", function () {{ lightCue(g.dataset.cue); }});
    g.addEventListener("keydown", function (e) {{
      if (e.key === "Enter" || e.key === " ") {{ e.preventDefault(); lightCue(g.dataset.cue); }}
    }});
  }});
}})();
</script>
"""

out = OUT / "post_kit.html"
out.write_text(HTML)
print("wrote", out, f"{len(HTML) / 1024:.0f} KB")
