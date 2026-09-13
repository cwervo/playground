/* kv.c - per-isolate in-memory KV namespace (chained hash map). */
#include "isolates.h"

#include <stdlib.h>
#include <string.h>

#define KV_BUCKETS (sizeof ((iso_kv *)0)->buckets / sizeof ((iso_kv *)0)->buckets[0])

static size_t kv_hash(const char *key, size_t n)
{
    uint64_t h = 1469598103934665603ull;
    for (size_t i = 0; i < n; i++) {
        h ^= (unsigned char)key[i];
        h *= 1099511628211ull;
    }
    return (size_t)(h % KV_BUCKETS);
}

void iso_kv_init(iso_kv *kv)
{
    memset(kv, 0, sizeof *kv);
}

void iso_kv_free(iso_kv *kv)
{
    for (size_t b = 0; b < KV_BUCKETS; b++) {
        iso_kv_entry *e = kv->buckets[b];
        while (e) {
            iso_kv_entry *n = e->next;
            free(e->key);
            free(e->value);
            free(e);
            e = n;
        }
    }
    memset(kv, 0, sizeof *kv);
}

static iso_kv_entry *kv_find(const iso_kv *kv, const char *key, size_t n)
{
    for (iso_kv_entry *e = kv->buckets[kv_hash(key, n)]; e; e = e->next)
        if (strlen(e->key) == n && memcmp(e->key, key, n) == 0)
            return e;
    return NULL;
}

const iso_kv_entry *iso_kv_get(const iso_kv *kv, const char *key, size_t klen)
{
    return kv_find(kv, key, klen);
}

int iso_kv_put(iso_kv *kv, const char *key, size_t klen, const char *val, size_t vlen)
{
    if (vlen > ISO_KV_MAX_VALUE || klen == 0 || klen > 512)
        return -1;
    iso_kv_entry *e = kv_find(kv, key, klen);
    if (!e) {
        if (kv->count >= ISO_KV_MAX_ENTRIES)
            return -1;
        e = calloc(1, sizeof *e);
        if (!e)
            return -1;
        e->key = malloc(klen + 1);
        if (!e->key) {
            free(e);
            return -1;
        }
        memcpy(e->key, key, klen);
        e->key[klen] = 0;
        size_t b = kv_hash(key, klen);
        e->next = kv->buckets[b];
        kv->buckets[b] = e;
        kv->count++;
    }
    char *nv = malloc(vlen + 1);
    if (!nv)
        return -1;
    memcpy(nv, val, vlen);
    nv[vlen] = 0;
    free(e->value);
    e->value = nv;
    e->vlen = vlen;
    e->updated_ms = iso_now_ms();
    return 0;
}

bool iso_kv_del(iso_kv *kv, const char *key, size_t klen)
{
    iso_kv_entry **pp = &kv->buckets[kv_hash(key, klen)];
    while (*pp) {
        iso_kv_entry *e = *pp;
        if (strlen(e->key) == klen && memcmp(e->key, key, klen) == 0) {
            *pp = e->next;
            free(e->key);
            free(e->value);
            free(e);
            kv->count--;
            return true;
        }
        pp = &e->next;
    }
    return false;
}

void iso_kv_each(const iso_kv *kv, void (*fn)(const iso_kv_entry *, void *), void *user)
{
    for (size_t b = 0; b < KV_BUCKETS; b++)
        for (iso_kv_entry *e = kv->buckets[b]; e; e = e->next)
            fn(e, user);
}
