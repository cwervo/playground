/*
 * smfb_core.h — Shannon Mouse Fly Brain, simulation core.
 *
 * A scaled, procedurally generated Drosophila-style connectome driving a
 * population of leaky integrate-and-fire (LIF) neurons, plus a tiny 2-D
 * arena in which a mouse (Theseus, after Claude Shannon's 1950 maze mouse)
 * is steered by the brain's descending neurons.
 *
 * Everything here is plain C so the same core runs on iOS, macOS, watchOS,
 * tvOS and Linux. On arm64 the hot loops are hand-written NEON assembly
 * (lif_neon.S); every kernel has a lane-for-lane identical portable C
 * fallback (lif_portable.c) so results are bit-exact across the two paths.
 */
#ifndef SMFB_CORE_H
#define SMFB_CORE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ------------------------------------------------------------------------
 * Regions (neuropils / cell classes). Order matters: it is the order the
 * populations are laid out in memory, and the schematic renderer indexes it.
 * ---------------------------------------------------------------------- */
typedef enum smfb_region {
    SMFB_ORN_L = 0,    /* olfactory receptor neurons, left antenna          */
    SMFB_ORN_R,        /* olfactory receptor neurons, right antenna         */
    SMFB_AL_L,         /* antennal lobe projection neurons                  */
    SMFB_AL_R,
    SMFB_KC_L,         /* mushroom body Kenyon cells (sparse odor code)     */
    SMFB_KC_R,
    SMFB_APL_L,        /* anterior paired lateral neuron (KC feedback inh.) */
    SMFB_APL_R,
    SMFB_MBON_APP_L,   /* mushroom body output neurons, approach valence    */
    SMFB_MBON_APP_R,
    SMFB_MBON_AV_L,    /* mushroom body output neurons, avoidance valence   */
    SMFB_MBON_AV_R,
    SMFB_LH_L,         /* lateral horn (innate odor valence)                */
    SMFB_LH_R,
    SMFB_CX,           /* central complex (EB ring + FB steering columns)   */
    SMFB_DN_L,         /* descending neurons: turn left                     */
    SMFB_DN_R,         /* descending neurons: turn right                    */
    SMFB_DN_FWD,       /* descending neurons: forward walking (DNp09-like)  */
    SMFB_MECH_L,       /* mechanosensory bristles, left whisker/leg         */
    SMFB_MECH_R,
    SMFB_DAN,          /* PAM dopaminergic reward neurons                   */
    SMFB_REGION_COUNT
} smfb_region;

typedef struct smfb_region_span {
    uint32_t start;    /* first neuron index (multiple of 4)                */
    uint32_t count;    /* neurons in the region (multiple of 4)             */
} smfb_region_span;

const char *smfb_region_name(smfb_region r);
int smfb_region_is_left(smfb_region r);   /* 1 = left hemisphere, 0 = right, -1 = midline */

/* ------------------------------------------------------------------------
 * Connectome: compressed sparse rows keyed by presynaptic neuron, so a
 * spike scatters its outgoing weights into the postsynaptic currents.
 * ---------------------------------------------------------------------- */
typedef struct smfb_connectome {
    uint32_t  n_neurons;      /* padded to a multiple of 16                 */
    uint32_t  n_synapses;
    uint32_t *row_ptr;        /* n_neurons + 1                              */
    uint32_t *col_idx;        /* n_synapses, sorted within each row         */
    float    *weight;         /* n_synapses, mV of postsynaptic current     */
    float    *bias;           /* n_neurons, tonic input per neuron (mV)     */
    smfb_region_span regions[SMFB_REGION_COUNT];
} smfb_connectome;

/* scale = 1 gives ~1.8k neurons / ~25k synapses; everything scales linearly. */
smfb_connectome *smfb_connectome_build(uint32_t scale, uint64_t seed);
void             smfb_connectome_free(smfb_connectome *c);

/* ------------------------------------------------------------------------
 * Kernels. Both implementations share these exact signatures; the
 * dispatcher below chooses between them.
 * ---------------------------------------------------------------------- */
typedef struct smfb_lif_args {
    float          *v;            /* 0  membrane potential (mV)              */
    float          *i_syn;        /* 8  synaptic current (mV, decays)        */
    const float    *i_ext;        /* 16 external input (mV)                  */
    uint32_t       *refrac;       /* 24 refractory steps remaining           */
    uint32_t       *rng4;         /* 32 four xorshift32 lanes, updated       */
    uint32_t       *out_spikes;   /* 40 indices of neurons that fired        */
    uint32_t        n;            /* 48 neuron count, multiple of 4          */
    uint32_t        refrac_steps; /* 52                                      */
    float           decay_syn;    /* 56 exp(-dt/tau_syn)                     */
    float           k_m;          /* 60 dt/tau_m                             */
    float           v_rest;       /* 64                                      */
    float           v_reset;      /* 68                                      */
    float           v_th;         /* 72                                      */
    float           noise_amp;    /* 76 uniform noise amplitude (mV)         */
} smfb_lif_args;

/* Returns the number of spikes written to out_spikes. */
typedef uint32_t (*smfb_lif_step_fn)(const smfb_lif_args *a);
typedef void     (*smfb_propagate_fn)(const uint32_t *spikes, uint32_t count,
                                      const uint32_t *row_ptr, const uint32_t *col_idx,
                                      const float *weight, float *i_syn);
typedef void     (*smfb_scale_fn)(float *x, uint32_t n, float a);
typedef float    (*smfb_sum_fn)(const float *x, uint32_t n);

typedef struct smfb_kernels {
    smfb_lif_step_fn  lif_step;
    smfb_propagate_fn propagate;
    smfb_scale_fn     scale;
    smfb_sum_fn       sum;
    const char       *name;       /* "neon" or "portable"                   */
} smfb_kernels;

const smfb_kernels *smfb_kernels_portable(void);
const smfb_kernels *smfb_kernels_neon(void);      /* NULL when not arm64    */
const smfb_kernels *smfb_kernels_default(void);   /* neon if available      */

/* Portable reference implementations (always compiled). */
uint32_t smfb_lif_step_portable(const smfb_lif_args *a);
void     smfb_propagate_portable(const uint32_t *spikes, uint32_t count,
                                 const uint32_t *row_ptr, const uint32_t *col_idx,
                                 const float *weight, float *i_syn);
void     smfb_scale_portable(float *x, uint32_t n, float a);
float    smfb_sum_portable(const float *x, uint32_t n);

/* NEON implementations (only present on arm64). */
#if defined(__aarch64__) || defined(__arm64__)
#define SMFB_HAVE_NEON 1
uint32_t smfb_lif_step_neon(const smfb_lif_args *a);
void     smfb_propagate_neon(const uint32_t *spikes, uint32_t count,
                             const uint32_t *row_ptr, const uint32_t *col_idx,
                             const float *weight, float *i_syn);
void     smfb_scale_neon(float *x, uint32_t n, float a);
float    smfb_sum_neon(const float *x, uint32_t n);
#else
#define SMFB_HAVE_NEON 0
#endif

/* ------------------------------------------------------------------------
 * Brain: connectome + neuron state + plasticity + activity readouts.
 * ---------------------------------------------------------------------- */
typedef struct smfb_brain_params {
    float dt_ms;          /* integration step, default 1.0                  */
    float tau_m_ms;       /* membrane time constant, default 10             */
    float tau_syn_ms;     /* synaptic decay, default 5                      */
    float v_rest, v_reset, v_th;
    float refrac_ms;      /* absolute refractory period, default 2          */
    float noise_mv;       /* background noise amplitude, default 6          */
    float glow_tau_ms;    /* activity trace used for rendering, default 60  */
    float elig_tau_ms;    /* KC eligibility trace for plasticity, default 1000 */
    float learn_rate;     /* KC->MBON_AV depression per reward, default 0.15 */
} smfb_brain_params;

smfb_brain_params smfb_brain_params_default(void);

typedef struct smfb_brain {
    smfb_connectome   *c;
    smfb_brain_params  p;
    const smfb_kernels *k;
    float    *v, *i_syn, *i_ext, *glow, *elig;
    uint32_t *refrac, *spikes;
    uint32_t  rng4[4];
    uint32_t  n_spikes;          /* spikes in the last step                 */
    uint64_t  step_count;
    uint64_t  total_spikes;
    uint32_t  region_spikes[SMFB_REGION_COUNT]; /* last step, per region    */
    float     dan_accum;         /* DAN spikes since the last plasticity pass */
} smfb_brain;

smfb_brain *smfb_brain_create(uint32_t scale, uint64_t seed, const smfb_brain_params *p /* NULL ok */);
void        smfb_brain_destroy(smfb_brain *b);
void        smfb_brain_use_kernels(smfb_brain *b, const smfb_kernels *k);
void        smfb_brain_step(smfb_brain *b);
/* Set external drive (mV) on every neuron of a region; `fraction` in (0,1] limits it to the first part. */
void        smfb_brain_drive_region(smfb_brain *b, smfb_region r, float mv, float fraction);
void        smfb_brain_clear_drive(smfb_brain *b);
float       smfb_brain_region_rate(const smfb_brain *b, smfb_region r);   /* mean glow, ~ spikes per glow_tau */
void        smfb_brain_apply_plasticity(smfb_brain *b);  /* reward-gated KC->MBON_AV depression */
uint32_t    smfb_brain_neuron_count(const smfb_brain *b);
uint32_t    smfb_brain_synapse_count(const smfb_brain *b);

/* ------------------------------------------------------------------------
 * World: arena, mouse, food, sensory-motor loop.
 * ---------------------------------------------------------------------- */
#define SMFB_MAX_FOOD 64

typedef struct smfb_food {
    float x, y;
    float amount;      /* 1.0 = fresh pellet, 0 = gone                       */
} smfb_food;

typedef struct smfb_mouse {
    float x, y;         /* arena units: width is 1.0, height is aspect      */
    float heading;      /* radians, 0 = +x                                   */
    float speed;        /* arena units per second                            */
    float gait_phase;   /* radians, advances with distance travelled         */
    float tail_phase;
    float eating;       /* 0..1, ramps up while chewing                      */
} smfb_mouse;

typedef struct smfb_world {
    float       width, height;
    smfb_mouse  mouse;
    smfb_food   food[SMFB_MAX_FOOD];
    uint32_t    n_food;
    uint32_t    pellets_eaten;
    /* readouts for the UI */
    float odor_l, odor_r;
    float rate_dn_l, rate_dn_r, rate_dn_fwd;
    float bump_l, bump_r;
    float reward;             /* seconds of reward drive remaining             */
    double time_s;
    float  brain_time_accum_ms;
} smfb_world;

void  smfb_world_init(smfb_world *w, float width, float height);
void  smfb_world_drop_food(smfb_world *w, float x, float y);
/* Advance by `seconds` of simulated time; runs the brain at its own dt. */
void  smfb_world_step(smfb_world *w, smfb_brain *b, float seconds);

#ifdef __cplusplus
}
#endif
#endif /* SMFB_CORE_H */
