/*
 * context_aarch64.S - fiber context switch for the AArch64 (AAPCS64) ABI.
 *
 * void iso_ctx_switch(iso_ctx *from, iso_ctx *to);   from=x0, to=x1
 *
 * Saves x19-x28, x29 (fp), x30 (lr) and d8-d15 (callee-saved low halves)
 * in a 160-byte frame on the current stack, stores sp in from->sp, loads
 * to->sp and restores the same frame before returning through x30.
 */
        .text
        .globl  iso_ctx_switch
        .type   iso_ctx_switch, %function
iso_ctx_switch:
        sub     sp, sp, #160
        stp     x19, x20, [sp, #0]
        stp     x21, x22, [sp, #16]
        stp     x23, x24, [sp, #32]
        stp     x25, x26, [sp, #48]
        stp     x27, x28, [sp, #64]
        stp     x29, x30, [sp, #80]
        stp     d8,  d9,  [sp, #96]
        stp     d10, d11, [sp, #112]
        stp     d12, d13, [sp, #128]
        stp     d14, d15, [sp, #144]

        mov     x9, sp
        str     x9, [x0]                /* from->sp = sp */
        ldr     x9, [x1]                /* sp = to->sp   */
        mov     sp, x9

        ldp     x19, x20, [sp, #0]
        ldp     x21, x22, [sp, #16]
        ldp     x23, x24, [sp, #32]
        ldp     x25, x26, [sp, #48]
        ldp     x27, x28, [sp, #64]
        ldp     x29, x30, [sp, #80]
        ldp     d8,  d9,  [sp, #96]
        ldp     d10, d11, [sp, #112]
        ldp     d12, d13, [sp, #128]
        ldp     d14, d15, [sp, #144]
        add     sp, sp, #160
        ret
        .size   iso_ctx_switch, .-iso_ctx_switch

/*
 * iso_ctx_trampoline: first code on a fresh fiber. iso_ctx_init leaves the
 * argument in x19 and the entry function in x20.
 */
        .globl  iso_ctx_trampoline
        .type   iso_ctx_trampoline, %function
iso_ctx_trampoline:
        mov     x0, x19
        blr     x20
        brk     #0
        .size   iso_ctx_trampoline, .-iso_ctx_trampoline

        .section .note.GNU-stack,"",%progbits
