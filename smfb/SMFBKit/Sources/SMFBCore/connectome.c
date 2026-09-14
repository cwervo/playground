/*
 * connectome.c — a procedural, FlyWire-shaped Drosophila connectome.
 *
 * The real fly brain (FlyWire / hemibrain) has ~140k neurons and ~50M
 * synapses; this generator lays out the same cell classes and the same
 * wiring logic — olfactory receptors -> antennal lobe -> Kenyon cells with
 * APL feedback inhibition -> mushroom body output neurons and lateral horn
 * -> central complex -> descending neurons — at a size a watch can step in
 * real time. Every rule is stated as an expected fan-in per postsynaptic
 * neuron, so synapse counts scale linearly with `scale`. The generator is
 * fully deterministic for a given seed.
 */
#define _POSIX_C_SOURCE 200809L
#include "smfb_core.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>

static const char *const region_names[SMFB_REGION_COUNT] = {
    "ORN L", "ORN R", "AL L", "AL R", "KC L", "KC R", "APL L", "APL R",
    "MBON+ L", "MBON+ R", "MBON- L", "MBON- R", "LH L", "LH R", "CX",
    "DN L", "DN R", "DN fwd", "MECH L", "MECH R", "DAN",
};

const char *smfb_region_name(smfb_region r)
{
    return (r >= 0 && r < SMFB_REGION_COUNT) ? region_names[r] : "?";
}

int smfb_region_is_left(smfb_region r)
{
    switch (r) {
    case SMFB_ORN_L: case SMFB_AL_L: case SMFB_KC_L: case SMFB_APL_L:
    case SMFB_MBON_APP_L: case SMFB_MBON_AV_L: case SMFB_LH_L:
    case SMFB_DN_L: case SMFB_MECH_L:
        return 1;
    case SMFB_CX: case SMFB_DN_FWD: case SMFB_DAN:
        return -1;
    default:
        return 0;
    }
}

/* Base population sizes at scale 1 (multiplied by scale, rounded up to 4). */
static const uint32_t base_counts[SMFB_REGION_COUNT] = {
    64, 64,     /* ORN     */
    32, 32,     /* AL PNs  */
    512, 512,   /* KC      */
    4, 4,       /* APL     */
    8, 8,       /* MBON+   */
    8, 8,       /* MBON-   */
    64, 64,     /* LH      */
    256,        /* CX      */
    16, 16, 16, /* DN L/R/fwd */
    32, 32,     /* MECH    */
    16,         /* DAN     */
};

/* Tonic drive per region (mV): the CX and forward DNs idle near threshold so
 * the mouse wanders on its own; sensory neurons sit quiet until driven. */
static const float base_bias[SMFB_REGION_COUNT] = {
    0, 0,  2, 2,  0, 0,  0, 0,  1, 1,  1, 1,  5, 5,  9.5f,  7, 7, 8,  0, 0,  0,
};

typedef struct rule {
    smfb_region pre, post;
    float k_in;        /* expected number of inputs per postsynaptic neuron */
    float w;           /* weight mean, mV; negative = inhibitory             */
    float w_cv;        /* coefficient of variation of the weight             */
} rule;

#define R(pre, post, k, w) { SMFB_##pre, SMFB_##post, k, w, 0.3f }
static const rule rules[] = {
    /* olfaction: ORN -> AL ipsilateral excitation, contralateral inhibition  */
    R(ORN_L, AL_L, 16, 6.0f), R(ORN_R, AL_R, 16, 6.0f),
    R(ORN_L, AL_R, 8, -3.0f), R(ORN_R, AL_L, 8, -3.0f),
    /* AL projection neurons -> Kenyon cells (~6 claws per KC) and LH        */
    R(AL_L, KC_L, 6, 8.0f),   R(AL_R, KC_R, 6, 8.0f),
    R(AL_L, LH_L, 16, 5.0f),  R(AL_R, LH_R, 16, 5.0f),
    /* APL feedback keeps the KC code sparse                                 */
    R(KC_L, APL_L, 64, 1.2f), R(KC_R, APL_R, 64, 1.2f),
    R(APL_L, KC_L, 2, -7.0f), R(APL_R, KC_R, 2, -7.0f),
    /* KC -> MBONs, both valences; reward learning depresses the aversive one */
    R(KC_L, MBON_APP_L, 100, 2.0f), R(KC_R, MBON_APP_R, 100, 2.0f),
    R(KC_L, MBON_AV_L, 100, 2.0f),  R(KC_R, MBON_AV_R, 100, 2.0f),
    /* innate attraction through the lateral horn                            */
    R(LH_L, DN_L, 20, 2.5f),  R(LH_R, DN_R, 20, 2.5f),
    R(LH_L, DN_R, 20, -2.5f), R(LH_R, DN_L, 20, -2.5f),
    /* strong odor means food is close: slow down (LH -> forward DNs)        */
    R(LH_L, DN_FWD, 20, -0.35f), R(LH_R, DN_FWD, 20, -0.35f),
    R(LH_L, CX, 10, 1.0f),    R(LH_R, CX, 10, 1.0f),
    /* learned valence: approach steers toward, avoidance steers away        */
    R(MBON_APP_L, DN_L, 8, 2.6f), R(MBON_APP_R, DN_R, 8, 2.6f),
    R(MBON_AV_L, DN_R, 8, 2.6f),  R(MBON_AV_R, DN_L, 8, 2.6f),
    /* central complex recurrence and its output to the descending neurons   */
    R(CX, CX, 14, 1.0f),      R(CX, CX, 6, -2.4f),
    R(CX, DN_FWD, 30, 0.7f),  R(CX, DN_L, 10, 0.5f), R(CX, DN_R, 10, 0.5f),
    /* whisker bump: turn away and pause                                     */
    R(MECH_L, DN_R, 10, 3.0f), R(MECH_R, DN_L, 10, 3.0f),
    R(MECH_L, DN_FWD, 10, -1.5f), R(MECH_R, DN_FWD, 10, -1.5f),
    /* winner-take-all turning                                               */
    R(DN_L, DN_R, 8, -1.5f),  R(DN_R, DN_L, 8, -1.5f),
};
#undef R

/* xorshift64* — generator RNG, independent of the simulation's lane RNGs */
typedef struct rng64 { uint64_t s; } rng64;
static inline uint64_t rng_next(rng64 *r)
{
    uint64_t x = r->s;
    x ^= x >> 12; x ^= x << 25; x ^= x >> 27;
    r->s = x;
    return x * 0x2545F4914F6CDD1DULL;
}
static inline double rng_unit(rng64 *r) { return (rng_next(r) >> 11) * (1.0 / 9007199254740992.0); }
static inline uint32_t rng_below(rng64 *r, uint32_t n) { return (uint32_t)(rng_unit(r) * n); }
static double rng_gauss(rng64 *r)
{
    double u = rng_unit(r), v = rng_unit(r);
    if (u < 1e-12) u = 1e-12;
    return sqrt(-2.0 * log(u)) * cos(6.283185307179586 * v);
}

typedef struct edge { uint32_t pre, post; float w; } edge;

static int edge_cmp(const void *a, const void *b)
{
    const edge *x = a, *y = b;
    if (x->pre != y->pre) return x->pre < y->pre ? -1 : 1;
    if (x->post != y->post) return x->post < y->post ? -1 : 1;
    return 0;
}

static void *aligned_zalloc(size_t bytes)
{
    void *p = NULL;
    size_t rounded = (bytes + 63) & ~(size_t)63;
    if (rounded == 0) rounded = 64;
    if (posix_memalign(&p, 64, rounded) != 0) return NULL;
    memset(p, 0, rounded);
    return p;
}

smfb_connectome *smfb_connectome_build(uint32_t scale, uint64_t seed)
{
    if (scale == 0) scale = 1;
    smfb_connectome *c = calloc(1, sizeof *c);
    if (!c) return NULL;

    uint32_t n = 0;
    for (int r = 0; r < SMFB_REGION_COUNT; r++) {
        uint32_t cnt = (base_counts[r] * scale + 3) & ~3u;
        c->regions[r].start = n;
        c->regions[r].count = cnt;
        n += cnt;
    }
    n = (n + 15) & ~15u;
    c->n_neurons = n;

    /* Sample edges rule by rule: for every postsynaptic neuron draw a
     * Poisson-ish number of presynaptic partners without replacement. */
    rng64 rng = { seed ? seed * 0x9E3779B97F4A7C15ULL : 0x5EED5EED5EED5EEDULL };
    size_t cap = 0, cnt = 0;
    edge *edges = NULL;
    for (size_t ri = 0; ri < sizeof rules / sizeof rules[0]; ri++) {
        const rule *rl = &rules[ri];
        smfb_region_span pre = c->regions[rl->pre], post = c->regions[rl->post];
        for (uint32_t j = 0; j < post.count; j++) {
            double kf = rl->k_in + rng_gauss(&rng) * sqrt(rl->k_in) * 0.5;
            uint32_t k = kf < 1 ? 1 : (uint32_t)(kf + 0.5);
            if (k > pre.count) k = pre.count;
            if (cnt + k > cap) {
                cap = cap ? cap * 2 : 4096;
                while (cnt + k > cap) cap *= 2;
                edges = realloc(edges, cap * sizeof *edges);
                if (!edges) { free(c); return NULL; }
            }
            for (uint32_t t = 0; t < k; t++) {
                uint32_t p = pre.start + rng_below(&rng, pre.count);
                if (rl->pre == rl->post && p == post.start + j) continue;   /* no autapses */
                float w = rl->w * (float)(1.0 + rl->w_cv * rng_gauss(&rng));
                if ((rl->w > 0 && w < 0.05f * rl->w) || (rl->w < 0 && w > 0.05f * rl->w))
                    w = 0.05f * rl->w;
                edges[cnt].pre = p;
                edges[cnt].post = post.start + j;
                edges[cnt].w = w;
                cnt++;
            }
        }
    }

    /* Sort, merge duplicates (same pre/post pair), and pack into CSR. */
    qsort(edges, cnt, sizeof *edges, edge_cmp);
    size_t uniq = 0;
    for (size_t i = 0; i < cnt; i++) {
        if (uniq > 0 && edges[uniq - 1].pre == edges[i].pre && edges[uniq - 1].post == edges[i].post) {
            edges[uniq - 1].w += edges[i].w;
        } else {
            edges[uniq++] = edges[i];
        }
    }
    c->n_synapses = (uint32_t)uniq;
    c->row_ptr = aligned_zalloc((size_t)(n + 1) * sizeof(uint32_t));
    c->col_idx = aligned_zalloc(uniq * sizeof(uint32_t));
    c->weight  = aligned_zalloc(uniq * sizeof(float));
    c->bias    = aligned_zalloc((size_t)n * sizeof(float));
    if (!c->row_ptr || !c->col_idx || !c->weight || !c->bias) {
        free(edges);
        smfb_connectome_free(c);
        return NULL;
    }
    for (size_t i = 0; i < uniq; i++) {
        c->row_ptr[edges[i].pre + 1]++;
        c->col_idx[i] = edges[i].post;
        c->weight[i] = edges[i].w;
    }
    for (uint32_t i = 0; i < n; i++) c->row_ptr[i + 1] += c->row_ptr[i];
    free(edges);

    for (int r = 0; r < SMFB_REGION_COUNT; r++) {
        smfb_region_span s = c->regions[r];
        for (uint32_t i = 0; i < s.count; i++)
            c->bias[s.start + i] = base_bias[r] * (float)(1.0 + 0.15 * rng_gauss(&rng));
    }
    return c;
}

void smfb_connectome_free(smfb_connectome *c)
{
    if (!c) return;
    free(c->row_ptr);
    free(c->col_idx);
    free(c->weight);
    free(c->bias);
    free(c);
}
