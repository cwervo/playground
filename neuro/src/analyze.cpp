// analyze.cpp — the whole numeric pass, exactly once.
//
// Reads  neuro/data/session-*.json  and  neuro/data/prior-graph.json
// Writes build/dashboard.nvm  (bytecode display file, the thing hosts execute)
//        build/derived.json    (same numbers in text, for diffing and for Tcl)
//
// Usage:
//   analyze --session data/session-2026-08-18.json
//           --prior   data/prior-graph.json
//           --out     build/dashboard.nvm
//           --json    build/derived.json
//           [--perm 200000] [--seed 20260818] [--deidentify]
//
// The engine does four things, in this order, and nothing else:
//   1. normalise heterogeneous instruments onto a common signed axis
//   2. compute the composites the vendor reports describe but never print
//   3. score the literature prior graph against the observed pattern, with a
//      permutation null
//   4. emit a display file that carries the numbers, the drawing, and the
//      argument together
#include <cmath>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <iostream>
#include <map>
#include <set>
#include <sstream>
#include <string>
#include <vector>

#include "json.hpp"
#include "nvm.hpp"
#include "stats.hpp"

using stats::Polarity;
using stats::Reading;
using stats::Ref;

// ---------------------------------------------------------------------------
// Design tokens. Kept here rather than in each host so that the plotter, the Tk
// window and the browser cannot drift apart. Values are the light-theme ink;
// hosts that render dark invert lightness and keep hue, which is why every
// colour below is specified with a deliberate mid lightness rather than a
// near-black or near-white.
// ---------------------------------------------------------------------------
namespace ink {
struct C { int r, g, b; };
// Contrast ratios are against the light-theme page ground #f6f7f9, which is
// what these were authored for; every host that renders dark inverts lightness
// and keeps hue, which preserves the ratios. Text-weight colours clear WCAG AA
// 4.5:1. kBorder is the one place chrome and canvas differ: the amber a bar is
// FILLED with only has to clear the 3:1 non-text standard, while the amber a
// margin figure is SET IN has to clear 4.5:1, so the emitter carries both.
constexpr C kFg        = {  24,  26,  32 };  // 16.4:1
constexpr C kMuted     = {  98, 104, 121 };  //  5.2:1
constexpr C kRule      = { 208, 212, 222 };  // rules only, never text
constexpr C kOk        = {  44, 111,  95 };  //  5.5:1
constexpr C kBorder    = { 196, 138,  38 };  //  2.8:1 -- FILL ONLY
constexpr C kBorderTxt = { 138,  98,  16 };  //  5.1:1 -- the amber for type
constexpr C kDeviant   = { 190,  70,  62 };  //  4.7:1
constexpr C kNoData    = { 143, 148, 162 };
constexpr C kAccent    = {  58,  96, 190 };  //  5.5:1
constexpr C kSubjective= { 118,  70, 166 };

inline C severityColour(int sev) {
    switch (sev) {
        case 0:  return kOk;
        case 1:  return kBorder;
        case 2:  return kDeviant;
        default: return kNoData;
    }
}
}  // namespace ink

// ---------------------------------------------------------------------------
static std::string slurp(const std::string& path) {
    std::ifstream f(path, std::ios::binary);
    if (!f) {
        std::cerr << "analyze: cannot open " << path << "\n";
        std::exit(2);
    }
    std::ostringstream ss;
    ss << f.rdbuf();
    return ss.str();
}

static Polarity polarityOf(const std::string& s) {
    if (s == "lower_better")  return Polarity::LowerBetter;
    if (s == "higher_better") return Polarity::HigherBetter;
    if (s == "band")          return Polarity::Band;
    return Polarity::None;
}

static uint8_t domainId(const std::string& d) {
    if (d == "subjective")   return 0;
    if (d == "psychometric") return 1;
    if (d == "behavioral")   return 2;
    if (d == "eeg" || d == "eeg_z") return 3;
    if (d == "erp")          return 4;
    if (d == "autonomic" || d == "cardiac") return 5;
    if (d == "immune")       return 6;
    return 7;  // derived
}

static std::string fmt(double v, int dp = 2) {
    char buf[64];
    std::snprintf(buf, sizeof buf, "%.*f", dp, v);
    return buf;
}

static std::string jsonEscape(const std::string& s) {
    std::string out;
    for (char c : s) {
        switch (c) {
            case '"':  out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n";  break;
            case '\t': out += "\\t";  break;
            case '\r': break;
            default:   out += c;      break;
        }
    }
    return out;
}

// ---------------------------------------------------------------------------
// Dual-register explanation. Every anchored element in the display file carries
// both a plain-language line and a full-fat one; the host chooses which to show
// and can show both. Keeping them adjacent in the source is deliberate: it is
// very hard to let the plain version drift into vagueness when the technical
// version is on the next line.
// ---------------------------------------------------------------------------
struct Explanation { std::string plain, full; };
static std::map<std::string, Explanation> gExplain;

static void explain(const std::string& id, const std::string& plain, const std::string& full) {
    gExplain[id] = {plain, full};
}

static void loadExplanations() {
    explain("srs.exec_attn",
            "You rated your own focus and organisation near the bottom of the scale.",
            "Self-report executive/attention composite = 8.33/100 against a >=61 reference, i.e. 86% below "
            "threshold. Subjective executive complaint is only weakly coupled to objective inhibitory "
            "performance in adults (Barkley 1997; Wright 2014) and loads heavily on concurrent mood "
            "(Castaneda 2008; Gifford 2015). Read alongside beh.commission and erp.p3a_amp before "
            "treating it as an executive finding.");
    explain("srs.affect",
            "You rated your mood as low, and the questionnaires agree.",
            "Self-report affect composite = 16.67/100. Converges with PHQ-9 12 (moderate) and GAD-7 13 "
            "(moderate). Unlike the executive domain this one has objective corroboration, so it is a "
            "concordant rather than a dissociated finding.");
    explain("psy.phq9",
            "A standard depression questionnaire, scoring in the moderate range.",
            "PHQ-9 = 12/27. 10-14 is the moderate band; the instrument's own guidance at this score is "
            "treatment plan with follow-up, and item 9 warrants a direct risk question (Kroenke 2001). "
            "The vendor report also flags this and recommends a risk assessment.");
    explain("psy.gad7",
            "A standard anxiety questionnaire, also in the moderate range.",
            "GAD-7 = 13/21. >=10 has sensitivity 0.89 / specificity 0.82 for GAD (Spitzer 2006). "
            "Mechanistically relevant here because anxious arousal is the most parsimonious single "
            "explanation for the VLF-dominant HRV plus elevated central beta1 seen below.");
    explain("psy.pclc",
            "A PTSD symptom checklist, elevated but under the usual cut-off.",
            "PCL-C = 49, against the 17-85 range and a conventional civilian cut of 50. Sitting one point "
            "below a cut-off is not evidence of absence: the score is 67% above the <=29 normal ceiling. "
            "Relevant to the EEG because raised peak alpha frequency and raised HF-HRV have both been "
            "reported in PTSD (Wahbeh & Oken 2013), and PAF here is at the top of the reference band.");
    explain("beh.rt",
            "You pressed the button about 88 ms slower than the slowest expected time.",
            "Mean reaction time 588.12 ms on a go/no-go task against a 200-500 ms reference: 17.6% past "
            "the upper edge. Isolated RT slowing with intact accuracy is a fatigue/arousal-cost signature "
            "rather than a resource-deficit one (Behrens 2023; Salthouse 1996). Antihistamines and "
            "untreated allergic rhinitis both independently slow psychomotor speed, and medications were "
            "not recorded at this visit.");
    explain("beh.rt_sd",
            "Your response times were uneven, roughly twice as variable as expected.",
            "Intra-individual RT standard deviation 18.61 ms against <=10 ms, i.e. 86% past threshold. "
            "RT variability is the single most replicated behavioural marker across ADHD and many other "
            "conditions and is better read as a general attentional-stability index than a diagnostic one "
            "(Kofler 2013 meta-analysis of 319 studies; Karalunas 2014 trans-diagnostic argument).");
    explain("beh.commission",
            "You rarely pressed when you should not have. Impulse control tested well.",
            "Commission error rate 2.45% against <=3%. Combined with P3a amplitude at 17.26 uV this is "
            "direct evidence against an inhibitory-control deficit, and it is the observation that most "
            "sharply contradicts the self-reported executive score.");
    explain("beh.omission",
            "You rarely missed a target you should have hit.",
            "Omission rate 8.57% against <=10%. Inside reference but with only 1.4 points of margin; "
            "omissions are the CPT index most sensitive to sustained-attention lapse, so the margin is "
            "worth carrying forward rather than rounding to 'normal'.");
    explain("eeg.tbr_eo",
            "A brainwave ratio often quoted for ADHD. Yours is 4% over the line.",
            "Theta:beta ratio 2.190 against <2.1 (eyes open, midline-central). Two independent reasons not "
            "to weight this: the Monastra normative tables the threshold derives from do not extend past "
            "age 31, which the report itself states; and TBR is a ratio, so a low beta denominator inflates "
            "it without any theta excess. Central beta1 z here is +1.92, i.e. beta is high, which makes a "
            "denominator artefact unlikely but also makes the elevated ratio harder to read as slowing. "
            "Meta-analytic support for TBR as an ADHD marker has weakened substantially (Arns 2013).");
    explain("eeg.paf_ec",
            "Your resting alpha rhythm is slightly faster than the top of the usual range.",
            "Peak alpha frequency 11.10 Hz eyes-closed occipital against 8.9-11.0 Hz: 0.9% past the edge, "
            "which is within the frequency resolution of a 1 Hz-binned spectrum. High PAF is associated "
            "with good semantic memory and with CNS over-arousal, insomnia and hypervigilance; the "
            "surrounding evidence here favours the second reading (Angelakis 2004; Grandy 2013).");
    explain("eegz.c.alpha2",
            "One brainwave band over the top of your head is clearly elevated.",
            "Central alpha2 (10-12.5 Hz) z = +2.18 eyes closed. This is the largest single EEG deviation in "
            "the record and the only band past 2 SD. Elevated central alpha2 at rest is described as a "
            "'readiness' or pre-motor idling state, normal in athletes mid-task and unhelpful at rest, "
            "where it is associated with hypervigilance and disturbed sleep.");
    explain("eegz.c.beta1",
            "A faster brainwave band is also running high, close to the cut-off.",
            "Central beta1 (12.5-25 Hz) z = +1.92, just inside 2 SD. Elevated central beta with elevated "
            "alpha2 and a VLF-dominant HRV spectrum is a coherent cortical-plus-autonomic over-arousal "
            "picture, and it is the pattern that anxiolytic or sleep-directed intervention would target.");
    explain("erp.p3a_lat",
            "Your brain's 'something new happened' response arrived 18 ms late.",
            "P300a latency 468 ms at Cz to a checkerboard/novelty stimulus against <450 ms: 4% past "
            "threshold, roughly one to two samples at typical acquisition rates. P3a indexes involuntary "
            "orienting and novelty evaluation (Friedman 2001; Polich 2007). A 4% latency excess with a "
            "large amplitude is a timing finding, not a capacity finding.");
    explain("erp.p3a_amp",
            "That same response was unusually strong. Novelty grabs your attention well.",
            "P300a amplitude 17.26 uV against >=6 uV, i.e. nearly three times the floor. Large P3a with "
            "normal commission errors is the clearest single piece of evidence against the ADHD "
            "hypothesis in this record.");
    explain("erp.p3b_ratio",
            "The follow-through response is weak compared to the initial grab: 38% where 50% is the floor.",
            "P3b/P3a amplitude ratio = 6.6/17.26 = 0.382 against the vendor's own stated >50% criterion, "
            "i.e. 23.5% short. The vendor states this criterion in prose on the ERP page and never prints "
            "the quotient anywhere in 17 pages. P3a is frontally-generated orienting; P3b is "
            "temporal-parietal context updating and memory consolidation (Polich 2007; Linden 2005). "
            "A loud P3a with a quiet P3b is the electrophysiological form of 'I get pulled toward new "
            "things and then lose the thread', and it maps onto the self-reported complaint far better "
            "than the theta:beta ratio does.");
    explain("erp.n100_lat",
            "The first visual response of your brain arrives about 38 ms late.",
            "N100 latency 288 ms at O2 to checkerboard reversal against <250 ms: 15.2% past threshold, the "
            "largest ERP deviation here and one of only three findings past the 15% borderline cut. N100 "
            "is early sensory registration, largely pre-attentive (Naatanen & Picton 1987). A delay this "
            "early propagates into every downstream latency, which is why the timing chain panel shows "
            "the deficit accumulating rather than appearing at one stage.");
    explain("ans.vlf_ratio",
            "The slowest part of your heart-rhythm signal dominates, which usually means a stress load.",
            "VLF/LF = 1115/951 = 1.173 against the vendor's >0.5 flag threshold, i.e. 135% past. This "
            "reproduces the 'value = 1.17' quoted in the report's neuroinflammation domain. VLF power over "
            "short recordings is a slow-recovery/allostatic-load component and is the HRV band most "
            "consistently associated with inflammatory markers (Usui & Nishida 2017; Shaffer & Ginsberg "
            "2017). Note the 2-minute epoch: VLF is poorly estimated below ~5 minutes and the absolute "
            "figure should be treated as indicative.");
    explain("ans.lf_hf",
            "Your sympathetic/parasympathetic balance sits about 3.7:1 toward the accelerator.",
            "LF/HF = 951/258 = 3.686 against a nominal 0.5-2.0. The LF/HF ratio as a sympathovagal index "
            "is contested and LF is not purely sympathetic, but the direction is corroborated here by an "
            "independent measure: HF is only 11.1% of total power.");
    explain("ans.hf_frac",
            "The 'brake' band of your heart rhythm is a small share of the total.",
            "HF fraction = 258/2323.9 = 11.1% against a nominal >=15%. HF power is respiratory sinus "
            "arrhythmia and is the cleanest non-invasive vagal index available. Low HF fraction alongside "
            "a perfectly normal SDNN of 82.09 ms is the useful nuance: total variability is fine, its "
            "distribution across bands is not, which is exactly what the spectral entropy figure captures.");
    explain("ans.sdnn",
            "Overall heart-rate variability is healthy.",
            "SDNN 82.09 ms against 36-100 ms, comfortably mid-band, and HRV total power 2323.9 ms^2 "
            "against >=800. This is why the vendor scored arousal regulation as normal. The band split "
            "below is where the abnormality actually lives; a single-number HRV summary would have missed "
            "it entirely.");
    explain("spt.burden",
            "26 of the 58 allergens tested came back positive. That is a high sensitisation load.",
            "44.8% of the non-control panel (26/58) produced a wheal >=3 mm, against a nominal <=15%. Histamine "
            "control 7 mm and glycerin control 0 mm, so the panel is technically valid and the reactions "
            "are real rather than dermographic. Strongly polysensitised to tree pollen (max 15 mm: black "
            "walnut, shagbark hickory, eastern oak), grasses (Timothy 15 mm) and dust mite (11 mm).");
    explain("spt.seasonal",
            "The test was done in mid-August, in the middle of ragweed and mugwort season.",
            "Test date 2026-08-18, New York. Mugwort 9 mm and ragweed 5 mm are in season at that date, so "
            "the subject was plausibly symptomatic and plausibly medicated during the same visit that "
            "produced the EEG, ERP and reaction-time data. Medications field reads UNKNOWN. First- and "
            "even second-generation H1 antagonists slow reaction time and blunt early sensory ERPs. This "
            "is the single largest uncontrolled confound in the battery and it is cheap to resolve: "
            "repeat the cognitive block off antihistamine, out of season.");
    explain("eeg.quality",
            "Four of nineteen sensors were unusable, so the brain-location analysis was switched off.",
            "FZ, T8, P3 and P8 rejected; 15/19 reliable channels against the 18-channel minimum for the "
            "vendor's LORETA source localisation, which was therefore suppressed on both eyes-open and "
            "eyes-closed runs. The rejected set includes the midline frontal electrode, which is the one "
            "most directly relevant to the anterior-cingulate claims the theta:beta and P3a discussions "
            "rest on. Any regional interpretation in this record is inference from a reduced montage.");
    explain("ecg.overread",
            "The heart tracing reads as a normal variant, but no doctor's signature is on this copy.",
            "12-lead: sinus bradycardia at 57 bpm with anterolateral ST elevation reported as a "
            "repolarisation variant; machine verdict PROBABLY NORMAL; comment field reads 'Unconfirmed "
            "Report'. Benign early repolarisation is common in young men and the intervals are "
            "unremarkable (PR 136, QRS 88, QTc 393). The actionable item is administrative rather than "
            "cardiological: obtain the physician overread.");
    explain("H1", "Is the body's stress system running hot?",
            "Sympathetic over-arousal / hypervigilance cluster.");
    explain("H2", "Is everything just running late rather than running badly?",
            "Timing slowed with capacity preserved; fatigue/arousal-cost profile.");
    explain("H3", "Is low mood driving how bad the thinking feels?",
            "Affective load driving subjective cognitive complaint.");
    explain("H4", "Is an over-active immune system part of the picture?",
            "Allergic/inflammatory systemic load.");
    explain("H5", "Does this look like textbook ADHD electrophysiology?",
            "Classic ADHD electrophysiology; the hypothesis the vendor screened and rejected.");
}

// ---------------------------------------------------------------------------
int main(int argc, char** argv) {
    std::string sessionPath = "data/session-2026-08-18.json";
    std::string priorPath   = "data/prior-graph.json";
    std::string outPath     = "build/dashboard.nvm";
    std::string jsonPath    = "build/derived.json";
    int    permIters = 200000;
    uint64_t seed    = 20260818ull;
    bool   deidentify = false;
    // Sketchpad's constraint drag, as a command-line hook: override a measured
    // value and every composite, every severity, every concordance score and
    // every permutation p-value downstream of it re-derives. tcl/explore.tcl
    // drives this on arrow-key nudge so the analyst can ask "what would have to
    // be different for this conclusion to change" without leaving the view.
    std::map<std::string, double> overrides;

    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        auto next = [&]() -> std::string { return (i + 1 < argc) ? argv[++i] : std::string(); };
        if      (a == "--session")    sessionPath = next();
        else if (a == "--prior")      priorPath   = next();
        else if (a == "--out")        outPath     = next();
        else if (a == "--json")       jsonPath    = next();
        else if (a == "--perm")       permIters   = std::stoi(next());
        else if (a == "--seed")       seed        = std::stoull(next());
        else if (a == "--deidentify") deidentify  = true;
        else if (a == "--override") {
            const std::string spec = next();
            const size_t eq = spec.find('=');
            if (eq == std::string::npos) {
                std::cerr << "analyze: --override wants id=value, got '" << spec << "'\n";
                return 2;
            }
            overrides[spec.substr(0, eq)] = std::stod(spec.substr(eq + 1));
        }
        else if (a == "-h" || a == "--help") {
            std::cout << "usage: analyze [--session f] [--prior f] [--out f.nvm] [--json f]\n"
                         "               [--perm N] [--seed N] [--deidentify]\n"
                         "               [--override id=value] ...\n";
            return 0;
        }
    }

    loadExplanations();

    const nj::Value session = nj::parse(slurp(sessionPath));
    const nj::Value prior   = nj::parse(slurp(priorPath));

    // -----------------------------------------------------------------------
    // 1. Load raw readings
    // -----------------------------------------------------------------------
    std::vector<Reading> readings;
    std::map<std::string, size_t> byId;

    auto addReading = [&](Reading m) {
        auto ov = overrides.find(m.id);
        if (ov != overrides.end()) {
            m.value = ov->second;
            m.valid = true;
            if (m.hasTrueZ) m.trueZ = ov->second;
        }
        stats::derive(m);
        byId[m.id] = readings.size();
        readings.push_back(std::move(m));
    };

    const nj::Value& metrics = session["metrics"];
    for (size_t i = 0; i < metrics.size(); ++i) {
        const nj::Value& mv = metrics[i];
        Reading m;
        m.id     = mv["id"].str();
        m.label  = mv["label"].str();
        m.domain = mv["domain"].str();
        if (mv["value"].isNumber()) {
            m.value = mv["value"].number;
            m.valid = true;
        }
        const nj::Value& r = mv["ref"];
        if (r.isObject() && r["lo"].isNumber() && r["hi"].isNumber()) {
            m.ref.present = true;
            m.ref.lo = r["lo"].number;
            m.ref.hi = r["hi"].number;
            m.ref.pol = polarityOf(mv["polarity"].str());
        }
        if (m.domain == "eeg_z" && m.valid) {
            m.trueZ = m.value;
            m.hasTrueZ = true;
        }
        addReading(std::move(m));
    }

    auto val = [&](const std::string& id) -> double {
        auto it = byId.find(id);
        return (it == byId.end() || !readings[it->second].valid) ? std::nan("")
                                                                 : readings[it->second].value;
    };

    // -----------------------------------------------------------------------
    // 2. Composites the vendor reports describe in prose but never print
    // -----------------------------------------------------------------------
    auto derived = [&](const std::string& id, const std::string& label, const std::string& domain,
                       double v, double lo, double hi, Polarity pol) {
        Reading m;
        m.id = id;
        m.label = label;
        m.domain = domain;
        m.value = v;
        m.valid = std::isfinite(v);
        m.ref.present = true;
        m.ref.lo = lo;
        m.ref.hi = hi;
        m.ref.pol = pol;
        addReading(std::move(m));
    };

    const double vlf = val("ans.vlf"), lf = val("ans.lf"), hf = val("ans.hf"), tp = val("ans.tp");
    derived("ans.vlf_ratio", "VLF / LF power ratio",        "autonomic", vlf / lf,  0.0,  0.5, Polarity::LowerBetter);
    derived("ans.lf_hf",     "LF / HF power ratio",         "autonomic", lf / hf,   0.5,  2.0, Polarity::LowerBetter);
    derived("ans.hf_frac",   "HF share of total power",     "autonomic", hf / tp,   0.15, 0.50, Polarity::HigherBetter);
    derived("ans.vlf_frac",  "VLF share of total power",    "autonomic", vlf / tp,  0.0,  0.35, Polarity::LowerBetter);

    const double p3a = val("erp.p3a_amp"), p3b = val("erp.p3b_amp");
    derived("erp.p3b_ratio", "P3b / P3a amplitude ratio",   "erp", p3b / p3a, 0.50, 2.0, Polarity::HigherBetter);
    derived("erp.timing_sum","Cumulative ERP timing debt",  "erp",
            (val("erp.n100_lat") - 250) + (val("erp.p3a_lat") - 450), -100.0, 0.0, Polarity::LowerBetter);

    // Allergen burden from the skin-prick panel, controls excluded.
    const nj::Value& spt = session["skin_prick"]["results"];
    int nPos = 0, nTested = 0, maxWheal = 0;
    std::map<std::string, int> posByClass, totByClass;
    for (size_t i = 0; i < spt.size(); ++i) {
        const std::string cls = spt[i]["class"].str();
        if (cls == "control") continue;
        const int w = (int)spt[i]["wheal_mm"].num(0);
        ++nTested;
        ++totByClass[cls];
        if (w >= 3) { ++nPos; ++posByClass[cls]; }
        maxWheal = std::max(maxWheal, w);
    }
    derived("spt.burden",    "Share of panel positive",     "immune",
            nTested ? (double)nPos / nTested : std::nan(""), 0.0, 0.15, Polarity::LowerBetter);
    derived("spt.max_wheal", "Largest wheal",               "immune", (double)maxWheal, 0.0, 3.0, Polarity::LowerBetter);

    // Spectral entropy of the HRV band split. A broad autonomic spectrum spends
    // its power across VLF/LF/HF; collapse toward one band lowers the entropy.
    // log2(3) = 1.585 bits is the flat maximum.
    const double hrvEntropy = stats::entropyBits({vlf, lf, hf});
    derived("ans.spec_entropy", "HRV spectral entropy",     "autonomic", hrvEntropy, 1.35, 1.585, Polarity::HigherBetter);

    // EEG montage completeness, so the biggest caveat in the record is a first-
    // class number rather than a footnote.
    const double reliable = session["acquisition"]["eeg"]["channels_reliable"].num(0);
    const double total    = session["acquisition"]["eeg"]["channels_total"].num(19);
    derived("eeg.quality", "Usable EEG channels", "eeg", reliable, 18.0, total, Polarity::HigherBetter);

    // -----------------------------------------------------------------------
    // 3. Score the prior graph
    // -----------------------------------------------------------------------
    std::map<std::string, double> sdev;
    for (const auto& m : readings)
        if (m.valid) sdev[m.id] = m.sdev;

    std::vector<stats::Hypothesis> hyps;
    const nj::Value& hs = prior["hypotheses"];
    for (size_t i = 0; i < hs.size(); ++i) {
        stats::Hypothesis h;
        h.id    = hs[i]["id"].str();
        h.name  = hs[i]["name"].str();
        h.plain = hs[i]["plain"].str();
        const nj::Value& es = hs[i]["edges"];
        for (size_t j = 0; j < es.size(); ++j) {
            stats::Edge e;
            e.a    = es[j]["a"].str();
            e.b    = es[j]["b"].str();
            e.sign = (int)es[j]["sign"].num(1);
            e.w    = es[j]["w"].num(1.0);
            e.cite = es[j]["cite"].str();
            e.note = es[j]["note"].str();
            h.edges.push_back(std::move(e));
        }
        hyps.push_back(std::move(h));
    }

    std::vector<stats::PermResult> perms;
    for (auto& h : hyps) {
        // Vary the stream per hypothesis so five tests do not share one shuffle
        // sequence, while keeping the whole run reproducible from one --seed.
        perms.push_back(stats::permutationTest(h, sdev, permIters, seed + 1013ull * perms.size()));
    }

    // -----------------------------------------------------------------------
    // 4. Where instruments measuring the same construct disagree
    // -----------------------------------------------------------------------
    auto sd = [&](const std::string& id) {
        auto it = byId.find(id);
        return (it == byId.end()) ? 0.0 : readings[it->second].sdev;
    };
    std::vector<stats::Dissonance> diss;
    // objGoodDirection: +1 when a higher sdev on the objective measure means
    // better function, -1 when it means worse.
    diss.push_back(stats::measureDissonance("Executive control",
        "srs.exec_attn", sd("srs.exec_attn"), "beh.commission", sd("beh.commission"), -1));
    diss.push_back(stats::measureDissonance("Attention allocation",
        "srs.exec_attn", sd("srs.exec_attn"), "erp.p3a_amp", sd("erp.p3a_amp"), +1));
    diss.push_back(stats::measureDissonance("Sustained attention",
        "srs.exec_attn", sd("srs.exec_attn"), "beh.omission", sd("beh.omission"), -1));
    diss.push_back(stats::measureDissonance("Sensory processing",
        "srs.sensory", sd("srs.sensory"), "erp.n100_lat", sd("erp.n100_lat"), -1));
    diss.push_back(stats::measureDissonance("Motor speed",
        "srs.motor", sd("srs.motor"), "beh.rt", sd("beh.rt"), -1));
    diss.push_back(stats::measureDissonance("Mood",
        "srs.affect", sd("srs.affect"), "psy.phq9", sd("psy.phq9"), -1));
    diss.push_back(stats::measureDissonance("Memory",
        "srs.memory", sd("srs.memory"), "eeg.paf_ec", sd("eeg.paf_ec"), +1));

    // =======================================================================
    // EMIT THE DISPLAY FILE
    // =======================================================================
    constexpr double CW = 1600;
    // Height is finalised after layout and patched into the header at build
    // time; the emitter only needs a placeholder to start with.
    double CH = 2760;
    nvm::Emitter em((uint32_t)CW, (uint32_t)2760);

    // -- symbol table --------------------------------------------------------
    for (const auto& m : readings) {
        nvm::Symbol s;
        s.name     = m.id;
        s.label    = m.label;
        s.value    = m.value;
        s.z        = m.sdev;
        s.dist     = m.dist;
        s.refLo    = m.ref.lo;
        s.refHi    = m.ref.hi;
        s.hasRef   = m.ref.present;
        s.severity = (uint8_t)m.severity;
        s.domain   = domainId(m.domain);
        s.valid    = m.valid;
        em.str(m.id);
        em.str(m.label);
        em.sym(s);
    }

    auto setColour = [&](ink::C c, int a = 255) { em.rgba(c.r, c.g, c.b, a); };

    // -- subroutine: drawBar -------------------------------------------------
    // Contract: caller pushes  x0, yTop, halfWidth, t   with t in [-1, 1].
    // Draws a rectangle of height 9 whose signed width is t * halfWidth.
    // Emitted first, jumped over, and reached only through OP_CALL. This is a
    // real subroutine in a real stack machine, not a macro: the ~40 bar draws
    // in the ladder panel below all go through this one body.
    em.op(nvm::OP_JMP);
    const size_t jmpOverSub = em.here();
    em.i16(0);
    const uint32_t SUB_BAR = em.here();
    em.op(nvm::OP_MUL);        // x0 yTop (halfWidth*t)
    em.pushf(9.0);             // x0 yTop w h
    em.op(nvm::OP_RECT);
    em.op(nvm::OP_RET);
    em.patchU16(jmpOverSub, (uint16_t)(em.here() - (jmpOverSub + 2)));
    em.setEntry(em.here());

    em.op(nvm::OP_CLEAR);
    em.font("ui", 13.0);

    // Panel geometry is emitted as a transform the host may override; the same
    // intrinsic sizes go into the meta sidecar so a host can re-flow panels
    // into any column layout without re-deriving a single number.
    struct PanelBox { std::string id, title; double x, y, w, h; };
    std::vector<PanelBox> boxes;

    auto beginPanel = [&](const std::string& id, const std::string& title,
                          double x, double y, double w, double h) {
        boxes.push_back({id, title, x, y, w, h});
        em.op(nvm::OP_PUSHMAT);
        em.pushf(x); em.pushf(y); em.op(nvm::OP_TRANS);
        em.panel(id, title);
        setColour(ink::kRule);
        em.linew(1.0);
        em.rect(0, 0, w, h);
        em.op(nvm::OP_STROKE);
        setColour(ink::kFg);
        em.font("ui-bold", 15.0);
        em.text(18, 28, title);
        em.font("ui", 12.0);
    };
    auto endPanel = [&]() {
        em.endPanel();
        em.op(nvm::OP_POPMAT);
    };

    auto note = [&](const std::string& id) {
        auto it = gExplain.find(id);
        if (it != gExplain.end()) em.note(it->second.plain, it->second.full);
    };

    // -----------------------------------------------------------------------
    // Panel: header
    // -----------------------------------------------------------------------
    {
        beginPanel("hdr", "Multimodal physiology, one session", 40, 30, CW - 80, 116);
        setColour(ink::kMuted);
        em.font("ui", 12.5);
        const std::string who = deidentify ? "SUBJ-001" : session["session"]["subject_ref"].str();
        em.text(18, 54,
                who + "  \xC2\xB7  " + session["session"]["date"].str() +
                "  \xC2\xB7  age " + fmt(session["session"]["age_years"].num(), 1) +
                "  \xC2\xB7  5 documents, 19 scanned pages, " + std::to_string(readings.size()) +
                " metrics, " + std::to_string(nTested) + " allergen sites");
        em.text(18, 76,
                "Every number below is transcribed from the source scans and re-derived here. "
                "n = 1 session: nothing on this page is a correlation coefficient.");
        setColour(ink::kDeviant);
        em.text(18, 98,
                "Not a diagnosis. Decision support for a conversation with a clinician, and a worked "
                "example of instrument disagreement.");
        endPanel();
    }

    // Running layout cursor for the left column. Panels below size themselves
    // from the data, so nothing here is a magic constant that silently starts
    // overlapping when a metric is added to the session file.
    double leftY = 170.0;

    // -----------------------------------------------------------------------
    // Panel: the margin ladder — every metric ranked by distance past threshold
    // -----------------------------------------------------------------------
    {
        std::vector<const Reading*> ladder;
        for (const auto& m : readings)
            if (m.valid && m.ref.present) ladder.push_back(&m);
        std::sort(ladder.begin(), ladder.end(),
                  [](const Reading* a, const Reading* b) { return a->dist > b->dist; });

        const double rowH = 19.0;
        const double panelH = 96 + rowH * ladder.size() + 26;
        // Full width: this is the panel that answers the question the vendor
        // reports raise and never close, so it gets the whole page.
        beginPanel("ladder", "How far past the line, really", 40, leftY, CW - 80, panelH);

        setColour(ink::kMuted);
        em.font("ui", 11.0);
        em.text(20, 52, "every measured metric, ranked by distance past its own reference edge, "
                        "as a fraction of that threshold");
        em.text(20, 68, "left of the axis = inside reference. three findings clear the 15% "
                        "borderline cut; six of the vendor's flags do not.");

        // Four columns, none of which overlap: label | bar | value | margin.
        const double axisX = 700, halfW = 380;
        const double colValue = 1180, colPct = 1320;
        const double top = 92, bottom = top + rowH * ladder.size() + 8;

        setColour(ink::kRule, 130);
        for (double g : {0.15, 0.5, 1.0, 2.0}) {
            const double gx = axisX + halfW * std::tanh(0.6 * g);
            em.linew(1.0);
            em.line(gx, top, gx, bottom);
            setColour(ink::kMuted);
            em.font("ui", 9.5);
            em.text(gx, top - 8, "+" + fmt(g, 2), nvm::AN_CENTRE);
            setColour(ink::kRule, 130);
        }
        // The borderline cut is the only line on this axis that decides
        // anything, so it is the only one drawn at full strength.
        setColour(ink::kBorder, 200);
        em.linew(1.5);
        {
            const double gx = axisX + halfW * std::tanh(0.6 * stats::kBorderlineCut);
            em.line(gx, top, gx, bottom);
        }
        setColour(ink::kRule);
        em.linew(1.0);
        em.line(axisX, top, axisX, bottom);

        setColour(ink::kMuted);
        em.font("ui", 9.5);
        em.text(colValue, top - 8, "value", nvm::AN_RIGHT);
        em.text(colPct,   top - 8, "margin", nvm::AN_RIGHT);

        double y = top + 12;
        for (const Reading* m : ladder) {
            em.anchor(m->id);
            note(m->id);
            em.flag((uint8_t)m->severity);

            setColour(ink::kFg);
            em.font("ui", 11.5);
            em.text(20, y + 8, m->label.substr(0, 52));

            // squashed so a dist of 3.5 stays on the panel without compressing
            // the crowded 0-0.3 region where the interesting calls live
            const double t = std::tanh(0.6 * m->dist);
            const ink::C c = ink::severityColour(m->severity);
            setColour(c, m->severity == 0 ? 150 : 235);

            em.pushf(axisX);
            em.pushf(y);
            em.pushf(halfW);
            em.pushf(t);
            em.op(nvm::OP_CALL);
            em.u16((uint16_t)SUB_BAR);
            em.op(nvm::OP_FILL);

            setColour(ink::kMuted);
            em.font("ui", 10.5);
            em.text(colValue, y + 8, fmt(m->value, 2), nvm::AN_RIGHT);
            setColour(m->severity == 2 ? ink::kDeviant
                                       : (m->severity == 1 ? ink::kBorderTxt : ink::kMuted));
            em.text(colPct, y + 8, (m->dist > 0 ? "+" : "") + fmt(m->dist * 100, 0) + "%",
                    nvm::AN_RIGHT);
            setColour(ink::kMuted);
            em.font("ui", 10.0);
            em.text(colPct + 30, y + 8, m->domain, nvm::AN_LEFT);
            y += rowH;
        }
        endPanel();
        leftY += panelH + 30;
    }

    // -----------------------------------------------------------------------
    // Panel: hypothesis concordance
    // -----------------------------------------------------------------------
    {
        beginPanel("concord", "Five stories, scored against the literature", 40, leftY, 760, 400);
        setColour(ink::kMuted);
        em.font("ui", 11.0);
        em.text(18, 50, "concordance C in [-1,+1] against a prior graph of published effect directions");
        em.text(18, 66, "p from permuting the same deviations across metrics; a weak null, read it as such");

        const double ax = 300, aw = 300;
        setColour(ink::kRule);
        em.line(ax + aw / 2, 82, ax + aw / 2, 82 + 62.0 * hyps.size());

        double y = 96;
        for (size_t i = 0; i < hyps.size(); ++i) {
            const auto& h = hyps[i];
            const auto& pr = perms[i];
            em.anchor(h.id);
            note(h.id);
            em.cite(std::to_string(h.nUsable) + "/" + std::to_string(h.nTotal) + " edges testable");

            const bool strong = (h.C > 0.25 && h.p < 0.05);
            em.flag(strong ? nvm::SEV_DEVIANT : (h.C > 0.1 ? nvm::SEV_BORDERLINE : nvm::SEV_OK));

            setColour(ink::kFg);
            em.font("ui-bold", 12.0);
            em.text(18, y + 4, h.id + "  " + h.name.substr(0, 34));
            setColour(ink::kMuted);
            em.font("ui", 10.5);
            em.text(18, y + 20, h.plain.substr(0, 46));

            // null band, then the observed marker on top of it
            const double cx = ax + aw / 2;
            setColour(ink::kRule, 170);
            em.rect(cx + (aw / 2) * (pr.nullMean - 2 * pr.nullSd), y - 6,
                    (aw / 2) * (4 * pr.nullSd), 20);
            em.op(nvm::OP_FILL);

            setColour(strong ? ink::kAccent : ink::kMuted);
            em.circle(cx + (aw / 2) * h.C, y + 4, 6);
            em.op(nvm::OP_FILL);

            setColour(ink::kFg);
            em.font("ui", 11.0);
            em.text(ax + aw + 24, y + 8, "C=" + fmt(h.C, 3), nvm::AN_LEFT);
            setColour(h.p < 0.05 ? ink::kAccent : ink::kMuted);
            em.text(ax + aw + 110, y + 8, "p=" + fmt(h.p, 4), nvm::AN_LEFT);
            y += 62;
        }
        endPanel();
    }

    // -----------------------------------------------------------------------
    // Panel: instrument disagreement
    // -----------------------------------------------------------------------
    {
        beginPanel("dissonance", "Where the instruments disagree", 840, leftY, 720, 400);
        setColour(ink::kMuted);
        em.font("ui", 11.0);
        em.text(18, 50, "purple = what you reported.  blue = what the instrument measured.");
        em.text(18, 66, "a long connector is the interesting case, in either direction.");

        const double ax = 340, aw = 300;
        setColour(ink::kRule);
        em.line(ax, 84, ax, 84 + 34.0 * diss.size());
        setColour(ink::kMuted);
        em.font("ui", 9.5);
        em.text(ax, 78, "reference", nvm::AN_CENTRE);

        double y = 98;
        for (const auto& d : diss) {
            em.anchor("diss." + d.construct);
            em.note(d.construct + ": " + d.reading,
                    "self-report " + d.subjectiveId + " sdev " + fmt(d.subjectiveSdev, 2) +
                    " vs objective " + d.objectiveId + " sdev " + fmt(d.objectiveSdev, 2) +
                    ", gap " + fmt(d.gap, 2) + " half-bands on a common function-quality axis");
            em.flag(std::fabs(d.gap) > 1.5 ? nvm::SEV_DEVIANT
                                           : (std::fabs(d.gap) > 0.5 ? nvm::SEV_BORDERLINE : nvm::SEV_OK));

            setColour(ink::kFg);
            em.font("ui", 11.5);
            em.text(18, y + 4, d.construct);

            const double sx = ax + (aw / 3) * std::max(-3.0, std::min(3.0, d.subjectiveSdev));
            const double ox = ax + (aw / 3) * std::max(-3.0, std::min(3.0,
                                   (d.gap + d.subjectiveSdev)));
            setColour(ink::kRule);
            em.linew(2.0);
            em.line(sx, y, ox, y);
            setColour(ink::kSubjective);
            em.circle(sx, y, 5.5);
            em.op(nvm::OP_FILL);
            setColour(ink::kAccent);
            em.circle(ox, y, 5.5);
            em.op(nvm::OP_FILL);

            setColour(ink::kMuted);
            em.font("ui", 10.0);
            em.text(ax + aw / 1.4, y + 4, d.reading, nvm::AN_LEFT);
            y += 40;
        }
        endPanel();
        leftY += 430;
    }

    // -----------------------------------------------------------------------
    // Panel: autonomic spectrum
    // -----------------------------------------------------------------------
    {
        beginPanel("ans", "Autonomic spectrum: total is fine, the split is not", 840, leftY, 720, 300);
        setColour(ink::kMuted);
        em.font("ui", 11.0);
        em.text(18, 50, "SDNN 82 ms and total power 2324 ms\xC2\xB2 both score normal.");
        em.text(18, 66, "the abnormality is in how that power is distributed.");

        struct Band { const char* name; double p; ink::C c; const char* gloss; };
        const Band bands[3] = {
            {"VLF", vlf, ink::kDeviant, "slow recovery / load"},
            {"LF",  lf,  ink::kBorder,  "mixed, baroreflex"},
            {"HF",  hf,  ink::kOk,      "vagal brake"},
        };
        const double bx = 60, bw = 150, baseY = 240, maxH = 130;
        for (int i = 0; i < 3; ++i) {
            const double h = maxH * (bands[i].p / 1200.0);
            em.anchor(std::string("ans.band.") + bands[i].name);
            em.note(std::string(bands[i].name) + " power " + fmt(bands[i].p, 0) + " ms\xC2\xB2 \xE2\x80\x94 " + bands[i].gloss,
                    std::string(bands[i].name) + " absolute power " + fmt(bands[i].p, 0) +
                    " ms^2, " + fmt(100.0 * bands[i].p / tp, 1) + "% of total power. "
                    "Expected ordering for this vendor is VLF < LF > HF; observed is VLF > LF > HF.");
            setColour(bands[i].c);
            em.rect(bx + i * (bw + 30), baseY - h, bw, h);
            em.op(nvm::OP_FILL);
            setColour(ink::kFg);
            em.font("ui-bold", 13.0);
            em.text(bx + i * (bw + 30) + bw / 2, baseY - h - 10, fmt(bands[i].p, 0), nvm::AN_CENTRE);
            setColour(ink::kMuted);
            em.font("ui", 11.0);
            em.text(bx + i * (bw + 30) + bw / 2, baseY + 18, bands[i].name, nvm::AN_CENTRE);
            em.font("ui", 9.5);
            em.text(bx + i * (bw + 30) + bw / 2, baseY + 34, bands[i].gloss, nvm::AN_CENTRE);
        }
        em.anchor("ans.spec_entropy");
        em.note("The power is bunched into one band instead of spread across three.",
                "Shannon entropy over the VLF/LF/HF split = " + fmt(hrvEntropy, 3) +
                " bits of a possible 1.585. Expected pattern VLF < LF > HF; observed VLF > LF > HF. "
                "Two-minute epoch, so the VLF estimate is indicative rather than definitive.");
        setColour(ink::kFg);
        em.font("ui", 12.0);
        em.text(560, 150, "entropy", nvm::AN_CENTRE);
        em.font("ui-bold", 26.0);
        em.text(560, 182, fmt(hrvEntropy, 3), nvm::AN_CENTRE);
        setColour(ink::kMuted);
        em.font("ui", 10.0);
        em.text(560, 202, "of 1.585 bits", nvm::AN_CENTRE);
        endPanel();
    }

    // -----------------------------------------------------------------------
    // Panel: the timing chain
    // -----------------------------------------------------------------------
    {
        beginPanel("timing", "The timing chain: where the delay accumulates", 40, leftY, 760, 300);
        setColour(ink::kMuted);
        em.font("ui", 11.0);
        em.text(18, 50, "each stage plotted against its own ceiling. amplitude is fine everywhere;");
        em.text(18, 66, "it is arrival time that slips, and the slip is already there at 288 ms.");

        struct Stage { const char* id; const char* label; double v, ceil; };
        const Stage chain[4] = {
            {"erp.n100_lat", "N100  first sight",        val("erp.n100_lat"), 250},
            {"erp.p3a_lat",  "P3a   novelty grab",       val("erp.p3a_lat"),  450},
            {"erp.p3b_lat",  "P3b   context update",     val("erp.p3b_lat"),  450},
            {"beh.rt",       "RT    finger moves",       val("beh.rt"),       500},
        };
        const double tx = 250, tw = 420, tmax = 640.0;
        setColour(ink::kRule);
        em.linew(1.0);
        for (double ms = 0; ms <= 600; ms += 100) {
            const double gx = tx + tw * (ms / tmax);
            em.line(gx, 92, gx, 236);
            setColour(ink::kMuted);
            em.font("ui", 9.5);
            em.text(gx, 254, fmt(ms, 0), nvm::AN_CENTRE);
            setColour(ink::kRule);
        }
        double y = 108;
        for (const auto& s : chain) {
            em.anchor(s.id);
            note(s.id);
            const bool over = s.v > s.ceil;
            em.flag(over ? ((s.v - s.ceil) / s.ceil > stats::kBorderlineCut ? nvm::SEV_DEVIANT
                                                                            : nvm::SEV_BORDERLINE)
                         : nvm::SEV_OK);
            setColour(ink::kFg);
            em.font("ui", 11.5);
            em.text(18, y + 4, s.label);

            // ceiling marker, then the observed bar. OP_MAP does the ms -> px
            // remap inside the VM so a host can retarget the axis at run time
            // by patching one PUSHF pair instead of re-emitting the panel.
            setColour(ink::kMuted, 150);
            const double cx = tx + tw * (s.ceil / tmax);
            em.line(cx, y - 12, cx, y + 12);

            setColour(over ? ink::severityColour((s.v - s.ceil) / s.ceil > stats::kBorderlineCut ? 2 : 1)
                           : ink::kOk, 220);
            em.pushf(s.v);
            em.pushf(0.0); em.pushf(tmax); em.pushf(0.0); em.pushf(tw);
            em.op(nvm::OP_MAP);            // -> pixels
            em.pushf(tx); em.op(nvm::OP_ADD);
            // stack: x1. Build RECT(tx, y-5, x1-tx, 10).
            em.pushf(tx); em.op(nvm::OP_SUB);   // width
            em.pushf(tx);                        // x
            em.op(nvm::OP_SWAP);                 // x, width
            em.pushf(y - 5.0);                   // x, width, y
            em.op(nvm::OP_SWAP);                 // x, y, width
            em.pushf(10.0);                      // x, y, width, h
            em.op(nvm::OP_RECT);
            em.op(nvm::OP_FILL);

            setColour(ink::kFg);
            em.font("ui", 10.5);
            em.text(tx + tw + 16, y + 4, fmt(s.v, 0) + " ms", nvm::AN_LEFT);
            y += 34;
        }
        setColour(ink::kMuted);
        em.font("ui", 10.0);
        em.text(18, 272, "vertical ticks are each stage's own reference ceiling");
        endPanel();
        leftY += 330;
    }

    // -----------------------------------------------------------------------
    // Panel: allergen burden
    // -----------------------------------------------------------------------
    {
        const double py = leftY;
        beginPanel("allergy",
                   "Immune load: " + std::to_string(nPos) + " of " + std::to_string(nTested) +
                   " sites positive",
                   40, py, 1520, 300);
        setColour(ink::kMuted);
        em.font("ui", 11.0);
        em.text(18, 50, "wheal diameter in mm, 15-minute read. >=3 mm is positive. "
                        "histamine control 7 mm, glycerin control 0 mm, so the panel is valid.");
        em.text(18, 66, "hollow squares are the two rows whose handwriting could not be read with confidence.");

        const double gx0 = 24, gy0 = 92, cell = 34, gap = 3;
        int col = 0;
        for (size_t i = 0; i < spt.size(); ++i) {
            const std::string cls = spt[i]["class"].str();
            if (cls == "control") continue;
            const int w = (int)spt[i]["wheal_mm"].num(0);
            const std::string name = spt[i]["allergen"].str();
            const std::string conf = spt[i]["confidence"].str();
            const double x = gx0 + col * (cell + gap);
            const double y = gy0 + (col / 42) * 0;  // single row band, wraps below
            const double px = gx0 + (col % 42) * (cell + gap);
            const double py2 = gy0 + (col / 42) * (cell + 46);
            (void)x; (void)y;

            em.anchor("spt." + spt[i]["site"].str());
            em.note(name + ": " + std::to_string(w) + " mm" + (w >= 3 ? " (positive)" : ""),
                    name + " [" + cls + "], wheal " + std::to_string(w) +
                    " mm, transcription confidence " + conf +
                    ". Positive threshold 3 mm over the negative control. Wheal size indexes "
                    "sensitisation, not clinical severity; correlation with symptoms requires exposure "
                    "history.");
            em.flag(w >= 10 ? nvm::SEV_DEVIANT : (w >= 3 ? nvm::SEV_BORDERLINE : nvm::SEV_OK));

            // Intensity from wheal size, hue from severity.
            const int a = w == 0 ? 40 : (int)std::min(255.0, 70 + 12.0 * w);
            const ink::C c = w >= 10 ? ink::kDeviant : (w >= 3 ? ink::kBorder : ink::kNoData);
            setColour(c, a);
            em.rect(px, py2, cell, cell);
            em.op(nvm::OP_FILL);
            if (conf != "high") {
                setColour(ink::kAccent);
                em.linew(1.5);
                em.rect(px, py2, cell, cell);
                em.op(nvm::OP_STROKE);
            }
            setColour(w >= 3 ? ink::C{255, 255, 255} : ink::kMuted);
            em.font("ui", 11.0);
            em.text(px + cell / 2, py2 + cell / 2 + 4, std::to_string(w), nvm::AN_CENTRE);
            ++col;
        }

        // Class summary, since 38 squares alone do not say "tree pollen".
        double lx = 24, ly = 250;
        setColour(ink::kFg);
        em.font("ui", 11.5);
        for (const auto& kv : totByClass) {
            const std::string s = kv.first + " " + std::to_string(posByClass[kv.first]) + "/" +
                                  std::to_string(kv.second);
            em.anchor("spt.class." + kv.first);
            em.note(s + " positive", "class-level positivity for " + kv.first);
            em.text(lx, ly, s);
            lx += 150;
        }
        endPanel();
        leftY = py + 330;
    }

    // -----------------------------------------------------------------------
    // Panel: the co-deviation chord, plus every prior edge as data
    // -----------------------------------------------------------------------
    {
        const double py = leftY;
        beginPanel("chord", "Structure, not correlation", 40, py, 1520, 420);
        setColour(ink::kMuted);
        em.font("ui", 11.0);
        em.text(18, 50, "ring position = deviation size. chords = prior-graph edges, "
                        "coloured by whether this person's data agrees with the published direction.");
        em.text(18, 66, "with n = 1 these chords are hypotheses drawn to scale, not measured associations.");

        // Ring of the most deviant metrics.
        std::vector<const Reading*> ring;
        for (const auto& m : readings)
            if (m.valid && sdev.count(m.id)) ring.push_back(&m);
        std::sort(ring.begin(), ring.end(),
                  [](const Reading* a, const Reading* b) { return std::fabs(a->sdev) > std::fabs(b->sdev); });
        if (ring.size() > 24) ring.resize(24);

        // An ellipse, not a circle: the panel is 1520 x 420, and forcing 24
        // labelled nodes onto a 140 px circle piles the labels on top of each
        // other while three quarters of the panel sits empty. Radius still
        // encodes deviation; only the aspect changes.
        std::map<std::string, std::pair<double, double>> pos;
        const double ccx = 760, ccy = 232, rx = 440, ry = 132;
        for (size_t i = 0; i < ring.size(); ++i) {
            const double a = -M_PI / 2 + 2 * M_PI * i / ring.size();
            const double k = 0.58 + 0.42 * std::min(1.0, std::fabs(ring[i]->sdev) / 3.0);
            pos[ring[i]->id] = {ccx + rx * k * std::cos(a), ccy + ry * k * std::sin(a)};
        }

        // Every computable edge is DECLARED, whether or not both of its
        // endpoints made the ring. EDGE is a semantic record, not a drawing
        // instruction, and tying it to the drawing would have silently dropped
        // the single most interesting relation in this dataset --
        // srs.exec_attn <-> beh.commission, the one the record contradicts --
        // because commission errors are too close to reference to rank into a
        // top-24 ring.
        for (size_t hi = 0; hi < hyps.size(); ++hi)
            for (const auto& e : hyps[hi].edges)
                if (e.computable) em.edge(e.a, e.b, hyps[hi].id, e.w, e.sign);

        // Chords are drawn only for pairs that are both on the ring, and are
        // drawn first so the nodes sit on top.
        for (size_t hi = 0; hi < hyps.size(); ++hi) {
            for (const auto& e : hyps[hi].edges) {
                if (!e.computable) continue;
                auto pa = pos.find(e.a), pb = pos.find(e.b);
                if (pa == pos.end() || pb == pos.end()) continue;
                const bool agrees = e.term > 0;
                setColour(agrees ? ink::kAccent : ink::kDeviant,
                          (int)(50 + 150 * std::min(1.0, std::fabs(e.term))));
                em.linew(0.8 + 2.4 * std::fabs(e.term));
                em.line(pa->second.first, pa->second.second, pb->second.first, pb->second.second);
            }
        }
        for (size_t i = 0; i < ring.size(); ++i) {
            const Reading* m = ring[i];
            const auto& p = pos[m->id];
            em.anchor(m->id);
            note(m->id);
            em.flag((uint8_t)m->severity);
            setColour(ink::severityColour(m->severity));
            em.circle(p.first, p.second, 5.0 + 2.5 * std::min(1.0, std::fabs(m->sdev) / 3.0));
            em.op(nvm::OP_FILL);
            setColour(ink::kMuted);
            em.font("ui", 9.0);
            const double a = -M_PI / 2 + 2 * M_PI * i / ring.size();
            const double lx = ccx + (rx + 34) * std::cos(a);
            const double ly = ccy + (ry + 26) * std::sin(a) + 3;
            em.text(lx, ly, m->id,
                    std::cos(a) < -0.25 ? nvm::AN_RIGHT
                                        : (std::cos(a) > 0.25 ? nvm::AN_LEFT : nvm::AN_CENTRE));
        }

        setColour(ink::kAccent);
        em.circle(60, 380, 5); em.op(nvm::OP_FILL);
        setColour(ink::kFg);
        em.font("ui", 11.0);
        em.text(76, 384, "this record agrees with the published direction");
        setColour(ink::kDeviant);
        em.circle(430, 380, 5); em.op(nvm::OP_FILL);
        setColour(ink::kFg);
        em.text(446, 384, "this record contradicts it \xE2\x80\x94 the interesting edges");
        endPanel();
        leftY = py + 450;
    }

    em.op(nvm::OP_HALT);

    // The document is exactly as tall as the panels turned out to be.
    CH = leftY + 40;
    em.setCanvas((uint32_t)CW, (uint32_t)CH);

    // -----------------------------------------------------------------------
    // Meta sidecar
    // -----------------------------------------------------------------------
    {
        std::ostringstream j;
        j << "{\"schema\":\"neuro/meta/v1\",\"panels\":[";
        for (size_t i = 0; i < boxes.size(); ++i) {
            if (i) j << ",";
            j << "{\"id\":\"" << boxes[i].id << "\",\"title\":\"" << jsonEscape(boxes[i].title)
              << "\",\"x\":" << boxes[i].x << ",\"y\":" << boxes[i].y
              << ",\"w\":" << boxes[i].w << ",\"h\":" << boxes[i].h << "}";
        }
        j << "],\"hypotheses\":[";
        for (size_t i = 0; i < hyps.size(); ++i) {
            if (i) j << ",";
            j << "{\"id\":\"" << hyps[i].id << "\",\"name\":\"" << jsonEscape(hyps[i].name)
              << "\",\"C\":" << hyps[i].C << ",\"p\":" << hyps[i].p
              << ",\"nullMean\":" << perms[i].nullMean << ",\"nullSd\":" << perms[i].nullSd
              << ",\"zVsNull\":" << perms[i].zVsNull
              << ",\"edgesUsable\":" << hyps[i].nUsable << ",\"edgesTotal\":" << hyps[i].nTotal << "}";
        }
        j << "],\"permutations\":" << permIters << ",\"seed\":" << seed
          << ",\"date\":\"" << session["session"]["date"].str() << "\""
          << ",\"metricsMeasured\":" << sdev.size() << "}";
        em.setMeta(j.str());
    }

    // -----------------------------------------------------------------------
    // Write
    // -----------------------------------------------------------------------
    {
        const std::vector<uint8_t> blob = em.build();
        std::ofstream out(outPath, std::ios::binary);
        if (!out) { std::cerr << "analyze: cannot write " << outPath << "\n"; return 3; }
        out.write((const char*)blob.data(), (std::streamsize)blob.size());
        std::cerr << "analyze: wrote " << outPath << "  " << blob.size() << " bytes, "
                  << em.symbols().size() << " symbols, " << em.strings().size() << " strings\n";
    }

    {
        std::ostringstream j;
        j << "{\n  \"schema\": \"neuro/derived/v1\",\n";
        j << "  \"session\": \"" << (deidentify ? "SUBJ-001" : session["session"]["id"].str()) << "\",\n";
        j << "  \"date\": \"" << session["session"]["date"].str() << "\",\n";
        j << "  \"permutations\": " << permIters << ", \"seed\": " << seed << ",\n";
        j << "  \"metrics\": [\n";
        for (size_t i = 0; i < readings.size(); ++i) {
            const auto& m = readings[i];
            j << "    {\"id\":\"" << m.id << "\",\"label\":\"" << jsonEscape(m.label)
              << "\",\"domain\":\"" << m.domain << "\",\"value\":"
              << (m.valid ? fmt(m.value, 4) : "null")
              << ",\"sdev\":" << fmt(m.sdev, 4)
              << ",\"dist\":" << fmt(m.dist, 4)
              << ",\"severity\":" << m.severity;
            auto e = gExplain.find(m.id);
            if (e != gExplain.end()) {
                j << ",\"plain\":\"" << jsonEscape(e->second.plain) << "\""
                  << ",\"full\":\"" << jsonEscape(e->second.full) << "\"";
            }
            j << "}" << (i + 1 < readings.size() ? "," : "") << "\n";
        }
        j << "  ],\n  \"hypotheses\": [\n";
        for (size_t i = 0; i < hyps.size(); ++i) {
            j << "    {\"id\":\"" << hyps[i].id << "\",\"name\":\"" << jsonEscape(hyps[i].name)
              << "\",\"plain\":\"" << jsonEscape(hyps[i].plain) << "\""
              << ",\"C\":" << fmt(hyps[i].C, 4) << ",\"p\":" << fmt(hyps[i].p, 5)
              << ",\"nullMean\":" << fmt(perms[i].nullMean, 4)
              << ",\"nullSd\":" << fmt(perms[i].nullSd, 4)
              << ",\"zVsNull\":" << fmt(perms[i].zVsNull, 3)
              << ",\"edgesUsable\":" << hyps[i].nUsable << ",\"edgesTotal\":" << hyps[i].nTotal
              << ",\"edges\":[";
            bool first = true;
            for (const auto& e : hyps[i].edges) {
                if (!first) j << ",";
                first = false;
                j << "{\"a\":\"" << e.a << "\",\"b\":\"" << e.b << "\",\"sign\":" << e.sign
                  << ",\"w\":" << e.w << ",\"term\":" << fmt(e.term, 4)
                  << ",\"computable\":" << (e.computable ? "true" : "false")
                  << ",\"cite\":\"" << jsonEscape(e.cite) << "\"}";
            }
            j << "]}" << (i + 1 < hyps.size() ? "," : "") << "\n";
        }
        j << "  ],\n  \"dissonance\": [\n";
        for (size_t i = 0; i < diss.size(); ++i) {
            const auto& d = diss[i];
            j << "    {\"construct\":\"" << jsonEscape(d.construct) << "\",\"subjective\":\""
              << d.subjectiveId << "\",\"objective\":\"" << d.objectiveId
              << "\",\"subjectiveSdev\":" << fmt(d.subjectiveSdev, 3)
              << ",\"objectiveSdev\":" << fmt(d.objectiveSdev, 3)
              << ",\"gap\":" << fmt(d.gap, 3) << ",\"reading\":\"" << jsonEscape(d.reading) << "\"}"
              << (i + 1 < diss.size() ? "," : "") << "\n";
        }
        j << "  ],\n";
        j << "  \"immune\": {\"tested\":" << nTested << ",\"positive\":" << nPos
          << ",\"maxWhealMm\":" << maxWheal << ",\"byClass\":{";
        bool first = true;
        for (const auto& kv : totByClass) {
            if (!first) j << ",";
            first = false;
            j << "\"" << kv.first << "\":{\"pos\":" << posByClass[kv.first] << ",\"n\":" << kv.second << "}";
        }
        j << "}},\n";
        j << "  \"autonomic\": {\"vlf\":" << vlf << ",\"lf\":" << lf << ",\"hf\":" << hf
          << ",\"total\":" << tp << ",\"entropyBits\":" << fmt(hrvEntropy, 4)
          << ",\"entropyMaxBits\":1.585}\n";
        j << "}\n";

        std::ofstream out(jsonPath);
        if (!out) { std::cerr << "analyze: cannot write " << jsonPath << "\n"; return 3; }
        out << j.str();
        std::cerr << "analyze: wrote " << jsonPath << "\n";
    }

    // -----------------------------------------------------------------------
    // Console summary
    // -----------------------------------------------------------------------
    if (!overrides.empty()) {
        std::cerr << "  overrides applied\n";
        for (const auto& kv : overrides) {
            const bool known = byId.count(kv.first) > 0;
            std::fprintf(stderr, "    %-34s = %-12.4f %s\n", kv.first.c_str(), kv.second,
                         known ? "" : "  <-- no such metric, ignored");
        }
    }
    std::cerr << "\n  concordance against the prior graph  (" << permIters << " permutations)\n";
    for (size_t i = 0; i < hyps.size(); ++i) {
        std::fprintf(stderr, "    %-3s %-46s C=%+.3f  p=%.4f  null %+.3f+-%.3f  z=%+.2f  %d/%d edges\n",
                     hyps[i].id.c_str(), hyps[i].name.c_str(), hyps[i].C, hyps[i].p,
                     perms[i].nullMean, perms[i].nullSd, perms[i].zVsNull,
                     hyps[i].nUsable, hyps[i].nTotal);
    }
    std::cerr << "\n  findings past the " << (int)(stats::kBorderlineCut * 100) << "% borderline cut\n";
    {
        std::vector<const Reading*> hot;
        for (const auto& m : readings)
            if (m.severity == 2) hot.push_back(&m);
        std::sort(hot.begin(), hot.end(),
                  [](const Reading* a, const Reading* b) { return a->dist > b->dist; });
        for (const Reading* m : hot)
            std::fprintf(stderr, "    %+7.1f%%  %-34s %s\n", m->dist * 100, m->id.c_str(), m->label.c_str());
    }
    std::cerr << "\n  hairline misses (flagged by the vendor, under the cut here)\n";
    for (const auto& m : readings)
        if (m.severity == 1)
            std::fprintf(stderr, "    %+7.1f%%  %-34s %s\n", m.dist * 100, m.id.c_str(), m.label.c_str());
    std::cerr << "\n";
    return 0;
}
