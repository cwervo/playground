/*
 * smfb_cli.c — headless Shannon Mouse Fly Brain.
 *
 *   smfb-cli [scale] [seconds] [seed]
 *
 * Runs the world with a few pellets and prints an ASCII arena plus the
 * per-region activity once a second. Useful for tuning the circuit without
 * an Apple device, and for profiling the kernels under qemu or on a Mac.
 */
#include "smfb_core.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static void draw(const smfb_world *w, const smfb_brain *b)
{
    enum { W = 48, H = 20 };
    char grid[H][W + 1];
    for (int y = 0; y < H; y++) { memset(grid[y], '.', W); grid[y][W] = 0; }
    for (uint32_t i = 0; i < w->n_food; i++) {
        int x = (int)(w->food[i].x / w->width * (W - 1)), y = (int)(w->food[i].y / w->height * (H - 1));
        grid[y][x] = w->food[i].amount > 0.5f ? '@' : 'o';
    }
    int mx = (int)(w->mouse.x / w->width * (W - 1)), my = (int)(w->mouse.y / w->height * (H - 1));
    static const char dirs[] = ">/^\\<\\v/";
    int d = (int)((w->mouse.heading / 6.2831853f) * 8.f + 0.5f) & 7;
    grid[my][mx] = dirs[d];
    printf("t=%6.2fs  mouse (%.2f,%.2f) hdg %.2f spd %.3f  odor L %.2f R %.2f  DN L %.2f R %.2f F %.2f  eaten %u\n",
           w->time_s, w->mouse.x, w->mouse.y, w->mouse.heading, w->mouse.speed,
           w->odor_l, w->odor_r, w->rate_dn_l, w->rate_dn_r, w->rate_dn_fwd, w->pellets_eaten);
    for (int y = 0; y < H; y++) puts(grid[y]);
    printf("  rates:");
    for (int r = 0; r < SMFB_REGION_COUNT; r++) printf(" %s=%.2f", smfb_region_name((smfb_region)r), smfb_brain_region_rate(b, (smfb_region)r));
    printf("\n\n");
}

int main(int argc, char **argv)
{
    uint32_t scale = argc > 1 ? (uint32_t)atoi(argv[1]) : 1;
    float seconds = argc > 2 ? (float)atof(argv[2]) : 20.f;
    uint64_t seed = argc > 3 ? (uint64_t)atoll(argv[3]) : 1;
    smfb_brain *b = smfb_brain_create(scale, seed, NULL);
    if (!b) { fprintf(stderr, "brain create failed\n"); return 1; }
    printf("smfb: %u neurons, %u synapses, kernels=%s\n", smfb_brain_neuron_count(b), smfb_brain_synapse_count(b), b->k->name);
    smfb_world w;
    smfb_world_init(&w, 1.f, 0.75f);
    smfb_world_drop_food(&w, 0.85f, 0.2f);
    smfb_world_drop_food(&w, 0.15f, 0.65f);
    smfb_world_drop_food(&w, 0.7f, 0.7f);
    clock_t c0 = clock();
    int frames = (int)(seconds * 60.f);
    for (int f = 0; f < frames; f++) {
        smfb_world_step(&w, b, 1.f / 60.f);
        if (f % 60 == 59) draw(&w, b);
    }
    double wall = (double)(clock() - c0) / CLOCKS_PER_SEC;
    printf("simulated %.1fs in %.2fs wall (%.1fx realtime), %llu steps, %.1f spikes/step\n",
           seconds, wall, seconds / (wall > 0 ? wall : 1e-9), (unsigned long long)b->step_count,
           (double)b->total_spikes / (double)b->step_count);
    smfb_brain_destroy(b);
    return 0;
}
