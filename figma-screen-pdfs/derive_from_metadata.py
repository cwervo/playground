#!/usr/bin/env python3
"""Derive data/<id>.json for screens from the page metadata XML.

Fallback for when the Figma MCP quota does not allow a per-screen `use_figma`
read. The metadata (from the Figma MCP `get_metadata` tool on page 0:1) lists
every layer with its name and box. For an auto-named text layer the name is its
content (Figma folds line breaks to spaces), so we use the name as the text.

Coordinates in the metadata are listed either relative to the container's own
origin (auto-layout frames, components) or in the container's parent's space
(groups and plain frames). Which one applies is decided per container by
checking which reading keeps all of its children inside its box; this matched
the positions read directly from Figma for every non-rotated text layer on the
14 screens used to validate it (rotated layers are off by their rotation).

Limitations of derived data (marked with "source": "metadata" in the JSON):
  * text inside component instances is not listed in the metadata, so it is
    not embedded; * line breaks and double spaces are lost; * a text layer that
    was manually renamed embeds its layer name instead of its content;
  * font size and alignment are unknown and estimated by the builder.

Usage: python3 derive_from_metadata.py [--force] [ids...]
  Without ids, derives every screen in screens.json that has no data file yet.
"""
import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

HERE = Path(__file__).resolve().parent
DATA = HERE / "data"
META = DATA / "page-metadata.xml"


def box(e):
    return (float(e.get("x")), float(e.get("y")), float(e.get("width")), float(e.get("height")))


def inside(child, cont, tol=1.5):
    x, y, w, h = child
    cx, cy, cw, ch = cont
    return x >= cx - tol and y >= cy - tol and x + w <= cx + cw + tol and y + h <= cy + ch + tol


def children_in_parent_space(container):
    """True when this container's children are listed in the container's
    parent's coordinate space (groups, and frames whose children are listed
    with page-relative offsets); False when they are relative to the
    container's own origin. Decided by which interpretation keeps every child
    inside the container's box, preferring the parent-space reading on a tie."""
    kids = [k for k in container if k.get("width") is not None]
    x, y, w, h = box(container)
    fits_parent = all(inside(box(k), (x, y, w, h)) for k in kids)
    fits_own = all(inside(box(k), (0, 0, w, h)) for k in kids)
    if fits_parent or not fits_own:
        return True
    return False


def collect(top):
    items = []

    def walk(container, ox, oy):
        for c in container:
            if c.get("hidden") == "true":
                continue
            x, y, w, h = box(c)
            if c.tag == "text":
                text = (c.get("name") or "").replace(" ", " ").strip()
                if text:
                    items.append({"id": c.get("id"), "c": text, "x": round(ox + x, 2), "y": round(oy + y, 2),
                                  "w": round(w, 2), "h": round(h, 2), "fs": None, "font": None, "lh": None,
                                  "align": None, "valign": None, "o": 1, "rot": 0})
            elif len(c):
                if children_in_parent_space(c):
                    walk(c, ox, oy)          # children already in this container's parent space
                else:
                    walk(c, ox + x, oy + y)  # children relative to this container's origin
    walk(top, 0.0, 0.0)
    return items


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    force = "--force" in sys.argv
    manifest = json.loads((HERE / "screens.json").read_text(encoding="utf-8"))
    root = ET.parse(META).getroot()
    tops = {t.get("id"): t for t in root}
    for s in manifest["screens"]:
        if args and s["id"] not in args:
            continue
        out = DATA / (s["id"].replace(":", "-") + ".json")
        if out.exists() and not force:
            continue
        top = tops[s["id"]]
        items = collect(top)
        data = {"id": s["id"], "name": top.get("name"), "w": float(top.get("width")), "h": float(top.get("height")),
                "count": len(items), "source": "metadata", "texts": items}
        out.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
        print(f"{out.name}: {len(items)} text layers (derived from metadata)")


if __name__ == "__main__":
    main()
