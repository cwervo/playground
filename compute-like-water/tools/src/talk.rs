use crate::qr;
use crate::sources::{escape, Source};
use crate::works_cited;
use std::collections::{BTreeMap, BTreeSet};

pub struct Talk {
    pub title: String,
    pub subtitle: String,
    pub speaker: String,
    pub duration: String,
    pub slides: Vec<Slide>,
}

#[derive(Default)]
pub struct Slide {
    pub time: String,
    pub heading: String,
    pub image: Option<String>,
    pub caption: Option<String>,
    pub quote: Option<String>,
    pub attribution: Option<String>,
    pub paragraphs: Vec<String>,
}

impl Talk {
    pub fn word_count(&self) -> usize {
        self.slides
            .iter()
            .flat_map(|s| s.paragraphs.iter())
            .map(|p| p.split_whitespace().count())
            .sum()
    }
}

/// Parse the talk script: `@key value` header lines, then `=== slide` blocks,
/// each with `@field` lines followed by blank-line-separated paragraphs.
pub fn parse(script: &str) -> Result<Talk, String> {
    let mut talk = Talk {
        title: String::new(),
        subtitle: String::new(),
        speaker: String::new(),
        duration: String::new(),
        slides: Vec::new(),
    };
    let mut slide: Option<Slide> = None;
    let mut para = String::new();

    let flush_para = |slide: &mut Option<Slide>, para: &mut String| {
        if !para.trim().is_empty() {
            slide
                .as_mut()
                .expect("paragraph text outside any slide")
                .paragraphs
                .push(para.trim().to_string());
        }
        para.clear();
    };

    for line in script.lines() {
        let trimmed = line.trim_end();
        if trimmed.trim() == "=== slide" {
            flush_para(&mut slide, &mut para);
            if let Some(s) = slide.take() {
                talk.slides.push(s);
            }
            slide = Some(Slide::default());
        } else if let Some(rest) = trimmed.strip_prefix('@') {
            flush_para(&mut slide, &mut para);
            let (key, value) = rest.split_once(' ').unwrap_or((rest, ""));
            let value = value.trim().to_string();
            match (&mut slide, key) {
                (None, "title") => talk.title = value,
                (None, "subtitle") => talk.subtitle = value,
                (None, "speaker") => talk.speaker = value,
                (None, "duration") => talk.duration = value,
                (Some(s), "time") => s.time = value,
                (Some(s), "heading") => s.heading = value,
                (Some(s), "image") => s.image = Some(value),
                (Some(s), "caption") => s.caption = Some(value),
                (Some(s), "quote") => s.quote = Some(value),
                (Some(s), "attribution") => s.attribution = Some(value),
                (scope, k) => {
                    return Err(format!(
                        "unknown @{k} in {} scope",
                        if scope.is_some() { "slide" } else { "header" }
                    ))
                }
            }
        } else if trimmed.trim().is_empty() {
            flush_para(&mut slide, &mut para);
        } else {
            if !para.is_empty() {
                para.push(' ');
            }
            para.push_str(trimmed.trim());
        }
    }
    flush_para(&mut slide, &mut para);
    if let Some(s) = slide.take() {
        talk.slides.push(s);
    }
    if talk.slides.is_empty() {
        return Err("no slides found".into());
    }
    Ok(talk)
}

/// Escape, then *emphasis* / **strong**, then expand [ref:id] citation chips.
fn render_inline(
    text: &str,
    sources: &BTreeMap<String, Source>,
    qr_cache: &mut BTreeMap<String, String>,
    used: &mut BTreeSet<String>,
) -> Result<String, String> {
    let mut s = escape(text);
    for (marker, open, close) in [("**", "<strong>", "</strong>"), ("*", "<em>", "</em>")] {
        let mut out = String::new();
        let mut inside = false;
        let mut rest = s.as_str();
        while let Some(i) = rest.find(marker) {
            out.push_str(&rest[..i]);
            out.push_str(if inside { close } else { open });
            inside = !inside;
            rest = &rest[i + marker.len()..];
        }
        out.push_str(rest);
        if inside {
            return Err(format!("unbalanced {marker} in: {text}"));
        }
        s = out;
    }
    // [ref:id] -> QR chip linking to the works-cited entry
    let mut out = String::new();
    let mut rest = s.as_str();
    while let Some(i) = rest.find("[ref:") {
        out.push_str(&rest[..i]);
        let after = &rest[i + 5..];
        let end = after
            .find(']')
            .ok_or_else(|| format!("unterminated [ref: near: {}", &rest[i..]))?;
        let id = &after[..end];
        let src = sources
            .get(id)
            .ok_or_else(|| format!("[ref:{id}] has no matching sources/{id}.json"))?;
        used.insert(id.to_string());
        let uri = match qr_cache.get(&src.url) {
            Some(u) => u.clone(),
            None => {
                let u = qr::data_uri(&src.url)?;
                qr_cache.insert(src.url.clone(), u.clone());
                u
            }
        };
        out.push_str(&format!(
            "<a class=\"ref\" href=\"#src-{id}\" title=\"{title}\">\
             <img class=\"refqr\" src=\"{uri}\" alt=\"QR code to source: {title}\" \
             width=\"22\" height=\"22\"><span class=\"reflabel\">{id}</span></a>",
            id = escape(id),
            title = escape(&src.title),
            uri = uri,
        ));
        rest = &after[end + 1..];
    }
    out.push_str(rest);
    Ok(out)
}

fn slide_card(slide: &Slide, idx: usize, total: usize) -> String {
    let visual = if let Some(img) = &slide.image {
        let cap = slide
            .caption
            .as_ref()
            .map(|c| format!("<figcaption>{}</figcaption>", escape(c)))
            .unwrap_or_default();
        format!(
            "<figure><img src=\"{img}\" alt=\"{alt}\" loading=\"lazy\">{cap}</figure>",
            img = escape(img),
            alt = escape(slide.caption.as_deref().unwrap_or(&slide.heading)),
        )
    } else if let Some(q) = &slide.quote {
        let attr = slide
            .attribution
            .as_ref()
            .map(|a| format!("<cite>&mdash; {}</cite>", escape(a)))
            .unwrap_or_default();
        format!("<blockquote class=\"bigquote\">{}{attr}</blockquote>", escape(q))
    } else {
        String::new()
    };
    format!(
        r#"<div class="slide">
  <div class="slidehead"><span class="time">{time}</span><span class="count">{n:02} / {total:02}</span></div>
  <h2>{heading}</h2>
  {visual}
</div>"#,
        time = escape(&slide.time),
        n = idx + 1,
        total = total,
        heading = escape(&slide.heading),
    )
}

pub fn render_index(talk: &Talk, sources: &BTreeMap<String, Source>) -> Result<String, String> {
    let mut qr_cache = BTreeMap::new();
    let mut used = BTreeSet::new();
    let total = talk.slides.len();

    let mut beats = String::new();
    for (i, slide) in talk.slides.iter().enumerate() {
        let paras: Result<Vec<String>, String> = slide
            .paragraphs
            .iter()
            .map(|p| Ok(format!("<p>{}</p>", render_inline(p, sources, &mut qr_cache, &mut used)?)))
            .collect();
        beats.push_str(&format!(
            r#"<section class="beat" id="slide-{n}">
<div class="slidecol">{card}</div>
<div class="script">{paras}</div>
</section>
"#,
            n = i + 1,
            card = slide_card(slide, i, total),
            paras = paras?.join("\n"),
        ));
    }

    for id in sources.keys() {
        if !used.contains(id) {
            eprintln!("note: source '{id}' is never referenced in talk.md");
        }
    }

    Ok(format!(
        r##"<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title} — a 30-minute talk</title>
<style>
:root {{ --bg:#16130e; --paper:#f5efe2; --ink:#241f17; --accent:#b3541e; --accent2:#1e6091; --faint:#8a7f6a; --rule:#d8cdb8; }}
* {{ box-sizing:border-box; }}
body {{ margin:0; background:var(--bg); color:var(--ink); font-family:Georgia,'Iowan Old Style',serif; line-height:1.62; }}
a {{ color:var(--accent2); }}
header.mast {{ max-width:76rem; margin:0 auto; padding:3.5rem 2rem 2.5rem; color:#f0e8d6; }}
header.mast .kicker {{ font-family:'Helvetica Neue',Arial,sans-serif; text-transform:uppercase; letter-spacing:.25em; font-size:.7rem; color:#d99a5b; }}
header.mast h1 {{ font-weight:normal; font-size:3rem; margin:.4rem 0 .6rem; }}
header.mast .dek {{ font-style:italic; color:#cfc4ab; max-width:44rem; font-size:1.1rem; }}
header.mast .meta {{ font-family:'Helvetica Neue',Arial,sans-serif; font-size:.75rem; color:#8a7f6a; margin-top:1rem; }}
main {{ max-width:76rem; margin:0 auto; padding:0 2rem 4rem; }}
section.beat {{ display:grid; grid-template-columns: minmax(0,30rem) minmax(0,1fr); gap:2.2rem; padding:2.4rem 0; border-top:1px solid #2e2921; }}
.slidecol {{ min-width:0; }}
.slide {{ position:sticky; top:1.2rem; background:var(--paper); border:1px solid var(--rule); padding:1.1rem 1.2rem 1.3rem; box-shadow:0 8px 30px rgba(0,0,0,.45); }}
.slidehead {{ display:flex; justify-content:space-between; font-family:'Helvetica Neue',Arial,sans-serif; font-size:.7rem; letter-spacing:.15em; color:var(--faint); }}
.slidehead .time {{ color:var(--accent); }}
.slide h2 {{ font-weight:normal; font-size:1.45rem; margin:.5rem 0 .7rem; color:var(--accent); line-height:1.2; }}
.slide figure {{ margin:0; }}
.slide img {{ width:100%; display:block; border:1px solid var(--rule); }}
.slide figcaption {{ font-family:'Helvetica Neue',Arial,sans-serif; font-size:.72rem; color:var(--faint); margin-top:.45rem; line-height:1.45; }}
.bigquote {{ margin:.4rem 0 0; font-size:1.15rem; font-style:italic; color:#4a4234; border-left:3px solid var(--accent); padding-left:.9rem; }}
.bigquote cite {{ display:block; margin-top:.6rem; font-size:.8rem; font-style:normal; color:var(--faint); }}
.script {{ min-width:0; color:#e8dfcc; font-size:1.04rem; }}
.script p {{ margin:0 0 1.15rem; }}
.script strong {{ color:#f7ecd4; }}
a.ref {{ display:inline-flex; align-items:center; gap:.28rem; vertical-align:-5px; margin:0 .12rem;
  background:#f5efe2; border:1px solid var(--rule); border-radius:3px; padding:1px 5px 1px 2px;
  text-decoration:none; }}
a.ref:hover {{ background:#fff; }}
img.refqr {{ display:block; background:#fff; width:22px; height:22px;
  transition:transform .15s ease; transform-origin:bottom left; position:relative; z-index:5; }}
a.ref:hover img.refqr {{ transform:scale(5.5); box-shadow:0 4px 24px rgba(0,0,0,.5); }}
.reflabel {{ font-family:'Helvetica Neue',Arial,sans-serif; font-size:.62rem; letter-spacing:.05em; color:#6a5f4c; }}
section#works-cited {{ background:var(--paper); border:1px solid var(--rule); margin:3rem 0 0; padding:2rem 2.2rem; }}
section#works-cited h2 {{ font-weight:normal; color:var(--accent); margin:0 0 .3rem; }}
section#works-cited .sub {{ color:var(--faint); font-style:italic; margin:0 0 1.4rem; font-size:.92rem; }}
footer.colophon {{ max-width:76rem; margin:0 auto; padding:2rem; color:#6a5f4c; font-family:'Helvetica Neue',Arial,sans-serif; font-size:.72rem; }}
@media (max-width: 900px) {{
  section.beat {{ grid-template-columns:1fr; }}
  .slide {{ position:static; }}
  header.mast h1 {{ font-size:2.1rem; }}
}}
{cite_css}
</style>
</head>
<body>
<header class="mast">
  <div class="kicker">Talk transcript &middot; canonical source of truth</div>
  <h1>{title}</h1>
  <p class="dek">{subtitle}</p>
  <p class="meta">{speaker} &middot; running time {duration} &middot; citation chips carry a scannable QR
  code to each source and link to the <a href="#works-cited" style="color:#d99a5b">works cited</a> below
  (also standalone: <a href="Works_Cited.html" style="color:#d99a5b">Works_Cited.html</a>)</p>
</header>
<main>
{beats}
<section id="works-cited">
<h2>Works Cited</h2>
<p class="sub">Mirrored from <a href="Works_Cited.html">Works_Cited.html</a>; both are generated from the
<code>sources/</code> folder of JSON records by <code>talkgen</code> (Rust). Scan any QR to open a source.</p>
{cited}
</section>
</main>
<footer class="colophon">
<p>Built with <code>talkgen</code> — a Rust tool in <code>tools/</code> that parses <code>talk.md</code>,
loads <code>sources/*.json</code>, renders QR codes as base64 SVG data URIs (qrcode + base64 crates), and
emits this page and Works_Cited.html. Images hot-linked from Wikimedia Commons under their respective
licenses. If an image fails to load its figure is hidden gracefully.</p>
</footer>
<script>
document.querySelectorAll('.slide figure img').forEach(function (img) {{
  img.addEventListener('error', function () {{
    var f = img.closest('figure'); if (f) f.style.display = 'none';
  }});
}});
</script>
</body>
</html>
"##,
        title = escape(&talk.title),
        subtitle = escape(&talk.subtitle),
        speaker = escape(&talk.speaker),
        duration = escape(&talk.duration),
        beats = beats,
        cited = works_cited::list_fragment(sources),
        cite_css = works_cited::CITE_CSS,
    ))
}
