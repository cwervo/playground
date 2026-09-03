# NY heat deaths by age cohort, matched to wet-bulb depression — summer 2026

Published page: https://claude.ai/code/artifact/da30fd07-9aa3-408a-adf3-cf4d3b139e09

## The short version

Summer 2026 heat mortality for New York **has not been published by age cohort, and will
not be for about a year.** NYC DOHMH counts heat deaths annually in arrears: the *2026*
Heat-Related Mortality Report, released this June, covers deaths through **2025**. The only
summer-2026 figure on the record is the OCME's three accidental-hyperthermia rulings from
the early-July heat wave, released without ages.

So this analysis runs the match in the direction the evidence actually supports. Every age
cohort has a **published critical wet-bulb limit** — the wet bulb above which the body can
no longer shed heat at rest — and those limits are measured per cohort. Summer 2026's
observed heat and humidity are tested against them directly.

**Finding.** At the 79 °F dew point New York recorded on 7 August 2026, every air
temperature from 82–94 °F yields a wet bulb at or above the older-adult critical limit
(26–28 °C), and none comes within 2 °C of the young-adult limit (30.6 °C). That 82–94 °F
window is the band DOHMH identifies as producing the large majority of the city's heat
deaths — hot but unremarkable days that trigger no warning.

## Files

| File | What it is |
|---|---|
| `psychro.py` | Wet bulb (Stull 2011), RH↔dew point (Magnus–Tetens), NWS heat index + numeric inverse |
| `analysis.py` | The analysis; writes `data.json`, prints a text summary |
| `data.json` | Full output |
| `chart-data.json` | Trimmed series for the page |
| `index.html` | The published page |

```
python3 analysis.py
```

## Provenance tiers

Every figure on the page carries one, because they are not equally solid.

- **A · Observed** — official statistic or reported observation.
- **B · Published** — peer-reviewed / agency research finding.
- **C · Derived** — computed here from tier-A inputs. Pure physics.
- **Not yet published** — stated as absent rather than filled in.

## What was deliberately not done

An earlier draft allocated the ~500 annual NYC heat deaths across cohorts as
`population × baseline mortality × (RR − 1)`. It returned **96 % of deaths to the 65+
group** — more concentrated than any published figure — because it compounded four
modelled assumptions. It was removed rather than shipped with a caveat. **No per-cohort
death count is asserted anywhere.**

Where humidity was not reported alongside a temperature (Central Park's 100 °F on 2 July,
LaGuardia's record 104 °F on 3 July), no wet bulb is computed. The 7 August marker is a
floor, not an estimate: wet bulb can never fall below dew point, so a 79 °F dew point puts
the wet bulb at ≥ 26.1 °C with no assumption at all.

## Validation

Stull reproduces the paper's worked example exactly (25 °C, 50 % RH → 18.0 °C). The
Rothfusz heat index returns 105.2 °F at 95 °F / 50 % against the NWS table's 107 °F, within
the regression's stated ±1.3 °F band.

## What would make this exact

Three sources would replace the derived parts with observations. All were unreachable from
the session that produced this (egress policy blocked every non-GitHub host):

- **NYC Environment & Health Data Portal**, heat-report appendix — per-cohort mortality tables.
- **NYS Heat Risk and Illness Dashboard** — near-real-time heat-related ED visits by age group.
- **NOAA hourly observations** for KNYC / KLGA — would replace five reported events with a
  full 92-day wet-bulb series.

## Sources

- NYC DOHMH, *2026 Heat-Related Mortality Report* — 21 heat-stress deaths in 2025 (19 in one
  June heat wave), ~500 heat-related deaths/yr, the 82–94 °F finding, the age gradient
  (lowest ≤ 20, highest 60+), no home AC as the dominant risk factor.
- NYC OCME via Spectrum News NY1, 6 Jul 2026 — three hyperthermia deaths.
- NWS / press-reported station observations, KNYC and KLGA, Jul–Aug 2026.
- Vecellio et al. 2022, *J Appl Physiol* (PSU HEAT) — young-adult critical wet bulb 30.6 °C, humid.
- Vecellio et al. 2023, *Commun Earth Environ* — older-adult critical limits, shifted leftward.
- NYS time-stratified case-crossover, 2025 — 85+ relative risk 1.83 (1.71–1.96).
- Stull 2011, *J Appl Meteor Climatol* 50(11):2267–2269 — wet-bulb approximation.
