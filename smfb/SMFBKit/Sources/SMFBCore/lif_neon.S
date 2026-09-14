/*
 * lif_neon.S — arm64 NEON kernels for the Shannon Mouse Fly Brain.
 *
 * Assembled by clang (Apple or ELF). On any other architecture this file
 * compiles to an empty object, and dispatch.c falls back to lif_portable.c.
 *
 *   smfb_lif_step_neon   4 neurons per iteration: noise, leak, synaptic and
 *                        external input, refractory hold, threshold, reset,
 *                        and compaction of the firing indices.
 *   smfb_propagate_neon  event-driven scatter of each spiking neuron's CSR
 *                        row into the postsynaptic currents (scalar A64 —
 *                        NEON has no scatter; the win here is unrolling).
 *   smfb_scale_neon      x[i] *= a          (activity / eligibility decay)
 *   smfb_sum_neon        sum(x[0..n))       (per-region rate readout)
 *
 * All array lengths are multiples of 4 and every buffer is 16-byte aligned;
 * the C side guarantees both. Only caller-saved registers are used
 * (x0-x17, v0-v7, v16-v31): nothing is spilled and nothing must be restored.
 */
#if defined(__aarch64__) || defined(__arm64__)

#if defined(__APPLE__)
#define SYM(x) _##x
#define GLOBAL(x) .globl _##x
#define TYPE(x)
#define SIZE(x)
#else
#define SYM(x) x
#define GLOBAL(x) .globl x
#define TYPE(x) .type x, %function
#define SIZE(x) .size x, .-x
#endif

/* smfb_lif_args field offsets (pinned by static asserts in dispatch.c) */
#define A_V            0
#define A_ISYN         8
#define A_IEXT         16
#define A_REFRAC       24
#define A_RNG4         32
#define A_OUT          40
#define A_N            48
#define A_REFRAC_STEPS 52
#define A_DECAY_SYN    56
#define A_KM           60
#define A_VREST        64
#define A_VRESET       68
#define A_VTH          72
#define A_NOISE        76

    .text
    .p2align 4

/* ------------------------------------------------------------------------
 * uint32_t smfb_lif_step_neon(const smfb_lif_args *a)   x0 = a
 * ------------------------------------------------------------------------ */
GLOBAL(smfb_lif_step_neon)
TYPE(smfb_lif_step_neon)
SYM(smfb_lif_step_neon):
    ldp     x1, x2, [x0, #A_V]          // x1 = v, x2 = i_syn
    ldp     x3, x4, [x0, #A_IEXT]       // x3 = i_ext, x4 = refrac
    ldp     x5, x6, [x0, #A_RNG4]       // x5 = rng4, x6 = out_spikes
    ldr     w7, [x0, #A_N]              // w7 = n
    ldr     w8, [x0, #A_REFRAC_STEPS]
    add     x9, x0, #A_DECAY_SYN
    ld1r    {v16.4s}, [x9], #4          // decay_syn
    ld1r    {v17.4s}, [x9], #4          // k_m
    ld1r    {v18.4s}, [x9], #4          // v_rest
    ld1r    {v19.4s}, [x9], #4          // v_reset
    ld1r    {v20.4s}, [x9], #4          // v_th
    ld1r    {v21.4s}, [x9]              // noise_amp
    fmov    v22.4s, #0.5
    fmul    v22.4s, v22.4s, v21.4s      // 0.5 * amp
    fneg    v22.4s, v22.4s              // -0.5 * amp
    fmov    v23.4s, #1.0
    dup     v24.4s, w8                  // refrac_steps as vector
    movi    v25.4s, #1                  // ones (u32) for uqsub
    ld1     {v26.4s}, [x5]              // rng state, 4 lanes
    mov     x10, x6                     // x10 = out cursor
    mov     w11, #0                     // lane index base (neuron index i)
    cbz     w7, 9f

1:
    ld1     {v0.4s}, [x1]               // v
    ld1     {v1.4s}, [x2]               // i_syn
    ld1     {v2.4s}, [x3], #16          // i_ext
    ld1     {v3.4s}, [x4]               // refrac (u32)

    // xorshift32 on four lanes
    shl     v4.4s, v26.4s, #13
    eor     v26.16b, v26.16b, v4.16b
    ushr    v4.4s, v26.4s, #17
    eor     v26.16b, v26.16b, v4.16b
    shl     v4.4s, v26.4s, #5
    eor     v26.16b, v26.16b, v4.16b
    // uniform [0,1): (x >> 9) | 0x3f800000, minus 1.0
    ushr    v4.4s, v26.4s, #9
    orr     v4.4s, #0x3f, lsl #24       // 0x3f800000 needs two byte-immediates
    orr     v4.4s, #0x80, lsl #16
    fsub    v4.4s, v4.4s, v23.4s
    // noise = u*amp + (-amp/2)
    mov     v5.16b, v22.16b
    fmla    v5.4s, v4.4s, v21.4s

    // dv = ((v_rest - v) + i_syn) + i_ext) + noise
    fsub    v6.4s, v18.4s, v0.4s
    fadd    v6.4s, v6.4s, v1.4s
    fadd    v6.4s, v6.4s, v2.4s
    fadd    v6.4s, v6.4s, v5.4s
    // vn = v + dv*k_m
    mov     v7.16b, v0.16b
    fmla    v7.4s, v6.4s, v17.4s

    // refractory hold: where refrac > 0, vn = v_reset, refrac -= 1
    cmtst   v27.4s, v3.4s, v3.4s        // mask: refrac != 0
    bit     v7.16b, v19.16b, v27.16b    // vn = mask ? v_reset : vn
    uqsub   v3.4s, v3.4s, v25.4s        // saturating decrement

    // threshold
    fcmge   v28.4s, v7.4s, v20.4s       // spike mask
    bit     v7.16b, v19.16b, v28.16b    // vn = spike ? v_reset : vn
    bit     v3.16b, v24.16b, v28.16b    // refrac = spike ? refrac_steps : refrac

    // synaptic decay for the next step
    fmul    v1.4s, v1.4s, v16.4s

    st1     {v7.4s}, [x1], #16
    st1     {v1.4s}, [x2], #16
    st1     {v3.4s}, [x4], #16

    // any spikes in this group?
    umaxv   s29, v28.4s
    fmov    w12, s29
    cbnz    w12, 3f
2:
    add     w11, w11, #4
    cmp     w11, w7
    b.lo    1b
    b       8f

3:  // compaction: test each lane, store its index
    mov     w12, v28.s[0]
    cbz     w12, 4f
    str     w11, [x10], #4
4:  mov     w12, v28.s[1]
    cbz     w12, 5f
    add     w13, w11, #1
    str     w13, [x10], #4
5:  mov     w12, v28.s[2]
    cbz     w12, 6f
    add     w13, w11, #2
    str     w13, [x10], #4
6:  mov     w12, v28.s[3]
    cbz     w12, 2b
    add     w13, w11, #3
    str     w13, [x10], #4
    b       2b

8:
    st1     {v26.4s}, [x5]              // write back rng state
9:
    sub     x0, x10, x6
    lsr     x0, x0, #2                  // spike count
    ret
SIZE(smfb_lif_step_neon)

/* ------------------------------------------------------------------------
 * void smfb_propagate_neon(const uint32_t *spikes, uint32_t count,
 *                          const uint32_t *row_ptr, const uint32_t *col_idx,
 *                          const float *weight, float *i_syn)
 * x0 spikes, w1 count, x2 row_ptr, x3 col_idx, x4 weight, x5 i_syn
 * ------------------------------------------------------------------------ */
    .p2align 4
GLOBAL(smfb_propagate_neon)
TYPE(smfb_propagate_neon)
SYM(smfb_propagate_neon):
    cbz     w1, 9f
    add     x6, x0, w1, uxtw #2         // end of spike list
1:
    ldr     w7, [x0], #4                // pre
    add     x8, x2, w7, uxtw #2
    ldp     w9, w10, [x8]               // k = row_ptr[pre], end = row_ptr[pre+1]
    sub     w11, w10, w9                // remaining
    add     x12, x3, w9, uxtw #2        // &col_idx[k]
    add     x13, x4, w9, uxtw #2        // &weight[k]
    cmp     w11, #4
    b.lo    3f
2:  // four synapses per iteration; column indices within a row are unique,
    // so the four read-modify-writes cannot alias each other.
    ldp     w14, w15, [x12]
    ldp     w16, w17, [x12, #8]
    add     x12, x12, #16
    ldp     s0, s1, [x13]
    ldp     s2, s3, [x13, #8]
    add     x13, x13, #16
    add     x14, x5, w14, uxtw #2
    add     x15, x5, w15, uxtw #2
    add     x16, x5, w16, uxtw #2
    add     x17, x5, w17, uxtw #2
    ldr     s4, [x14]
    ldr     s5, [x15]
    ldr     s6, [x16]
    ldr     s7, [x17]
    fadd    s4, s4, s0
    fadd    s5, s5, s1
    fadd    s6, s6, s2
    fadd    s7, s7, s3
    str     s4, [x14]
    str     s5, [x15]
    str     s6, [x16]
    str     s7, [x17]
    sub     w11, w11, #4
    cmp     w11, #4
    b.hs    2b
3:
    cbz     w11, 5f
4:
    ldr     w14, [x12], #4
    ldr     s0, [x13], #4
    add     x14, x5, w14, uxtw #2
    ldr     s4, [x14]
    fadd    s4, s4, s0
    str     s4, [x14]
    subs    w11, w11, #1
    b.ne    4b
5:
    cmp     x0, x6
    b.lo    1b
9:
    ret
SIZE(smfb_propagate_neon)

/* ------------------------------------------------------------------------
 * void smfb_scale_neon(float *x, uint32_t n, float a)   x0, w1, s0
 * ------------------------------------------------------------------------ */
    .p2align 4
GLOBAL(smfb_scale_neon)
TYPE(smfb_scale_neon)
SYM(smfb_scale_neon):
    cbz     w1, 9f
    dup     v1.4s, v0.s[0]
    cmp     w1, #16
    b.lo    2f
1:
    ld1     {v2.4s, v3.4s, v4.4s, v5.4s}, [x0]
    fmul    v2.4s, v2.4s, v1.4s
    fmul    v3.4s, v3.4s, v1.4s
    fmul    v4.4s, v4.4s, v1.4s
    fmul    v5.4s, v5.4s, v1.4s
    st1     {v2.4s, v3.4s, v4.4s, v5.4s}, [x0], #64
    sub     w1, w1, #16
    cmp     w1, #16
    b.hs    1b
    cbz     w1, 9f
2:
    ld1     {v2.4s}, [x0]
    fmul    v2.4s, v2.4s, v1.4s
    st1     {v2.4s}, [x0], #16
    subs    w1, w1, #4
    b.ne    2b
9:
    ret
SIZE(smfb_scale_neon)

/* ------------------------------------------------------------------------
 * float smfb_sum_neon(const float *x, uint32_t n)   x0, w1 -> s0
 * Four running lane sums, then pairwise reduction (matches lif_portable.c).
 * ------------------------------------------------------------------------ */
    .p2align 4
GLOBAL(smfb_sum_neon)
TYPE(smfb_sum_neon)
SYM(smfb_sum_neon):
    movi    v0.4s, #0
    cbz     w1, 2f
1:
    ld1     {v1.4s}, [x0], #16
    fadd    v0.4s, v0.4s, v1.4s
    subs    w1, w1, #4
    b.ne    1b
2:
    faddp   v0.4s, v0.4s, v0.4s         // [s0+s1, s2+s3, s0+s1, s2+s3]
    faddp   s0, v0.2s                   // (s0+s1) + (s2+s3)
    ret
SIZE(smfb_sum_neon)

#endif /* arm64 */

#if defined(__ELF__)
    .section .note.GNU-stack,"",%progbits
#endif
