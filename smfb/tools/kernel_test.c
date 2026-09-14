/*
 * kernel_test.c — checks the simulation kernels.
 *
 * On arm64 every kernel is run through both the NEON and the portable path on
 * identical inputs and the outputs must match bit for bit. On other hosts only
 * the portable path runs, and the invariants below still hold.
 */
#define _POSIX_C_SOURCE 200809L
#include "smfb_core.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures = 0;
#define CHECK(cond, ...) do { if (!(cond)) { failures++; printf("FAIL %s:%d: ", __FILE__, __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

static uint64_t rs = 0x1234567887654321ULL;
static uint32_t r32(void) { rs ^= rs << 13; rs ^= rs >> 7; rs ^= rs << 17; return (uint32_t)(rs >> 16); }
static float rf(float lo, float hi) { return lo + (hi - lo) * (r32() / 4294967296.0f); }

static void *al(size_t bytes) { void *p; if (posix_memalign(&p, 64, (bytes + 63) & ~63ul)) abort(); memset(p, 0, bytes); return p; }

static void run_lif(const smfb_kernels *k, uint32_t n, uint32_t steps, float *v, float *is, uint32_t *rf_, uint32_t *rng, uint32_t *out, uint32_t *count, const float *ie)
{
    smfb_lif_args a = { v, is, ie, rf_, rng, out, n, 2, 0.8187f, 0.1f, -65.f, -65.f, -50.f, 6.f };
    uint32_t total = 0;
    for (uint32_t s = 0; s < steps; s++) total += k->lif_step(&a);
    *count = total;
}

static void test_lif(const smfb_kernels *ka, const smfb_kernels *kb)
{
    const uint32_t n = 4096, steps = 50;
    float *v0 = al(n * 4), *is0 = al(n * 4), *ie = al(n * 4);
    uint32_t *rf0 = al(n * 4);
    for (uint32_t i = 0; i < n; i++) { v0[i] = rf(-70, -48); is0[i] = rf(-3, 12); ie[i] = rf(0, 14); rf0[i] = (r32() % 5 == 0) ? r32() % 3 : 0; }
    uint32_t rng0[4] = { 0x1234567, 0x89abcde, 0xf0f0f0f, 0x7777777 };

    float *va = al(n * 4), *isa = al(n * 4), *vb = al(n * 4), *isb = al(n * 4);
    uint32_t *rfa = al(n * 4), *rfb = al(n * 4), *outa = al(n * 4), *outb = al(n * 4), rnga[4], rngb[4], ca, cb;
    memcpy(va, v0, n * 4); memcpy(isa, is0, n * 4); memcpy(rfa, rf0, n * 4); memcpy(rnga, rng0, 16);
    memcpy(vb, v0, n * 4); memcpy(isb, is0, n * 4); memcpy(rfb, rf0, n * 4); memcpy(rngb, rng0, 16);
    run_lif(ka, n, steps, va, isa, rfa, rnga, outa, &ca, ie);
    run_lif(kb, n, steps, vb, isb, rfb, rngb, outb, &cb, ie);
    CHECK(ca == cb, "lif spike totals differ: %s=%u %s=%u", ka->name, ca, kb->name, cb);
    CHECK(memcmp(va, vb, n * 4) == 0, "lif membrane potentials differ");
    CHECK(memcmp(isa, isb, n * 4) == 0, "lif synaptic currents differ");
    CHECK(memcmp(rfa, rfb, n * 4) == 0, "lif refractory counters differ");
    CHECK(memcmp(rnga, rngb, 16) == 0, "lif rng state differs");
    CHECK(ca > 0, "no spikes at all");
    for (uint32_t i = 0; i < n; i++) CHECK(va[i] < -50.f, "v[%u]=%f above threshold after step", i, va[i]);

    /* single step: the emitted index list must be sorted and match v>=th logic */
    smfb_lif_args a = { va, isa, ie, rfa, rnga, outa, n, 2, 0.8187f, 0.1f, -65.f, -65.f, -50.f, 6.f };
    uint32_t c = ka->lif_step(&a);
    for (uint32_t i = 1; i < c; i++) CHECK(outa[i - 1] < outa[i], "spike list not sorted at %u", i);
    for (uint32_t i = 0; i < c; i++) CHECK(rfa[outa[i]] == 2 && va[outa[i]] == -65.f, "spiking neuron %u not reset", outa[i]);
    printf("  lif_step  %-8s vs %-8s  %u spikes / %u neuron-steps  ok\n", ka->name, kb->name, ca, n * steps);
    free(v0); free(is0); free(ie); free(rf0); free(va); free(isa); free(vb); free(isb); free(rfa); free(rfb); free(outa); free(outb);
}

static void test_propagate(const smfb_kernels *ka, const smfb_kernels *kb)
{
    smfb_connectome *c = smfb_connectome_build(2, 42);
    CHECK(c != NULL, "connectome build failed");
    uint32_t n = c->n_neurons;
    uint32_t *spk = al(n * 4), cnt = 0;
    for (uint32_t i = 0; i < n; i++) if (r32() % 20 == 0) spk[cnt++] = i;
    float *ia = al(n * 4), *ib = al(n * 4);
    for (uint32_t i = 0; i < n; i++) ia[i] = ib[i] = rf(-1, 1);
    ka->propagate(spk, cnt, c->row_ptr, c->col_idx, c->weight, ia);
    kb->propagate(spk, cnt, c->row_ptr, c->col_idx, c->weight, ib);
    CHECK(memcmp(ia, ib, n * 4) == 0, "propagate results differ");
    /* rows sorted & in range */
    for (uint32_t i = 0; i < n; i++)
        for (uint32_t k = c->row_ptr[i]; k + 1 < c->row_ptr[i + 1]; k++)
            CHECK(c->col_idx[k] < c->col_idx[k + 1] && c->col_idx[k + 1] < n, "row %u unsorted", i);
    printf("  propagate %-8s vs %-8s  %u spikes over %u synapses  ok\n", ka->name, kb->name, cnt, c->n_synapses);
    smfb_connectome_free(c);
    free(spk); free(ia); free(ib);
}

static void test_scale_sum(const smfb_kernels *ka, const smfb_kernels *kb)
{
    for (uint32_t n = 4; n <= 4096; n *= 2) {
        float *xa = al(n * 4), *xb = al(n * 4);
        for (uint32_t i = 0; i < n; i++) xa[i] = xb[i] = rf(-5, 5);
        float sa = ka->sum(xa, n), sb = kb->sum(xb, n);
        CHECK(sa == sb, "sum differs at n=%u: %g vs %g", n, sa, sb);
        double ref = 0; for (uint32_t i = 0; i < n; i++) ref += xa[i];
        CHECK(fabs(ref - sa) < 1e-3 * n, "sum off from double reference at n=%u", n);
        ka->scale(xa, n, 0.9f); kb->scale(xb, n, 0.9f);
        CHECK(memcmp(xa, xb, n * 4) == 0, "scale differs at n=%u", n);
        free(xa); free(xb);
    }
    /* odd multiple of 4 (not 16) exercises the tail loop */
    { uint32_t n = 44; float *xa = al(n * 4), *xb = al(n * 4);
      for (uint32_t i = 0; i < n; i++) xa[i] = xb[i] = (float)i;
      ka->scale(xa, n, 2.f); kb->scale(xb, n, 2.f);
      CHECK(memcmp(xa, xb, n * 4) == 0 && xa[43] == 86.f, "scale tail");
      free(xa); free(xb); }
    printf("  scale/sum %-8s vs %-8s  ok\n", ka->name, kb->name);
}

static void test_behaviour(const smfb_kernels *k)
{
    smfb_brain *b = smfb_brain_create(1, 7, NULL);
    CHECK(b != NULL, "brain create");
    smfb_brain_use_kernels(b, k);
    smfb_world w; smfb_world_init(&w, 1.f, 1.f);
    w.mouse.x = 0.2f; w.mouse.y = 0.5f; w.mouse.heading = 0.f;
    smfb_world_drop_food(&w, 0.8f, 0.5f);
    float d0 = 0.6f, best = d0; double t_eat = -1;
    for (int i = 0; i < 30 * 60 && t_eat < 0; i++) {
        smfb_world_step(&w, b, 1.f / 60.f);
        float dx = w.mouse.x - 0.8f, dy = w.mouse.y - 0.5f, d = sqrtf(dx * dx + dy * dy);
        if (d < best) best = d;
        if (w.pellets_eaten > 0) t_eat = w.time_s;
    }
    CHECK(b->total_spikes > 0, "brain silent");
    CHECK(best < d0 * 0.5f, "mouse never approached the pellet (closest %.3f)", best);
    CHECK(t_eat > 0, "mouse never ate the pellet within 30 s (closest %.3f)", best);
    printf("  behaviour %-8s  %u neurons, %u synapses, %.1f spikes/step; ate pellet at t=%.1fs  ok\n",
           k->name, smfb_brain_neuron_count(b), smfb_brain_synapse_count(b),
           (double)b->total_spikes / (double)b->step_count, t_eat);
    smfb_brain_destroy(b);
}

int main(void)
{
    const smfb_kernels *portable = smfb_kernels_portable();
    const smfb_kernels *neon = smfb_kernels_neon();
    const smfb_kernels *other = neon ? neon : portable;
    printf("kernel_test: neon %s\n", neon ? "available" : "not available on this host");
    test_lif(other, portable);
    test_propagate(other, portable);
    test_scale_sum(other, portable);
    test_behaviour(other);
    if (neon) test_behaviour(portable);
    printf(failures ? "%d FAILURES\n" : "all kernel tests passed\n", failures);
    return failures ? 1 : 0;
}
