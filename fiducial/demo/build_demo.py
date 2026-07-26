#!/usr/bin/env python3
"""Assemble the self-contained Fiducial Optical Bench artifact by injecting the
base64 test-image thumbnails into template.html -> fiducial-playground.html."""
import json, pathlib

here = pathlib.Path(__file__).parent
thumbs = json.loads((here.parent / "tools" / "thumbs.json").read_text())
tpl = (here / "template.html").read_text()
out = tpl.replace("/*__THUMBS__*/{}", json.dumps(thumbs))
(here / "fiducial-playground.html").write_text(out)
print("wrote fiducial-playground.html  (%d KB)" % (len(out) // 1024))
