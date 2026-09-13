/* main.c - command line entry point. */
#include "isolates.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void usage(void)
{
    fprintf(stderr,
        "isolates %s - a tiny Workers-style isolate platform\n\n"
        "usage:\n"
        "  isolates serve [--port N] [--bind ADDR] [--data DIR] [--examples DIR]\n"
        "                 [--dashboard DIR] [--load NAME=FILE ...] [-v]\n"
        "  isolates run FILE [--name NAME] [--method M] [--path P] [--body B]\n"
        "                 [--header K:V ...] [--env K=V ...] [--kv K=V ...]\n"
        "                 [--cpu N] [--mem BYTES] [-v]\n"
        "  isolates asm FILE            disassemble a script\n"
        "  isolates bench FILE [-n N] [-c C]  run N invocations, C at a time\n"
        "  isolates reference           list the instruction set\n"
        "  isolates version\n",
        ISO_VERSION);
}

static char *slurp(const char *path, size_t *len)
{
    FILE *f = strcmp(path, "-") == 0 ? stdin : fopen(path, "rb");
    if (!f) {
        perror(path);
        return NULL;
    }
    iso_buf b = {0};
    char chunk[4096];
    size_t r;
    while ((r = fread(chunk, 1, sizeof chunk, f)) > 0)
        iso_buf_append(&b, chunk, r);
    if (f != stdin)
        fclose(f);
    if (!b.p)
        iso_buf_append(&b, "", 0);
    *len = b.n;
    return b.p;
}

static iso_isolate *deploy_file(iso_platform *p, const char *name, const char *path)
{
    size_t len;
    char *src = slurp(path, &len);
    if (!src)
        return NULL;
    iso_script *s;
    char err[256];
    if (iso_assemble(src, len, &s, err, sizeof err) < 0) {
        fprintf(stderr, "%s: %s\n", path, err);
        free(src);
        return NULL;
    }
    free(src);
    iso_isolate *iso = iso_platform_deploy(p, name, s, err, sizeof err);
    iso_script_unref(s);
    if (!iso)
        fprintf(stderr, "%s\n", err);
    return iso;
}

static void name_from_path(const char *path, char *out, size_t n)
{
    const char *base = strrchr(path, '/');
    base = base ? base + 1 : path;
    size_t i = 0;
    for (; base[i] && base[i] != '.' && i + 1 < n; i++) {
        char c = base[i];
        if (c >= 'A' && c <= 'Z')
            c = (char)(c + 32);
        if (!((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-'))
            c = '-';
        out[i] = c;
    }
    out[i] = 0;
    if (!iso_name_valid(out))
        snprintf(out, n, "worker");
}

/* ---------------------------------------------------------------- */
static void print_done(iso_fiber *f, void *user)
{
    bool verbose = *(bool *)user;
    if (f->error_code) {
        printf("HTTP/1.1 %d\nX-Isolate-Error: %d\n\nError %d: %s\n",
               f->error_code == ISO_ERR_LIMITS ? 503 : 500, f->error_code,
               f->error_code, f->error);
    } else {
        printf("HTTP/1.1 %d\n", f->res.status);
        for (int i = 0; i < f->res.nheaders; i++)
            printf("%s: %s\n", f->res.headers[i].name, f->res.headers[i].value);
        printf("\n%.*s\n", (int)f->res.body_len, f->res.body ? f->res.body : "");
    }
    if (verbose)
        fprintf(stderr, "-- %llu instructions, %llu us cpu, %zu bytes peak, %u switches\n",
                (unsigned long long)f->executed, (unsigned long long)(f->cpu_ns / 1000),
                f->arena.peak, f->switches);
}

static int cmd_run(int argc, char **argv)
{
    if (argc < 1) {
        usage();
        return 2;
    }
    const char *file = argv[0];
    char name[ISO_NAME_MAX];
    name_from_path(file, name, sizeof name);
    iso_platform p;
    iso_platform_init(&p);
    iso_request req;
    iso_request_init(&req);
    uint64_t cpu = 0;
    size_t mem = 0;
    bool verbose = false;
    const char *kvs[64];
    int nkv = 0;
    const char *envs[64];
    int nenv = 0;
    for (int i = 1; i < argc; i++) {
        const char *a = argv[i];
        const char *v = i + 1 < argc ? argv[i + 1] : NULL;
        if (!strcmp(a, "-v")) {
            verbose = true;
        } else if (!strcmp(a, "--name") && v) {
            snprintf(name, sizeof name, "%s", v);
            i++;
        } else if (!strcmp(a, "--method") && v) {
            free(req.method);
            req.method = strdup(v);
            i++;
        } else if (!strcmp(a, "--path") && v) {
            free(req.path);
            free(req.query);
            const char *q = strchr(v, '?');
            req.path = q ? strndup(v, (size_t)(q - v)) : strdup(v);
            req.query = strdup(q ? q + 1 : "");
            i++;
        } else if (!strcmp(a, "--body") && v) {
            free(req.body);
            req.body = strdup(v);
            req.body_len = strlen(v);
            i++;
        } else if (!strcmp(a, "--header") && v) {
            const char *colon = strchr(v, ':');
            if (colon) {
                const char *val = colon + 1;
                while (*val == ' ')
                    val++;
                iso_request_add_header(&req, v, (size_t)(colon - v), val, strlen(val));
            }
            i++;
        } else if (!strcmp(a, "--kv") && v && nkv < 64) {
            kvs[nkv++] = v;
            i++;
        } else if (!strcmp(a, "--env") && v && nenv < 64) {
            envs[nenv++] = v;
            i++;
        } else if (!strcmp(a, "--cpu") && v) {
            cpu = strtoull(v, NULL, 10);
            i++;
        } else if (!strcmp(a, "--mem") && v) {
            mem = strtoull(v, NULL, 10);
            i++;
        } else {
            fprintf(stderr, "unknown option %s\n", a);
            usage();
            return 2;
        }
    }
    iso_isolate *iso = deploy_file(&p, name, file);
    if (!iso)
        return 1;
    if (cpu || mem)
        iso_isolate_set_limits(iso, cpu ? cpu : iso->cpu_limit, mem ? mem : iso->mem_limit);
    for (int i = 0; i < nkv; i++) {
        const char *eq = strchr(kvs[i], '=');
        if (eq)
            iso_kv_put(&iso->kv, kvs[i], (size_t)(eq - kvs[i]), eq + 1, strlen(eq + 1));
    }
    for (int i = 0; i < nenv; i++) {
        const char *eq = strchr(envs[i], '=');
        if (eq) {
            char *k = strndup(envs[i], (size_t)(eq - envs[i]));
            iso_isolate_set_env(iso, k, eq + 1);
            free(k);
        }
    }
    iso_fiber *f = iso_fiber_create(&p, iso, &req, print_done, &verbose);
    if (!f) {
        fprintf(stderr, "could not create fiber\n");
        return 1;
    }
    iso_invoke_sync(&p, f);
    if (verbose)
        for (int i = 0; i < iso->log_count; i++)
            fprintf(stderr, "log: %s\n", iso->logs[(iso->log_head + i) % ISO_LOG_RING].msg);
    int rc = iso->errors ? 1 : 0;
    iso_platform_free(&p);
    return rc;
}

static int cmd_asm(int argc, char **argv)
{
    if (argc < 1) {
        usage();
        return 2;
    }
    size_t len;
    char *src = slurp(argv[0], &len);
    if (!src)
        return 1;
    iso_script *s;
    char err[256];
    if (iso_assemble(src, len, &s, err, sizeof err) < 0) {
        fprintf(stderr, "%s: %s\n", argv[0], err);
        free(src);
        return 1;
    }
    free(src);
    printf("; %u instructions, %u constants\n", s->ncode, s->nconsts);
    for (uint32_t i = 0; i < s->ncode; i++) {
        const iso_insn *in = &s->code[i];
        printf("%5u  ", i);
        switch (in->op) {
        case OP_PUSH_STR:
            printf("push \"%.*s\"\n", (int)s->consts[in->imm].n, s->consts[in->imm].p);
            break;
        case OP_PUSH_INT: case OP_LOAD: case OP_STORE:
            printf("%s %lld\n", iso_op_name(in->op), (long long)in->imm);
            break;
        case OP_JMP: case OP_JZ: case OP_JNZ: case OP_CALL:
            printf("%s @%lld\n", iso_op_name(in->op), (long long)in->imm);
            break;
        case OP_SYS:
            printf("%s\n", iso_sys_name((int)in->imm));
            break;
        default:
            printf("%s\n", iso_op_name(in->op));
        }
    }
    iso_script_unref(s);
    return 0;
}

static void bench_done(iso_fiber *f, void *user)
{
    (void)f;
    (*(uint64_t *)user)++;
}

static int cmd_bench(int argc, char **argv)
{
    if (argc < 1) {
        usage();
        return 2;
    }
    int n = 10000, conc = 64;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "-n") && i + 1 < argc)
            n = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-c") && i + 1 < argc)
            conc = atoi(argv[++i]);
    }
    iso_platform p;
    iso_platform_init(&p);
    iso_isolate *iso = deploy_file(&p, "bench", argv[0]);
    if (!iso)
        return 1;
    uint64_t done = 0, started = 0;
    uint64_t t0 = iso_now_ns();
    while ((int)done < n) {
        while ((int)started < n && p.sched.nrunnable < conc) {
            iso_request req;
            iso_request_init(&req);
            if (!iso_fiber_create(&p, iso, &req, bench_done, &done))
                break;
            started++;
        }
        iso_sched_tick(&p);
    }
    uint64_t dt = iso_now_ns() - t0;
    printf("%d invocations, concurrency %d: %.1f ms total, %.1f us/invocation, "
           "%.0f req/s\n%llu instructions (%.1f M insn/s), %llu context switches, "
           "%llu errors\n",
           n, conc, dt / 1e6, dt / 1e3 / n, n / (dt / 1e9),
           (unsigned long long)iso->instructions, iso->instructions / (dt / 1e9) / 1e6,
           (unsigned long long)p.sched.switches, (unsigned long long)iso->errors);
    iso_platform_free(&p);
    return 0;
}

static int cmd_serve(int argc, char **argv)
{
    iso_platform p;
    iso_platform_init(&p);
    iso_server_opts o = { "127.0.0.1", 8787, NULL, false };
    const char *data = NULL;
    for (int i = 0; i < argc; i++) {
        const char *a = argv[i];
        const char *v = i + 1 < argc ? argv[i + 1] : NULL;
        if (!strcmp(a, "--port") && v) {
            o.port = atoi(v);
            i++;
        } else if (!strcmp(a, "--bind") && v) {
            o.bind = v;
            i++;
        } else if (!strcmp(a, "--data") && v) {
            data = v;
            i++;
        } else if (!strcmp(a, "--examples") && v) {
            setenv("ISOLATES_EXAMPLES", v, 1);
            i++;
        } else if (!strcmp(a, "--dashboard") && v) {
            o.dashboard_dir = v;
            i++;
        } else if (!strcmp(a, "--load") && v) {
            const char *eq = strchr(v, '=');
            char name[ISO_NAME_MAX];
            if (eq) {
                snprintf(name, sizeof name, "%.*s", (int)(eq - v), v);
                deploy_file(&p, name, eq + 1);
            } else {
                name_from_path(v, name, sizeof name);
                deploy_file(&p, name, v);
            }
            i++;
        } else if (!strcmp(a, "-v")) {
            o.verbose = true;
        } else {
            fprintf(stderr, "unknown option %s\n", a);
            usage();
            return 2;
        }
    }
    if (data) {
        int n = iso_platform_load_dir(&p, data);
        if (n < 0)
            fprintf(stderr, "isolates: cannot open data dir %s\n", data);
        else
            fprintf(stderr, "isolates: loaded %d worker(s) from %s\n", n, data);
        /* persist anything passed via --load too */
        for (iso_isolate *iso = p.isolates; iso; iso = iso->next)
            iso_platform_save(&p, iso);
    }
    int rc = iso_server_run(&p, &o);
    iso_platform_free(&p);
    return rc;
}

static int cmd_reference(void)
{
    for (size_t i = 0; i < iso_mnemonic_count(); i++) {
        const char *name, *operand, *desc;
        iso_mnemonic_at(i, &name, &operand, &desc);
        printf("%-12s %-11s %s\n", name, operand, desc);
    }
    return 0;
}

int main(int argc, char **argv)
{
    if (argc < 2) {
        usage();
        return 2;
    }
    const char *cmd = argv[1];
    if (!strcmp(cmd, "serve"))
        return cmd_serve(argc - 2, argv + 2);
    if (!strcmp(cmd, "run"))
        return cmd_run(argc - 2, argv + 2);
    if (!strcmp(cmd, "asm"))
        return cmd_asm(argc - 2, argv + 2);
    if (!strcmp(cmd, "bench"))
        return cmd_bench(argc - 2, argv + 2);
    if (!strcmp(cmd, "reference"))
        return cmd_reference();
    if (!strcmp(cmd, "version")) {
        printf("isolates %s (%s)\n", ISO_VERSION, iso_ctx_arch());
        return 0;
    }
    usage();
    return 2;
}
