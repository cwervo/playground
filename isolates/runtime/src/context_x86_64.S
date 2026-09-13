/*
 * context_x86_64.S - fiber context switch for the System V x86-64 ABI.
 *
 * struct iso_ctx { void *sp; }
 *
 * void iso_ctx_switch(iso_ctx *from, iso_ctx *to);   from=rdi, to=rsi
 *
 * Callee-saved registers (rbp, rbx, r12-r15) are pushed onto the current
 * stack, the stack pointer is stored in from->sp, then to->sp becomes the
 * stack pointer and the same registers are popped. The final `ret` lands in
 * whoever called iso_ctx_switch on the other stack (or, for a fresh fiber,
 * in iso_ctx_trampoline).
 */
        .text
        .globl  iso_ctx_switch
        .type   iso_ctx_switch, @function
iso_ctx_switch:
        .cfi_startproc
        pushq   %rbp
        .cfi_adjust_cfa_offset 8
        pushq   %rbx
        .cfi_adjust_cfa_offset 8
        pushq   %r12
        .cfi_adjust_cfa_offset 8
        pushq   %r13
        .cfi_adjust_cfa_offset 8
        pushq   %r14
        .cfi_adjust_cfa_offset 8
        pushq   %r15
        .cfi_adjust_cfa_offset 8

        movq    %rsp, (%rdi)            /* from->sp = rsp */
        movq    (%rsi), %rsp            /* rsp = to->sp   */

        popq    %r15
        .cfi_adjust_cfa_offset -8
        popq    %r14
        .cfi_adjust_cfa_offset -8
        popq    %r13
        .cfi_adjust_cfa_offset -8
        popq    %r12
        .cfi_adjust_cfa_offset -8
        popq    %rbx
        .cfi_adjust_cfa_offset -8
        popq    %rbp
        .cfi_adjust_cfa_offset -8
        ret
        .cfi_endproc
        .size   iso_ctx_switch, .-iso_ctx_switch

/*
 * iso_ctx_trampoline: the first "return address" of a fresh fiber.
 * iso_ctx_init places the entry function in r13 and its argument in r12.
 * The entry function must never return; if it does we trap.
 */
        .globl  iso_ctx_trampoline
        .type   iso_ctx_trampoline, @function
iso_ctx_trampoline:
        .cfi_startproc
        .cfi_undefined rip              /* stop unwinders here */
        movq    %r12, %rdi
        callq   *%r13
        ud2
        .cfi_endproc
        .size   iso_ctx_trampoline, .-iso_ctx_trampoline

        .section .note.GNU-stack,"",@progbits
