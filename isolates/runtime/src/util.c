/* util.c - clocks, growable buffers, JSON reading and writing. */
#include "isolates.h"

#include <ctype.h>
#include <math.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

uint64_t iso_now_ns(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}

uint64_t iso_now_ms(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    return (uint64_t)ts.tv_sec * 1000ull + (uint64_t)ts.tv_nsec / 1000000ull;
}

/* ------------------------------------------------------------------ */
/* iso_buf                                                             */
/* ------------------------------------------------------------------ */
void iso_buf_free(iso_buf *b)
{
    free(b->p);
    b->p = NULL;
    b->n = b->cap = 0;
}

static int buf_reserve(iso_buf *b, size_t extra)
{
    if (b->n + extra + 1 <= b->cap)
        return 0;
    size_t ncap = b->cap ? b->cap : 256;
    while (ncap < b->n + extra + 1)
        ncap *= 2;
    char *np = realloc(b->p, ncap);
    if (!np)
        return -1;
    b->p = np;
    b->cap = ncap;
    return 0;
}

int iso_buf_append(iso_buf *b, const char *p, size_t n)
{
    if (buf_reserve(b, n) < 0)
        return -1;
    memcpy(b->p + b->n, p, n);
    b->n += n;
    b->p[b->n] = 0;
    return 0;
}

int iso_buf_puts(iso_buf *b, const char *s)
{
    return iso_buf_append(b, s, strlen(s));
}

int iso_buf_printf(iso_buf *b, const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    va_list ap2;
    va_copy(ap2, ap);
    int need = vsnprintf(NULL, 0, fmt, ap);
    va_end(ap);
    if (need < 0 || buf_reserve(b, (size_t)need) < 0) {
        va_end(ap2);
        return -1;
    }
    vsnprintf(b->p + b->n, (size_t)need + 1, fmt, ap2);
    va_end(ap2);
    b->n += (size_t)need;
    return 0;
}

int iso_buf_json_str(iso_buf *b, const char *s, size_t n)
{
    if (iso_buf_append(b, "\"", 1) < 0)
        return -1;
    for (size_t i = 0; i < n; i++) {
        unsigned char c = (unsigned char)s[i];
        const char *esc = NULL;
        char tmp[8];
        switch (c) {
        case '"': esc = "\\\""; break;
        case '\\': esc = "\\\\"; break;
        case '\n': esc = "\\n"; break;
        case '\r': esc = "\\r"; break;
        case '\t': esc = "\\t"; break;
        case '\b': esc = "\\b"; break;
        case '\f': esc = "\\f"; break;
        default:
            if (c < 0x20) {
                snprintf(tmp, sizeof tmp, "\\u%04x", c);
                esc = tmp;
            }
        }
        if (esc) {
            if (iso_buf_puts(b, esc) < 0)
                return -1;
        } else if (iso_buf_append(b, (const char *)&c, 1) < 0)
            return -1;
    }
    return iso_buf_append(b, "\"", 1);
}

/* ------------------------------------------------------------------ */
/* JSON parser                                                         */
/* ------------------------------------------------------------------ */
typedef struct jp {
    const char *start;
    const char *p, *end;
    char *err;
    size_t errlen;
    int depth;
} jp;

static void jp_fail(jp *j, const char *msg)
{
    if (j->err && j->errlen && !j->err[0])
        snprintf(j->err, j->errlen, "json: %s at offset %zu", msg,
                 (size_t)(j->p - j->start));
}

static void jp_ws(jp *j)
{
    while (j->p < j->end && isspace((unsigned char)*j->p))
        j->p++;
}

static json_val *jv_new(int t)
{
    json_val *v = calloc(1, sizeof *v);
    if (v)
        v->t = t;
    return v;
}

static void json_free_contents(json_val *v)
{
    free(v->str);
    for (int i = 0; i < v->n; i++)
        json_free_contents(&v->items[i]);
    free(v->items);
    if (v->keys) {
        for (int i = 0; i < v->n; i++)
            free(v->keys[i]);
        free(v->keys);
    }
    memset(v, 0, sizeof *v);
}

void json_free(json_val *v)
{
    if (!v)
        return;
    json_free_contents(v);
    free(v);
}

static int jp_value(jp *j, json_val *out);

static int jp_string(jp *j, char **out)
{
    if (j->p >= j->end || *j->p != '"') {
        jp_fail(j, "expected string");
        return -1;
    }
    j->p++;
    iso_buf b = {0};
    while (j->p < j->end && *j->p != '"') {
        unsigned char c = (unsigned char)*j->p++;
        if (c == '\\') {
            if (j->p >= j->end) {
                iso_buf_free(&b);
                jp_fail(j, "bad escape");
                return -1;
            }
            char e = *j->p++;
            switch (e) {
            case '"': iso_buf_append(&b, "\"", 1); break;
            case '\\': iso_buf_append(&b, "\\", 1); break;
            case '/': iso_buf_append(&b, "/", 1); break;
            case 'b': iso_buf_append(&b, "\b", 1); break;
            case 'f': iso_buf_append(&b, "\f", 1); break;
            case 'n': iso_buf_append(&b, "\n", 1); break;
            case 'r': iso_buf_append(&b, "\r", 1); break;
            case 't': iso_buf_append(&b, "\t", 1); break;
            case 'u': {
                if (j->end - j->p < 4) {
                    iso_buf_free(&b);
                    jp_fail(j, "bad \\u escape");
                    return -1;
                }
                char hex[5] = {j->p[0], j->p[1], j->p[2], j->p[3], 0};
                j->p += 4;
                unsigned cp = (unsigned)strtoul(hex, NULL, 16);
                if (cp >= 0xD800 && cp <= 0xDBFF && j->end - j->p >= 6 &&
                    j->p[0] == '\\' && j->p[1] == 'u') {
                    char hex2[5] = {j->p[2], j->p[3], j->p[4], j->p[5], 0};
                    unsigned lo = (unsigned)strtoul(hex2, NULL, 16);
                    if (lo >= 0xDC00 && lo <= 0xDFFF) {
                        cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
                        j->p += 6;
                    }
                }
                char u[4];
                int n;
                if (cp < 0x80) {
                    u[0] = (char)cp; n = 1;
                } else if (cp < 0x800) {
                    u[0] = (char)(0xC0 | (cp >> 6));
                    u[1] = (char)(0x80 | (cp & 0x3F)); n = 2;
                } else if (cp < 0x10000) {
                    u[0] = (char)(0xE0 | (cp >> 12));
                    u[1] = (char)(0x80 | ((cp >> 6) & 0x3F));
                    u[2] = (char)(0x80 | (cp & 0x3F)); n = 3;
                } else {
                    u[0] = (char)(0xF0 | (cp >> 18));
                    u[1] = (char)(0x80 | ((cp >> 12) & 0x3F));
                    u[2] = (char)(0x80 | ((cp >> 6) & 0x3F));
                    u[3] = (char)(0x80 | (cp & 0x3F)); n = 4;
                }
                iso_buf_append(&b, u, (size_t)n);
                break;
            }
            default:
                iso_buf_free(&b);
                jp_fail(j, "bad escape");
                return -1;
            }
        } else {
            iso_buf_append(&b, (const char *)&c, 1);
        }
    }
    if (j->p >= j->end) {
        iso_buf_free(&b);
        jp_fail(j, "unterminated string");
        return -1;
    }
    j->p++;
    if (!b.p)
        iso_buf_append(&b, "", 0);
    *out = b.p;
    return 0;
}

static int jp_push(json_val *c, const char *key)
{
    json_val *items = realloc(c->items, (size_t)(c->n + 1) * sizeof *items);
    if (!items)
        return -1;
    c->items = items;
    memset(&c->items[c->n], 0, sizeof c->items[c->n]);
    if (key) {
        char **keys = realloc(c->keys, (size_t)(c->n + 1) * sizeof *keys);
        if (!keys)
            return -1;
        c->keys = keys;
        c->keys[c->n] = (char *)key;
    }
    c->n++;
    return 0;
}

static int jp_value(jp *j, json_val *out)
{
    jp_ws(j);
    if (j->p >= j->end) {
        jp_fail(j, "unexpected end");
        return -1;
    }
    if (++j->depth > 64) {
        jp_fail(j, "too deep");
        return -1;
    }
    int rc = 0;
    char c = *j->p;
    if (c == '{') {
        out->t = J_OBJ;
        j->p++;
        jp_ws(j);
        if (j->p < j->end && *j->p == '}') {
            j->p++;
        } else {
            for (;;) {
                jp_ws(j);
                char *key;
                if (jp_string(j, &key) < 0) {
                    rc = -1;
                    break;
                }
                jp_ws(j);
                if (j->p >= j->end || *j->p != ':') {
                    free(key);
                    jp_fail(j, "expected ':'");
                    rc = -1;
                    break;
                }
                j->p++;
                if (jp_push(out, key) < 0) {
                    free(key);
                    rc = -1;
                    break;
                }
                if (jp_value(j, &out->items[out->n - 1]) < 0) {
                    rc = -1;
                    break;
                }
                jp_ws(j);
                if (j->p < j->end && *j->p == ',') {
                    j->p++;
                    continue;
                }
                if (j->p < j->end && *j->p == '}') {
                    j->p++;
                    break;
                }
                jp_fail(j, "expected ',' or '}'");
                rc = -1;
                break;
            }
        }
    } else if (c == '[') {
        out->t = J_ARR;
        j->p++;
        jp_ws(j);
        if (j->p < j->end && *j->p == ']') {
            j->p++;
        } else {
            for (;;) {
                if (jp_push(out, NULL) < 0) {
                    rc = -1;
                    break;
                }
                if (jp_value(j, &out->items[out->n - 1]) < 0) {
                    rc = -1;
                    break;
                }
                jp_ws(j);
                if (j->p < j->end && *j->p == ',') {
                    j->p++;
                    continue;
                }
                if (j->p < j->end && *j->p == ']') {
                    j->p++;
                    break;
                }
                jp_fail(j, "expected ',' or ']'");
                rc = -1;
                break;
            }
        }
    } else if (c == '"') {
        out->t = J_STR;
        rc = jp_string(j, &out->str);
    } else if (c == 't' && j->end - j->p >= 4 && strncmp(j->p, "true", 4) == 0) {
        out->t = J_BOOL;
        out->b = true;
        j->p += 4;
    } else if (c == 'f' && j->end - j->p >= 5 && strncmp(j->p, "false", 5) == 0) {
        out->t = J_BOOL;
        j->p += 5;
    } else if (c == 'n' && j->end - j->p >= 4 && strncmp(j->p, "null", 4) == 0) {
        out->t = J_NULL;
        j->p += 4;
    } else if (c == '-' || isdigit((unsigned char)c)) {
        out->t = J_NUM;
        char *stop;
        out->num = strtod(j->p, &stop);
        if (stop == j->p) {
            jp_fail(j, "bad number");
            rc = -1;
        } else
            j->p = stop;
    } else {
        jp_fail(j, "unexpected character");
        rc = -1;
    }
    j->depth--;
    return rc;
}

json_val *json_parse(const char *s, size_t n, char *err, size_t errlen)
{
    if (err && errlen)
        err[0] = 0;
    jp j = { s, s, s + n, err, errlen, 0 };
    json_val *v = jv_new(J_NULL);
    if (!v)
        return NULL;
    if (jp_value(&j, v) < 0) {
        json_free(v);
        return NULL;
    }
    jp_ws(&j);
    if (j.p != j.end) {
        jp_fail(&j, "trailing characters");
        json_free(v);
        return NULL;
    }
    return v;
}

json_val *json_get(json_val *obj, const char *key)
{
    if (!obj || obj->t != J_OBJ)
        return NULL;
    for (int i = 0; i < obj->n; i++)
        if (strcmp(obj->keys[i], key) == 0)
            return &obj->items[i];
    return NULL;
}

const char *json_str(json_val *obj, const char *key, const char *dflt)
{
    json_val *v = json_get(obj, key);
    return (v && v->t == J_STR) ? v->str : dflt;
}

double json_num(json_val *obj, const char *key, double dflt)
{
    json_val *v = json_get(obj, key);
    return (v && v->t == J_NUM) ? v->num : dflt;
}
