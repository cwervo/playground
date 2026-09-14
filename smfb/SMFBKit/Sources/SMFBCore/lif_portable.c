/*
 * lif_portable.c — reference implementations of the simulation kernels.
 *
 * These are written to be *lane-for-lane identical* to the NEON assembly in
 * lif_neon.S: four neurons are processed per iteration, each with its own
 * xorshift32 stream, and every floating point operation is issued in the
 * same order (fmaf where the assembly uses fmla). That is what lets the test
 * harness demand bit-exact agreement between the two paths.
 */
#include "smfb_core.h"
#include <math.h>
#include <string.h>

static inline uint32_t xorshift32(uint32_t x)
{
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    return x;
}

/* [0,1) from the top 23 bits, exactly as the assembly builds it. */
static inline float unit_float(uint32_t x)
{
    union { uint32_t u; float f; } c;
    c.u = (x >> 9) | 0x3f800000u;
    return c.f - 1.0f;
}

uint32_t smfb_lif_step_portable(const smfb_lif_args *a)
{
    float *v = a->v, *is = a->i_syn;
    const float *ie = a->i_ext;
    uint32_t *rf = a->refrac;
    uint32_t rng[4] = { a->rng4[0], a->rng4[1], a->rng4[2], a->rng4[3] };
    const float half_amp = 0.5f * a->noise_amp;
    uint32_t count = 0;

    for (uint32_t i = 0; i < a->n; i += 4) {
        for (uint32_t l = 0; l < 4; l++) {
            uint32_t j = i + l;
            uint32_t x = xorshift32(rng[l]);
            rng[l] = x;
            float u = unit_float(x);
            /* noise = u*amp - amp/2  (fmla in asm: acc + u*amp) */
            float noise = fmaf(u, a->noise_amp, -half_amp);
            float in    = is[j];
            float dv    = a->v_rest - v[j];
            dv = dv + in;
            dv = dv + ie[j];
            dv = dv + noise;
            float vn = fmaf(dv, a->k_m, v[j]);
            uint32_t r = rf[j];
            if (r > 0) { vn = a->v_reset; r -= 1; }
            uint32_t spike = vn >= a->v_th;
            if (spike) { vn = a->v_reset; r = a->refrac_steps; a->out_spikes[count++] = j; }
            v[j]  = vn;
            is[j] = in * a->decay_syn;
            rf[j] = r;
        }
    }
    a->rng4[0] = rng[0]; a->rng4[1] = rng[1]; a->rng4[2] = rng[2]; a->rng4[3] = rng[3];
    return count;
}

void smfb_propagate_portable(const uint32_t *spikes, uint32_t count,
                             const uint32_t *row_ptr, const uint32_t *col_idx,
                             const float *weight, float *i_syn)
{
    for (uint32_t s = 0; s < count; s++) {
        uint32_t pre = spikes[s];
        uint32_t k = row_ptr[pre], end = row_ptr[pre + 1];
        for (; k < end; k++)
            i_syn[col_idx[k]] += weight[k];
    }
}

void smfb_scale_portable(float *x, uint32_t n, float a)
{
    for (uint32_t i = 0; i < n; i++) x[i] *= a;
}

/* Four partial sums, combined pairwise like NEON's faddp, so rounding matches. */
float smfb_sum_portable(const float *x, uint32_t n)
{
    float s0 = 0.f, s1 = 0.f, s2 = 0.f, s3 = 0.f;
    for (uint32_t i = 0; i < n; i += 4) {
        s0 += x[i]; s1 += x[i + 1]; s2 += x[i + 2]; s3 += x[i + 3];
    }
    float p0 = s0 + s1, p1 = s2 + s3;
    return p0 + p1;
}

const smfb_kernels *smfb_kernels_portable(void)
{
    static const smfb_kernels k = {
        smfb_lif_step_portable, smfb_propagate_portable,
        smfb_scale_portable, smfb_sum_portable, "portable"
    };
    return &k;
}
