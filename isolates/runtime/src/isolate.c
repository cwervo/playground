/* isolate.c - isolates, fibers, scheduler, requests/responses, persistence. */
#include "isolates.h"

#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

/* ------------------------------------------------------------------ */
/* Requests / responses                                                */
/* ------------------------------------------------------------------ */
static char *dupn(const char *p, size_t n)
{
    char *s = malloc(n + 1);
    if (!s)
        return NULL;
    memcpy(s, p, n);
    s[n] = 0;
    return s;
}

void iso_request_init(iso_request *r)
{
    memset(r, 0, sizeof *r);
    r->method = strdup("GET");
    r->path = strdup("/");
    r->query = strdup("");
}

void iso_request_free(iso_request *r)
{
    free(r->method);
    free(r->path);
    free(r->query);
    free(r->body);
    for (int i = 0; i < r->nheaders; i++) {
        free(r->headers[i].name);
        free(r->headers[i].value);
    }
    memset(r, 0, sizeof *r);
}

int iso_request_add_header(iso_request *r, const char *n, size_t nl, const char *v, size_t vl)
{
    if (r->nheaders >= ISO_MAX_HEADERS)
        return -1;
    r->headers[r->nheaders].name = dupn(n, nl);
    r->headers[r->nheaders].value = dupn(v, vl);
    if (!r->headers[r->nheaders].name || !r->headers[r->nheaders].value)
        return -1;
    r->nheaders++;
    return 0;
}

const char *iso_request_header(const iso_request *r, const char *name)
{
    for (int i = 0; i < r->nheaders; i++)
        if (strcasecmp(r->headers[i].name, name) == 0)
            return r->headers[i].value;
    return NULL;
}

void iso_response_init(iso_response *r)
{
    memset(r, 0, sizeof *r);
    r->status = 200;
}

void iso_response_free(iso_response *r)
{
    free(r->body);
    for (int i = 0; i < r->nheaders; i++) {
        free(r->headers[i].name);
        free(r->headers[i].value);
    }
    memset(r, 0, sizeof *r);
}

int iso_response_set_header(iso_response *r, const char *n, size_t nl, const char *v, size_t vl)
{
    for (int i = 0; i < r->nheaders; i++) {
        if (strlen(r->headers[i].name) == nl && strncasecmp(r->headers[i].name, n, nl) == 0) {
            char *nv = dupn(v, vl);
            if (!nv)
                return -1;
            free(r->headers[i].value);
            r->headers[i].value = nv;
            return 0;
        }
    }
    if (r->nheaders >= ISO_MAX_HEADERS)
        return -1;
    r->headers[r->nheaders].name = dupn(n, nl);
    r->headers[r->nheaders].value = dupn(v, vl);
    if (!r->headers[r->nheaders].name || !r->headers[r->nheaders].value)
        return -1;
    r->nheaders++;
    return 0;
}

int iso_response_append(iso_response *r, const char *p, size_t n)
{
    if (r->body_len + n > ISO_MAX_BODY)
        return -1;
    if (r->body_len + n + 1 > r->body_cap) {
        size_t ncap = r->body_cap ? r->body_cap : 512;
        while (ncap < r->body_len + n + 1)
            ncap *= 2;
        char *nb = realloc(r->body, ncap);
        if (!nb)
            return -1;
        r->body = nb;
        r->body_cap = ncap;
    }
    memcpy(r->body + r->body_len, p, n);
    r->body_len += n;
    r->body[r->body_len] = 0;
    return 0;
}

/* ------------------------------------------------------------------ */
/* Platform / isolates                                                 */
/* ------------------------------------------------------------------ */
void iso_platform_init(iso_platform *p)
{
    memset(p, 0, sizeof *p);
    p->started_ms = iso_now_ms();
}

bool iso_name_valid(const char *name)
{
    size_t n = strlen(name);
    if (n == 0 || n >= ISO_NAME_MAX)
        return false;
    for (size_t i = 0; i < n; i++) {
        char c = name[i];
        if (!(islower((unsigned char)c) || isdigit((unsigned char)c) || c == '-'))
            return false;
    }
    return name[0] != '-' && name[n - 1] != '-';
}

iso_isolate *iso_platform_find(iso_platform *p, const char *name)
{
    for (iso_isolate *i = p->isolates; i; i = i->next)
        if (strcmp(i->name, name) == 0)
            return i;
    return NULL;
}

static void isolate_free(iso_isolate *iso)
{
    iso_script_unref(iso->script);
    iso_kv_free(&iso->kv);
    for (int i = 0; i < iso->nenv; i++) {
        free(iso->env[i].name);
        free(iso->env[i].value);
    }
    free(iso->env);
    free(iso);
}

iso_isolate *iso_platform_deploy(iso_platform *p, const char *name, iso_script *script,
                                 char *err, size_t errlen)
{
    if (!iso_name_valid(name)) {
        snprintf(err, errlen, "invalid worker name '%s' (use a-z, 0-9 and '-', max %d chars)",
                 name, ISO_NAME_MAX - 1);
        return NULL;
    }
    iso_isolate *iso = iso_platform_find(p, name);
    if (!iso) {
        iso = calloc(1, sizeof *iso);
        if (!iso) {
            snprintf(err, errlen, "out of memory");
            return NULL;
        }
        snprintf(iso->name, sizeof iso->name, "%s", name);
        iso_kv_init(&iso->kv);
        iso->cpu_limit = ISO_DEFAULT_CPU_LIMIT;
        iso->mem_limit = ISO_DEFAULT_MEM_LIMIT;
        iso->created_ms = iso_now_ms();
        /* append to keep listing order stable */
        iso_isolate **pp = &p->isolates;
        while (*pp)
            pp = &(*pp)->next;
        *pp = iso;
        p->nisolates++;
    }
    /* Hot swap: in-flight fibers keep a reference to the old script. */
    iso_script_ref(script);
    iso_script_unref(iso->script);
    iso->script = script;
    iso->deployed_ms = iso_now_ms();
    iso->deploys++;
    iso_isolate_log(iso, "deployed version %d (%u instructions, %u constants)",
                    iso->deploys, script->ncode, script->nconsts);
    return iso;
}

bool iso_platform_remove(iso_platform *p, const char *name)
{
    iso_isolate **pp = &p->isolates;
    while (*pp) {
        if (strcmp((*pp)->name, name) == 0) {
            iso_isolate *iso = *pp;
            if (iso->inflight > 0)
                return false; /* caller retries later */
            *pp = iso->next;
            isolate_free(iso);
            p->nisolates--;
            return true;
        }
        pp = &(*pp)->next;
    }
    return false;
}

void iso_platform_free(iso_platform *p)
{
    iso_isolate *i = p->isolates;
    while (i) {
        iso_isolate *n = i->next;
        isolate_free(i);
        i = n;
    }
    free(p->data_dir);
    memset(p, 0, sizeof *p);
}

void iso_isolate_set_limits(iso_isolate *iso, uint64_t cpu, size_t mem)
{
    if (cpu < 1000)
        cpu = 1000;
    if (cpu > 100000000ull)
        cpu = 100000000ull;
    if (mem < ISO_MIN_MEM_LIMIT)
        mem = ISO_MIN_MEM_LIMIT;
    if (mem > ISO_MAX_MEM_LIMIT)
        mem = ISO_MAX_MEM_LIMIT;
    iso->cpu_limit = cpu;
    iso->mem_limit = mem;
}

void iso_isolate_set_env(iso_isolate *iso, const char *name, const char *value)
{
    for (int i = 0; i < iso->nenv; i++) {
        if (strcmp(iso->env[i].name, name) == 0) {
            if (!value) {
                free(iso->env[i].name);
                free(iso->env[i].value);
                iso->env[i] = iso->env[--iso->nenv];
            } else {
                char *nv = strdup(value);
                if (nv) {
                    free(iso->env[i].value);
                    iso->env[i].value = nv;
                }
            }
            return;
        }
    }
    if (!value)
        return;
    iso_env *ne = realloc(iso->env, (size_t)(iso->nenv + 1) * sizeof *ne);
    if (!ne)
        return;
    iso->env = ne;
    iso->env[iso->nenv].name = strdup(name);
    iso->env[iso->nenv].value = strdup(value);
    iso->nenv++;
}

void iso_isolate_log(iso_isolate *iso, const char *fmt, ...)
{
    iso_log_entry *e = &iso->logs[(iso->log_head + iso->log_count) % ISO_LOG_RING];
    if (iso->log_count == ISO_LOG_RING)
        iso->log_head = (iso->log_head + 1) % ISO_LOG_RING;
    else
        iso->log_count++;
    e->ts_ms = iso_now_ms();
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(e->msg, sizeof e->msg, fmt, ap);
    va_end(ap);
}

/* ------------------------------------------------------------------ */
/* Persistence: <data>/<name>.isoasm + <data>/<name>.meta.json         */
/* ------------------------------------------------------------------ */
static int write_file(const char *path, const char *data, size_t n)
{
    char tmp[1024];
    snprintf(tmp, sizeof tmp, "%s.tmp", path);
    FILE *f = fopen(tmp, "wb");
    if (!f)
        return -1;
    if (fwrite(data, 1, n, f) != n) {
        fclose(f);
        unlink(tmp);
        return -1;
    }
    fclose(f);
    return rename(tmp, path);
}

static char *read_file(const char *path, size_t *n)
{
    FILE *f = fopen(path, "rb");
    if (!f)
        return NULL;
    iso_buf b = {0};
    char chunk[4096];
    size_t r;
    while ((r = fread(chunk, 1, sizeof chunk, f)) > 0)
        iso_buf_append(&b, chunk, r);
    fclose(f);
    if (!b.p)
        iso_buf_append(&b, "", 0);
    *n = b.n;
    return b.p;
}

int iso_platform_save(iso_platform *p, iso_isolate *iso)
{
    if (!p->data_dir)
        return 0;
    char path[1024];
    snprintf(path, sizeof path, "%s/%s.isoasm", p->data_dir, iso->name);
    if (write_file(path, iso->script->source, iso->script->source_len) < 0)
        return -1;
    iso_buf b = {0};
    iso_buf_printf(&b, "{\"cpu_limit\":%llu,\"mem_limit\":%zu,\"env\":{",
                   (unsigned long long)iso->cpu_limit, iso->mem_limit);
    for (int i = 0; i < iso->nenv; i++) {
        if (i)
            iso_buf_puts(&b, ",");
        iso_buf_json_str(&b, iso->env[i].name, strlen(iso->env[i].name));
        iso_buf_puts(&b, ":");
        iso_buf_json_str(&b, iso->env[i].value, strlen(iso->env[i].value));
    }
    iso_buf_puts(&b, "}}\n");
    snprintf(path, sizeof path, "%s/%s.meta.json", p->data_dir, iso->name);
    int rc = write_file(path, b.p, b.n);
    iso_buf_free(&b);
    return rc;
}

int iso_platform_unlink(iso_platform *p, const char *name)
{
    if (!p->data_dir)
        return 0;
    char path[1024];
    snprintf(path, sizeof path, "%s/%s.isoasm", p->data_dir, name);
    unlink(path);
    snprintf(path, sizeof path, "%s/%s.meta.json", p->data_dir, name);
    unlink(path);
    return 0;
}

int iso_platform_load_dir(iso_platform *p, const char *dir)
{
    free(p->data_dir);
    p->data_dir = strdup(dir);
    mkdir(dir, 0755);
    DIR *d = opendir(dir);
    if (!d)
        return -1;
    int loaded = 0;
    struct dirent *de;
    while ((de = readdir(d))) {
        size_t n = strlen(de->d_name);
        if (n < 8 || strcmp(de->d_name + n - 7, ".isoasm") != 0)
            continue;
        char name[ISO_NAME_MAX];
        if (n - 7 >= sizeof name)
            continue;
        memcpy(name, de->d_name, n - 7);
        name[n - 7] = 0;
        if (!iso_name_valid(name))
            continue;
        char path[1024];
        snprintf(path, sizeof path, "%s/%s", dir, de->d_name);
        size_t len;
        char *src = read_file(path, &len);
        if (!src)
            continue;
        iso_script *s;
        char err[256];
        if (iso_assemble(src, len, &s, err, sizeof err) < 0) {
            fprintf(stderr, "isolates: skipping %s: %s\n", path, err);
            free(src);
            continue;
        }
        free(src);
        iso_isolate *iso = iso_platform_deploy(p, name, s, err, sizeof err);
        iso_script_unref(s);
        if (!iso)
            continue;
        snprintf(path, sizeof path, "%s/%s.meta.json", dir, name);
        char *meta = read_file(path, &len);
        if (meta) {
            json_val *m = json_parse(meta, len, err, sizeof err);
            if (m) {
                iso_isolate_set_limits(iso,
                    (uint64_t)json_num(m, "cpu_limit", (double)iso->cpu_limit),
                    (size_t)json_num(m, "mem_limit", (double)iso->mem_limit));
                json_val *env = json_get(m, "env");
                if (env && env->t == J_OBJ)
                    for (int i = 0; i < env->n; i++)
                        if (env->items[i].t == J_STR)
                            iso_isolate_set_env(iso, env->keys[i], env->items[i].str);
                json_free(m);
            }
            free(meta);
        }
        loaded++;
    }
    closedir(d);
    return loaded;
}

/* ------------------------------------------------------------------ */
/* Fibers                                                              */
/* ------------------------------------------------------------------ */
static void fiber_main(void *arg)
{
    iso_fiber *f = arg;
    f->state = FIBER_RUNNING;
    for (;;) {
        uint64_t t0 = iso_now_ns();
        int r = iso_vm_run(f, ISO_SLICE);
        f->cpu_ns += iso_now_ns() - t0;
        if (r != 0)
            break;
        /* time slice over: hand the CPU back to the scheduler */
        f->switches++;
        iso_ctx_switch(&f->ctx, &f->sched->ctx);
    }
    f->state = FIBER_DONE;
    iso_ctx_switch(&f->ctx, &f->sched->ctx);
    /* A finished fiber is never resumed. */
    abort();
}

iso_fiber *iso_fiber_create(iso_platform *p, iso_isolate *iso, iso_request *req,
                            void (*on_done)(iso_fiber *, void *), void *user)
{
    iso_fiber *f = calloc(1, sizeof *f);
    if (!f)
        return NULL;
    f->iso = iso;
    f->script = iso->script;
    iso_script_ref(f->script);
    f->sched = &p->sched;
    f->req = *req;              /* move */
    memset(req, 0, sizeof *req);
    iso_response_init(&f->res);
    f->on_done = on_done;
    f->user = user;
    f->budget = iso->cpu_limit;
    f->state = FIBER_READY;

    if (iso_arena_init(&f->arena, iso->mem_limit) < 0) {
        iso_fiber_free(f);
        return NULL;
    }
    /* Fiber stack with a guard page below it. */
    long page = sysconf(_SC_PAGESIZE);
    f->stack_size = ISO_FIBER_STACK + (size_t)page;
    f->stack = mmap(NULL, f->stack_size, PROT_READ | PROT_WRITE,
                    MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (f->stack == MAP_FAILED) {
        f->stack = NULL;
        iso_fiber_free(f);
        return NULL;
    }
    mprotect(f->stack, (size_t)page, PROT_NONE);
    iso_ctx_init(&f->ctx, f->stack, f->stack_size, fiber_main, f);

    f->start_ns = iso_now_ns();
    iso->inflight++;
    iso->requests++;
    p->requests++;
    uint64_t sec = iso_now_ms() / 1000;
    if (sec != iso->rps_sec) {
        /* clear the slots we skipped */
        uint64_t gap = sec - iso->rps_sec;
        if (gap > 60)
            gap = 60;
        for (uint64_t k = 1; k <= gap; k++)
            iso->rps_ring[(iso->rps_sec + k) % 60] = 0;
        iso->rps_sec = sec;
    }
    iso->rps_ring[sec % 60]++;

    /* enqueue */
    f->next = NULL;
    if (p->sched.tail)
        p->sched.tail->next = f;
    else
        p->sched.head = f;
    p->sched.tail = f;
    p->sched.nrunnable++;
    p->sched.fibers_total++;
    return f;
}

void iso_fiber_free(iso_fiber *f)
{
    if (!f)
        return;
    if (f->stack)
        munmap(f->stack, f->stack_size);
    iso_arena_free(&f->arena);
    iso_request_free(&f->req);
    iso_response_free(&f->res);
    iso_script_unref(f->script);
    free(f);
}

static void fiber_finish(iso_platform *p, iso_fiber *f)
{
    iso_isolate *iso = f->iso;
    f->end_ns = iso_now_ns();
    iso->inflight--;
    iso->instructions += f->executed;
    iso->cpu_ns += f->cpu_ns;
    if (f->cpu_ns > iso->max_cpu_ns)
        iso->max_cpu_ns = f->cpu_ns;
    if (f->arena.peak > iso->peak_mem)
        iso->peak_mem = f->arena.peak;
    iso->last_invoked_ms = iso_now_ms();
    if (f->error_code) {
        iso->errors++;
        p->errors++;
        iso_isolate_log(iso, "error %d: %s", f->error_code, f->error);
    }
    p->sched.fibers_done++;
    if (f->on_done)
        f->on_done(f, f->user);
    iso_fiber_free(f);
}

int iso_sched_tick(iso_platform *p)
{
    iso_sched *s = &p->sched;
    int finished = 0;
    iso_fiber **pp = &s->head;
    while (*pp) {
        iso_fiber *f = *pp;
        s->switches++;
        iso_ctx_switch(&s->ctx, &f->ctx);
        if (f->state == FIBER_DONE) {
            *pp = f->next;
            s->nrunnable--;
            fiber_finish(p, f);
            finished++;
        } else {
            pp = &f->next;
        }
    }
    /* recompute tail (cheap; queues are short) */
    s->tail = NULL;
    for (iso_fiber *f = s->head; f; f = f->next)
        s->tail = f;
    return finished;
}

void iso_invoke_sync(iso_platform *p, iso_fiber *f)
{
    bool alive = true;
    /* Tick until this particular fiber has finished. We detect that by
     * watching the queue rather than the (freed) pointer. */
    while (alive) {
        alive = false;
        for (iso_fiber *q = p->sched.head; q; q = q->next)
            if (q == f) {
                alive = true;
                break;
            }
        if (alive)
            iso_sched_tick(p);
    }
}
