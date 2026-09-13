/*
 * isolates.h - a small Cloudflare-Workers-style isolate platform.
 *
 * One OS thread hosts many "isolates". Each isolate owns a deployed worker
 * script (bytecode), a KV namespace, resource limits and metrics. Every
 * incoming request becomes a fiber: a coroutine with its own machine stack
 * (switched with hand-written assembly), its own memory arena and its own
 * instruction budget. A cooperative scheduler round-robins the fibers.
 */
#ifndef ISOLATES_H
#define ISOLATES_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define ISO_VERSION "0.1.0"

#define ISO_DEFAULT_CPU_LIMIT   100000      /* instructions per invocation */
#define ISO_DEFAULT_MEM_LIMIT   (256 * 1024) /* arena bytes per invocation */
#define ISO_MIN_MEM_LIMIT       (16 * 1024)
#define ISO_MAX_MEM_LIMIT       (64u * 1024 * 1024)
#define ISO_SLICE               2000        /* instructions per time slice */
#define ISO_FIBER_STACK         (256 * 1024)
#define ISO_MAX_HEADERS         32
#define ISO_MAX_BODY            (1024 * 1024)
#define ISO_LOG_RING            256
#define ISO_KV_MAX_ENTRIES      4096
#define ISO_KV_MAX_VALUE        (64 * 1024)
#define ISO_NAME_MAX            48

/* Error codes, in the spirit of Cloudflare's 11xx worker errors. */
#define ISO_ERR_TRAP    1101 /* worker threw an exception */
#define ISO_ERR_LIMITS  1102 /* worker exceeded resource limits */

/* ------------------------------------------------------------------ */
/* Context switching (runtime/src/context_<arch>.S)                    */
/* ------------------------------------------------------------------ */
typedef struct iso_ctx {
    void *sp;
} iso_ctx;

/* Save callee-saved registers on the current stack, store the stack
 * pointer into *from, load *to's stack pointer and restore its registers. */
void iso_ctx_switch(iso_ctx *from, iso_ctx *to);
/* First code to run on a fresh fiber stack; calls entry(arg). */
void iso_ctx_trampoline(void);
/* Prepare a fresh stack so that the first switch into ctx runs entry(arg). */
void iso_ctx_init(iso_ctx *ctx, void *stack_base, size_t stack_size,
                  void (*entry)(void *), void *arg);
const char *iso_ctx_arch(void);

/* ------------------------------------------------------------------ */
/* Memory arena                                                        */
/* ------------------------------------------------------------------ */
typedef struct iso_arena {
    uint8_t *base;
    size_t size;
    size_t used;
    size_t peak;
} iso_arena;

int   iso_arena_init(iso_arena *a, size_t size);
void *iso_arena_alloc(iso_arena *a, size_t n); /* NULL when exhausted */
void  iso_arena_reset(iso_arena *a);
void  iso_arena_free(iso_arena *a);

/* ------------------------------------------------------------------ */
/* Bytecode                                                            */
/* ------------------------------------------------------------------ */
typedef struct iso_str {
    const char *p;
    uint32_t n;
} iso_str;

enum iso_op {
    OP_NOP = 0,
    OP_PUSH_INT, OP_PUSH_STR, OP_POP, OP_DUP, OP_SWAP, OP_OVER,
    OP_ADD, OP_SUB, OP_MUL, OP_DIV, OP_MOD, OP_NEG,
    OP_EQ, OP_NE, OP_LT, OP_LE, OP_GT, OP_GE,
    OP_NOT, OP_AND, OP_OR,
    OP_JMP, OP_JZ, OP_JNZ, OP_CALL, OP_RET,
    OP_LOAD, OP_STORE,
    OP_CONCAT, OP_LEN, OP_SUBSTR, OP_ITOA, OP_ATOI, OP_UPPER, OP_LOWER,
    OP_FIND, OP_STARTS,
    OP_HALT,
    OP_SYS,
    OP__COUNT
};

enum iso_sys {
    SYS_REQ_METHOD = 0, SYS_REQ_PATH, SYS_REQ_QUERY, SYS_REQ_BODY, SYS_REQ_HEADER,
    SYS_RES_STATUS, SYS_RES_HEADER, SYS_RES_BODY,
    SYS_KV_GET, SYS_KV_PUT, SYS_KV_DEL, SYS_KV_HAS,
    SYS_LOG, SYS_TIME, SYS_YIELD, SYS_ENV, SYS_RAND, SYS_WORKER, SYS_SPIN,
    SYS__COUNT
};

typedef struct iso_insn {
    uint8_t op;
    int64_t imm; /* integer immediate, constant index, jump target, slot, sys id */
} iso_insn;

typedef struct iso_script {
    iso_insn *code;
    uint32_t  ncode;
    iso_str  *consts;
    uint32_t  nconsts;
    char     *source;
    size_t    source_len;
    int       refs;
} iso_script;

int  iso_assemble(const char *src, size_t len, iso_script **out,
                  char *err, size_t errlen);
void iso_script_ref(iso_script *s);
void iso_script_unref(iso_script *s);
const char *iso_op_name(int op);
const char *iso_sys_name(int sys);
size_t iso_mnemonic_count(void);
void iso_mnemonic_at(size_t i, const char **name, const char **operand, const char **desc);

/* ------------------------------------------------------------------ */
/* KV namespace                                                        */
/* ------------------------------------------------------------------ */
typedef struct iso_kv_entry {
    char *key;
    char *value;
    size_t vlen;
    uint64_t updated_ms;
    struct iso_kv_entry *next;
} iso_kv_entry;

typedef struct iso_kv {
    iso_kv_entry *buckets[257];
    int count;
} iso_kv;

void iso_kv_init(iso_kv *kv);
void iso_kv_free(iso_kv *kv);
const iso_kv_entry *iso_kv_get(const iso_kv *kv, const char *key, size_t klen);
int  iso_kv_put(iso_kv *kv, const char *key, size_t klen, const char *val, size_t vlen);
bool iso_kv_del(iso_kv *kv, const char *key, size_t klen);
void iso_kv_each(const iso_kv *kv, void (*fn)(const iso_kv_entry *, void *), void *user);

/* ------------------------------------------------------------------ */
/* Requests and responses                                              */
/* ------------------------------------------------------------------ */
typedef struct iso_header {
    char *name;
    char *value;
} iso_header;

typedef struct iso_request {
    char *method;
    char *path;
    char *query;
    iso_header headers[ISO_MAX_HEADERS];
    int nheaders;
    char *body;
    size_t body_len;
} iso_request;

typedef struct iso_response {
    int status;
    iso_header headers[ISO_MAX_HEADERS];
    int nheaders;
    char *body;
    size_t body_len;
    size_t body_cap;
} iso_response;

void iso_request_init(iso_request *r);
void iso_request_free(iso_request *r);
int  iso_request_add_header(iso_request *r, const char *n, size_t nl, const char *v, size_t vl);
const char *iso_request_header(const iso_request *r, const char *name);
void iso_response_init(iso_response *r);
void iso_response_free(iso_response *r);
int  iso_response_set_header(iso_response *r, const char *n, size_t nl, const char *v, size_t vl);
int  iso_response_append(iso_response *r, const char *p, size_t n);

/* ------------------------------------------------------------------ */
/* Isolates, fibers, scheduler                                         */
/* ------------------------------------------------------------------ */
#define ISO_VM_STACK   256
#define ISO_VM_LOCALS  64
#define ISO_VM_CALLS   64

typedef struct iso_val {
    enum { V_INT, V_STR } t;
    union {
        int64_t i;
        iso_str s;
    };
} iso_val;

typedef struct iso_vm {
    iso_val  stack[ISO_VM_STACK];
    int      sp;
    iso_val  locals[ISO_VM_LOCALS];
    uint32_t pc;
    uint32_t calls[ISO_VM_CALLS];
    int      csp;
} iso_vm;

typedef struct iso_log_entry {
    uint64_t ts_ms;
    char msg[240];
} iso_log_entry;

typedef struct iso_env {
    char *name;
    char *value;
} iso_env;

struct iso_sched;
struct iso_fiber;

typedef struct iso_isolate {
    char name[ISO_NAME_MAX];
    iso_script *script;
    iso_kv kv;
    iso_env *env;
    int nenv;
    uint64_t cpu_limit;   /* instructions per invocation */
    size_t   mem_limit;   /* arena bytes per invocation */
    uint64_t created_ms;
    uint64_t deployed_ms;
    int      deploys;

    /* metrics */
    uint64_t requests;
    uint64_t errors;
    uint64_t instructions;
    uint64_t cpu_ns;
    uint64_t max_cpu_ns;
    uint64_t last_invoked_ms;
    size_t   peak_mem;
    int      inflight;
    uint32_t rps_ring[60];
    uint64_t rps_sec;

    iso_log_entry logs[ISO_LOG_RING];
    int log_head;
    int log_count;

    struct iso_isolate *next;
} iso_isolate;

typedef struct iso_fiber {
    iso_isolate *iso;
    iso_script  *script;
    struct iso_sched *sched;
    iso_ctx  ctx;
    void    *stack;
    size_t   stack_size;
    iso_arena arena;
    iso_vm   vm;
    iso_request  req;
    iso_response res;
    enum { FIBER_READY, FIBER_RUNNING, FIBER_DONE } state;
    uint64_t budget;
    uint64_t executed;
    int      error_code;
    char     error[256];
    uint64_t start_ns;
    uint64_t end_ns;
    uint64_t cpu_ns;
    uint32_t switches;
    void (*on_done)(struct iso_fiber *, void *);
    void *user;
    struct iso_fiber *next;
} iso_fiber;

typedef struct iso_sched {
    iso_ctx ctx;
    iso_fiber *head;
    iso_fiber *tail;
    int nrunnable;
    uint64_t switches;
    uint64_t fibers_total;
    uint64_t fibers_done;
} iso_sched;

typedef struct iso_platform {
    iso_isolate *isolates;
    int nisolates;
    iso_sched sched;
    uint64_t started_ms;
    uint64_t requests;
    uint64_t errors;
    char *data_dir;
} iso_platform;

uint64_t iso_now_ns(void);
uint64_t iso_now_ms(void);

void iso_platform_init(iso_platform *p);
void iso_platform_free(iso_platform *p);
iso_isolate *iso_platform_find(iso_platform *p, const char *name);
iso_isolate *iso_platform_deploy(iso_platform *p, const char *name, iso_script *script,
                                 char *err, size_t errlen);
bool iso_platform_remove(iso_platform *p, const char *name);
bool iso_name_valid(const char *name);
void iso_isolate_set_limits(iso_isolate *iso, uint64_t cpu, size_t mem);
void iso_isolate_set_env(iso_isolate *iso, const char *name, const char *value);
void iso_isolate_log(iso_isolate *iso, const char *fmt, ...);
int  iso_platform_save(iso_platform *p, iso_isolate *iso);
int  iso_platform_unlink(iso_platform *p, const char *name);
int  iso_platform_load_dir(iso_platform *p, const char *dir);

/* Fibers: one per invocation. The request is moved into the fiber. */
iso_fiber *iso_fiber_create(iso_platform *p, iso_isolate *iso, iso_request *req,
                            void (*on_done)(iso_fiber *, void *), void *user);
void iso_fiber_free(iso_fiber *f);
int  iso_vm_run(iso_fiber *f, uint64_t max_insns);

/* Run every runnable fiber for one slice; done fibers get on_done(). */
int  iso_sched_tick(iso_platform *p);
/* Run the fiber to completion on the calling thread (tests, CLI). */
void iso_invoke_sync(iso_platform *p, iso_fiber *f);

/* ------------------------------------------------------------------ */
/* Small utilities                                                     */
/* ------------------------------------------------------------------ */
typedef struct iso_buf {
    char *p;
    size_t n;
    size_t cap;
} iso_buf;

void iso_buf_free(iso_buf *b);
int  iso_buf_append(iso_buf *b, const char *p, size_t n);
int  iso_buf_puts(iso_buf *b, const char *s);
int  iso_buf_printf(iso_buf *b, const char *fmt, ...);
int  iso_buf_json_str(iso_buf *b, const char *s, size_t n);

/* Minimal JSON DOM */
typedef struct json_val {
    enum { J_NULL, J_BOOL, J_NUM, J_STR, J_ARR, J_OBJ } t;
    bool b;
    double num;
    char *str;
    struct json_val *items;
    char **keys;
    int n;
} json_val;

json_val *json_parse(const char *s, size_t n, char *err, size_t errlen);
void      json_free(json_val *v);
json_val *json_get(json_val *obj, const char *key);
const char *json_str(json_val *obj, const char *key, const char *dflt);
double    json_num(json_val *obj, const char *key, double dflt);

/* HTTP server (runtime/src/http.c) */
typedef struct iso_server_opts {
    const char *bind;
    int port;
    const char *dashboard_dir;
    bool verbose;
} iso_server_opts;

int iso_server_run(iso_platform *p, const iso_server_opts *opts);

#endif /* ISOLATES_H */
