/* test_vm.c - unit tests for the assembler, VM, fibers and scheduler. */
#include "isolates.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures;
#define CHECK(cond)                                                       \
    do {                                                                  \
        if (!(cond)) {                                                    \
            failures++;                                                   \
            fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
        }                                                                 \
    } while (0)

typedef struct result {
    int status;
    int error_code;
    char body[4096];
    char error[256];
    uint64_t executed;
    uint32_t switches;
    int done;
} result;

static void capture(iso_fiber *f, void *user)
{
    result *r = user;
    r->status = f->res.status;
    r->error_code = f->error_code;
    snprintf(r->body, sizeof r->body, "%.*s", (int)f->res.body_len, f->res.body ? f->res.body : "");
    snprintf(r->error, sizeof r->error, "%s", f->error);
    r->executed = f->executed;
    r->switches = f->switches;
    r->done++;
}

static iso_isolate *deploy(iso_platform *p, const char *name, const char *src)
{
    iso_script *s;
    char err[256];
    if (iso_assemble(src, strlen(src), &s, err, sizeof err) < 0) {
        fprintf(stderr, "assemble failed: %s\n", err);
        return NULL;
    }
    iso_isolate *iso = iso_platform_deploy(p, name, s, err, sizeof err);
    iso_script_unref(s);
    return iso;
}

static result run(iso_platform *p, iso_isolate *iso, const char *method, const char *path,
                  const char *body)
{
    result r = {0};
    iso_request req;
    iso_request_init(&req);
    free(req.method);
    req.method = strdup(method);
    free(req.path);
    req.path = strdup(path);
    if (body) {
        req.body = strdup(body);
        req.body_len = strlen(body);
    }
    iso_fiber *f = iso_fiber_create(p, iso, &req, capture, &r);
    CHECK(f != NULL);
    if (f)
        iso_invoke_sync(p, f);
    CHECK(r.done == 1);
    return r;
}

/* A raw fiber ping-pong through the assembly switch. */
static iso_ctx main_ctx, fiber_ctx;
static int counter;
static char stack[64 * 1024];

static void hop(void *arg)
{
    CHECK(arg == &counter);
    for (int i = 0; i < 5; i++) {
        counter++;
        iso_ctx_switch(&fiber_ctx, &main_ctx);
    }
    counter = -1;
    iso_ctx_switch(&fiber_ctx, &main_ctx);
    abort();
}

static void test_context_switch(void)
{
    iso_ctx_init(&fiber_ctx, stack, sizeof stack, hop, &counter);
    for (int i = 1; i <= 5; i++) {
        iso_ctx_switch(&main_ctx, &fiber_ctx);
        CHECK(counter == i);
    }
    iso_ctx_switch(&main_ctx, &fiber_ctx);
    CHECK(counter == -1);
}

static void test_assembler_errors(void)
{
    iso_script *s;
    char err[256];
    CHECK(iso_assemble("bogus", 5, &s, err, sizeof err) < 0);
    CHECK(strstr(err, "unknown instruction") != NULL);
    CHECK(iso_assemble("jmp nowhere", 11, &s, err, sizeof err) < 0);
    CHECK(strstr(err, "undefined label") != NULL);
    CHECK(iso_assemble("push \"open", 10, &s, err, sizeof err) < 0);
    CHECK(strstr(err, "unterminated") != NULL);
    CHECK(iso_assemble("a:\na:\n", 6, &s, err, sizeof err) < 0);
    CHECK(strstr(err, "duplicate") != NULL);
    CHECK(iso_assemble("load 99", 7, &s, err, sizeof err) < 0);
    CHECK(iso_assemble("; only a comment\n", 17, &s, err, sizeof err) < 0);
    CHECK(strstr(err, "no instructions") != NULL);
    const char *ok = "push 1 ; comment\n# another\nlabel: push \"a\\n\\\"b\" halt";
    CHECK(iso_assemble(ok, strlen(ok), &s, err, sizeof err) < 0); /* two insns on one line */
    ok = "push 1\nlabel:\n  push \"a\\n\\\"b\"\nhalt\n";
    CHECK(iso_assemble(ok, strlen(ok), &s, err, sizeof err) == 0);
    CHECK(s->ncode == 3);
    CHECK(s->nconsts == 1);
    CHECK(s->consts[0].n == 4);
    iso_script_unref(s);
}

static void test_arithmetic_and_strings(iso_platform *p)
{
    iso_isolate *iso = deploy(p, "calc",
        "push 6\npush 7\nmul\nitoa\nres.body\n"
        "push \" \"\nres.body\n"
        "push \"abc\"\nupper\npush \"def\"\nconcat\nres.body\n"
        "push \" \"\nres.body\n"
        "push \"hello world\"\npush \"world\"\nfind\nres.body\n"
        "push \" \"\nres.body\n"
        "push \"hello\"\npush 1\npush 3\nsubstr\nres.body\n"
        "push \" \"\nres.body\n"
        "push \"-17\"\natoi\npush 2\nmod\nres.body\n"
        "push \" \"\nres.body\n"
        "push \"ab\"\npush \"ab\"\neq\npush \"ab\"\npush \"ac\"\nlt\nand\nres.body\n"
        "push 201\nres.status\nhalt\n");
    CHECK(iso != NULL);
    result r = run(p, iso, "GET", "/", NULL);
    CHECK(r.error_code == 0);
    CHECK(r.status == 201);
    CHECK(strcmp(r.body, "42 ABCdef 6 ell -1 1") == 0);
}

static void test_control_flow(iso_platform *p)
{
    /* sum 1..100 with a loop and a subroutine */
    iso_isolate *iso = deploy(p, "loop",
        "push 0\nstore 0\npush 1\nstore 1\n"
        "again:\nload 1\npush 100\ngt\njnz done\n"
        "call add_it\nload 1\npush 1\nadd\nstore 1\njmp again\n"
        "done:\nload 0\nres.body\nhalt\n"
        "add_it:\nload 0\nload 1\nadd\nstore 0\nret\n");
    CHECK(iso != NULL);
    result r = run(p, iso, "GET", "/", NULL);
    CHECK(r.error_code == 0);
    CHECK(strcmp(r.body, "5050") == 0);
}

static void test_traps(iso_platform *p)
{
    iso_isolate *iso = deploy(p, "traps", "push 1\npush 0\ndiv\nhalt\n");
    result r = run(p, iso, "GET", "/", NULL);
    CHECK(r.error_code == ISO_ERR_TRAP);
    CHECK(strstr(r.error, "division by zero") != NULL);

    iso = deploy(p, "traps", "pop\nhalt\n");
    r = run(p, iso, "GET", "/", NULL);
    CHECK(r.error_code == ISO_ERR_TRAP);
    CHECK(strstr(r.error, "underflow") != NULL);

    iso = deploy(p, "traps", "push \"x\"\npush 1\nadd\nhalt\n");
    r = run(p, iso, "GET", "/", NULL);
    CHECK(r.error_code == ISO_ERR_TRAP);
    CHECK(strstr(r.error, "type error") != NULL);

    iso = deploy(p, "traps", "ret\n");
    r = run(p, iso, "GET", "/", NULL);
    CHECK(r.error_code == ISO_ERR_TRAP);

    iso = deploy(p, "traps", "loop:\npush 1\njmp loop\n");
    r = run(p, iso, "GET", "/", NULL);
    CHECK(r.error_code == ISO_ERR_TRAP);
    CHECK(strstr(r.error, "stack overflow") != NULL);

    iso = deploy(p, "traps", "rec:\ncall rec\n");
    r = run(p, iso, "GET", "/", NULL);
    CHECK(r.error_code == ISO_ERR_TRAP);
    CHECK(strstr(r.error, "call stack overflow") != NULL);
    CHECK(iso->errors == 6);
}

static void test_limits(iso_platform *p)
{
    iso_isolate *iso = deploy(p, "limits", "loop:\njmp loop\n");
    iso_isolate_set_limits(iso, 5000, ISO_MIN_MEM_LIMIT);
    result r = run(p, iso, "GET", "/", NULL);
    CHECK(r.error_code == ISO_ERR_LIMITS);
    CHECK(r.executed == 5000);
    CHECK(r.switches == 5000 / ISO_SLICE);

    iso = deploy(p, "limits", "push \"0123456789abcdef\"\nloop:\ndup\nconcat\njmp loop\n");
    iso_isolate_set_limits(iso, 1000000, ISO_MIN_MEM_LIMIT);
    r = run(p, iso, "GET", "/", NULL);
    CHECK(r.error_code == ISO_ERR_LIMITS);
    CHECK(strstr(r.error, "memory") != NULL);

    /* the budget is per invocation: a fresh request works again */
    iso = deploy(p, "limits", "push \"ok\"\nres.body\nhalt\n");
    r = run(p, iso, "GET", "/", NULL);
    CHECK(r.error_code == 0);
    CHECK(strcmp(r.body, "ok") == 0);
}

static void test_request_and_kv(iso_platform *p)
{
    iso_isolate *iso = deploy(p, "kv",
        "req.method\npush \"PUT\"\neq\njz get\n"
        "req.path\nreq.body\nkv.put\npush \"stored\"\nres.body\nhalt\n"
        "get:\nreq.path\nkv.get\nres.body\n"
        "push \"x-hits\"\npush \"hits\"\nkv.get\natoi\npush 1\nadd\ndup\nstore 0\nitoa\nres.header\n"
        "push \"hits\"\nload 0\nkv.put\nhalt\n");
    result r = run(p, iso, "PUT", "/color", "blue");
    CHECK(r.error_code == 0);
    CHECK(strcmp(r.body, "stored") == 0);
    r = run(p, iso, "GET", "/color", NULL);
    CHECK(strcmp(r.body, "blue") == 0);
    r = run(p, iso, "GET", "/color", NULL);
    CHECK(r.error_code == 0);
    const iso_kv_entry *e = iso_kv_get(&iso->kv, "hits", 4);
    CHECK(e && strcmp(e->value, "2") == 0);
    CHECK(iso->kv.count == 2);
    CHECK(iso->requests == 3);
    CHECK(iso->log_count >= 1);

    iso_isolate_set_env(iso, "GREETING", "hey");
    iso = deploy(p, "kv", "push \"GREETING\"\nenv\nres.body\nhalt\n");
    r = run(p, iso, "GET", "/", NULL);
    CHECK(strcmp(r.body, "hey") == 0);
    CHECK(iso->deploys == 2);
}

static void test_scheduler_interleaves(iso_platform *p)
{
    /* Two long-running fibers must alternate rather than run back to back. */
    iso_isolate *a = deploy(p, "a", "push 0\nstore 0\nl:\nload 0\npush 1\nadd\ndup\nstore 0\npush 3000\nlt\njnz l\npush \"a\"\nres.body\nhalt\n");
    iso_isolate *b = deploy(p, "b", "push 0\nstore 0\nl:\nload 0\npush 1\nadd\ndup\nstore 0\npush 3000\nlt\njnz l\npush \"b\"\nres.body\nhalt\n");
    result ra = {0}, rb = {0};
    iso_request req;
    iso_request_init(&req);
    iso_fiber *fa = iso_fiber_create(p, a, &req, capture, &ra);
    iso_request_init(&req);
    iso_fiber *fb = iso_fiber_create(p, b, &req, capture, &rb);
    CHECK(fa && fb);
    CHECK(p->sched.nrunnable == 2);
    uint64_t switches0 = p->sched.switches;
    int ticks = 0;
    while (p->sched.nrunnable > 0) {
        iso_sched_tick(p);
        ticks++;
    }
    CHECK(ra.done == 1 && rb.done == 1);
    CHECK(strcmp(ra.body, "a") == 0 && strcmp(rb.body, "b") == 0);
    /* each fiber needs several slices; every tick switches into both */
    CHECK(ticks > 5);
    CHECK(p->sched.switches - switches0 >= (uint64_t)ticks * 2 - 1);
    CHECK(ra.switches > 0 && rb.switches > 0);
}

static void test_json(void)
{
    char err[128];
    const char *doc = "{\"a\":[1,2,{\"b\":\"c\\n\\u00e9\"}],\"t\":true,\"n\":null,\"x\":-1.5}";
    json_val *v = json_parse(doc, strlen(doc), err, sizeof err);
    CHECK(v != NULL);
    if (v) {
        json_val *a = json_get(v, "a");
        CHECK(a && a->t == J_ARR && a->n == 3);
        CHECK(a && a->items[0].num == 1);
        CHECK(a && strcmp(json_str(&a->items[2], "b", ""), "c\n\xc3\xa9") == 0);
        CHECK(json_get(v, "t")->b == true);
        CHECK(json_num(v, "x", 0) == -1.5);
        json_free(v);
    }
    CHECK(json_parse("{\"a\":}", 6, err, sizeof err) == NULL);
    CHECK(err[0] != 0);
    CHECK(json_parse("[1,2] x", 7, err, sizeof err) == NULL);

    iso_buf b = {0};
    iso_buf_json_str(&b, "q\"\\\n\x01", 5);
    CHECK(strcmp(b.p, "\"q\\\"\\\\\\n\\u0001\"") == 0);
    iso_buf_free(&b);
}

static void test_platform(iso_platform *p)
{
    CHECK(iso_name_valid("my-worker-1"));
    CHECK(!iso_name_valid("Bad"));
    CHECK(!iso_name_valid("-x"));
    CHECK(!iso_name_valid(""));
    int before = p->nisolates;
    iso_isolate *iso = deploy(p, "temp", "halt\n");
    CHECK(iso && p->nisolates == before + 1);
    CHECK(iso_platform_find(p, "temp") == iso);
    CHECK(iso_platform_remove(p, "temp"));
    CHECK(!iso_platform_remove(p, "temp"));
    CHECK(p->nisolates == before);
    char err[128];
    CHECK(iso_platform_deploy(p, "Not Valid", NULL, err, sizeof err) == NULL);
}

int main(void)
{
    test_context_switch();
    test_assembler_errors();
    test_json();
    iso_platform p;
    iso_platform_init(&p);
    test_arithmetic_and_strings(&p);
    test_control_flow(&p);
    test_traps(&p);
    test_limits(&p);
    test_request_and_kv(&p);
    test_scheduler_interleaves(&p);
    test_platform(&p);
    iso_platform_free(&p);
    if (failures) {
        fprintf(stderr, "%d check(s) failed\n", failures);
        return 1;
    }
    printf("test_vm: all checks passed\n");
    return 0;
}
