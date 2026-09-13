/* arena.c - per-invocation bump allocator backed by mmap. */
#include "isolates.h"

#include <string.h>
#include <sys/mman.h>

int iso_arena_init(iso_arena *a, size_t size)
{
    size = (size + 4095) & ~(size_t)4095;
    void *p = mmap(NULL, size, PROT_READ | PROT_WRITE,
                   MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (p == MAP_FAILED) {
        a->base = NULL;
        return -1;
    }
    a->base = p;
    a->size = size;
    a->used = 0;
    a->peak = 0;
    return 0;
}

void *iso_arena_alloc(iso_arena *a, size_t n)
{
    size_t aligned = (n + 15) & ~(size_t)15;
    if (!a->base || aligned < n || a->used + aligned > a->size)
        return NULL;
    void *p = a->base + a->used;
    a->used += aligned;
    if (a->used > a->peak)
        a->peak = a->used;
    return p;
}

void iso_arena_reset(iso_arena *a)
{
    a->used = 0;
}

void iso_arena_free(iso_arena *a)
{
    if (a->base)
        munmap(a->base, a->size);
    memset(a, 0, sizeof *a);
}
