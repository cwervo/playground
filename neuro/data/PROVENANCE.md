# Provenance

Where every number in `session-2026-08-18.json` came from, and how confident the
transcription is.

The five source PDFs are **image scans with no text layer** — `pypdf` extracts
20 characters from a 39-page file. Everything here was read visually from page
renders at 130–300 dpi. That makes transcription a first-class source of error,
so it is recorded rather than assumed away.

---

## The documents

| File | Pages | What it is | Note |
|---|---|---|---|
| `22f30673-PROC.pdf` | 13 | Evoke Comprehensive Report r5.9.1 | **pages scanned out of order** |
| `aa117c94-PROC_.pdf` | 1 | Evoke Summary Report r5.9.1 | landscape |
| `ca957827-evoke.pdf` | 3 | Firefly Neuroscience Brain Insights Report | |
| `876ca390-EDC_consult_needed.pdf` | 1 | 12-lead ECG, Midmark ECG Analysis 8.4.2 | landscape |
| `eb6e012e-PROC___.pdf` | 1 | Allergy skin test, Stallergenes Greer Skintestor OMNI | fax scan, handwritten values |

All five carry the same patient identifiers and the same date, 2026-08-18.

### Page order in the Comprehensive Report

The scan is shuffled. Mapping from PDF page to printed page number:

| PDF page | Report page | Content |
|---|---|---|
| 6 | 1 | cover, signatories |
| 7 | 2 | ADHD screening result, neurofunctional domains |
| 10 | 3 | patient header, screener, memory subtypes, response metrics |
| 3 | 4 | heart metrics, ECG waveform, HRV spectrum |
| 2 | 5 | ERP waveforms and results |
| 8 | 6 | EEG raw data, both conditions |
| 12 | 7 | EEG head maps, 2–30 Hz, both conditions |
| 1 | 8 | LORETA source localisation — **not performed** |
| 9 | 9 | data summary tables |
| 5 | 10 | heart and ERP summary tables |
| 13 | 11 | eyes-open EEG summary |
| 4 | 12 | eyes-closed EEG summary |
| 11 | 13 | references |

Anyone re-reading the source should work from the printed page numbers, not the
PDF order.

---

## Confidence levels

Each metric and each skin-test site carries a `confidence` field.

**`high`** — printed digits, read unambiguously, and cross-checked against a
second appearance in another document wherever one exists. That cross-check
catches real things: reaction time appears as `588 ms` on the Comprehensive
Report's summary table and as `588.12` in the Firefly report, and RT variability
appears as both `19 ms` (rounded, summary pages) and `18.61` (Neurofunctional
Domains narrative). The unrounded value is used and the rounded one is recorded
in a `note`.

**`medium`** — printed and legible, but appearing only once, or quoted inside
prose without a stated montage. The three `eegz.g.*` metrics are medium: the
Comprehensive Report's Neurofunctional Domains section quotes global theta,
beta and delta z-scores in running text and never says which montage or
reference they came from, and they do not match the Firefly regional table.

**`low`** — genuinely ambiguous. Two sites, both on the skin-test sheet. See
below.

---

## The skin-test sheet

This is the only handwritten document in the set, and it is a fax scan of one.

The handwritten wheal values sit **low in each row and straddle the row rule**,
so a naive read is off by one throughout. The alignment is fixed by the two
controls, which have known expected values:

- **B1, positive histamine control = 7 mm.** A histamine control is expected to
  produce a wheal; 7 mm is typical.
- **B10, negative glycerin control = 0 mm.** A glycerin control is expected to
  produce nothing.

Both land correctly under the reading "the digit belongs to the row whose bottom
rule it straddles", which anchors every other row on the sheet. That the panel's
own controls are both in range also means the panel is technically valid: a dead
histamine control or a reactive glycerin control would make the whole sheet
uninterpretable, and this one is neither.

### The two low-confidence readings

**B28 *D. pteronyssinus* = 0 mm and B29 *D. farinae* = 11 mm.**

The `0` and the `11` in these two rows could be swapped. The two dust mite
species are usually concordant — someone sensitised to one is usually sensitised
to the other — so a 0/11 split is the less likely clinical picture, which argues
for a transcription error. Against that, the anchoring rule that works for every
other row on the sheet gives 0/11 as written.

**This is left as written and marked `confidence: "low"`, with an `ambiguity`
note.** It is drawn as a hollow square in the dashboard's immune panel, so the
uncertainty is visible in every rendering rather than resolved in the author's
favour and forgotten.

It does not change any conclusion: the allergen burden composite counts sites
`>= 3 mm`, and exactly one of the two is positive either way.

### Also marked medium

`A6 Almond = 6 mm` and `A9 Pecan = 9 mm` are the only two positives in an
otherwise entirely negative 20-site food tray, and the digits are less cleanly
formed than the tray B values. Both are plausible — tree-nut sensitisation
alongside heavy tree-pollen sensitisation is common — but they are the two food
values worth re-reading against the original.

`B18 Kentucky bluegrass = 7`, `B19 perennial rye = 9`, `B20 meadow fescue = 7`
are marked medium: the writing in that block is cramped and the digits overlap
the rule more than elsewhere. All three are positive under any plausible
reading, so the grass class stays 6/6.

---

## Values the engine derives rather than transcribes

Ten quantities in the dashboard appear in no source document. They are computed
in `src/analyze.cpp` and defined in `data/prior-graph.json` under
`derived_metrics`, so the definition travels with the data:

`ans.vlf_ratio`, `ans.lf_hf`, `ans.hf_frac`, `ans.vlf_frac`,
`ans.spec_entropy`, `erp.p3b_ratio`, `erp.timing_sum`, `spt.burden`,
`spt.max_wheal`, `eeg.quality`.

Two of these deserve a note.

**`ans.vlf_ratio` reproduces an undocumented vendor figure.** The Comprehensive
Report's neuroinflammation domain states "High HRV VLF is associated with
increased systemic stress or inflammatory processes (value = 1.17, threshold >
0.5)" without ever defining what the value is. 1115 / 951 = 1.1725. It is the
VLF/LF ratio. Naming it matters because it changes the reading: the flag is a
*balance* statement, not an absolute VLF elevation.

**`erp.p3b_ratio` evaluates a criterion the vendor states and never computes.**
The ERP page gives the P300b amplitude reference as ">= 6 µV **and** > 50% P300a
power". Both amplitudes are printed. The quotient — 6.6 / 17.26 = 0.382, i.e.
23.5% short of the stated floor — appears nowhere in seventeen pages.

---

## What is deliberately not in the dataset

- **Nothing was inferred to fill a gap.** `eeg.paf_eo` is `null` because the
  report says *Indiscernible*; it is not imputed from the eyes-closed value.
  `null` and `0` are kept distinct all the way through the pipeline, which is
  why `src/json.hpp` has a separate Null tag.
- **Medications.** The field reads `UNKNOWN` on the source and reads `UNKNOWN`
  here. It is the largest uncontrolled variable in the battery and inventing a
  plausible value would have hidden that.
- **Head-map z-scores.** The Comprehensive Report shows 58 topographic maps
  across 29 frequency bins and two conditions. Reading per-electrode z-scores
  off a greyscale contour plot in a fax-quality scan would produce numbers with
  error bars wider than the effects. Only the regional z-scores that Firefly
  printed as digits are transcribed.
- **Direct identifiers.** `subject_ref` is `SUBJ-001`. Name, date of birth and
  medical-record number appear in the source PDFs and are not carried into this
  repository. `analyze --deidentify` additionally suppresses the report code in
  the emitted display file.

---

## The figures

`figures/extract-figures.py` cuts the 15 data figures out of the same scans as
TIFFs. It reads the **native embedded bitmap** of each page rather than a
re-rasterised render — these PDFs store one full-page image per page at 1:1 with
the page box — so a crop contains exactly the scanner's pixels.

That last point is why the resolution numbers in `MANIFEST.csv` are derived from
physical paper size and not from the PDF page box. These files were built with
1 pt = 1 px, so the page box reports 72 ppi for every document, which is
arithmetically correct and physically meaningless. Against real paper:

| Document | Bitmap | Paper | Effective |
|---|---|---|---|
| Evoke Comprehensive / Summary | 1728 × 2236 | US Letter | 203 ppi |
| Firefly Brain Insights | 1728 × 2445 | A4 | 209 ppi |
| 12-lead ECG | 3300 × 2550 | US Letter landscape | 300 ppi |
| Allergy skin test | 1728 × 2176 | — | **204 × 196 ppi** |

The skin test's anisotropy is not an error: 204 × 196 dpi is exactly Group 3 fax
fine mode, which independently confirms the sheet reached the practice as a fax
and explains its transcription difficulty. The TIFF keeps both axes rather than
averaging them.

The Firefly report contributes no figures — all three of its pages are tables.

## Reproducing the transcription

```sh
pip install pypdfium2 pillow
python3 - <<'EOF'
import pypdfium2 as pdfium
doc = pdfium.PdfDocument("22f30673-PROC.pdf")
for i in range(len(doc)):
    doc[i].render(scale=130/72).to_pil().convert("L").save(f"p{i+1:02d}.png")
EOF
```

The skin-test sheet needs 300 dpi and cropping to read the handwriting; 130 dpi
is enough for everything else.
