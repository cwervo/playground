#!/usr/bin/env python3
"""Build text-embedded (searchable, selectable) PDFs for each Figma screen.

Each screen becomes a one-page PDF whose page size equals the frame size in
Figma (1 Figma px = 1 PDF pt). The page shows the pixel render of the frame,
and every visible text layer from Figma is written on top as *invisible* PDF
text (render mode 3) at the layer's exact bounding box, the same technique an
OCR tool uses to make a scanned page searchable. The result looks exactly like
the Figma render but the text is selectable, searchable and copyable.

Inputs
  screens.json     ordered list of screens (id + name)
  data/<id>.json   text layers per screen, exported from Figma (see README)
  renders/         one PNG/JPG per screen, named by node id ("47-572.png")
                   or by frame name ("Main screen - Borrowing.png"),
                   optionally with an @2x / @3x suffix

Outputs
  pdfs/NN - <name>.pdf   one PDF per screen
  pdfs/All screens.pdf   every screen in one PDF, with bookmarks

Usage
  python3 build_pdfs.py                # build everything (fails if a render is missing)
  python3 build_pdfs.py --placeholder  # use a blank page where a render is missing (for testing)
  python3 build_pdfs.py --only 47:572  # build a single screen
"""
import argparse
import json
import re
import sys
from pathlib import Path

import pymupdf

HERE = Path(__file__).resolve().parent
DATA = HERE / "data"
RENDERS = HERE / "renders"
OUT = HERE / "pdfs"

FONT_CANDIDATES = [
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/TTF/DejaVuSans.ttf",
    "/Library/Fonts/Arial Unicode.ttf",
    "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
    "C:/Windows/Fonts/arial.ttf",
]
ALIGN = {"LEFT": pymupdf.TEXT_ALIGN_LEFT, "CENTER": pymupdf.TEXT_ALIGN_CENTER,
         "RIGHT": pymupdf.TEXT_ALIGN_RIGHT, "JUSTIFIED": pymupdf.TEXT_ALIGN_JUSTIFY}
INVISIBLE = 3  # PDF text render mode 3: neither fill nor stroke, but still selectable


def sanitize_id(node_id: str) -> str:
    return node_id.replace(":", "-")


def safe_filename(name: str) -> str:
    return re.sub(r'[\\/:*?"<>|]+', "-", name).strip()


def pick_font():
    for path in FONT_CANDIDATES:
        if Path(path).exists():
            return path
    return None


def find_render(screen):
    stems = [sanitize_id(screen["id"]), screen["name"], safe_filename(screen["name"])]
    suffixes = ["", "@1x", "@2x", "@3x", "@4x"]
    exts = [".png", ".jpg", ".jpeg", ".webp"]
    for stem in stems:
        for suf in suffixes:
            for ext in exts:
                p = RENDERS / f"{stem}{suf}{ext}"
                if p.exists():
                    return p
    return None


def load_texts(screen):
    p = DATA / f"{sanitize_id(screen['id'])}.json"
    if not p.exists():
        return None
    return json.loads(p.read_text(encoding="utf-8"))


def estimate_font_size(font, text, rect):
    """For layers whose font size is unknown (data derived from metadata):
    the largest size at which the wrapped text still fits the box."""
    lines = text.split("\n")
    for fs in range(72, 3, -1):
        n_lines = sum(max(1, -(-font.text_length(line, fontsize=fs) // max(rect.width - 0.5, 1))) for line in lines)
        if n_lines * fs * 1.2 <= rect.height + 0.5:
            return float(fs)
    return 4.0


def add_text_layer(page, texts, font, fontfile):
    """Write each Figma text layer as invisible text inside its bounding box."""
    written = 0
    for t in texts:
        text = t["c"].replace("\u2028", "\n").replace("\r", "\n")
        if not text.strip():
            continue
        rect = pymupdf.Rect(t["x"], t["y"], t["x"] + t["w"], t["y"] + t["h"]) & page.rect
        if rect.is_empty or rect.width < 1 or rect.height < 1:
            continue
        fs = float(t["fs"]) if t.get("fs") else estimate_font_size(font, text, rect)
        align = ALIGN.get(t.get("align"), pymupdf.TEXT_ALIGN_LEFT)
        lines = text.split("\n")
        # Line height ratio: Figma gives px or %, or AUTO (about 1.2 for most fonts).
        lh = t.get("lh")
        if isinstance(lh, str) and lh.endswith("%"):
            ratio = float(lh[:-1]) / 100
        elif lh:
            ratio = float(lh) / fs if fs else 1.2
        else:
            ratio = 1.2
        ratio = min(max(ratio, 1.0), 3.0)
        # Fit the font size to the box: the widest line must fit the box width.
        # The substitute font (DejaVu) is wider than most UI fonts, so this
        # usually shrinks the text a bit; it is invisible anyway, only its
        # position matters for selection and search.
        widest = max((font.text_length(line, fontsize=1) for line in lines), default=0)
        if widest > 0:
            fs = min(fs, (rect.width - 0.5) / widest)
        fs = max(fs, 1.0)
        # Estimate how many lines the block occupies and honour Figma's vertical
        # alignment, so text centred in a tall box lands where the glyphs are.
        n_lines = sum(max(1, -(-font.text_length(line, fontsize=fs) // max(rect.width - 0.5, 1))) for line in lines)
        block_h = n_lines * fs * ratio
        top = rect.y0
        valign = t.get("valign")
        if block_h < rect.height:
            if valign == "CENTER":
                top = rect.y0 + (rect.height - block_h) / 2
            elif valign == "BOTTOM":
                top = rect.y1 - block_h
        box = pymupdf.Rect(rect.x0 - 0.5, top - 0.5, rect.x1 + 1.0, max(rect.y1, top + block_h) + 1.0)
        rc = -1
        size = fs
        while size >= 1.0:
            rc = page.insert_textbox(box, text, fontsize=size, fontname="figtext", fontfile=fontfile,
                                     align=align, render_mode=INVISIBLE, lineheight=ratio)
            if rc >= 0:
                break
            size *= 0.9
        if rc < 0:
            # Last resort: a single invisible line at the box baseline.
            page.insert_text(pymupdf.Point(rect.x0, rect.y1 - 1), text.replace("\n", " "),
                             fontsize=max(size, 1.0), fontname="figtext", fontfile=fontfile,
                             render_mode=INVISIBLE)
        written += 1
    return written


def build_screen(doc, screen, data, render, fontfile, placeholder):
    w, h = float(data["w"]), float(data["h"])
    page = doc.new_page(width=w, height=h)
    if render is not None:
        page.insert_image(page.rect, filename=str(render))
    elif placeholder:
        page.draw_rect(page.rect, color=None, fill=(0.96, 0.96, 0.96))
        page.insert_text((16, 40), f"[render missing] {screen['name']}", fontsize=11, color=(0.5, 0.5, 0.5))
    font = pymupdf.Font(fontfile=fontfile) if fontfile else pymupdf.Font("helv")
    return add_text_layer(page, data["texts"], font, fontfile)


def verify(pdf_path, data):
    """Check that every text layer's words can be found in the PDF's text."""
    doc = pymupdf.open(pdf_path)
    extracted = " ".join(page.get_text() for page in doc)
    doc.close()
    norm = lambda s: re.sub(r"\s+", " ", s).strip()
    ext_norm = norm(extracted)
    missing = []
    for t in data["texts"]:
        for word in norm(t["c"]).split(" "):
            if word and word not in ext_norm:
                missing.append(word)
                break
    return missing


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--placeholder", action="store_true", help="build with a blank page when a render is missing")
    ap.add_argument("--only", help="node id of a single screen to build, e.g. 47:572")
    ap.add_argument("--out", default=str(OUT), help="output directory")
    args = ap.parse_args()

    manifest = json.loads((HERE / "screens.json").read_text(encoding="utf-8"))
    screens = list(enumerate(manifest["screens"], 1))
    if args.only:
        screens = [(n, s) for n, s in screens if s["id"] == args.only]
    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    fontfile = pick_font()
    if not fontfile:
        print("warning: no Unicode TTF found, falling back to Helvetica (some symbols may be dropped)")

    missing_renders, missing_data = [], []
    combined = pymupdf.open()
    toc = []
    report = []
    for n, screen in screens:
        data = load_texts(screen)
        if data is None:
            missing_data.append(screen)
            continue
        render = find_render(screen)
        if render is None:
            missing_renders.append(screen)
            if not args.placeholder:
                continue
        doc = pymupdf.open()
        count = build_screen(doc, screen, data, render, fontfile, args.placeholder)
        title = screen["name"]
        doc.set_metadata({"title": title, "subject": f"Figma screen {screen['id']} from {manifest['page']}",
                          "keywords": "figma, screen, collectory", "creator": "build_pdfs.py"})
        pdf_path = out_dir / f"{n:02d} - {safe_filename(title)}.pdf"
        doc.save(str(pdf_path), garbage=3, deflate=True)
        doc.close()
        missing_words = verify(pdf_path, data)
        report.append((pdf_path.name, count, len(data["texts"]), missing_words, render is not None))
        combined.insert_pdf(pymupdf.open(str(pdf_path)))
        toc.append([1, title, len(combined)])

    if len(combined):
        combined.set_toc(toc)
        combined.set_metadata({"title": "All screens", "subject": manifest["page"], "creator": "build_pdfs.py"})
        combined.save(str(out_dir / "All screens.pdf"), garbage=3, deflate=True)
    combined.close()

    for name, count, total, missing, has_render in report:
        flag = "" if has_render else "  [placeholder page]"
        note = "" if not missing else f"  MISSING WORDS: {missing[:5]}"
        print(f"{name}: {count}/{total} text layers embedded{flag}{note}")
    print(f"\n{len(report)} PDF(s) written to {out_dir}")
    if missing_data:
        print(f"{len(missing_data)} screen(s) have no data/<id>.json: " + ", ".join(s["id"] for s in missing_data))
    if missing_renders:
        print(f"{len(missing_renders)} screen(s) have no render in renders/: " + ", ".join(s["name"] for s in missing_renders))
        if not args.placeholder:
            sys.exit(1)


if __name__ == "__main__":
    main()
