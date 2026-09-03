"""
Summer 2026 NYC heat: exposure (wet-bulb) matched to age-cohort mortality risk.

PROVENANCE TIERS -- every number carries one. Nothing is presented as observed
that was not actually observed.

  A  OBSERVED    Official/press-reported observation or an official statistic.
  B  PUBLISHED   Peer-reviewed or agency-published research finding.
  C  DERIVED     Computed by this script from tier-A inputs (pure physics).
  D  MODELLED    An allocation/scenario built on A+B. NOT an observation.

Run:  python3 analysis.py   ->  writes data.json and prints a summary.
"""
import json, math
from psychro import (f_to_c, c_to_f, rh_from_dewpoint, dewpoint_from_rh,
                     wet_bulb_stull, wet_bulb_depression, heat_index_f,
                     rh_from_heat_index)

# ---------------------------------------------------------------------------
# 1. Summer 2026 NYC heat events  (tier A observations; tier C computations)
# ---------------------------------------------------------------------------
# Only conditions that were actually reported are entered. Where humidity was
# not reported alongside temperature, the field is None and no wet bulb is
# computed -- we report a bound instead of inventing a number.

EVENTS = [
    dict(id="jul02", date="2026-07-02", station="Central Park (KNYC)",
         label="First 100 degF since 2012",
         t_f=100.0, td_f=None, hi_f=None,
         note="Tied the July 2 record set in 1966; first triple-digit reading "
              "in Central Park since 2012.",
         source="press/NWS-reported observation"),
    dict(id="jul03cp", date="2026-07-03", station="Central Park (KNYC)",
         label="Peak heat index 106 degF",
         t_f=None, td_f=None, hi_f=106.0,
         note="Heat index reported at 106 degF Thursday afternoon. Air "
              "temperature not separately reported, so the wet bulb is given "
              "as the range consistent with that heat index.",
         source="press-reported NWS heat index"),
    dict(id="jul03lga", date="2026-07-03", station="LaGuardia (KLGA)",
         label="All-time July record 104 degF",
         t_f=104.0, td_f=None, hi_f=None,
         note="Broke the previous 101 degF record set in 1966 by 3 degF.",
         source="press/NWS-reported observation"),
    dict(id="jul04mid", date="2026-07-04", station="LaGuardia (KLGA)",
         label="Record-warm midnight, 94 degF",
         t_f=94.0, td_f=70.0, hi_f=None,
         note="Highest midnight temperature in the station's record. Overnight "
              "temperatures held 88-91 degF with dew points above 70 degF. "
              "Dew point taken at its reported floor, so the wet bulb below is "
              "a MINIMUM.",
         source="press/NWS-reported observation"),
    dict(id="aug07", date="2026-08-07", station="New York City",
         label="Dew point 79 degF, 1 degF off all-time record",
         t_f=None, td_f=79.0, hi_f=None,
         note="Air temperature not reported with it. Because T_wb is always "
              ">= T_dew, this dew point alone puts a hard floor under the wet "
              "bulb with no assumption required.",
         source="press-reported observation"),
]

def enrich(ev):
    """Tier C: compute what the physics permits, and nothing more."""
    out = dict(ev)
    t_f, td_f, hi_f = ev["t_f"], ev["td_f"], ev["hi_f"]

    if t_f is not None and td_f is not None:
        t_c, td_c = f_to_c(t_f), f_to_c(td_f)
        rh = rh_from_dewpoint(t_c, td_c)
        twb = wet_bulb_stull(t_c, rh)
        out.update(rh=rh, twb_c=twb, twb_f=c_to_f(twb),
                   depression_c=t_c - twb, depression_f=(t_f - c_to_f(twb)),
                   basis="T + dew point", exact=True)

    elif t_f is None and td_f is not None:
        # Only a dew point. T_wb >= T_dew is exact and assumption-free.
        out.update(rh=None, twb_c=f_to_c(td_f), twb_f=td_f,
                   depression_c=None, depression_f=None,
                   basis="dew point only -> wet-bulb FLOOR", exact=False,
                   bound="lower")

    elif t_f is not None and td_f is None and hi_f is None:
        out.update(rh=None, twb_c=None, twb_f=None,
                   depression_c=None, depression_f=None,
                   basis="temperature only -- humidity not reported, no wet bulb",
                   exact=False)

    elif hi_f is not None:
        # Invert the Rothfusz regression across plausible air temperatures to
        # get the (T, RH) locus consistent with the reported heat index.
        locus = []
        for t in range(94, 102):
            rh = rh_from_heat_index(float(t), hi_f)
            if rh is None or not (5.0 <= rh <= 100.0):
                continue
            t_c = f_to_c(float(t))
            twb = wet_bulb_stull(t_c, rh)
            locus.append(dict(t_f=float(t), rh=rh, twb_c=twb, twb_f=c_to_f(twb),
                              depression_c=t_c - twb))
        out.update(locus=locus, exact=False, basis="heat index inverted -> (T,RH) locus",
                   twb_c=(min(p["twb_c"] for p in locus) if locus else None),
                   twb_c_max=(max(p["twb_c"] for p in locus) if locus else None))
    return out

events = [enrich(e) for e in EVENTS]

# ---------------------------------------------------------------------------
# 2. The band that actually kills people (tier A framing, tier C physics)
# ---------------------------------------------------------------------------
# NYC DOHMH: the large majority of heat-exacerbated deaths occur on days that
# are merely hot -- 82-94 degF -- not on the record-breaking days. This section
# shows why, in wet-bulb terms: across that band, humidity, not temperature,
# governs how much evaporative headroom a body has.

DEWPOINTS_F = [60, 65, 70, 74, 79]   # 79 = the Aug 7 2026 NYC observation
TEMPS_F = list(range(80, 105, 1))

depression_curves = []
for td_f in DEWPOINTS_F:
    pts = []
    for t_f in TEMPS_F:
        if t_f <= td_f:
            continue
        t_c, td_c = f_to_c(t_f), f_to_c(td_f)
        rh = rh_from_dewpoint(t_c, td_c)
        if rh < 5:
            continue
        twb = wet_bulb_stull(t_c, rh)
        pts.append(dict(t_f=t_f, rh=round(rh, 1),
                        twb_c=round(twb, 2), twb_f=round(c_to_f(twb), 1),
                        depression_c=round(t_c - twb, 2),
                        depression_f=round(t_f - c_to_f(twb), 2),
                        hi_f=round(heat_index_f(float(t_f), rh), 1)))
    depression_curves.append(dict(dewpoint_f=td_f, points=pts))

# ---------------------------------------------------------------------------
# 3. Age-cohort critical environmental limits (tier B, published)
# ---------------------------------------------------------------------------
# PSU HEAT Project. Young healthy adults: critical wet bulb ~30.6 degC in
# warm-humid conditions at minimal activity -- well below the theorised 35 degC.
# Older adults: compensability curves shift leftward; critical limits in humid
# conditions fall to roughly 26-28 degC at minimal activity.
COHORT_LIMITS = [
    dict(cohort="Young healthy adults (18-40)", twb_crit_c=30.6, twb_crit_lo=30.6,
         twb_crit_hi=30.6, tier="B",
         source="Vecellio et al. 2022, J Appl Physiol (PSU HEAT) -- humid, RH>50%, minimal activity"),
    dict(cohort="Older adults (65+)", twb_crit_c=27.0, twb_crit_lo=26.0,
         twb_crit_hi=28.0, tier="B",
         source="Vecellio et al. 2023, Commun Earth Environ -- older-adult limits, humid, minimal activity"),
]

# ---------------------------------------------------------------------------
# 4. Age cohorts (tier A population; tier B risk anchors)
# ---------------------------------------------------------------------------
# NOTE ON WHAT IS *NOT* HERE. An earlier version of this script allocated the
# ~500 annual NYC heat deaths across cohorts by multiplying population x
# baseline mortality x (RR-1). It returned 96% of deaths to the 65+ group --
# more concentrated than any published figure -- because it stacked four
# modelled assumptions. It has been removed rather than shipped with a caveat.
# DOHMH has not published a per-cohort count this analysis could retrieve, so
# no per-cohort death count is asserted here.
#
# What IS defensible is the physiological mapping: each cohort has a published
# critical wet-bulb limit, and summer 2026's observed wet bulbs can be tested
# against those limits directly. That is section 5.

COHORTS = [
    dict(cohort="0-17",  pop=1_760_000, share_pop=0.200),
    dict(cohort="18-44", pop=3_520_000, share_pop=0.400),
    dict(cohort="45-64", pop=2_110_000, share_pop=0.240),
    dict(cohort="65-74", pop=  800_000, share_pop=0.091),
    dict(cohort="75-84", pop=  440_000, share_pop=0.050),
    dict(cohort="85+",   pop=  174_000, share_pop=0.020),
]
# Published NY relative risks this analysis could actually retrieve:
RR_PUBLISHED = {"85+": dict(rr=1.83, ci=[1.71, 1.96],
                            source="NYS time-stratified case-crossover (2025)")}
for c in COHORTS:
    pub = RR_PUBLISHED.get(c["cohort"])
    c["rr_published"] = pub["rr"] if pub else None
    c["rr_ci"] = pub["ci"] if pub else None
    c["rr_source"] = pub["source"] if pub else None
    # Which published critical-limit band this cohort falls under.
    c["limit_band"] = ("older" if c["cohort"] in ("65-74", "75-84", "85+")
                       else "young" if c["cohort"] == "18-44" else "not established")

DOHMH_GRADIENT = ("Heat-stress deaths occur in every age group; rates are lowest "
                  "at ages 20 and under and highest at ages 60 and over. DOHMH "
                  "publishes the shape of the gradient, not per-cohort counts.")

ANNUAL_HEAT_DEATHS = 500   # tier A: NYC DOHMH, "nearly 500 New Yorkers" per year

# ---------------------------------------------------------------------------
# 5. Did summer 2026 cross each cohort's limit?  (tier C on tier A+B)
# ---------------------------------------------------------------------------
OLDER_LO, OLDER_HI, YOUNG = 26.0, 28.0, 30.6

def classify(twb_c):
    if twb_c is None: return None
    if twb_c >= YOUNG:    return "exceeds young-adult limit"
    if twb_c >= OLDER_HI: return "exceeds older-adult limit"
    if twb_c >= OLDER_LO: return "within older-adult limit band"
    return "below both limits"

crossings = []
for e in events:
    twb = e.get("twb_c")
    if twb is None: continue
    hi = e.get("twb_c_max", twb)
    crossings.append(dict(id=e["id"], date=e["date"], station=e["station"],
                          label=e["label"], twb_lo_c=twb, twb_hi_c=hi,
                          exact=e.get("exact", False), bound=e.get("bound"),
                          verdict_lo=classify(twb), verdict_hi=classify(hi)))

# How much of the "merely hot" 82-94 degF band sits above the older-adult limit,
# as a function of dew point?
band = []
for cur in depression_curves:
    pts = [p for p in cur["points"] if 82 <= p["t_f"] <= 94]
    over_lo = [p for p in pts if p["twb_c"] >= OLDER_LO]
    over_hi = [p for p in pts if p["twb_c"] >= OLDER_HI]
    band.append(dict(dewpoint_f=cur["dewpoint_f"], n=len(pts),
                     frac_over_older_lo=len(over_lo)/len(pts) if pts else 0.0,
                     frac_over_older_hi=len(over_hi)/len(pts) if pts else 0.0,
                     frac_over_young=0.0,
                     twb_at_90=next((p["twb_c"] for p in pts if p["t_f"]==90), None),
                     depression_at_90=next((p["depression_c"] for p in pts if p["t_f"]==90), None)))

# ---------------------------------------------------------------------------
# 6. Emit
# ---------------------------------------------------------------------------
data = dict(
    generated="2026-09-03",
    events=events,
    depression_curves=depression_curves,
    cohort_limits=COHORT_LIMITS,
    cohorts=COHORTS,
    dohmh_gradient=DOHMH_GRADIENT,
    annual_heat_deaths=ANNUAL_HEAT_DEATHS,
    crossings=crossings,
    band_analysis=band,
    limits=dict(older_lo=OLDER_LO, older_hi=OLDER_HI, young=YOUNG),
    confirmed_2026=dict(
        ocme_hyperthermia_deaths=3,
        note="NYC OCME ruled 3 deaths accidental hyperthermia during the early-July "
             "2026 heat wave; all died at home. No age breakdown has been released. "
             "The full summer-2026 toll, including heat-exacerbated deaths, is not "
             "expected until the 2027 DOHMH Heat-Related Mortality Report.",
        tier="A"),
)
with open("data.json", "w") as fh:
    json.dump(data, fh, indent=2)

print("SUMMER 2026 NYC EVENTS -- wet bulb where the physics permits")
print("-" * 80)
for e in events:
    line = f"{e['date']}  {e['station'][:20]:<20}"
    if e.get("twb_c") is not None and e.get("exact"):
        line += f" Twb {e['twb_c']:5.1f}C  depression {e['depression_c']:4.1f}C"
    elif e.get("bound") == "lower":
        line += f" Twb >={e['twb_c']:5.1f}C  [floor from dew point alone]"
    elif e.get("locus"):
        line += f" Twb {e['twb_c']:5.1f}-{e['twb_c_max']:.1f}C  [locus from heat index]"
    else:
        line += "  -- humidity not reported, no wet bulb computed"
    print(line)

print()
print("CROSSINGS vs PUBLISHED AGE-COHORT CRITICAL LIMITS")
print(f"  older adults 65+ : {OLDER_LO}-{OLDER_HI} C wet bulb   young adults 18-40 : {YOUNG} C")
print("-" * 80)
for c in crossings:
    rng = f"{c['twb_lo_c']:.1f}" + (f"-{c['twb_hi_c']:.1f}" if c['twb_hi_c'] > c['twb_lo_c'] else "")
    print(f"  {c['date']}  Twb {rng:>11}C  -> {c['verdict_hi']}")

print()
print("THE 82-94 degF BAND (where DOHMH says most heat deaths happen)")
print("-" * 80)
print(f"{'dew pt':>7} {'Twb@90F':>9} {'headroom@90F':>13} {'% of band >= older-adult limit':>32}")
for b in band:
    print(f"{b['dewpoint_f']:>6}F {b['twb_at_90']:>8.1f}C {b['depression_at_90']:>12.1f}C "
          f"{b['frac_over_older_lo']*100:>28.0f}%")

print()
print("AGE COHORTS -- population and the risk anchors that are actually published")
print("-" * 80)
print(f"{'cohort':>7} {'population':>11} {'pop share':>10} {'published RR':>14} {'limit band':>18}")
for c in COHORTS:
    rr = f"{c['rr_published']:.2f}" if c['rr_published'] else "not published"
    print(f"{c['cohort']:>7} {c['pop']:>11,} {c['share_pop']*100:>9.1f}% {rr:>14} {c['limit_band']:>18}")
print(f"\n  {DOHMH_GRADIENT}")
