#!/usr/bin/env python3
"""extract-figures.py — cut the figures out of the five source scans as TIFFs.

Everything else in this project is C++ and Tcl. This one step is Python because
decoding the image streams inside a PDF is not something worth hand-rolling, and
because the point here is to touch the pixels as little as possible.

That is the governing decision: the five PDFs are page-sized scans whose
embedded bitmaps are 1:1 with the page box, so the figures are pulled from the
**native embedded bitmap** rather than from a re-rasterised render. No
resampling, no interpolation, no invented detail — a crop out of this script
contains exactly the pixels the scanner produced. The 12-lead is a true 300 dpi
scan; the Evoke pages are about 203 ppi on letter. Both numbers go in the
manifest so nobody has to guess later.

Each figure box below is given in fractions of the page and then tightened to
the actual ink by `trim_to_ink`, so the hand-picked numbers only have to be
roughly right and the output is snug regardless.

    python3 figures/extract-figures.py --out build/figures
    python3 figures/extract-figures.py --out build/figures --zip build/figures.zip

Output naming, as requested:

    $Condition_$Test_$Company_$Date_$timestampoftest.tiff
"""

import argparse
import csv
import io
import json
import os
import sys
import zipfile

try:
    import pypdf
    from PIL import Image, TiffImagePlugin
except ImportError:
    sys.exit("needs pypdf and pillow:  pip install pypdf pillow")


SRC = "/root/.claude/uploads/35daf6a0-612b-5ce9-befe-b6ffdeec3045"

# ---------------------------------------------------------------------------
# Documents.
#
# `pdf_page` is the index in the scanned file, which for the Comprehensive
# Report is NOT the printed page number: that scan arrived shuffled. Both are
# recorded so a reader can find the original.
#
# `timestamp` and `ts_source` are kept separate on purpose. Only two of the
# three instruments actually print an acquisition time, and passing off a fax
# transmission stamp as a test time in a filename would be a quiet lie. The
# filename gets the best available number; the manifest says what that number
# really is.
# ---------------------------------------------------------------------------
DOCS = {
    "comp": {
        "file": "22f30673-PROC.pdf",
        "title": "Evoke Comprehensive Report r5.9.1",
        "company": "Evoke",
        "date": "2026-08-18",
        "timestamp": "152200",
        "ts_source": "cover page, 'Based on test performed on: 08-18-2026, 3:22 PM'",
        "paper_in": (8.5, 11.0),   # US Letter portrait
    },
    "summary": {
        "file": "aa117c94-PROC_.pdf",
        "title": "Evoke Summary Report r5.9.1",
        "company": "Evoke",
        "date": "2026-08-18",
        "timestamp": "152200",
        "ts_source": "same acquisition as the Comprehensive Report (Report Code Evoke01090P2185S1)",
        "paper_in": (11.0, 8.5),   # US Letter landscape
    },
    "firefly": {
        "file": "ca957827-evoke.pdf",
        "title": "Firefly Neuroscience Brain Insights Report",
        "company": "Firefly",
        "date": "2026-08-18",
        "timestamp": "152200",
        "ts_source": "derived from the Evoke acquisition it summarises",
        "paper_in": (8.27, 11.69),  # A4 portrait
    },
    "ecg12": {
        "file": "876ca390-EDC_consult_needed.pdf",
        "title": "12-lead resting ECG, Midmark ECG Analysis 8.4.2",
        "company": "Midmark",
        "date": "2026-08-18",
        "timestamp": "145116",
        "ts_source": "ECG device clock, 'Date of Report: 08/18/26 14:51:16'",
        "paper_in": (11.0, 8.5),   # US Letter landscape
    },
    "spt": {
        "file": "eb6e012e-PROC___.pdf",
        "title": "Percutaneous allergy skin test, Stallergenes Greer Skintestor OMNI",
        "company": "StallergenesGreer",
        "date": "2026-08-18",
        "timestamp": "165100",
        "ts_source": "FAX TRANSMISSION header 08/18/2026 16:51 -- the form records a test "
                     "DATE but no test TIME, so this is a transmission stamp, not an "
                     "acquisition stamp, and is an upper bound on the true test time",
        "paper_in": (8.47, 11.10),  # Group 3 fax, fine mode -- 204 x 196 dpi
    },
}

# ---------------------------------------------------------------------------
# The figures. Boxes are (x0, y0, x1, y1) as fractions of the page, deliberately
# loose; trim_to_ink tightens them.
#
# Only data figures are here. The stock brain illustration in the Comprehensive
# Report's masthead is decoration, not a result, and is left out.
#
# The 12-lead crop starts below the demographics block. That is the correct
# figure boundary anyway, and it has the useful side effect of keeping the
# patient's name, DOB and record number out of a file meant to be handed around.
# ---------------------------------------------------------------------------
FIGURES = [
    # --- Evoke Comprehensive Report ---------------------------------------
    dict(doc="comp", pdf_page=3, printed_page=4, box=(0.27, 0.150, 0.95, 0.268),
         condition="Resting", test="ECG-Waveform",
         caption="Cardiac P-Q-R-S waveform, 5 s sample from the pre-artifacted single-lead ECG"),
    dict(doc="comp", pdf_page=3, printed_page=4, box=(0.27, 0.268, 0.95, 0.390),
         condition="Resting", test="HRV-Tachogram",
         caption="Heart-rate variability tachogram, RR interval in ms, 60-120 s"),
    dict(doc="comp", pdf_page=3, printed_page=4, box=(0.18, 0.648, 0.68, 0.905),
         condition="Resting", test="HRV-PowerSpectrum",
         caption="HRV frequency spectrum: VLF 1115, LF 951, HF 258 ms^2. "
                 "Expected VLF < LF > HF; observed VLF > LF > HF"),

    dict(doc="comp", pdf_page=2, printed_page=5, box=(0.29, 0.142, 0.66, 0.272),
         condition="GoNoGo", test="ERP-P300a-Cz",
         caption="P300a at Cz to checkerboard stimulus. Latency 468 ms (ref <450), "
                 "amplitude 17.3 uV (ref >=6)"),
    dict(doc="comp", pdf_page=2, printed_page=5, box=(0.29, 0.272, 0.66, 0.402),
         condition="GoNoGo", test="ERP-P300b-Pz",
         caption="P300b at Pz to target stimulus. Latency 380 ms, amplitude 6.6 uV -- "
                 "38% of P300a against a stated >50% criterion"),
    dict(doc="comp", pdf_page=2, printed_page=5, box=(0.29, 0.412, 0.66, 0.542),
         condition="GoNoGo", test="ERP-N100-O2",
         caption="N100 at O2 to checkerboard stimulus. Latency 288 ms (ref <250), "
                 "amplitude -7.6 uV"),

    dict(doc="comp", pdf_page=8, printed_page=6, box=(0.15, 0.165, 0.96, 0.470),
         condition="EyesOpen", test="EEG-RawTrace",
         caption="Raw EEG, 10 s sample, 19 channels with FZ/T8/P3/P8 rejected"),
    dict(doc="comp", pdf_page=8, printed_page=6, box=(0.15, 0.470, 0.96, 0.775),
         condition="EyesClosed", test="EEG-RawTrace",
         caption="Raw EEG, 10 s sample, same montage. Alpha rhythm visible posteriorly"),

    dict(doc="comp", pdf_page=12, printed_page=7, box=(0.030, 0.145, 0.500, 0.838),
         condition="EyesOpen", test="EEG-HeadMaps",
         caption="Frequency amplitude head maps 2-30 Hz vs normative database, z-scored"),
    dict(doc="comp", pdf_page=12, printed_page=7, box=(0.505, 0.145, 0.980, 0.838),
         condition="EyesClosed", test="EEG-HeadMaps",
         caption="Frequency amplitude head maps 2-30 Hz vs normative database, z-scored"),

    dict(doc="comp", pdf_page=10, printed_page=3, box=(0.05, 0.196, 0.92, 0.478),
         condition="SelfReport", test="Screener-Domains",
         caption="Neuropsychological screener by domain, 0-100, reference >=60. "
                 "Global score 34%"),

    # --- Evoke Summary Report ---------------------------------------------
    dict(doc="summary", pdf_page=1, printed_page=1, box=(0.585, 0.228, 0.998, 0.848),
         condition="EyesClosed", test="EEG-HeadMaps-Summary",
         caption="Eyes-closed head maps as printed on the one-page summary"),
    dict(doc="summary", pdf_page=1, printed_page=1, box=(0.295, 0.310, 0.605, 0.855),
         condition="GoNoGo", test="Result-Gauges",
         caption="Poor / Moderate / Good result gauges for the neuropsychological "
                 "testing and brain biomarker blocks"),

    # --- 12-lead ECG ------------------------------------------------------
    dict(doc="ecg12", pdf_page=1, printed_page=1, box=(0.028, 0.200, 0.960, 0.930),
         condition="Resting", test="ECG-12Lead",
         caption="12-lead resting ECG, 25 mm/s, 10 mm/mV. Sinus bradycardia 57 bpm; "
                 "anterolateral ST elevation read as a repolarisation variant. "
                 "Demographics block cropped away"),

    # --- Allergy skin test -------------------------------------------------
    dict(doc="spt", pdf_page=1, printed_page=1, box=(0.132, 0.163, 0.845, 0.760),
         condition="Percutaneous", test="SPT-40Panel",
         caption="Skin-prick result grid, both trays, wheal in mm at 15 min. "
                 "Histamine control 7 mm, glycerin control 0 mm"),
]


# ---------------------------------------------------------------------------
def native_page_image(path, page_index):
    """The embedded bitmap for a page, at the resolution the scanner produced.

    Every page in this set holds exactly one full-page image, so 'the first
    image' is unambiguous. If that ever stops being true this raises rather
    than silently picking a logo.
    """
    reader = pypdf.PdfReader(path)
    page = reader.pages[page_index - 1]
    images = list(page.images)
    if len(images) != 1:
        raise RuntimeError(f"{os.path.basename(path)} page {page_index}: "
                           f"expected 1 embedded image, found {len(images)}")
    im = images[0].image
    box = page.mediabox
    return im, float(box.width), float(box.height)


def trim_to_ink(im, pad=14, row_frac=0.004, col_frac=0.004):
    """Shrink a crop to the ink inside it, then re-pad.

    Rows and columns whose dark-pixel count falls below a small fraction of
    their length are treated as margin. The fraction rather than an absolute
    count is what makes this survive the scanner speckle on the faxed pages: a
    handful of stray dark pixels in a blank row does not hold the crop open.
    """
    g = im.convert("L")
    px = g.load()
    w, h = g.size
    thr = 200

    rows = []
    for y in range(h):
        n = 0
        for x in range(0, w, 2):          # every other column is plenty
            if px[x, y] < thr:
                n += 1
        rows.append(n)
    cols = []
    for x in range(w):
        n = 0
        for y in range(0, h, 2):
            if px[x, y] < thr:
                n += 1
        cols.append(n)

    row_min = max(1, int(row_frac * (w / 2)))
    col_min = max(1, int(col_frac * (h / 2)))

    ys = [y for y, n in enumerate(rows) if n >= row_min]
    xs = [x for x, n in enumerate(cols) if n >= col_min]
    if not ys or not xs:
        return im                          # nothing found; leave the crop alone

    y0 = max(0, min(ys) - pad)
    y1 = min(h, max(ys) + 1 + pad)
    x0 = max(0, min(xs) - pad)
    x1 = min(w, max(xs) + 1 + pad)
    return im.crop((x0, y0, x1, y1))


def filename(fig, doc):
    return "{condition}_{test}_{company}_{date}_{ts}.tiff".format(
        condition=fig["condition"], test=fig["test"],
        company=doc["company"], date=doc["date"], ts=doc["timestamp"])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=SRC, help="directory holding the five source PDFs")
    ap.add_argument("--out", default="build/figures")
    ap.add_argument("--zip", dest="zippath", default=None)
    ap.add_argument("--no-trim", action="store_true")
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    page_cache = {}
    manifest = []

    for fig in FIGURES:
        doc = DOCS[fig["doc"]]
        path = os.path.join(args.src, doc["file"])
        key = (path, fig["pdf_page"])
        if key not in page_cache:
            page_cache[key] = native_page_image(path, fig["pdf_page"])
        page_im, pt_w, pt_h = page_cache[key]

        W, H = page_im.size
        x0, y0, x1, y1 = fig["box"]
        crop = page_im.crop((int(x0 * W), int(y0 * H), int(x1 * W), int(y1 * H)))
        if not args.no_trim:
            crop = trim_to_ink(crop)
        crop = crop.convert("L")

        # These PDFs were built with 1 pt == 1 px, so the page box carries no
        # resolution information -- dividing by it would report 72 ppi for
        # every document, which is arithmetically right and physically wrong.
        # Real resolution comes from the physical paper the page represents.
        # The skin-test sheet lands on 204 x 196, which is exactly Group 3 fax
        # fine mode, so the anisotropy is kept rather than averaged away.
        # Page 7 of the Comprehensive Report is landscape inside an otherwise
        # portrait document, so orientation is taken from the bitmap rather than
        # from the document-level declaration.
        paper_w, paper_h = sorted(doc["paper_in"])
        if W > H:
            paper_w, paper_h = paper_h, paper_w
        ppi_x = round(W / paper_w)
        ppi_y = round(H / paper_h)
        ppi = f"{ppi_x}x{ppi_y}" if ppi_x != ppi_y else str(ppi_x)

        name = filename(fig, doc)
        out = os.path.join(args.out, name)

        description = (
            f"{fig['caption']}. "
            f"Source: {doc['title']}, PDF page {fig['pdf_page']} "
            f"(printed page {fig['printed_page']}). "
            f"Acquisition {doc['date']} {doc['timestamp'][:2]}:{doc['timestamp'][2:4]}:"
            f"{doc['timestamp'][4:]} -- timestamp source: {doc['ts_source']}. "
            f"Native crop from the embedded scan at {ppi} ppi, no resampling. "
            f"De-identified: no name, DOB or record number."
        )

        info = TiffImagePlugin.ImageFileDirectory_v2()
        info[270] = description                    # ImageDescription
        info[305] = "neuro/figures/extract-figures.py"   # Software
        info[315] = doc["company"]                 # Artist, i.e. the instrument vendor
        crop.save(out, format="TIFF", compression="tiff_lzw",
                  dpi=(ppi_x, ppi_y), tiffinfo=info)

        manifest.append(dict(
            filename=name,
            condition=fig["condition"], test=fig["test"], company=doc["company"],
            date=doc["date"], timestamp=doc["timestamp"], timestamp_source=doc["ts_source"],
            source_document=doc["title"], source_file=doc["file"],
            pdf_page=fig["pdf_page"], printed_page=fig["printed_page"],
            width_px=crop.size[0], height_px=crop.size[1],
            ppi_x=ppi_x, ppi_y=ppi_y,
            caption=fig["caption"],
        ))
        print(f"  {name:66s} {crop.size[0]:5d} x {crop.size[1]:5d} px  @{ppi} ppi")

    # -- manifest, in both a machine and a human shape ----------------------
    with open(os.path.join(args.out, "MANIFEST.csv"), "w", newline="") as f:
        wr = csv.DictWriter(f, fieldnames=list(manifest[0].keys()))
        wr.writeheader()
        wr.writerows(manifest)
    with open(os.path.join(args.out, "MANIFEST.json"), "w") as f:
        json.dump({"schema": "neuro/figures/v1", "figures": manifest}, f, indent=2)

    with open(os.path.join(args.out, "README.txt"), "w") as f:
        f.write(README.format(n=len(manifest)))

    if args.zippath:
        os.makedirs(os.path.dirname(args.zippath) or ".", exist_ok=True)
        with zipfile.ZipFile(args.zippath, "w", zipfile.ZIP_DEFLATED) as z:
            for entry in sorted(os.listdir(args.out)):
                z.write(os.path.join(args.out, entry), arcname=os.path.join("figures", entry))
        size = os.path.getsize(args.zippath)
        print(f"\n  {args.zippath}  {size/1024/1024:.1f} MB, {len(manifest)} TIFFs + manifest")


README = """FIGURES FROM THE SOURCE CLINICAL DOCUMENTS
==========================================

{n} figures cut from the five scanned documents of a single clinic visit on
2026-08-18, saved as LZW-compressed grayscale TIFF.

NAMING
------

    $Condition_$Test_$Company_$Date_$timestampoftest.tiff

    Condition  EyesOpen | EyesClosed | Resting | GoNoGo | SelfReport | Percutaneous
    Test       the instrument and, where relevant, the channel
    Company    the vendor whose device or software produced the figure
    Date       ISO, acquisition date
    timestamp  HHMMSS -- see the caveat below

HOW THESE WERE MADE
-------------------

The five PDFs are page-sized scans. Each figure is a crop out of the page's
NATIVE EMBEDDED BITMAP, not out of a re-rendered raster: no resampling and no
interpolation, so what is here is exactly what the scanner produced. Crop
boundaries were hand-placed and then tightened to the ink automatically.

Effective resolution differs by document and is recorded per file, both in the
manifest and in each TIFF's ImageDescription tag:

    12-lead ECG          300 ppi       a true 300 dpi scan, letter landscape
    Evoke reports        203 ppi       letter
    Firefly report       209 ppi       A4
    Allergy skin test    204 x 196 ppi Group 3 fax, fine mode -- the anisotropy
                                       is real and is preserved in the TIFF tags

THE TIMESTAMP CAVEAT -- PLEASE READ
-----------------------------------

Only one of the three instruments prints an acquisition time.

    145116   12-lead ECG. Real. The device clock: "Date of Report:
             08/18/26  14:51:16".

    152200   All Evoke and Firefly figures. Real, but to the minute only:
             the Comprehensive Report cover states "Based on test performed
             on: 08-18-2026, 3:22 PM". Seconds are zero-filled, not measured.

    165100   Allergy skin test. NOT A TEST TIME. The form records a test date
             and no test time; 16:51 is the FAX TRANSMISSION stamp in the page
             header. It is an upper bound on when the test happened, nothing
             more.

Every filename carries the best number available for its document; the
`timestamp_source` column in MANIFEST.csv says what that number actually is.
Do not sort these by filename and call the result a timeline.

WHAT IS NOT HERE
----------------

Decorative artwork. The stock brain illustration in the Comprehensive Report's
masthead is not a result and was not extracted.

DE-IDENTIFICATION
-----------------

No file contains a name, date of birth or medical record number. The 12-lead
crop begins below the demographics block, which is the correct figure boundary
in any case. The figures are still health data about a real person.

REGENERATING
------------

    python3 figures/extract-figures.py --out build/figures --zip build/figures.zip

or, from neuro/:

    make figures
"""


if __name__ == "__main__":
    main()
