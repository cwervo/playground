# Full fat: the biomedical engineering

Technical companion to [`01-plain-language.md`](01-plain-language.md). Same
sections, same order, no simplification.

Numbers in this document are the ones the engine derives; where a vendor value
and a re-derived value differ, both are given. Everything is reproducible with
`make` from `data/session-2026-08-18.json`.

---

## 1. Instruments and what each one actually measures

### 1.1 Resting quantitative EEG

19-channel 10-20 montage, eyes-open and eyes-closed blocks, vendor-default
linked-ear reference. Spectral estimates are reported in 1 Hz bins from 2 to
30 Hz as amplitude head maps expressed as z-scores against a normative
database.

The two vendors band the spectrum differently and the difference matters:

| Band | Evoke (head maps) | Firefly (regional z) |
|---|---|---|
| delta | 2–3 | not reported |
| theta | 4–7 | 3.5–7.5 |
| alpha1 | 8–9 | 7.5–10.0 |
| alpha2 | 10–12 | 10.0–12.5 |
| beta1 | 13–18 | 12.5–25.0 |
| beta2 | 19–30 | 25.0–35.0 |
| spindle | — | 19–21 |

Any comparison across the two reports has to carry that mapping. Firefly's
beta1 subsumes Evoke's beta1 *and* the lower half of its beta2, which is why the
Firefly central beta1 z of +1.92 and the Evoke narrative's global beta z of
−2.20 are not in contradiction — they are different bands over different
montages.

**Data quality is the governing constraint.** FZ, T8, P3 and P8 were rejected,
leaving 15 of 19 reliable channels against the vendor's 18-channel minimum for
sLORETA-family source localisation, which was therefore suppressed on both
conditions. Three consequences:

- No regional localisation exists in this record. Every regional statement in
  the vendor prose ("anterior cingulate", "frontal lobe dysfunction") is
  inference from scalp topography over a reduced montage, not from an inverse
  solution.
- The rejected set includes **FZ**, the midline frontal electrode. Theta:beta
  ratio is conventionally read at Cz or Fz, and the anterior-cingulate slow-wave
  story the report tells about ADHD subtypes rests on exactly that region.
- With four channels gone, the interpolation used to build the head maps has a
  materially larger error over the affected scalp regions, and the maps do not
  indicate where.

The engine promotes this to a first-class metric — `eeg.quality`, 15 usable
against a floor of 18, a 16.7% shortfall — rather than leaving it as a footnote.

### 1.2 Event-related potentials

Visual oddball with checkerboard-reversal and target conditions, go/no-go button
press, epochs −200 to +1000 ms.

| Component | Site | Result | Reference | Margin |
|---|---|---|---|---|
| N100 latency | O2 | 288 ms | < 250 ms | **+15.2%** |
| N100 amplitude | O2 | −7.55 µV | ≤ −6 µV | −25.8% (inside) |
| P300a latency | Cz | 468 ms | < 450 ms | +4.0% |
| P300a amplitude | Cz | 17.26 µV | ≥ 6 µV | −187.7% (inside) |
| P300b latency | Pz | 380 ms | < 450 ms | −15.6% (inside) |
| P300b amplitude | Pz | 6.6 µV | ≥ 6 µV | −10.0% (inside) |
| **P3b/P3a ratio** | — | **0.382** | **≥ 0.50** | **+23.5%** |

The N100 is a largely pre-attentive index of early sensory registration
(Näätänen & Picton 1987). A 38 ms delay at the first cortical stage propagates
into every downstream latency, which is why the timing-chain panel in the
dashboard plots the four stages against their own ceilings rather than as
independent flags — the deficit accumulates, it does not appear at one stage.

The P3a/P3b dissociation is the finding this record turns on, and it is the one
the vendor states as a criterion and never evaluates. From Polich's (2007)
integrative account: **P3a** is a frontally-generated response to novelty and
stimulus-driven attentional orienting; **P3b** is a temporal-parietal response
reflecting context updating and memory-trace consolidation. Both are present
here; P3a is close to three times its floor while P3b is 10% above it. The
quotient — orienting drive relative to consolidation drive — is 0.382 against a
stated 0.50 floor, i.e. 23.5% short of criterion.

The electrophysiological reading is: attentional capture is intact and possibly
strong; the downstream consolidation that converts capture into a retained,
categorised event is comparatively weak. Compare the subjective complaint of
"pulled toward new things, then lose the thread". That mapping is far better
supported than the theta:beta ratio that got flagged instead.

#### 1.2.1 The order the components arrive in

The table above is latencies against ceilings, one row at a time, which is how
the report presents them and how they were entered here. Reading them as a
*sequence* says something the rows do not.

`video/trace.py` digitises the three printed curves back into numbers — axis and
tick marks only, never the printed peak values, so the report's own figures are
a test rather than an input, and all three pass within 0.7 µV and 7 ms.
`video/analyse.py` then takes the principal deflection of each channel and sorts
by latency:

```
O2  287 ms   −7.61 µV   negative
Pz  387 ms   +6.67 µV   positive
Cz  464 ms  +17.69 µV   positive
```

N100, then the parietal **P3b**, then the frontocentral **P3a**. The
conventional sequence is the other way round: P3a is the earlier, faster,
stimulus-driven orienting response and P3b follows it (Squires, Squires & Hillyard
1975; Polich 2007). Here the orienting response arrives 77 ms *after* the
consolidation response.

That is the same dissociation §1.2 derives from the 0.382 amplitude quotient,
arriving by an independent route — one measures how big the two responses are,
the other measures which one gets there first, and they agree. Two measurements
of one underlying thing is weaker evidence than two independent things agreeing,
so this is corroboration rather than a second finding; it is worth stating
because it is legible directly in the printed curves and appears nowhere in the
printed text.

Caveats, in order of size. These are three separate single-channel averages, not
a simultaneous multichannel recording, so "order" here means the order of three
printed curves and not a propagation delay measured across a field. The channels
also come from two different conditions — Cz and O2 from checkerboard reversal,
Pz from target — and the report does not state whether the averages share
epochs. And a peak latency measured off a scan is only as good as the tick marks
it was calibrated against, which is why the validation table is printed with the
result.

### 1.3 Behavioural (CPT / go-no-go)

| Metric | Result | Reference | Margin |
|---|---|---|---|
| Mean RT | 588.12 ms | 200–500 ms | **+17.6%** |
| RT SD (intra-individual) | 18.61 ms | ≤ 10 ms | **+86.1%** |
| Omission rate | 8.57% | ≤ 10% | −14.3% (inside) |
| Commission rate | 2.45% | ≤ 3% | −18.3% (inside) |

The dissociation is clean: **timing degraded, accuracy preserved**. Intra-
individual RT variability is the single most replicated behavioural marker in
the attention literature (Kofler et al. 2013, 319 studies) and also the least
specific — Karalunas et al. (2014) argue explicitly for reading it as a
trans-diagnostic phenotype rather than a diagnostic sign. Elevated RT SD with
normal commission errors and a large P3a is *not* an inhibitory-control
phenotype.

### 1.4 Autonomic (HRV) and cardiac

Two-minute single-lead resting recording, plus a separate 12-lead.

| Metric | Result | Reference | Margin |
|---|---|---|---|
| Heart rate | 55.88 bpm | 50–80 | inside |
| SDNN | 82.09 ms | 36–100 | inside |
| Total power | 2323.9 ms² | ≥ 800 | inside |
| VLF | 1115 ms² | — | — |
| LF | 951 ms² | — | — |
| HF | 258 ms² | — | — |
| **VLF/LF** | **1.173** | ≤ 0.5 | **+134.5%** |
| **LF/HF** | **3.686** | 0.5–2.0 | **+84.3%** |
| **HF fraction** | **11.10%** | ≥ 15% | **+26.0%** |
| VLF fraction | 47.98% | ≤ 35% | +37.1% |
| **Spectral entropy** | **1.388 bits** | ≥ 1.35 of 1.585 | inside, barely |

Three of the five time-domain and total-power figures are unremarkable, which is
why the vendor scored arousal regulation as *normal*. The abnormality is
entirely in the **distribution** of the power, not its total, and no
single-number HRV summary can see it. That is the case for putting the band
split on the page as a shape rather than as a score.

The engine reproduces the vendor's own undocumented composite: the report's
neuroinflammation domain quotes "High HRV VLF ... value = 1.17, threshold > 0.5"
with no definition. 1115/951 = **1.1725**. The quantity is the VLF/LF ratio, and
naming it is worth doing because it changes how the flag should be read — it is
a *balance* statement, not an absolute VLF elevation.

Expected pattern for this vendor is VLF < LF > HF. Observed is VLF > LF > HF.

Caveats that matter:

- **Two minutes is short for VLF.** The Task Force standard and Shaffer &
  Ginsberg (2017) both put VLF estimation on ≥ 5-minute records; below that the
  lowest-frequency bins are poorly resolved and contaminated by non-stationarity
  and by the very slow trend of the recording itself. The *direction* here is
  corroborated by two independent quantities (LF/HF 3.69 and HF fraction 11.1%),
  so the finding survives; the absolute 1115 ms² should not be quoted.
- **LF/HF as a sympathovagal index is contested.** LF is not purely sympathetic;
  it carries baroreflex and respiratory contributions. It is used here only as
  one of three converging indicators, never alone.
- HF fraction is the cleanest available non-invasive vagal index (respiratory
  sinus arrhythmia) and is the one to trust most of the three.

**12-lead:** sinus bradycardia at 57 bpm, PR 136 ms, QRS 88 ms, QT/QTc 398/393
ms, axes P 45° / QRS 50° / T 39°. Machine reading: anterolateral ST elevation as
a repolarisation variant; verdict PROBABLY NORMAL. Benign early repolarisation
is common in young men and every interval here is unremarkable. Note the QRS
discrepancy between instruments — 88 ms on the 12-lead, 97 ms on the Evoke
single-lead — which is within the expected disagreement between a 12-lead
measurement and a single-lead automated one, and is worth knowing about before
anyone treats either figure as precise. The actionable item is administrative:
the comment field reads **Unconfirmed Report**, so no physician overread is on
this copy.

### 1.5 Percutaneous allergy panel

60 sites across two trays, wheal diameter read at 15 minutes, 3 mm over negative
control as the positivity threshold.

Controls: **histamine 7 mm, glycerin 0 mm.** Both in range, so the panel is
technically valid and the reactions are genuine rather than dermographic — worth
stating explicitly, because a panel with a dead histamine control or a reactive
glycerin control is uninterpretable and this one is neither.

| Class | Positive / tested | Largest |
|---|---|---|
| Tree | 10 / 12 | 15 mm (black walnut, shagbark hickory, eastern oak) |
| Grass | 6 / 6 | 15 mm (Timothy) |
| Weed | 6 / 7 | 9 mm (mugwort) |
| Indoor | 2 / 8 | 11 mm (dust mite) |
| Food | 2 / 20 | 9 mm (pecan) |
| Mould | 0 / 5 | — |
| **Total** | **26 / 58 (44.8%)** | **15 mm** |

Wheal size indexes **sensitisation**, not clinical severity; correlating it with
symptoms requires exposure history, which is not in this record. What the
numbers do establish is a substantial IgE-mediated load with a strong
outdoor-pollen weighting, and a grass panel that is 6 for 6.

**Two transcriptions are marked low-confidence.** The handwritten wheal values
sit low in each row and straddle the row rule; anchoring on the two controls
(histamine 7, glycerin 0) fixes the alignment for the rest, but rows B28 and B29
— *D. pteronyssinus* 0 mm and *D. farinae* 11 mm — could be swapped. The two
mites are usually concordant, so a 0/11 split is the less likely reading. This
is carried through the whole pipeline as `confidence: "low"` and drawn as a
hollow square in the immune panel, rather than being quietly resolved in the
author's favour.

---

## 2. Normalisation: putting five instruments on one axis

Two derived quantities are computed for every metric.

### 2.1 `dist` — distance past the threshold

For a **one-sided** criterion with threshold `T`:

```
lower-is-better:   dist = (v − T) / |T|
higher-is-better:  dist = (T − v) / |T|
```

For a **two-sided** band `[lo, hi]` of width `W`:

```
v < lo:   dist = (lo − v) / W
v > hi:   dist = (v − hi) / W
inside:   dist = −min(v − lo, hi − v) / W
```

Negative means inside the reference with that much margin left.

The choice of denominator is the load-bearing decision. Normalising a one-sided
criterion by an invented band width lets an author make any exceedance look
small by widening the invented far edge; normalising by the threshold itself
cannot be gamed that way, and it makes "4% over the line" and "225% over the
line" directly comparable across instruments with unrelated units. That single
convention is what turns a page of red dots into a ranking.

Severity follows from `dist` alone: inside → OK, `0 < dist < 0.15` → borderline,
`dist ≥ 0.15` → deviant. The 15% cut is a judgement call and it is stated as
one; `stats::kBorderlineCut` is a single constant and moving it moves every
host at once.

### 2.2 `sdev` — signed deviation for the graph

Where a vendor supplied a genuine normative z (the `eeg_z` metrics), that value
is used. Otherwise a pseudo-z in half-band units:

```
sdev = (v − centre) / (W/2)          centre = (lo + hi)/2
```

so ±2 lands on the band edges.

Critically, `sdev` runs in each metric's **own natural direction** — larger
value gives larger `sdev` — and never in a "badness" direction. The prior graph
is written in natural units ("high LF/HF goes with high central beta"), so
flipping to badness would silently invert half the edges. The two axes have
different jobs and are kept apart: `dist` is for ranking findings, `sdev` is for
scoring relationships.

### 2.3 Composites the vendors describe but never print

| Derived | Definition | Result |
|---|---|---|
| `ans.vlf_ratio` | VLF / LF | 1.173 — reproduces the report's unexplained "1.17" |
| `ans.lf_hf` | LF / HF | 3.686 |
| `ans.hf_frac` | HF / total | 0.1110 |
| `ans.vlf_frac` | VLF / total | 0.4798 |
| `ans.spec_entropy` | Shannon entropy over {VLF, LF, HF} | 1.388 of 1.585 bits |
| `erp.p3b_ratio` | P3b amp / P3a amp | 0.382 against a stated 0.50 floor |
| `erp.timing_sum` | (N100 − 250) + (P3a − 450) | 56 ms of cumulative timing debt |
| `spt.burden` | positives / non-control sites | 0.448 |
| `spt.max_wheal` | max wheal | 15 mm |
| `eeg.quality` | usable channels | 15 of a required 18 |

---

## 3. The statistics, and what they are not

### 3.1 Why there is no correlation coefficient anywhere

n = 1 session. There is no sample over which to estimate a correlation. Any `r`
printed on a single-subject panel is a decoration. The co-deviation matrix in
`stats::coDeviationMatrix` is labelled *structure*, and the chord panel says so
on its face: "with n = 1 these chords are hypotheses drawn to scale, not
measured associations."

### 3.2 What is answerable: concordance against a prior graph

`data/prior-graph.json` encodes 32 **directed prior expectations** taken from
the literature the two vendor reports themselves cite — "published work expects
A and B to co-deviate with sign s, at weight w" — grouped into five hypotheses.

For a hypothesis H:

```
C(H) = Σ_e w_e · s_e · tanh(sdev_a / 2) · tanh(sdev_b / 2)  /  Σ_e w_e
```

bounded in [−1, +1]. The `tanh` squash is not cosmetic: without it,
`srs.exec_attn` at −3.70 half-bands would single-handedly decide every
hypothesis it appears in.

### 3.3 The null

Permute the observed `sdev` vector across metrics, recompute C, repeat 200 000
times, seeded. This asks whether the *pairing* carries the signal.

```
p = (#{C_perm ≥ C_obs} + 1) / (N + 1)
```

The add-one correction means a p-value is never reported as exactly zero on a
finite number of permutations.

**This is a weak null and it is labelled as one everywhere it appears.** Metrics
are not genuinely exchangeable — a heart-rate deviation and a PHQ-9 deviation
are not drawn from a common pool — and edges within a hypothesis share
endpoints, so successive permutations are not independent. Read a low p as "this
pattern is not obviously an artefact of reshuffling", not as evidence of an
effect. There is no multiplicity correction across the five hypotheses either;
with five tests at α = 0.05 the family-wise error rate is about 0.23, so H2 at
p = 0.0063 would survive Bonferroni and H1, H3, H4 comfortably so.

### 3.4 Results

200 000 permutations, seed 20260818, all edges computable:

| | Hypothesis | C | p | null | z vs null | edges |
|---|---|---|---|---|---|---|
| **H3** | Mood driving the complaint | **+0.740** | **< 0.0001** | +0.005 ± 0.145 | **+5.06** | 7/7 |
| **H1** | Sympathetic over-arousal | **+0.573** | **0.0002** | −0.003 ± 0.148 | **+3.90** | 7/7 |
| **H4** | Allergic / inflammatory load | **+0.528** | **0.0044** | −0.004 ± 0.173 | **+3.08** | 5/5 |
| **H2** | Timing slowed, capacity intact | **+0.401** | **0.0063** | −0.002 ± 0.145 | **+2.79** | 7/7 |
| H5 | Classic ADHD electrophysiology | +0.120 | 0.1735 | +0.000 ± 0.159 | +0.75 | 6/6 |

H5 was constructed from six real, well-cited ADHD edges — theta:beta against
self-reported executive function and against commission errors, central theta
against theta:beta, P3a amplitude against theta:beta, omissions against
theta:beta, central beta1 against theta:beta. It is not a straw man, and it does
not separate from chance. That is an independent line of evidence arriving at
the vendor's own conclusion by a different route.

### 3.5 Sensitivity

The engine takes `--override id=value` and re-derives everything downstream —
composites, severities, all five concordances, all five permutation nulls. It is
how the claims above were stress-tested and how the Tk explorer's arrow-key
constraint drag works.

```
make whatif M=beh.rt V=430
```

Setting reaction time to a normal 430 ms drops H2 from C = 0.401 / p = 0.0063 to
C = 0.233 / p = 0.047 and H4 from 0.528 to 0.449. So H2 leans on RT roughly as
much as you would expect a "timing" hypothesis to, and H4 does not collapse
without it — its support is distributed across the allergen burden and the
autonomic ratios rather than resting on one measure.

---

## 4. Instrument disagreement

The quantity no report in this set prints. For each construct measured by both a
self-report scale and an objective instrument, both are projected onto a common
function-quality axis and subtracted:

| Construct | self-report `sdev` | objective | objective `sdev` | gap | reading |
|---|---|---|---|---|---|
| Attention allocation | −3.70 | P3a amplitude | −0.34 | **+3.36** | feels much worse than it measures |
| Executive control | −3.70 | commission rate | +0.63 | **+3.07** | feels much worse than it measures |
| Sustained attention | −3.70 | omission rate | +0.71 | **+2.99** | feels much worse than it measures |
| Memory | −1.81 | peak alpha frequency | +1.09 | **+2.90** | feels much worse than it measures |
| Motor speed | −2.63 | reaction time | +1.59 | +1.04 | feels worse than it measures |
| Sensory processing | −1.78 | N100 latency | +1.30 | +0.47 | self-report and instrument agree |
| Mood | −3.27 | PHQ-9 | +5.00 | **−1.73** | measures much worse than it feels |

Three readings fall out of that table.

**The three attention constructs are the largest gaps in the record**, all in
the same direction, all substantial. This is the classic depression-associated
subjective cognitive complaint pattern (Gifford et al. 2015; Castaneda et al.
2008): the complaint is real, the distress is real, and the deficit it names is
not the one the instruments find.

**Sensory processing is the one place the two agree** — self-report 45.83 and a
15.2%-late N100 both point the same way. That makes the sensory finding the most
robust in the battery, and it is the one the vendor also scored as deviant.

**Mood inverts**: the objective instrument reads *worse* than the self-report
scale. PHQ-9 12 with GAD-7 13 and PCL-C 49 is a heavier load than a
17-out-of-100 self-rating conveys.

Two limitations of this table, stated because they change how far it can be
pushed:

**The P3a row understates itself.** P3a amplitude 17.26 µV has a `sdev` of
−0.34, which looks unremarkable, because the reference is really one-sided
(≥ 6 µV) and the pseudo-z needs a band, so an artificial upper edge of 40 µV
puts the band centre at 23 and a genuinely excellent amplitude below it. The
`dist` column has no such problem — it reads −187.7%, i.e. deep inside
reference — which is why `dist` and not `sdev` is what the ladder ranks on. Read
this row's gap as directionally right and numerically conservative.

**The memory row pairs weakly matched constructs.** Peak alpha frequency is a
defensible correlate of memory performance (Grandy et al. 2013; Klimesch's work
on alpha and semantic memory) but it is not a memory test, and PAF here is
elevated for reasons the arousal hypothesis explains better. That row is the
weakest in the table and should not be quoted without this sentence.

`stats::measureDissonance` is deliberately given an explicit
`objGoodDirection` argument per pair rather than inferring it from the metric's
polarity: getting the sign wrong here would invert a clinical reading, and an
inference that subtle should be written down at every call site.

---

## 5. Synthesis

A 31-year-old, strongly atopic, tested in pollen season on unrecorded
medication, presenting with attention complaints, whose record shows:

1. **No electrophysiological ADHD signature.** Vendor screen negative at 90%
   confidence; independent concordance scoring puts the ADHD hypothesis at
   p = 0.17. The theta:beta flag that would support it is 4% over a threshold
   whose normative tables the report says do not cover this age.

2. **Preserved capacity, degraded timing.** P3a amplitude at 2.9× floor,
   commission 2.45%, omission 8.57% — against N100 +15.2%, RT +17.6%, RT SD
   +86.1%. Fatigue/arousal-cost profile, not resource-deficit profile.

3. **A P3a/P3b amplitude inversion at 0.382 against a stated 0.50 floor**, which
   describes the presenting complaint better than anything the report flagged,
   and which the report never computed.

4. **Cortical and autonomic over-arousal that agree with each other.** Central
   alpha2 z = +2.18 and beta1 z = +1.92, PAF at the ceiling of its band, against
   VLF/LF 1.173, LF/HF 3.686, HF fraction 11.1%. Two independent modalities,
   same direction, coherent with GAD-7 13 and PCL-C 49.

5. **Substantial atopy (26/58) with an unresolved pharmacological confound.**
   H1-antagonists and untreated rhinitis both slow psychomotor speed and blunt
   early sensory ERPs; the medication field says UNKNOWN; the test date sits in
   ragweed and mugwort season. This is the largest uncontrolled variable in the
   battery and the cheapest to resolve.

6. **A quality floor under all of it.** 15 of 19 channels, no source
   localisation, a 2-minute HRV epoch, and an unread 12-lead.

The highest-yield next step is not another instrument. It is repeating the
existing cognitive block under two controlled conditions — off antihistamine,
out of season — and, separately, treating the mood and sleep findings and
re-measuring RT and RT variability. Between them those two moves discriminate
among H1, H2 and H4, which is more than a second battery on the same afternoon
would have done.

---

## 6. Sources

Every citation in `data/prior-graph.json` is drawn from the reference lists of
the two vendor reports themselves — Evoke r5.9.1 (34 numbered references on the
Comprehensive Report's final page, indices into a 150-entry clinician's manual)
and Firefly Brain Insights (23 references). The prior graph is therefore scored
against the same literature the vendors used to generate their flags, which is
the fairest available test: it cannot be accused of picking a friendlier
evidence base than the reports it is checking.
