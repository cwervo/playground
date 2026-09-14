/* dispatch.c — choose NEON or portable kernels, and pin the ABI the assembly relies on. */
#include "smfb_core.h"
#include <stddef.h>

#define SMFB_STATIC_ASSERT(cond, name) typedef char smfb_assert_##name[(cond) ? 1 : -1]
SMFB_STATIC_ASSERT(offsetof(smfb_lif_args, v) == 0, v);
SMFB_STATIC_ASSERT(offsetof(smfb_lif_args, i_syn) == 8, i_syn);
SMFB_STATIC_ASSERT(offsetof(smfb_lif_args, i_ext) == 16, i_ext);
SMFB_STATIC_ASSERT(offsetof(smfb_lif_args, refrac) == 24, refrac);
SMFB_STATIC_ASSERT(offsetof(smfb_lif_args, rng4) == 32, rng4);
SMFB_STATIC_ASSERT(offsetof(smfb_lif_args, out_spikes) == 40, out);
SMFB_STATIC_ASSERT(offsetof(smfb_lif_args, n) == 48, n);
SMFB_STATIC_ASSERT(offsetof(smfb_lif_args, refrac_steps) == 52, rs);
SMFB_STATIC_ASSERT(offsetof(smfb_lif_args, decay_syn) == 56, ds);
SMFB_STATIC_ASSERT(offsetof(smfb_lif_args, k_m) == 60, km);
SMFB_STATIC_ASSERT(offsetof(smfb_lif_args, v_rest) == 64, vrest);
SMFB_STATIC_ASSERT(offsetof(smfb_lif_args, v_reset) == 68, vreset);
SMFB_STATIC_ASSERT(offsetof(smfb_lif_args, v_th) == 72, vth);
SMFB_STATIC_ASSERT(offsetof(smfb_lif_args, noise_amp) == 76, noise);

const smfb_kernels *smfb_kernels_neon(void)
{
#if SMFB_HAVE_NEON
    static const smfb_kernels k = {
        smfb_lif_step_neon, smfb_propagate_neon, smfb_scale_neon, smfb_sum_neon, "neon"
    };
    return &k;
#else
    return NULL;
#endif
}

const smfb_kernels *smfb_kernels_default(void)
{
    const smfb_kernels *k = smfb_kernels_neon();
    return k ? k : smfb_kernels_portable();
}
