/* http.c - single-threaded HTTP/1.1 server, worker routing, control API. */
#include "isolates.h"

#include <arpa/inet.h>
#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <unistd.h>

#define MAX_REQUEST (ISO_MAX_BODY + 64 * 1024)

typedef struct conn {
    int fd;
    iso_buf in;
    iso_buf out;
    size_t out_off;
    enum { C_READ, C_WAIT, C_WRITE, C_CLOSE } state;
    bool api_invoke;
    uint64_t t0;
    struct conn *next;
} conn;

typedef struct server {
    iso_platform *p;
    iso_server_opts opts;
    int listen_fd;
    conn *conns;
    int nconns;
    uint64_t total_conns;
} server;

static volatile sig_atomic_t g_stop = 0;

static void on_signal(int sig)
{
    (void)sig;
    g_stop = 1;
}

/* ------------------------------------------------------------------ */
/* Response helpers                                                    */
/* ------------------------------------------------------------------ */
static const char *status_text(int code)
{
    switch (code) {
    case 200: return "OK";
    case 201: return "Created";
    case 204: return "No Content";
    case 301: return "Moved Permanently";
    case 302: return "Found";
    case 304: return "Not Modified";
    case 400: return "Bad Request";
    case 401: return "Unauthorized";
    case 403: return "Forbidden";
    case 404: return "Not Found";
    case 405: return "Method Not Allowed";
    case 409: return "Conflict";
    case 413: return "Payload Too Large";
    case 422: return "Unprocessable Entity";
    case 429: return "Too Many Requests";
    case 500: return "Internal Server Error";
    case 502: return "Bad Gateway";
    case 503: return "Service Unavailable";
    default: return "Status";
    }
}

static void begin_response(conn *c, int status)
{
    c->out.n = 0;
    iso_buf_printf(&c->out, "HTTP/1.1 %d %s\r\n", status, status_text(status));
    iso_buf_puts(&c->out, "Server: isolates/" ISO_VERSION "\r\n"
                          "Connection: close\r\n"
                          "Access-Control-Allow-Origin: *\r\n"
                          "Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS\r\n"
                          "Access-Control-Allow-Headers: Content-Type\r\n");
}

static void finish_response(conn *c, const char *body, size_t n)
{
    iso_buf_printf(&c->out, "Content-Length: %zu\r\n\r\n", n);
    if (body && n)
        iso_buf_append(&c->out, body, n);
    c->out_off = 0;
    c->state = C_WRITE;
}

static void send_simple(conn *c, int status, const char *ctype, const char *body, size_t n)
{
    begin_response(c, status);
    iso_buf_printf(&c->out, "Content-Type: %s\r\n", ctype);
    finish_response(c, body, n);
}

static void send_json(conn *c, int status, iso_buf *body)
{
    send_simple(c, status, "application/json; charset=utf-8", body->p ? body->p : "", body->n);
    iso_buf_free(body);
}

static void send_error(conn *c, int status, const char *msg)
{
    iso_buf b = {0};
    iso_buf_puts(&b, "{\"error\":");
    iso_buf_json_str(&b, msg, strlen(msg));
    iso_buf_puts(&b, "}");
    send_json(c, status, &b);
}

/* ------------------------------------------------------------------ */
/* JSON serializers                                                    */
/* ------------------------------------------------------------------ */
static void json_kv_str(iso_buf *b, const char *key, const char *val)
{
    iso_buf_json_str(b, key, strlen(key));
    iso_buf_puts(b, ":");
    iso_buf_json_str(b, val, strlen(val));
}

static void json_isolate_summary(iso_buf *b, const iso_isolate *iso)
{
    iso_buf_puts(b, "{");
    json_kv_str(b, "name", iso->name);
    iso_buf_printf(b,
        ",\"created_ms\":%llu,\"deployed_ms\":%llu,\"deploys\":%d,"
        "\"instructions_in_script\":%u,\"constants\":%u,\"script_bytes\":%zu,"
        "\"cpu_limit\":%llu,\"mem_limit\":%zu,"
        "\"requests\":%llu,\"errors\":%llu,\"instructions\":%llu,"
        "\"cpu_ns\":%llu,\"max_cpu_ns\":%llu,\"last_invoked_ms\":%llu,"
        "\"peak_mem\":%zu,\"inflight\":%d,\"kv_entries\":%d,\"env_count\":%d",
        (unsigned long long)iso->created_ms, (unsigned long long)iso->deployed_ms,
        iso->deploys, iso->script->ncode, iso->script->nconsts, iso->script->source_len,
        (unsigned long long)iso->cpu_limit, iso->mem_limit,
        (unsigned long long)iso->requests, (unsigned long long)iso->errors,
        (unsigned long long)iso->instructions, (unsigned long long)iso->cpu_ns,
        (unsigned long long)iso->max_cpu_ns, (unsigned long long)iso->last_invoked_ms,
        iso->peak_mem, iso->inflight, iso->kv.count, iso->nenv);
    /* requests per second over the last 60 seconds, oldest first */
    iso_buf_puts(b, ",\"rps\":[");
    uint64_t now_sec = iso_now_ms() / 1000;
    for (int k = 59; k >= 0; k--) {
        uint64_t sec = now_sec - (uint64_t)k;
        uint32_t v = 0;
        if (sec <= iso->rps_sec && iso->rps_sec - sec < 60)
            v = iso->rps_ring[sec % 60];
        iso_buf_printf(b, "%s%u", k == 59 ? "" : ",", v);
    }
    iso_buf_puts(b, "]}");
}

static void json_isolate_detail(iso_buf *b, const iso_isolate *iso)
{
    json_isolate_summary(b, iso);
    b->n--; /* drop closing brace */
    iso_buf_puts(b, ",\"script\":");
    iso_buf_json_str(b, iso->script->source, iso->script->source_len);
    iso_buf_puts(b, ",\"env\":{");
    for (int i = 0; i < iso->nenv; i++) {
        if (i)
            iso_buf_puts(b, ",");
        json_kv_str(b, iso->env[i].name, iso->env[i].value);
    }
    iso_buf_puts(b, "}}");
}

static void json_logs(iso_buf *b, const iso_isolate *iso)
{
    iso_buf_puts(b, "{\"logs\":[");
    for (int i = 0; i < iso->log_count; i++) {
        const iso_log_entry *e = &iso->logs[(iso->log_head + i) % ISO_LOG_RING];
        iso_buf_printf(b, "%s{\"ts_ms\":%llu,\"msg\":", i ? "," : "",
                       (unsigned long long)e->ts_ms);
        iso_buf_json_str(b, e->msg, strlen(e->msg));
        iso_buf_puts(b, "}");
    }
    iso_buf_puts(b, "]}");
}

struct kv_ctx {
    iso_buf *b;
    int i;
};

static void kv_each_json(const iso_kv_entry *e, void *user)
{
    struct kv_ctx *k = user;
    iso_buf_printf(k->b, "%s{\"key\":", k->i++ ? "," : "");
    iso_buf_json_str(k->b, e->key, strlen(e->key));
    iso_buf_puts(k->b, ",\"value\":");
    iso_buf_json_str(k->b, e->value, e->vlen);
    iso_buf_printf(k->b, ",\"updated_ms\":%llu}", (unsigned long long)e->updated_ms);
}

static void json_kv(iso_buf *b, const iso_isolate *iso)
{
    struct kv_ctx k = { b, 0 };
    iso_buf_puts(b, "{\"entries\":[");
    iso_kv_each(&iso->kv, kv_each_json, &k);
    iso_buf_printf(b, "],\"count\":%d}", iso->kv.count);
}

static void json_disasm(iso_buf *b, const iso_script *s)
{
    iso_buf_puts(b, "{\"listing\":[");
    for (uint32_t i = 0; i < s->ncode; i++) {
        const iso_insn *in = &s->code[i];
        char line[512];
        switch (in->op) {
        case OP_PUSH_INT: case OP_LOAD: case OP_STORE:
            snprintf(line, sizeof line, "%s %lld", iso_op_name(in->op), (long long)in->imm);
            break;
        case OP_JMP: case OP_JZ: case OP_JNZ: case OP_CALL:
            snprintf(line, sizeof line, "%s @%lld", iso_op_name(in->op), (long long)in->imm);
            break;
        case OP_PUSH_STR:
            snprintf(line, sizeof line, "push \"%.*s\"%s", (int)(s->consts[in->imm].n > 40 ? 40 : s->consts[in->imm].n),
                     s->consts[in->imm].p, s->consts[in->imm].n > 40 ? "..." : "");
            break;
        case OP_SYS:
            snprintf(line, sizeof line, "%s", iso_sys_name((int)in->imm));
            break;
        default:
            snprintf(line, sizeof line, "%s", iso_op_name(in->op));
        }
        iso_buf_printf(b, "%s{\"pc\":%u,\"op\":%d,\"text\":", i ? "," : "", i, in->op);
        iso_buf_json_str(b, line, strlen(line));
        iso_buf_puts(b, "}");
    }
    iso_buf_printf(b, "],\"instructions\":%u,\"constants\":%u}", s->ncode, s->nconsts);
}

static void json_status(iso_buf *b, server *sv)
{
    iso_platform *p = sv->p;
    uint64_t now = iso_now_ms();
    iso_buf_puts(b, "{");
    json_kv_str(b, "version", ISO_VERSION);
    iso_buf_puts(b, ",");
    json_kv_str(b, "arch", iso_ctx_arch());
    iso_buf_printf(b,
        ",\"uptime_ms\":%llu,\"isolates\":%d,\"requests\":%llu,\"errors\":%llu,"
        "\"inflight\":%d,\"context_switches\":%llu,\"fibers_total\":%llu,"
        "\"fibers_done\":%llu,\"connections\":%d,\"connections_total\":%llu,"
        "\"slice_instructions\":%d,\"fiber_stack_bytes\":%d,"
        "\"default_cpu_limit\":%d,\"default_mem_limit\":%d,"
        "\"persistence\":%s,\"pid\":%d}",
        (unsigned long long)(now - p->started_ms), p->nisolates,
        (unsigned long long)p->requests, (unsigned long long)p->errors,
        p->sched.nrunnable, (unsigned long long)p->sched.switches,
        (unsigned long long)p->sched.fibers_total, (unsigned long long)p->sched.fibers_done,
        sv->nconns, (unsigned long long)sv->total_conns,
        ISO_SLICE, ISO_FIBER_STACK, ISO_DEFAULT_CPU_LIMIT, ISO_DEFAULT_MEM_LIMIT,
        p->data_dir ? "true" : "false", (int)getpid());
}

/* ------------------------------------------------------------------ */
/* Worker invocation                                                   */
/* ------------------------------------------------------------------ */
static void worker_done(iso_fiber *f, void *user)
{
    conn *c = user;
    uint64_t wall_us = (f->end_ns - f->start_ns) / 1000;
    if (c->api_invoke) {
        iso_buf b = {0};
        iso_buf_printf(&b, "{\"status\":%d,\"headers\":{", f->error_code ? 500 : f->res.status);
        for (int i = 0; i < f->res.nheaders; i++) {
            if (i)
                iso_buf_puts(&b, ",");
            json_kv_str(&b, f->res.headers[i].name, f->res.headers[i].value);
        }
        iso_buf_puts(&b, "},\"body\":");
        iso_buf_json_str(&b, f->res.body ? f->res.body : "", f->res.body_len);
        iso_buf_printf(&b, ",\"error_code\":%d,\"error\":", f->error_code);
        iso_buf_json_str(&b, f->error, strlen(f->error));
        iso_buf_printf(&b,
            ",\"instructions\":%llu,\"cpu_us\":%llu,\"wall_us\":%llu,"
            "\"mem_peak\":%zu,\"mem_limit\":%zu,\"cpu_limit\":%llu,\"switches\":%u}",
            (unsigned long long)f->executed, (unsigned long long)(f->cpu_ns / 1000),
            (unsigned long long)wall_us, f->arena.peak, f->arena.size,
            (unsigned long long)f->iso->cpu_limit, f->switches);
        send_json(c, 200, &b);
        return;
    }
    if (f->error_code) {
        char msg[400];
        int n = snprintf(msg, sizeof msg, "Error %d: %s\n", f->error_code,
                         f->error_code == ISO_ERR_LIMITS
                             ? "Worker exceeded resource limits" : "Worker threw exception");
        n += snprintf(msg + n, sizeof msg - (size_t)n, "%s\n", f->error);
        begin_response(c, f->error_code == ISO_ERR_LIMITS ? 503 : 500);
        iso_buf_printf(&c->out, "Content-Type: text/plain; charset=utf-8\r\n"
                                "X-Isolate-Error: %d\r\n", f->error_code);
        finish_response(c, msg, (size_t)n);
        return;
    }
    begin_response(c, f->res.status);
    bool have_ct = false;
    for (int i = 0; i < f->res.nheaders; i++) {
        if (strcasecmp(f->res.headers[i].name, "content-length") == 0 ||
            strcasecmp(f->res.headers[i].name, "connection") == 0)
            continue;
        if (strcasecmp(f->res.headers[i].name, "content-type") == 0)
            have_ct = true;
        iso_buf_printf(&c->out, "%s: %s\r\n", f->res.headers[i].name, f->res.headers[i].value);
    }
    if (!have_ct)
        iso_buf_puts(&c->out, "Content-Type: text/plain; charset=utf-8\r\n");
    iso_buf_printf(&c->out, "X-Isolate-Worker: %s\r\nX-Isolate-Instructions: %llu\r\n"
                            "X-Isolate-CPU-us: %llu\r\nX-Isolate-Switches: %u\r\n",
                   f->iso->name, (unsigned long long)f->executed,
                   (unsigned long long)(f->cpu_ns / 1000), f->switches);
    finish_response(c, f->res.body, f->res.body_len);
}

static void dispatch_worker(server *sv, conn *c, iso_isolate *iso, iso_request *req, bool api)
{
    c->api_invoke = api;
    iso_fiber *f = iso_fiber_create(sv->p, iso, req, worker_done, c);
    if (!f) {
        iso_request_free(req);
        send_error(c, 503, "could not allocate an isolate fiber");
        return;
    }
    c->state = C_WAIT;
}

/* ------------------------------------------------------------------ */
/* Static files (built Flutter dashboard)                              */
/* ------------------------------------------------------------------ */
static const char *mime_for(const char *path)
{
    const char *dot = strrchr(path, '.');
    if (!dot)
        return "application/octet-stream";
    dot++;
    if (!strcmp(dot, "html")) return "text/html; charset=utf-8";
    if (!strcmp(dot, "js")) return "text/javascript";
    if (!strcmp(dot, "mjs")) return "text/javascript";
    if (!strcmp(dot, "css")) return "text/css";
    if (!strcmp(dot, "json")) return "application/json";
    if (!strcmp(dot, "png")) return "image/png";
    if (!strcmp(dot, "jpg") || !strcmp(dot, "jpeg")) return "image/jpeg";
    if (!strcmp(dot, "svg")) return "image/svg+xml";
    if (!strcmp(dot, "ico")) return "image/x-icon";
    if (!strcmp(dot, "wasm")) return "application/wasm";
    if (!strcmp(dot, "ttf")) return "font/ttf";
    if (!strcmp(dot, "otf")) return "font/otf";
    if (!strcmp(dot, "woff")) return "font/woff";
    if (!strcmp(dot, "woff2")) return "font/woff2";
    if (!strcmp(dot, "txt")) return "text/plain; charset=utf-8";
    return "application/octet-stream";
}

static bool serve_static(server *sv, conn *c, const char *path)
{
    if (!sv->opts.dashboard_dir)
        return false;
    if (strstr(path, ".."))
        return false;
    char full[1024];
    if (strcmp(path, "/") == 0)
        path = "/index.html";
    snprintf(full, sizeof full, "%s%s", sv->opts.dashboard_dir, path);
    struct stat st;
    if (stat(full, &st) != 0 || !S_ISREG(st.st_mode)) {
        /* SPA fallback for extension-less routes */
        if (strrchr(path, '.') && strrchr(path, '.') > strrchr(path, '/'))
            return false;
        snprintf(full, sizeof full, "%s/index.html", sv->opts.dashboard_dir);
        if (stat(full, &st) != 0 || !S_ISREG(st.st_mode))
            return false;
        path = "/index.html";
    }
    FILE *f = fopen(full, "rb");
    if (!f)
        return false;
    iso_buf b = {0};
    char chunk[8192];
    size_t r;
    while ((r = fread(chunk, 1, sizeof chunk, f)) > 0)
        iso_buf_append(&b, chunk, r);
    fclose(f);
    send_simple(c, 200, mime_for(path), b.p ? b.p : "", b.n);
    iso_buf_free(&b);
    return true;
}

/* ------------------------------------------------------------------ */
/* Control API                                                         */
/* ------------------------------------------------------------------ */
static int hexval(int c)
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

static size_t url_decode(char *s)
{
    char *w = s, *r = s;
    while (*r) {
        if (*r == '%' && hexval(r[1]) >= 0 && hexval(r[2]) >= 0) {
            *w++ = (char)(hexval(r[1]) * 16 + hexval(r[2]));
            r += 3;
        } else
            *w++ = *r++;
    }
    *w = 0;
    return (size_t)(w - s);
}

static bool load_examples(server *sv, iso_buf *b)
{
    const char *dir = getenv("ISOLATES_EXAMPLES");
    if (!dir)
        dir = "workers";
    iso_buf_puts(b, "{\"examples\":[");
    char cmd[1400];
    int i = 0;
    /* readdir order is unspecified: collect names and sort them */
    char names[64][128];
    int nn = 0;
    {
        DIR *d = opendir(dir);
        if (d) {
            struct dirent *de;
            while ((de = readdir(d)) && nn < 64) {
                size_t n = strlen(de->d_name);
                if (n > 7 && strcmp(de->d_name + n - 7, ".isoasm") == 0)
                    snprintf(names[nn++], sizeof names[0], "%s", de->d_name);
            }
            closedir(d);
        }
    }
    for (int a = 0; a < nn; a++)
        for (int k = a + 1; k < nn; k++)
            if (strcmp(names[a], names[k]) > 0) {
                char t[128];
                memcpy(t, names[a], sizeof t);
                memcpy(names[a], names[k], sizeof t);
                memcpy(names[k], t, sizeof t);
            }
    for (int a = 0; a < nn; a++) {
        snprintf(cmd, sizeof cmd, "%s/%.127s", dir, names[a]);
        FILE *f = fopen(cmd, "rb");
        if (!f)
            continue;
        iso_buf src = {0};
        char chunk[4096];
        size_t r;
        while ((r = fread(chunk, 1, sizeof chunk, f)) > 0)
            iso_buf_append(&src, chunk, r);
        fclose(f);
        if (!src.p)
            iso_buf_append(&src, "", 0);
        char name[128];
        snprintf(name, sizeof name, "%.*s", (int)(strlen(names[a]) - 7), names[a]);
        /* description = first comment line */
        char desc[200] = "";
        if (src.p[0] == ';' || src.p[0] == '#') {
            const char *s = src.p + 1;
            while (*s == ' ')
                s++;
            const char *e = strchr(s, '\n');
            snprintf(desc, sizeof desc, "%.*s", (int)(e ? e - s : (long)strlen(s)), s);
        }
        iso_buf_printf(b, "%s{", i++ ? "," : "");
        json_kv_str(b, "name", name);
        iso_buf_puts(b, ",");
        json_kv_str(b, "description", desc);
        iso_buf_puts(b, ",\"script\":");
        iso_buf_json_str(b, src.p, src.n);
        iso_buf_puts(b, "}");
        iso_buf_free(&src);
    }
    iso_buf_puts(b, "]}");
    return true;
}

static void api_reference(iso_buf *b)
{
    iso_buf_puts(b, "{\"instructions\":[");
    for (size_t i = 0; i < iso_mnemonic_count(); i++) {
        const char *name, *operand, *desc;
        iso_mnemonic_at(i, &name, &operand, &desc);
        iso_buf_printf(b, "%s{", i ? "," : "");
        json_kv_str(b, "name", name);
        iso_buf_puts(b, ",");
        json_kv_str(b, "operand", operand);
        iso_buf_puts(b, ",");
        json_kv_str(b, "desc", desc);
        iso_buf_puts(b, "}");
    }
    iso_buf_puts(b, "]}");
}

static void api_deploy(server *sv, conn *c, const char *name, const char *body, size_t blen)
{
    char err[256];
    json_val *j = json_parse(body, blen, err, sizeof err);
    if (!j || j->t != J_OBJ) {
        json_free(j);
        send_error(c, 400, j ? "body must be a JSON object" : err);
        return;
    }
    const char *script = json_str(j, "script", NULL);
    if (!script) {
        json_free(j);
        send_error(c, 400, "missing \"script\"");
        return;
    }
    if (!iso_name_valid(name)) {
        json_free(j);
        send_error(c, 400, "invalid worker name (a-z, 0-9, '-')");
        return;
    }
    iso_script *s;
    if (iso_assemble(script, strlen(script), &s, err, sizeof err) < 0) {
        iso_buf b = {0};
        iso_buf_puts(&b, "{\"error\":");
        iso_buf_json_str(&b, err, strlen(err));
        iso_buf_puts(&b, ",\"kind\":\"assemble\"}");
        json_free(j);
        send_json(c, 422, &b);
        return;
    }
    bool existed = iso_platform_find(sv->p, name) != NULL;
    iso_isolate *iso = iso_platform_deploy(sv->p, name, s, err, sizeof err);
    iso_script_unref(s);
    if (!iso) {
        json_free(j);
        send_error(c, 400, err);
        return;
    }
    json_val *cpu = json_get(j, "cpu_limit");
    json_val *mem = json_get(j, "mem_limit");
    if ((cpu && cpu->t == J_NUM) || (mem && mem->t == J_NUM))
        iso_isolate_set_limits(iso,
            cpu && cpu->t == J_NUM ? (uint64_t)cpu->num : iso->cpu_limit,
            mem && mem->t == J_NUM ? (size_t)mem->num : iso->mem_limit);
    json_val *env = json_get(j, "env");
    if (env && env->t == J_OBJ) {
        /* replace the whole binding set */
        while (iso->nenv > 0)
            iso_isolate_set_env(iso, iso->env[0].name, NULL);
        for (int i = 0; i < env->n; i++) {
            if (env->items[i].t == J_STR)
                iso_isolate_set_env(iso, env->keys[i], env->items[i].str);
            else if (env->items[i].t == J_NUM) {
                char tmp[64];
                snprintf(tmp, sizeof tmp, "%.17g", env->items[i].num);
                iso_isolate_set_env(iso, env->keys[i], tmp);
            }
        }
    }
    json_free(j);
    if (iso_platform_save(sv->p, iso) < 0)
        iso_isolate_log(iso, "warning: could not persist to %s", sv->p->data_dir);
    iso_buf b = {0};
    json_isolate_detail(&b, iso);
    send_json(c, existed ? 200 : 201, &b);
}

static void api_invoke(server *sv, conn *c, iso_isolate *iso, const char *body, size_t blen)
{
    char err[256];
    json_val *j = NULL;
    if (blen) {
        j = json_parse(body, blen, err, sizeof err);
        if (!j || j->t != J_OBJ) {
            json_free(j);
            send_error(c, 400, j ? "body must be a JSON object" : err);
            return;
        }
    }
    iso_request req;
    iso_request_init(&req);
    if (j) {
        const char *m = json_str(j, "method", "GET");
        const char *path = json_str(j, "path", "/");
        const char *q = strchr(path, '?');
        free(req.method);
        req.method = strdup(m);
        for (char *s = req.method; *s; s++)
            *s = (char)toupper((unsigned char)*s);
        free(req.path);
        free(req.query);
        if (q) {
            req.path = strndup(path, (size_t)(q - path));
            req.query = strdup(q + 1);
        } else {
            req.path = strdup(path);
            req.query = strdup("");
        }
        const char *rb = json_str(j, "body", NULL);
        if (rb) {
            req.body = strdup(rb);
            req.body_len = strlen(rb);
        }
        json_val *h = json_get(j, "headers");
        if (h && h->t == J_OBJ)
            for (int i = 0; i < h->n; i++)
                if (h->items[i].t == J_STR)
                    iso_request_add_header(&req, h->keys[i], strlen(h->keys[i]),
                                           h->items[i].str, strlen(h->items[i].str));
        json_free(j);
    }
    dispatch_worker(sv, c, iso, &req, true);
}

static void api_assemble(conn *c, const char *body, size_t blen)
{
    char err[256];
    json_val *j = json_parse(body, blen, err, sizeof err);
    const char *script = j ? json_str(j, "script", NULL) : NULL;
    if (!script) {
        json_free(j);
        send_error(c, 400, j ? "missing \"script\"" : err);
        return;
    }
    iso_script *s;
    iso_buf b = {0};
    if (iso_assemble(script, strlen(script), &s, err, sizeof err) < 0) {
        iso_buf_puts(&b, "{\"ok\":false,\"error\":");
        iso_buf_json_str(&b, err, strlen(err));
        iso_buf_puts(&b, "}");
    } else {
        iso_buf_puts(&b, "{\"ok\":true,\"disasm\":");
        json_disasm(&b, s);
        iso_buf_puts(&b, "}");
        iso_script_unref(s);
    }
    json_free(j);
    send_json(c, 200, &b);
}

/* path is already stripped of "/api". */
static void handle_api(server *sv, conn *c, const char *method, char *path,
                       const char *body, size_t blen)
{
    iso_platform *p = sv->p;
    iso_buf b = {0};

    if (!strcmp(path, "/status") && !strcmp(method, "GET")) {
        json_status(&b, sv);
        send_json(c, 200, &b);
        return;
    }
    if (!strcmp(path, "/reference") && !strcmp(method, "GET")) {
        api_reference(&b);
        send_json(c, 200, &b);
        return;
    }
    if (!strcmp(path, "/examples") && !strcmp(method, "GET")) {
        load_examples(sv, &b);
        send_json(c, 200, &b);
        return;
    }
    if (!strcmp(path, "/assemble") && !strcmp(method, "POST")) {
        api_assemble(c, body, blen);
        return;
    }
    if (!strcmp(path, "/workers") && !strcmp(method, "GET")) {
        iso_buf_puts(&b, "{\"workers\":[");
        int i = 0;
        for (iso_isolate *iso = p->isolates; iso; iso = iso->next) {
            if (i++)
                iso_buf_puts(&b, ",");
            json_isolate_summary(&b, iso);
        }
        iso_buf_puts(&b, "]}");
        send_json(c, 200, &b);
        return;
    }
    if (strncmp(path, "/workers/", 9) == 0) {
        char name[ISO_NAME_MAX];
        const char *rest = strchr(path + 9, '/');
        size_t nl = rest ? (size_t)(rest - (path + 9)) : strlen(path + 9);
        if (nl == 0 || nl >= sizeof name) {
            send_error(c, 404, "unknown worker");
            return;
        }
        memcpy(name, path + 9, nl);
        name[nl] = 0;
        if (!rest)
            rest = "";
        iso_isolate *iso = iso_platform_find(p, name);

        if (!*rest && !strcmp(method, "PUT")) {
            api_deploy(sv, c, name, body, blen);
            return;
        }
        if (!iso) {
            send_error(c, 404, "unknown worker");
            return;
        }
        if (!*rest && !strcmp(method, "GET")) {
            json_isolate_detail(&b, iso);
            send_json(c, 200, &b);
            return;
        }
        if (!*rest && !strcmp(method, "DELETE")) {
            if (!iso_platform_remove(p, name)) {
                send_error(c, 409, "worker has in-flight requests; retry");
                return;
            }
            iso_platform_unlink(p, name);
            send_simple(c, 200, "application/json", "{\"ok\":true}", 11);
            return;
        }
        if (!strcmp(rest, "/logs") && !strcmp(method, "GET")) {
            json_logs(&b, iso);
            send_json(c, 200, &b);
            return;
        }
        if (!strcmp(rest, "/logs") && !strcmp(method, "DELETE")) {
            iso->log_head = iso->log_count = 0;
            send_simple(c, 200, "application/json", "{\"ok\":true}", 11);
            return;
        }
        if (!strcmp(rest, "/disasm") && !strcmp(method, "GET")) {
            json_disasm(&b, iso->script);
            send_json(c, 200, &b);
            return;
        }
        if (!strcmp(rest, "/invoke") && !strcmp(method, "POST")) {
            api_invoke(sv, c, iso, body, blen);
            return;
        }
        if (!strcmp(rest, "/kv") && !strcmp(method, "GET")) {
            json_kv(&b, iso);
            send_json(c, 200, &b);
            return;
        }
        if (!strcmp(rest, "/kv") && !strcmp(method, "DELETE")) {
            iso_kv_free(&iso->kv);
            send_simple(c, 200, "application/json", "{\"ok\":true}", 11);
            return;
        }
        if (strncmp(rest, "/kv/", 4) == 0) {
            char key[600];
            snprintf(key, sizeof key, "%s", rest + 4);
            size_t klen = url_decode(key);
            if (!strcmp(method, "PUT") || !strcmp(method, "POST")) {
                if (iso_kv_put(&iso->kv, key, klen, body, blen) < 0) {
                    send_error(c, 422, "kv rejected (empty key, too large, or namespace full)");
                    return;
                }
                send_simple(c, 200, "application/json", "{\"ok\":true}", 11);
                return;
            }
            if (!strcmp(method, "DELETE")) {
                bool ok = iso_kv_del(&iso->kv, key, klen);
                send_simple(c, ok ? 200 : 404, "application/json",
                            ok ? "{\"ok\":true}" : "{\"ok\":false}", ok ? 11 : 12);
                return;
            }
            if (!strcmp(method, "GET")) {
                const iso_kv_entry *e = iso_kv_get(&iso->kv, key, klen);
                if (!e) {
                    send_error(c, 404, "no such key");
                    return;
                }
                send_simple(c, 200, "application/octet-stream", e->value, e->vlen);
                return;
            }
        }
    }
    send_error(c, 404, "no such API endpoint");
}

/* ------------------------------------------------------------------ */
/* Request parsing and routing                                         */
/* ------------------------------------------------------------------ */
static void route_request(server *sv, conn *c, char *head, size_t head_len,
                          const char *body, size_t blen)
{
    (void)head_len;
    /* request line */
    char *line_end = strstr(head, "\r\n");
    if (!line_end) {
        send_error(c, 400, "malformed request");
        return;
    }
    *line_end = 0;
    char *method = head;
    char *sp = strchr(method, ' ');
    if (!sp) {
        send_error(c, 400, "malformed request line");
        return;
    }
    *sp++ = 0;
    char *target = sp;
    sp = strchr(target, ' ');
    if (sp)
        *sp = 0;
    char *query = strchr(target, '?');
    if (query)
        *query++ = 0;
    else
        query = "";
    for (char *s = method; *s; s++)
        *s = (char)toupper((unsigned char)*s);

    /* headers */
    iso_request req;
    iso_request_init(&req);
    char *h = line_end + 2;
    while (h && *h) {
        char *he = strstr(h, "\r\n");
        if (he)
            *he = 0;
        if (!*h)
            break;
        char *colon = strchr(h, ':');
        if (colon) {
            *colon = 0;
            char *v = colon + 1;
            while (*v == ' ' || *v == '\t')
                v++;
            iso_request_add_header(&req, h, strlen(h), v, strlen(v));
        }
        h = he ? he + 2 : NULL;
    }

    if (sv->opts.verbose)
        fprintf(stderr, "[http] %s %s%s%s\n", method, target, *query ? "?" : "", query);

    if (!strcmp(method, "OPTIONS")) {
        iso_request_free(&req);
        begin_response(c, 204);
        iso_buf_puts(&c->out, "Access-Control-Max-Age: 86400\r\n");
        finish_response(c, NULL, 0);
        return;
    }

    /* control plane */
    if (!strncmp(target, "/api/", 5) || !strcmp(target, "/api")) {
        char *apath = target + 4;
        if (!*apath)
            apath = "/";
        iso_request_free(&req);
        handle_api(sv, c, method, apath, body, blen);
        return;
    }

    /* worker by path prefix: /w/<name>[/rest] */
    iso_isolate *iso = NULL;
    char *wpath = target;
    if (!strncmp(target, "/w/", 3)) {
        char *name = target + 3;
        char *slash = strchr(name, '/');
        char nbuf[ISO_NAME_MAX];
        size_t nl = slash ? (size_t)(slash - name) : strlen(name);
        if (nl > 0 && nl < sizeof nbuf) {
            memcpy(nbuf, name, nl);
            nbuf[nl] = 0;
            iso = iso_platform_find(sv->p, nbuf);
        }
        if (!iso) {
            iso_request_free(&req);
            char msg[200];
            snprintf(msg, sizeof msg, "Error 1003: no worker named '%.*s' is deployed\n",
                     (int)nl, name);
            send_simple(c, 404, "text/plain; charset=utf-8", msg, strlen(msg));
            return;
        }
        wpath = slash ? slash : "/";
    } else {
        /* worker by hostname: <name>.<anything> */
        const char *host = iso_request_header(&req, "host");
        if (host) {
            const char *dot = strchr(host, '.');
            if (dot && dot - host < ISO_NAME_MAX) {
                char nbuf[ISO_NAME_MAX];
                memcpy(nbuf, host, (size_t)(dot - host));
                nbuf[dot - host] = 0;
                iso = iso_platform_find(sv->p, nbuf);
            }
        }
    }

    if (!iso) {
        if (serve_static(sv, c, target)) {
            iso_request_free(&req);
            return;
        }
        iso_request_free(&req);
        const char *msg =
            "isolates " ISO_VERSION "\n\n"
            "No worker is bound to this route.\n"
            "  workers:   /w/<name>/...   or   Host: <name>.<domain>\n"
            "  control:   /api/status, /api/workers, ...\n"
            "  dashboard: run with --dashboard <flutter build dir>\n";
        send_simple(c, 404, "text/plain; charset=utf-8", msg, strlen(msg));
        return;
    }

    free(req.method);
    free(req.path);
    free(req.query);
    req.method = strdup(method);
    req.path = strdup(wpath);
    req.query = strdup(query);
    if (blen) {
        req.body = malloc(blen + 1);
        if (req.body) {
            memcpy(req.body, body, blen);
            req.body[blen] = 0;
            req.body_len = blen;
        }
    }
    dispatch_worker(sv, c, iso, &req, false);
}

/* Returns true once a full request was consumed and handled. */
static bool try_parse(server *sv, conn *c)
{
    if (!c->in.p)
        return false;
    char *hdr_end = memmem(c->in.p, c->in.n, "\r\n\r\n", 4);
    if (!hdr_end) {
        if (c->in.n > 64 * 1024) {
            send_error(c, 431, "headers too large");
            return true;
        }
        return false;
    }
    size_t head_len = (size_t)(hdr_end - c->in.p) + 4;
    size_t clen = 0;
    /* case-insensitive Content-Length scan inside the header block */
    for (char *s = c->in.p; s < hdr_end; s++) {
        if ((s == c->in.p || s[-1] == '\n') && strncasecmp(s, "content-length:", 15) == 0) {
            clen = strtoull(s + 15, NULL, 10);
            break;
        }
    }
    if (clen > ISO_MAX_BODY) {
        send_error(c, 413, "body too large");
        return true;
    }
    if (c->in.n < head_len + clen)
        return false;
    c->in.p[head_len - 2] = 0; /* terminate header block (keeps final CRLF pair split) */
    route_request(sv, c, c->in.p, head_len, c->in.p + head_len, clen);
    return true;
}

/* ------------------------------------------------------------------ */
/* Event loop                                                          */
/* ------------------------------------------------------------------ */
static void set_nonblock(int fd)
{
    int fl = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, fl | O_NONBLOCK);
}

static void conn_close(server *sv, conn *c)
{
    close(c->fd);
    iso_buf_free(&c->in);
    iso_buf_free(&c->out);
    free(c);
    sv->nconns--;
}

int iso_server_run(iso_platform *p, const iso_server_opts *opts)
{
    server sv = {0};
    sv.p = p;
    sv.opts = *opts;

    signal(SIGPIPE, SIG_IGN);
    signal(SIGINT, on_signal);
    signal(SIGTERM, on_signal);

    sv.listen_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (sv.listen_fd < 0) {
        perror("socket");
        return -1;
    }
    int one = 1;
    setsockopt(sv.listen_fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    struct sockaddr_in addr = {0};
    addr.sin_family = AF_INET;
    addr.sin_port = htons((uint16_t)opts->port);
    if (inet_pton(AF_INET, opts->bind ? opts->bind : "127.0.0.1", &addr.sin_addr) != 1) {
        fprintf(stderr, "isolates: bad bind address\n");
        return -1;
    }
    if (bind(sv.listen_fd, (struct sockaddr *)&addr, sizeof addr) < 0) {
        perror("bind");
        return -1;
    }
    if (listen(sv.listen_fd, 128) < 0) {
        perror("listen");
        return -1;
    }
    set_nonblock(sv.listen_fd);

    fprintf(stderr, "isolates %s (%s) listening on http://%s:%d  workers=%d%s%s\n",
            ISO_VERSION, iso_ctx_arch(), opts->bind ? opts->bind : "127.0.0.1", opts->port,
            p->nisolates, p->data_dir ? "  data=" : "", p->data_dir ? p->data_dir : "");

    struct pollfd *pfds = NULL;
    size_t pcap = 0;

    while (!g_stop) {
        size_t need = (size_t)sv.nconns + 1;
        if (need > pcap) {
            pcap = need * 2;
            pfds = realloc(pfds, pcap * sizeof *pfds);
        }
        pfds[0].fd = sv.listen_fd;
        pfds[0].events = POLLIN;
        size_t n = 1;
        for (conn *c = sv.conns; c; c = c->next, n++) {
            pfds[n].fd = c->fd;
            pfds[n].events = c->state == C_READ ? POLLIN : c->state == C_WRITE ? POLLOUT : 0;
            pfds[n].revents = 0;
        }
        int timeout = p->sched.nrunnable > 0 ? 0 : 1000;
        int rc = poll(pfds, (nfds_t)n, timeout);
        if (rc < 0) {
            if (errno == EINTR)
                continue;
            perror("poll");
            break;
        }

        if (pfds[0].revents & POLLIN) {
            for (;;) {
                int fd = accept(sv.listen_fd, NULL, NULL);
                if (fd < 0)
                    break;
                set_nonblock(fd);
                setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
                conn *c = calloc(1, sizeof *c);
                c->fd = fd;
                c->state = C_READ;
                c->t0 = iso_now_ns();
                c->next = sv.conns;
                sv.conns = c;
                sv.nconns++;
                sv.total_conns++;
            }
        }

        n = 1;
        for (conn *c = sv.conns; c; c = c->next, n++) {
            short ev = pfds[n].revents;
            if (ev & (POLLERR | POLLNVAL)) {
                if (c->state != C_WAIT)
                    c->state = C_CLOSE;
                continue;
            }
            if (c->state == C_READ && (ev & (POLLIN | POLLHUP))) {
                char buf[16384];
                ssize_t r = read(c->fd, buf, sizeof buf);
                if (r == 0 || (r < 0 && errno != EAGAIN && errno != EWOULDBLOCK)) {
                    c->state = C_CLOSE;
                    continue;
                }
                if (r > 0) {
                    if (c->in.n + (size_t)r > MAX_REQUEST) {
                        send_error(c, 413, "request too large");
                        continue;
                    }
                    iso_buf_append(&c->in, buf, (size_t)r);
                    try_parse(&sv, c);
                }
            } else if (c->state == C_WRITE && (ev & (POLLOUT | POLLHUP))) {
                ssize_t w = write(c->fd, c->out.p + c->out_off, c->out.n - c->out_off);
                if (w < 0 && errno != EAGAIN && errno != EWOULDBLOCK) {
                    c->state = C_CLOSE;
                    continue;
                }
                if (w > 0)
                    c->out_off += (size_t)w;
                if (c->out_off >= c->out.n)
                    c->state = C_CLOSE;
            }
        }

        /* Run every runnable isolate fiber for one time slice. */
        if (p->sched.nrunnable > 0)
            iso_sched_tick(p);

        /* Drain any responses that became writable synchronously. */
        for (conn *c = sv.conns; c; c = c->next) {
            if (c->state == C_WRITE && c->out_off < c->out.n) {
                ssize_t w = write(c->fd, c->out.p + c->out_off, c->out.n - c->out_off);
                if (w > 0)
                    c->out_off += (size_t)w;
                else if (w < 0 && errno != EAGAIN && errno != EWOULDBLOCK)
                    c->state = C_CLOSE;
                if (c->out_off >= c->out.n)
                    c->state = C_CLOSE;
            }
        }

        conn **pp = &sv.conns;
        while (*pp) {
            conn *c = *pp;
            if (c->state == C_CLOSE) {
                *pp = c->next;
                conn_close(&sv, c);
            } else
                pp = &c->next;
        }
    }

    fprintf(stderr, "isolates: shutting down\n");
    /* Let in-flight fibers finish so their connections get answered. */
    while (p->sched.nrunnable > 0)
        iso_sched_tick(p);
    while (sv.conns) {
        conn *c = sv.conns;
        sv.conns = c->next;
        if (c->state == C_WRITE)
            (void)!write(c->fd, c->out.p + c->out_off, c->out.n - c->out_off);
        conn_close(&sv, c);
    }
    free(pfds);
    close(sv.listen_fd);
    return 0;
}
