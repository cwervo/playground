/*
 * world.c — the arena. A mouse, some crumbs, and a fly brain in between.
 *
 * Sensory side: two "antennae" sample an odor field made of Gaussian plumes
 * around each pellet and drive the left/right ORNs; whiskers that poke past
 * the wall drive the mechanosensory neurons; chewing drives the DANs.
 * Motor side: descending-neuron rates set turning and forward speed.
 */
#include "smfb_core.h"
#include <math.h>
#include <string.h>

#define ANTENNA_ANGLE   0.70f     /* radians off the heading                  */
#define ANTENNA_REACH   0.07f     /* arena units                              */
#define PLUME_SIGMA     0.30f
#define ORN_GAIN        30.0f     /* mV at saturation                         */
#define FOOD_MARGIN     0.07f     /* keep pellets clear of the walls          */
#define WHISKER_REACH   0.045f
#define EAT_RADIUS      0.05f
#define EAT_RATE        0.45f     /* pellet per second                        */
#define REWARD_SECONDS  0.35f
#define TURN_GAIN       9.0f      /* rad/s per unit (rate_l - rate_r)         */
#define SPEED_BASE      0.02f
#define SPEED_GAIN      1.2f
#define SPEED_MAX       0.26f
#define RATE_TAU        0.08f     /* seconds, motor rate smoothing            */

void smfb_world_init(smfb_world *w, float width, float height)
{
    memset(w, 0, sizeof *w);
    w->width = width > 0 ? width : 1.f;
    w->height = height > 0 ? height : 1.f;
    w->mouse.x = w->width * 0.5f;
    w->mouse.y = w->height * 0.5f;
    w->mouse.heading = 0.7f;
    w->mouse.speed = SPEED_BASE;
}

void smfb_world_drop_food(smfb_world *w, float x, float y)
{
    if (x < FOOD_MARGIN) x = FOOD_MARGIN;
    if (x > w->width - FOOD_MARGIN) x = w->width - FOOD_MARGIN;
    if (y < FOOD_MARGIN) y = FOOD_MARGIN;
    if (y > w->height - FOOD_MARGIN) y = w->height - FOOD_MARGIN;
    uint32_t slot = w->n_food;
    if (slot >= SMFB_MAX_FOOD) {
        /* recycle the most-eaten pellet */
        slot = 0;
        for (uint32_t i = 1; i < w->n_food; i++)
            if (w->food[i].amount < w->food[slot].amount) slot = i;
    } else {
        w->n_food++;
    }
    w->food[slot].x = x;
    w->food[slot].y = y;
    w->food[slot].amount = 1.0f;
}

static float odor_at(const smfb_world *w, float x, float y)
{
    float sum = 0.f;
    const float inv = 1.0f / (2.0f * PLUME_SIGMA * PLUME_SIGMA);
    for (uint32_t i = 0; i < w->n_food; i++) {
        float dx = x - w->food[i].x, dy = y - w->food[i].y;
        sum += w->food[i].amount * expf(-(dx * dx + dy * dy) * inv);
    }
    return sum;
}

static void remove_food(smfb_world *w, uint32_t i)
{
    w->food[i] = w->food[w->n_food - 1];
    w->n_food--;
}

void smfb_world_step(smfb_world *w, smfb_brain *b, float seconds)
{
    if (seconds <= 0.f) return;
    if (seconds > 0.25f) seconds = 0.25f;   /* never try to catch up a long pause */
    smfb_mouse *m = &w->mouse;
    const float dt = b->p.dt_ms * 0.001f;

    /* --- sense ------------------------------------------------------- */
    float c = cosf(m->heading), s = sinf(m->heading);
    float lx = m->x + ANTENNA_REACH * cosf(m->heading + ANTENNA_ANGLE);
    float ly = m->y + ANTENNA_REACH * sinf(m->heading + ANTENNA_ANGLE);
    float rx = m->x + ANTENNA_REACH * cosf(m->heading - ANTENNA_ANGLE);
    float ry = m->y + ANTENNA_REACH * sinf(m->heading - ANTENNA_ANGLE);
    w->odor_l = odor_at(w, lx, ly);
    w->odor_r = odor_at(w, rx, ry);

    float wlx = m->x + WHISKER_REACH * cosf(m->heading + 0.9f);
    float wly = m->y + WHISKER_REACH * sinf(m->heading + 0.9f);
    float wrx = m->x + WHISKER_REACH * cosf(m->heading - 0.9f);
    float wry = m->y + WHISKER_REACH * sinf(m->heading - 0.9f);
    float nose_x = m->x + WHISKER_REACH * c, nose_y = m->y + WHISKER_REACH * s;
    int outside_l = wlx < 0 || wlx > w->width || wly < 0 || wly > w->height;
    int outside_r = wrx < 0 || wrx > w->width || wry < 0 || wry > w->height;
    int outside_n = nose_x < 0 || nose_x > w->width || nose_y < 0 || nose_y > w->height;
    w->bump_l = outside_l || (outside_n && !outside_r) ? 1.f : 0.f;
    w->bump_r = outside_r || (outside_n && !outside_l) ? 1.f : 0.f;
    if (outside_n && !outside_l && !outside_r) { w->bump_l = 1.f; }   /* head-on: pick a side */

    /* chewing? */
    int chewing = 0;
    for (uint32_t i = 0; i < w->n_food; i++) {
        float dx = m->x - w->food[i].x, dy = m->y - w->food[i].y;
        if (dx * dx + dy * dy < EAT_RADIUS * EAT_RADIUS) { chewing = 1; break; }
    }

    smfb_brain_clear_drive(b);
    /* half of each ORN population is tuned to food odor; saturating response */
    float dl = ORN_GAIN * w->odor_l / (0.6f + w->odor_l);
    float dr = ORN_GAIN * w->odor_r / (0.6f + w->odor_r);
    smfb_brain_drive_region(b, SMFB_ORN_L, dl, 0.5f);
    smfb_brain_drive_region(b, SMFB_ORN_R, dr, 0.5f);
    if (w->bump_l > 0) smfb_brain_drive_region(b, SMFB_MECH_L, 18.f, 1.f);
    if (w->bump_r > 0) smfb_brain_drive_region(b, SMFB_MECH_R, 18.f, 1.f);
    if (w->reward > 0) smfb_brain_drive_region(b, SMFB_DAN, 20.f, 1.f);

    /* --- think: run the brain at its own clock ------------------------ */
    w->brain_time_accum_ms += seconds * 1000.f;
    const float alpha = dt / RATE_TAU;
    while (w->brain_time_accum_ms >= b->p.dt_ms) {
        w->brain_time_accum_ms -= b->p.dt_ms;
        smfb_brain_step(b);
        const smfb_connectome *cn = b->c;
        float fl = (float)b->region_spikes[SMFB_DN_L]   / (float)cn->regions[SMFB_DN_L].count   / dt;
        float fr = (float)b->region_spikes[SMFB_DN_R]   / (float)cn->regions[SMFB_DN_R].count   / dt;
        float ff = (float)b->region_spikes[SMFB_DN_FWD] / (float)cn->regions[SMFB_DN_FWD].count / dt;
        /* rates in spikes/s per neuron, smoothed; scaled so ~100 Hz -> 1.0 */
        w->rate_dn_l   += alpha * (fl * 0.01f - w->rate_dn_l);
        w->rate_dn_r   += alpha * (fr * 0.01f - w->rate_dn_r);
        w->rate_dn_fwd += alpha * (ff * 0.01f - w->rate_dn_fwd);
    }
    if (w->reward > 0) smfb_brain_apply_plasticity(b);

    /* --- act ---------------------------------------------------------- */
    float target_speed = SPEED_BASE + SPEED_GAIN * w->rate_dn_fwd;
    if (target_speed > SPEED_MAX) target_speed = SPEED_MAX;
    float turn = TURN_GAIN * (w->rate_dn_l - w->rate_dn_r);
    if (chewing) { target_speed = 0.f; turn *= 0.2f; }
    m->eating += ((chewing ? 1.f : 0.f) - m->eating) * fminf(1.f, seconds * 6.f);
    m->speed += (target_speed - m->speed) * fminf(1.f, seconds * (chewing ? 40.f : 8.f));
    m->heading += turn * seconds;
    if (m->heading > 6.283185307f) m->heading -= 6.283185307f;
    if (m->heading < 0.f) m->heading += 6.283185307f;
    float step = m->speed * seconds;
    m->x += step * cosf(m->heading);
    m->y += step * sinf(m->heading);
    if (m->x < 0.01f) m->x = 0.01f;
    if (m->y < 0.01f) m->y = 0.01f;
    if (m->x > w->width - 0.01f) m->x = w->width - 0.01f;
    if (m->y > w->height - 0.01f) m->y = w->height - 0.01f;
    m->gait_phase += step * 200.f;
    m->tail_phase += seconds * (4.f + 30.f * m->speed);
    if (m->gait_phase > 6.283185307f) m->gait_phase -= 6.283185307f;
    if (m->tail_phase > 6.283185307f) m->tail_phase -= 6.283185307f;

    /* --- eat ---------------------------------------------------------- */
    for (uint32_t i = 0; i < w->n_food; ) {
        float dx = m->x - w->food[i].x, dy = m->y - w->food[i].y;
        if (dx * dx + dy * dy < EAT_RADIUS * EAT_RADIUS) {
            w->food[i].amount -= EAT_RATE * seconds;
            w->reward = REWARD_SECONDS;
            if (w->food[i].amount <= 0.f) { remove_food(w, i); w->pellets_eaten++; continue; }
        }
        i++;
    }
    if (w->reward > 0) w->reward -= seconds;
    w->time_s += seconds;
}
