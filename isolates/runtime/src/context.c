/* context.c - lay out a fresh fiber stack for the assembly switch. */
#include "isolates.h"

#include <string.h>

void iso_ctx_init(iso_ctx *ctx, void *stack_base, size_t stack_size,
                  void (*entry)(void *), void *arg)
{
    uintptr_t top = ((uintptr_t)stack_base + stack_size) & ~(uintptr_t)15;
#if defined(__x86_64__)
    /* Frame popped by iso_ctx_switch: r15 r14 r13 r12 rbx rbp, then the
     * return address, then two padding slots. After the six pops and the
     * `ret`, rsp == top - 16, which is 16-byte aligned as the ABI requires
     * at the trampoline's first instruction. */
    uint64_t *sp = (uint64_t *)(top - 72);
    memset(sp, 0, 72);
    sp[2] = (uint64_t)(uintptr_t)entry; /* r13 */
    sp[3] = (uint64_t)(uintptr_t)arg;   /* r12 */
    sp[6] = (uint64_t)(uintptr_t)iso_ctx_trampoline;
    ctx->sp = sp;
#elif defined(__aarch64__)
    uint64_t *sp = (uint64_t *)(top - 160);
    memset(sp, 0, 160);
    sp[0]  = (uint64_t)(uintptr_t)arg;   /* x19 */
    sp[1]  = (uint64_t)(uintptr_t)entry; /* x20 */
    sp[11] = (uint64_t)(uintptr_t)iso_ctx_trampoline; /* x30 */
    ctx->sp = sp;
#else
#error "isolates: unsupported architecture (need x86_64 or aarch64)"
#endif
}

const char *iso_ctx_arch(void)
{
#if defined(__x86_64__)
    return "x86_64";
#elif defined(__aarch64__)
    return "aarch64";
#else
    return "unknown";
#endif
}
