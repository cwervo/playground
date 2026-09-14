/* brain.c — neuron state, stepping, activity traces and reward plasticity. */
#define _POSIX_C_SOURCE 200809L
#include "smfb_core.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>

smfb_brain_params smfb_brain_params_default(void)
{
    smfb_brain_params p;
    p.dt_ms = 1.0f;
    p.tau_m_ms = 10.0f;
    p.tau_syn_ms = 5.0f;
    p.v_rest = -65.0f;
    p.v_reset = -65.0f;
    p.v_th = -50.0f;
    p.refrac_ms = 2.0f;
    p.noise_mv = 50.0f;
    p.glow_tau_ms = 60.0f;
    p.elig_tau_ms = 1000.0f;
    p.learn_rate = 0.15f;
    return p;
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

smfb_brain *smfb_brain_create(uint32_t scale, uint64_t seed, const smfb_brain_params *params)
{
    smfb_brain *b = calloc(1, sizeof *b);
    if (!b) return NULL;
    b->p = params ? *params : smfb_brain_params_default();
    b->k = smfb_kernels_default();
    b->c = smfb_connectome_build(scale, seed);
    if (!b->c) { free(b); return NULL; }
    uint32_t n = b->c->n_neurons;
    b->v      = aligned_zalloc(n * sizeof(float));
    b->i_syn  = aligned_zalloc(n * sizeof(float));
    b->i_ext  = aligned_zalloc(n * sizeof(float));
    b->glow   = aligned_zalloc(n * sizeof(float));
    b->elig   = aligned_zalloc(n * sizeof(float));
    b->refrac = aligned_zalloc(n * sizeof(uint32_t));
    b->spikes = aligned_zalloc(n * sizeof(uint32_t));
    if (!b->v || !b->i_syn || !b->i_ext || !b->glow || !b->elig || !b->refrac || !b->spikes) {
        smfb_brain_destroy(b);
        return NULL;
    }
    uint64_t s = seed ^ 0xD1B54A32D192ED03ULL;
    for (int l = 0; l < 4; l++) {
        s ^= s << 13; s ^= s >> 7; s ^= s << 17;
        b->rng4[l] = (uint32_t)(s >> 8) | 1u;
    }
    for (uint32_t i = 0; i < n; i++) {
        /* start scattered between rest and threshold so the network doesn't fire in lockstep */
        s ^= s << 13; s ^= s >> 7; s ^= s << 17;
        float u = (float)((s >> 11) * (1.0 / 9007199254740992.0));
        b->v[i] = b->p.v_rest + (b->p.v_th - b->p.v_rest) * u * 0.8f;
    }
    smfb_brain_clear_drive(b);
    return b;
}

void smfb_brain_destroy(smfb_brain *b)
{
    if (!b) return;
    smfb_connectome_free(b->c);
    free(b->v); free(b->i_syn); free(b->i_ext); free(b->glow); free(b->elig);
    free(b->refrac); free(b->spikes);
    free(b);
}

void smfb_brain_use_kernels(smfb_brain *b, const smfb_kernels *k)
{
    if (k) b->k = k;
}

uint32_t smfb_brain_neuron_count(const smfb_brain *b)  { return b->c->n_neurons; }
uint32_t smfb_brain_synapse_count(const smfb_brain *b) { return b->c->n_synapses; }

void smfb_brain_clear_drive(smfb_brain *b)
{
    memcpy(b->i_ext, b->c->bias, b->c->n_neurons * sizeof(float));
}

void smfb_brain_drive_region(smfb_brain *b, smfb_region r, float mv, float fraction)
{
    smfb_region_span s = b->c->regions[r];
    uint32_t cnt = (uint32_t)(s.count * fraction + 0.5f);
    if (cnt > s.count) cnt = s.count;
    for (uint32_t i = 0; i < cnt; i++) b->i_ext[s.start + i] += mv;
}

static smfb_region region_of(const smfb_connectome *c, uint32_t idx)
{
    for (int r = SMFB_REGION_COUNT - 1; r >= 0; r--)
        if (idx >= c->regions[r].start) return (smfb_region)r;
    return SMFB_ORN_L;
}

void smfb_brain_step(smfb_brain *b)
{
    const smfb_connectome *c = b->c;
    const smfb_brain_params *p = &b->p;
    smfb_lif_args a;
    a.v = b->v; a.i_syn = b->i_syn; a.i_ext = b->i_ext; a.refrac = b->refrac;
    a.rng4 = b->rng4; a.out_spikes = b->spikes;
    a.n = c->n_neurons;
    a.refrac_steps = (uint32_t)(p->refrac_ms / p->dt_ms + 0.5f);
    a.decay_syn = expf(-p->dt_ms / p->tau_syn_ms);
    a.k_m = p->dt_ms / p->tau_m_ms;
    a.v_rest = p->v_rest; a.v_reset = p->v_reset; a.v_th = p->v_th;
    a.noise_amp = p->noise_mv;

    uint32_t n_sp = b->k->lif_step(&a);
    b->n_spikes = n_sp;
    b->total_spikes += n_sp;
    b->step_count++;

    /* spikes arrive at their targets on the next step */
    b->k->propagate(b->spikes, n_sp, c->row_ptr, c->col_idx, c->weight, b->i_syn);

    /* activity trace for rendering and rate readout */
    b->k->scale(b->glow, c->n_neurons, expf(-p->dt_ms / p->glow_tau_ms));
    b->k->scale(b->elig, c->n_neurons, expf(-p->dt_ms / p->elig_tau_ms));
    memset(b->region_spikes, 0, sizeof b->region_spikes);
    for (uint32_t i = 0; i < n_sp; i++) {
        uint32_t idx = b->spikes[i];
        b->glow[idx] += 1.0f;
        smfb_region r = region_of(c, idx);
        b->region_spikes[r]++;
        if (r == SMFB_KC_L || r == SMFB_KC_R) b->elig[idx] += 1.0f;
    }
    b->dan_accum += (float)b->region_spikes[SMFB_DAN];
}

float smfb_brain_region_rate(const smfb_brain *b, smfb_region r)
{
    smfb_region_span s = b->c->regions[r];
    if (s.count == 0) return 0.f;
    return b->k->sum(b->glow + s.start, s.count) / (float)s.count;
}

/* Three-factor rule: dopamine (reward) x recent KC activity (eligibility)
 * depresses the KC -> MBON-avoid synapses, the fly's appetitive memory. */
void smfb_brain_apply_plasticity(smfb_brain *b)
{
    if (b->dan_accum <= 0.f) return;
    const smfb_connectome *c = b->c;
    float dan = b->dan_accum / (float)c->regions[SMFB_DAN].count;
    b->dan_accum = 0.f;
    float lr = b->p.learn_rate * dan;
    if (lr > 0.9f) lr = 0.9f;
    uint32_t av_lo = c->regions[SMFB_MBON_AV_L].start;
    uint32_t av_hi = c->regions[SMFB_MBON_AV_R].start + c->regions[SMFB_MBON_AV_R].count;
    for (int side = 0; side < 2; side++) {
        smfb_region_span kc = c->regions[side ? SMFB_KC_R : SMFB_KC_L];
        for (uint32_t i = 0; i < kc.count; i++) {
            uint32_t pre = kc.start + i;
            float e = b->elig[pre];
            if (e < 0.05f) continue;
            float f = 1.0f - lr * (e > 1.f ? 1.f : e);
            for (uint32_t k = c->row_ptr[pre]; k < c->row_ptr[pre + 1]; k++) {
                uint32_t post = c->col_idx[k];
                if (post >= av_lo && post < av_hi) c->weight[k] *= f;
            }
        }
    }
}
