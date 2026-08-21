// stats.hpp — the honest-statistics layer.
//
// ---------------------------------------------------------------------------
// THE PROBLEM THIS FILE EXISTS TO SOLVE
// ---------------------------------------------------------------------------
// The word "cross-correlation" is doing a lot of work in most single-session
// health dashboards, and almost none of it is statistical. With n = 1 session
// there is no sample over which to estimate a correlation coefficient. Anyone
// who prints an r on a one-subject panel is printing a decoration.
//
// What IS answerable from one session is a different and more useful question:
//
//     Published work says certain measures should move together, and in which
//     direction. Does THIS person's pattern of deviations agree with that
//     published structure more than a reshuffling of the same deviations would?
//
// That is a permutation test on a concordance statistic over a prior graph.
// It has a null hypothesis, a test statistic, and a p-value, and none of them
// pretend to be a correlation. Everything in this file computes that, plus the
// two descriptive quantities the reports themselves never print: how far past
// a threshold each flag actually sits, and where two instruments that measure
// the same construct disagree.
// ---------------------------------------------------------------------------
#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <map>
#include <numeric>
#include <random>
#include <string>
#include <vector>

namespace stats {

// ---------------------------------------------------------------------------
// Reference bands
// ---------------------------------------------------------------------------
enum class Polarity { LowerBetter, HigherBetter, Band, None };

struct Ref {
    bool present = false;
    double lo = 0.0;
    double hi = 0.0;
    Polarity pol = Polarity::None;
};

struct Reading {
    std::string id;
    std::string label;
    std::string domain;
    double value = std::nan("");
    bool valid = false;
    Ref ref;
    double trueZ = std::nan("");   // supplied by the vendor for eeg_z metrics
    bool hasTrueZ = false;

    // Derived below.
    double sdev = 0.0;   // signed deviation in half-band units, NATURAL direction
    double dist = 0.0;   // distance past the nearer reference edge; <=0 means inside
    int severity = 3;    // 0 ok, 1 borderline, 2 deviant, 3 not measured
};

// How far past the relevant threshold a value sits, expressed relative to the
// threshold itself for one-sided criteria and to the band width for two-sided
// ones. Negative means the value is inside the band, and the magnitude is then
// the remaining margin.
//
// The choice of denominator matters more than it looks. Normalising a one-sided
// criterion by an invented band width lets an author make any exceedance look
// small by widening the invented far edge. Normalising by the threshold cannot
// be gamed that way, and it makes "8% over the line" and "86% over the line"
// directly comparable across instruments with completely different units.
inline double distancePastEdge(double v, const Ref& r) {
    if (!r.present) return -1.0;
    const double width = r.hi - r.lo;
    switch (r.pol) {
        case Polarity::LowerBetter: {
            const double T = r.hi;
            const double denom = (std::fabs(T) > 1e-12) ? std::fabs(T) : (width > 0 ? width : 1.0);
            return (v - T) / denom;
        }
        case Polarity::HigherBetter: {
            const double T = r.lo;
            const double denom = (std::fabs(T) > 1e-12) ? std::fabs(T) : (width > 0 ? width : 1.0);
            return (T - v) / denom;
        }
        default: {
            if (width <= 0) return -1.0;
            if (v < r.lo) return (r.lo - v) / width;
            if (v > r.hi) return (v - r.hi) / width;
            return -std::min(v - r.lo, r.hi - v) / width;
        }
    }
}

// Signed deviation in half-band units, in the metric's OWN natural direction
// (larger value => larger sdev), never in a "badness" direction. The prior
// graph is written in natural units -- "high LF/HF goes with high central
// beta" -- so flipping to badness here would silently invert half the edges.
inline double signedDeviation(double v, const Ref& r, double trueZ, bool hasTrueZ) {
    if (hasTrueZ) return trueZ;
    if (!r.present) return 0.0;
    const double width = r.hi - r.lo;
    if (width <= 0) return 0.0;
    const double centre = 0.5 * (r.lo + r.hi);
    return (v - centre) / (0.5 * width);  // +-2 at the band edges
}

// Hairline misses and real ones should not share a colour. 15% past the
// threshold is the cut; below that the flag is reported as borderline and the
// exact margin is carried into the bytecode so every host can show it.
constexpr double kBorderlineCut = 0.15;

inline int severityOf(const Reading& m) {
    if (!m.valid) return 3;
    if (!m.ref.present) return 0;
    if (m.dist <= 0.0) return 0;
    return (m.dist < kBorderlineCut) ? 1 : 2;
}

inline void derive(Reading& m) {
    if (!m.valid) {
        m.sdev = 0.0;
        m.dist = 0.0;
        m.severity = 3;
        return;
    }
    m.sdev = signedDeviation(m.value, m.ref, m.trueZ, m.hasTrueZ);
    m.dist = distancePastEdge(m.value, m.ref);
    m.severity = severityOf(m);
}

// ---------------------------------------------------------------------------
// Prior graph and the concordance statistic
// ---------------------------------------------------------------------------
struct Edge {
    std::string a, b;
    int sign = 1;
    double w = 1.0;
    std::string cite;
    std::string note;

    // Filled in during scoring.
    double term = 0.0;      // signed contribution in [-1, 1]
    bool computable = false;
};

struct Hypothesis {
    std::string id, name, plain;
    std::vector<Edge> edges;

    double C = 0.0;         // concordance in [-1, 1]
    double p = 1.0;         // permutation p-value, one-sided (C >= C_obs)
    int nUsable = 0;
    int nTotal = 0;
    double weightUsed = 0.0;
};

// Squashing each factor through tanh keeps one enormous deviation from
// swamping a hypothesis. Without it, srs.exec_attn at -3.7 half-bands would
// single-handedly decide every hypothesis it appears in.
inline double squash(double sdev) { return std::tanh(0.5 * sdev); }

// C = sum_e w_e * sign_e * squash(sdev_a) * squash(sdev_b) / sum_e w_e
// Edges naming a metric that was not measured are dropped, and the count of
// dropped edges is reported so the reader can see how much of the hypothesis
// was actually testable.
inline double concordance(Hypothesis& h, const std::map<std::string, double>& sdev, bool record) {
    double num = 0.0, den = 0.0;
    int usable = 0;
    for (auto& e : h.edges) {
        auto ia = sdev.find(e.a);
        auto ib = sdev.find(e.b);
        const bool ok = (ia != sdev.end() && ib != sdev.end());
        if (record) {
            e.computable = ok;
            e.term = 0.0;
        }
        if (!ok) continue;
        const double t = e.sign * squash(ia->second) * squash(ib->second);
        if (record) e.term = t;
        num += e.w * t;
        den += e.w;
        ++usable;
    }
    if (record) {
        h.nUsable = usable;
        h.nTotal = (int)h.edges.size();
        h.weightUsed = den;
    }
    return (den > 0.0) ? (num / den) : 0.0;
}

// Null model: the same multiset of deviations, reassigned at random to the
// metrics. This asks whether the *pairing* carries the signal, which is the
// only exchangeability assumption available at n = 1. It is a weak null and it
// is labelled as one everywhere it is reported: metrics are not genuinely
// exchangeable (a heart-rate deviation and a PHQ-9 deviation are not drawn
// from a common pool), and edges within a hypothesis share endpoints, so
// successive permutations are not independent. Read the p-value as "this
// pattern is not obviously an artefact of reshuffling", not as evidence of an
// effect.
struct PermResult {
    double p = 1.0;
    double nullMean = 0.0;
    double nullSd = 0.0;
    double zVsNull = 0.0;
    int iterations = 0;
};

inline PermResult permutationTest(Hypothesis& h,
                                  const std::map<std::string, double>& sdev,
                                  int iterations,
                                  uint64_t seed) {
    PermResult res;
    res.iterations = iterations;

    std::vector<std::string> keys;
    std::vector<double> vals;
    keys.reserve(sdev.size());
    vals.reserve(sdev.size());
    for (const auto& kv : sdev) {
        keys.push_back(kv.first);
        vals.push_back(kv.second);
    }
    if (keys.size() < 3) return res;

    const double observed = concordance(h, sdev, true);
    h.C = observed;

    std::mt19937_64 rng(seed);
    std::vector<double> shuffled = vals;
    std::map<std::string, double> trial;
    double sum = 0.0, sumSq = 0.0;
    int atLeast = 0;

    for (int it = 0; it < iterations; ++it) {
        std::shuffle(shuffled.begin(), shuffled.end(), rng);
        for (size_t i = 0; i < keys.size(); ++i) trial[keys[i]] = shuffled[i];
        const double c = concordance(h, trial, false);
        sum += c;
        sumSq += c * c;
        if (c >= observed) ++atLeast;
    }

    // Add-one correction, so a p-value is never reported as exactly zero on a
    // finite number of permutations.
    res.p = (atLeast + 1.0) / (iterations + 1.0);
    res.nullMean = sum / iterations;
    const double var = std::max(0.0, sumSq / iterations - res.nullMean * res.nullMean);
    res.nullSd = std::sqrt(var);
    res.zVsNull = (res.nullSd > 1e-12) ? (observed - res.nullMean) / res.nullSd : 0.0;
    h.p = res.p;
    return res;
}

// ---------------------------------------------------------------------------
// Instrument disagreement
// ---------------------------------------------------------------------------
// Two instruments claiming to measure the same construct, disagreeing. This is
// the most clinically interesting quantity in a battery like this one and no
// vendor report in the set prints it. Positive gap means the self-report is
// worse than the objective measure; negative means the opposite.
struct Dissonance {
    std::string construct;
    std::string subjectiveId, objectiveId;
    double subjectiveSdev = 0.0, objectiveSdev = 0.0;
    double gap = 0.0;           // objective - subjective, in half-band units
    std::string reading;        // short human verdict
};

inline Dissonance measureDissonance(const std::string& construct,
                                    const std::string& subjId, double subjSdev,
                                    const std::string& objId, double objSdev,
                                    // +1 if higher objective sdev means better function
                                    int objGoodDirection) {
    Dissonance d;
    d.construct = construct;
    d.subjectiveId = subjId;
    d.objectiveId = objId;
    d.subjectiveSdev = subjSdev;
    d.objectiveSdev = objSdev;
    // Put both on a common "function quality" axis before subtracting: the
    // self-report scales are already higher-is-better, the objective ones vary.
    const double objQuality = objGoodDirection * objSdev;
    d.gap = objQuality - subjSdev;
    if (d.gap > 1.5)       d.reading = "feels much worse than it measures";
    else if (d.gap > 0.5)  d.reading = "feels worse than it measures";
    else if (d.gap < -1.5) d.reading = "measures much worse than it feels";
    else if (d.gap < -0.5) d.reading = "measures worse than it feels";
    else                   d.reading = "self-report and instrument agree";
    return d;
}

// ---------------------------------------------------------------------------
// Structural co-deviation
// ---------------------------------------------------------------------------
// M[i][j] = squash(sdev_i) * squash(sdev_j). This is NOT a correlation and the
// hosts are required to label it as structure. It answers "which pairs of
// findings are jointly extreme and in which relative direction", which is a
// legitimate descriptive question about a single vector, and it is the matrix
// the dashboard's chord view is drawn from.
inline std::vector<std::vector<double>> coDeviationMatrix(const std::vector<double>& sdev) {
    const size_t n = sdev.size();
    std::vector<std::vector<double>> m(n, std::vector<double>(n, 0.0));
    for (size_t i = 0; i < n; ++i)
        for (size_t j = 0; j < n; ++j)
            m[i][j] = squash(sdev[i]) * squash(sdev[j]);
    return m;
}

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------
inline double mean(const std::vector<double>& v) {
    if (v.empty()) return 0.0;
    return std::accumulate(v.begin(), v.end(), 0.0) / v.size();
}

inline double sd(const std::vector<double>& v) {
    if (v.size() < 2) return 0.0;
    const double m = mean(v);
    double s = 0.0;
    for (double x : v) s += (x - m) * (x - m);
    return std::sqrt(s / (v.size() - 1));
}

// Shannon entropy of a discrete distribution, in bits. Used on the HRV band
// split to give a single number for "how spread across bands is the autonomic
// power". A healthy spectrum is broad; VLF dominance collapses it.
inline double entropyBits(std::vector<double> p) {
    double total = 0.0;
    for (double x : p) total += std::max(0.0, x);
    if (total <= 0) return 0.0;
    double h = 0.0;
    for (double x : p) {
        const double q = std::max(0.0, x) / total;
        if (q > 0) h -= q * std::log2(q);
    }
    return h;
}

}  // namespace stats
