/* vm.c - assembler and interpreter for worker scripts ("isoasm"). */
#include "isolates.h"

#include <ctype.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ------------------------------------------------------------------ */
/* Mnemonic table                                                      */
/* ------------------------------------------------------------------ */
enum arg_kind { A_NONE, A_INT, A_INT_OR_STR, A_LABEL, A_SLOT, A_STR };

typedef struct mnemonic {
    const char *name;
    uint8_t op;
    int64_t imm;      /* sys id for OP_SYS */
    enum arg_kind arg;
    const char *desc;
} mnemonic;

static const mnemonic MNEMONICS[] = {
    { "nop",     OP_NOP,      0, A_NONE, "do nothing" },
    { "push",    OP_PUSH_INT, 0, A_INT_OR_STR, "push an integer or \"string\" literal" },
    { "pop",     OP_POP,      0, A_NONE, "discard the top of the stack" },
    { "dup",     OP_DUP,      0, A_NONE, "duplicate the top of the stack" },
    { "swap",    OP_SWAP,     0, A_NONE, "swap the top two values" },
    { "over",    OP_OVER,     0, A_NONE, "copy the second value to the top" },
    { "add",     OP_ADD,      0, A_NONE, "a b -> a+b" },
    { "sub",     OP_SUB,      0, A_NONE, "a b -> a-b" },
    { "mul",     OP_MUL,      0, A_NONE, "a b -> a*b" },
    { "div",     OP_DIV,      0, A_NONE, "a b -> a/b (traps on zero)" },
    { "mod",     OP_MOD,      0, A_NONE, "a b -> a%b" },
    { "neg",     OP_NEG,      0, A_NONE, "a -> -a" },
    { "eq",      OP_EQ,       0, A_NONE, "a b -> a==b (ints or strings)" },
    { "ne",      OP_NE,       0, A_NONE, "a b -> a!=b" },
    { "lt",      OP_LT,       0, A_NONE, "a b -> a<b" },
    { "le",      OP_LE,       0, A_NONE, "a b -> a<=b" },
    { "gt",      OP_GT,       0, A_NONE, "a b -> a>b" },
    { "ge",      OP_GE,       0, A_NONE, "a b -> a>=b" },
    { "not",     OP_NOT,      0, A_NONE, "a -> !a" },
    { "and",     OP_AND,      0, A_NONE, "a b -> a&&b" },
    { "or",      OP_OR,       0, A_NONE, "a b -> a||b" },
    { "jmp",     OP_JMP,      0, A_LABEL, "jump to label" },
    { "jz",      OP_JZ,       0, A_LABEL, "pop; jump if zero/empty" },
    { "jnz",     OP_JNZ,      0, A_LABEL, "pop; jump if non-zero/non-empty" },
    { "call",    OP_CALL,     0, A_LABEL, "call a label (returns with ret)" },
    { "ret",     OP_RET,      0, A_NONE, "return from call" },
    { "load",    OP_LOAD,     0, A_SLOT, "push local slot n (0-63)" },
    { "store",   OP_STORE,    0, A_SLOT, "pop into local slot n" },
    { "concat",  OP_CONCAT,   0, A_NONE, "a b -> a+b as strings (ints are formatted)" },
    { "len",     OP_LEN,      0, A_NONE, "s -> byte length" },
    { "substr",  OP_SUBSTR,   0, A_NONE, "s start len -> substring" },
    { "itoa",    OP_ITOA,     0, A_NONE, "int -> string" },
    { "atoi",    OP_ATOI,     0, A_NONE, "string -> int (0 if invalid)" },
    { "upper",   OP_UPPER,    0, A_NONE, "s -> UPPERCASE" },
    { "lower",   OP_LOWER,    0, A_NONE, "s -> lowercase" },
    { "find",    OP_FIND,     0, A_NONE, "hay needle -> index or -1" },
    { "starts",  OP_STARTS,   0, A_NONE, "s prefix -> 1 if s starts with prefix" },
    { "halt",    OP_HALT,     0, A_NONE, "finish the request and send the response" },
    /* host calls */
    { "req.method", OP_SYS, SYS_REQ_METHOD, A_NONE, "-> request method" },
    { "req.path",   OP_SYS, SYS_REQ_PATH,   A_NONE, "-> request path (after /w/<name>)" },
    { "req.query",  OP_SYS, SYS_REQ_QUERY,  A_NONE, "-> raw query string" },
    { "req.body",   OP_SYS, SYS_REQ_BODY,   A_NONE, "-> request body" },
    { "req.header", OP_SYS, SYS_REQ_HEADER, A_NONE, "name -> header value or \"\"" },
    { "res.status", OP_SYS, SYS_RES_STATUS, A_NONE, "code -> set response status" },
    { "res.header", OP_SYS, SYS_RES_HEADER, A_NONE, "name value -> set response header" },
    { "res.body",   OP_SYS, SYS_RES_BODY,   A_NONE, "value -> append to response body" },
    { "kv.get",     OP_SYS, SYS_KV_GET,     A_NONE, "key -> value or \"\"" },
    { "kv.put",     OP_SYS, SYS_KV_PUT,     A_NONE, "key value -> store" },
    { "kv.del",     OP_SYS, SYS_KV_DEL,     A_NONE, "key -> delete" },
    { "kv.has",     OP_SYS, SYS_KV_HAS,     A_NONE, "key -> 1 if present" },
    { "log",        OP_SYS, SYS_LOG,        A_NONE, "value -> append to worker log" },
    { "time",       OP_SYS, SYS_TIME,       A_NONE, "-> unix time in ms" },
    { "yield",      OP_SYS, SYS_YIELD,      A_NONE, "give up the CPU until the next scheduler round" },
    { "env",        OP_SYS, SYS_ENV,        A_NONE, "name -> binding value or \"\"" },
    { "rand",       OP_SYS, SYS_RAND,       A_NONE, "n -> random int in [0,n)" },
    { "worker",     OP_SYS, SYS_WORKER,     A_NONE, "-> this worker's name" },
    { "spin",       OP_SYS, SYS_SPIN,       A_NONE, "n -> burn n instructions of CPU budget" },
};
#define NMNEMONICS (sizeof MNEMONICS / sizeof MNEMONICS[0])

static const char *OP_NAMES[OP__COUNT] = {
    "nop", "push", "push", "pop", "dup", "swap", "over",
    "add", "sub", "mul", "div", "mod", "neg",
    "eq", "ne", "lt", "le", "gt", "ge",
    "not", "and", "or",
    "jmp", "jz", "jnz", "call", "ret",
    "load", "store",
    "concat", "len", "substr", "itoa", "atoi", "upper", "lower",
    "find", "starts",
    "halt", "sys",
};

size_t iso_mnemonic_count(void)
{
    return NMNEMONICS;
}

void iso_mnemonic_at(size_t i, const char **name, const char **operand, const char **desc)
{
    static const char *ARGS[] = { "", "int", "int|string", "label", "slot", "string" };
    *name = MNEMONICS[i].name;
    *operand = ARGS[MNEMONICS[i].arg];
    *desc = MNEMONICS[i].desc;
}

const char *iso_op_name(int op)
{
    return (op >= 0 && op < OP__COUNT) ? OP_NAMES[op] : "?";
}

const char *iso_sys_name(int sys)
{
    for (size_t i = 0; i < NMNEMONICS; i++)
        if (MNEMONICS[i].op == OP_SYS && MNEMONICS[i].imm == sys)
            return MNEMONICS[i].name;
    return "?";
}

/* ------------------------------------------------------------------ */
/* Assembler                                                           */
/* ------------------------------------------------------------------ */
typedef struct label {
    char name[64];
    int64_t target;   /* -1 while unresolved */
    int line;
} label;

typedef struct fixup {
    uint32_t insn;
    char name[64];
    int line;
} fixup;

typedef struct asm_state {
    iso_script *s;
    uint32_t code_cap;
    uint32_t const_cap;
    label *labels;
    int nlabels, label_cap;
    fixup *fixups;
    int nfixups, fixup_cap;
    char *err;
    size_t errlen;
} asm_state;

static int asm_fail(asm_state *st, int line, const char *fmt, ...)
{
    char msg[200];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(msg, sizeof msg, fmt, ap);
    va_end(ap);
    snprintf(st->err, st->errlen, "line %d: %s", line, msg);
    return -1;
}

static int emit(asm_state *st, uint8_t op, int64_t imm)
{
    iso_script *s = st->s;
    if (s->ncode == st->code_cap) {
        uint32_t ncap = st->code_cap ? st->code_cap * 2 : 64;
        iso_insn *n = realloc(s->code, ncap * sizeof *n);
        if (!n)
            return -1;
        s->code = n;
        st->code_cap = ncap;
    }
    s->code[s->ncode].op = op;
    s->code[s->ncode].imm = imm;
    s->ncode++;
    return 0;
}

static int add_const(asm_state *st, const char *p, size_t n)
{
    iso_script *s = st->s;
    for (uint32_t i = 0; i < s->nconsts; i++)
        if (s->consts[i].n == n && memcmp(s->consts[i].p, p, n) == 0)
            return (int)i;
    if (s->nconsts == st->const_cap) {
        uint32_t ncap = st->const_cap ? st->const_cap * 2 : 16;
        iso_str *c = realloc(s->consts, ncap * sizeof *c);
        if (!c)
            return -1;
        s->consts = c;
        st->const_cap = ncap;
    }
    char *copy = malloc(n + 1);
    if (!copy)
        return -1;
    memcpy(copy, p, n);
    copy[n] = 0;
    s->consts[s->nconsts].p = copy;
    s->consts[s->nconsts].n = (uint32_t)n;
    return (int)s->nconsts++;
}

static label *find_label(asm_state *st, const char *name)
{
    for (int i = 0; i < st->nlabels; i++)
        if (strcmp(st->labels[i].name, name) == 0)
            return &st->labels[i];
    return NULL;
}

static int add_label(asm_state *st, const char *name, int64_t target, int line)
{
    if (find_label(st, name))
        return asm_fail(st, line, "duplicate label '%s'", name);
    if (st->nlabels == st->label_cap) {
        int ncap = st->label_cap ? st->label_cap * 2 : 16;
        label *l = realloc(st->labels, (size_t)ncap * sizeof *l);
        if (!l)
            return -1;
        st->labels = l;
        st->label_cap = ncap;
    }
    label *l = &st->labels[st->nlabels++];
    snprintf(l->name, sizeof l->name, "%s", name);
    l->target = target;
    l->line = line;
    return 0;
}

static int add_fixup(asm_state *st, uint32_t insn, const char *name, int line)
{
    if (st->nfixups == st->fixup_cap) {
        int ncap = st->fixup_cap ? st->fixup_cap * 2 : 16;
        fixup *f = realloc(st->fixups, (size_t)ncap * sizeof *f);
        if (!f)
            return -1;
        st->fixups = f;
        st->fixup_cap = ncap;
    }
    fixup *f = &st->fixups[st->nfixups++];
    f->insn = insn;
    snprintf(f->name, sizeof f->name, "%s", name);
    f->line = line;
    return 0;
}

static bool ident_char(int c)
{
    return isalnum(c) || c == '_' || c == '.' || c == '-';
}

/* Parse a quoted string starting at *pp (pointing at the opening quote).
 * Writes the unescaped bytes into out (malloc'd). */
static int parse_string(asm_state *st, const char **pp, const char *end,
                        char **out, size_t *outlen, int line)
{
    const char *p = *pp + 1;
    char *buf = malloc((size_t)(end - p) + 1);
    if (!buf)
        return -1;
    size_t n = 0;
    while (p < end && *p != '"') {
        if (*p == '\\') {
            p++;
            if (p >= end) {
                free(buf);
                return asm_fail(st, line, "unterminated escape");
            }
            switch (*p) {
            case 'n': buf[n++] = '\n'; break;
            case 't': buf[n++] = '\t'; break;
            case 'r': buf[n++] = '\r'; break;
            case '"': buf[n++] = '"'; break;
            case '\\': buf[n++] = '\\'; break;
            case '0': buf[n++] = '\0'; break;
            default:
                free(buf);
                return asm_fail(st, line, "unknown escape '\\%c'", *p);
            }
            p++;
        } else {
            buf[n++] = *p++;
        }
    }
    if (p >= end) {
        free(buf);
        return asm_fail(st, line, "unterminated string");
    }
    *pp = p + 1;
    *out = buf;
    *outlen = n;
    return 0;
}

static const mnemonic *find_mnemonic(const char *name, size_t n)
{
    for (size_t i = 0; i < NMNEMONICS; i++)
        if (strlen(MNEMONICS[i].name) == n && strncmp(MNEMONICS[i].name, name, n) == 0)
            return &MNEMONICS[i];
    return NULL;
}

static int assemble_line(asm_state *st, const char *p, const char *end, int line)
{
    while (p < end && isspace((unsigned char)*p))
        p++;
    if (p == end || *p == ';' || *p == '#')
        return 0;

    const char *tok = p;
    while (p < end && ident_char((unsigned char)*p))
        p++;
    size_t toklen = (size_t)(p - tok);
    if (toklen == 0)
        return asm_fail(st, line, "unexpected character '%c'", *p);

    /* label definition */
    if (p < end && *p == ':') {
        char name[64];
        if (toklen >= sizeof name)
            return asm_fail(st, line, "label too long");
        memcpy(name, tok, toklen);
        name[toklen] = 0;
        if (add_label(st, name, st->s->ncode, line) < 0)
            return -1;
        p++;
        return assemble_line(st, p, end, line);
    }

    const mnemonic *m = find_mnemonic(tok, toklen);
    if (!m)
        return asm_fail(st, line, "unknown instruction '%.*s'", (int)toklen, tok);

    while (p < end && isspace((unsigned char)*p))
        p++;
    bool have_arg = p < end && *p != ';' && *p != '#';

    int64_t imm = m->imm;
    uint8_t op = m->op;

    switch (m->arg) {
    case A_NONE:
        if (have_arg)
            return asm_fail(st, line, "'%s' takes no operand", m->name);
        break;
    case A_INT_OR_STR:
    case A_STR:
    case A_INT:
    case A_SLOT:
        if (!have_arg)
            return asm_fail(st, line, "'%s' needs an operand", m->name);
        if (*p == '"') {
            if (m->arg == A_INT || m->arg == A_SLOT)
                return asm_fail(st, line, "'%s' needs a number", m->name);
            char *str = NULL;
            size_t slen = 0;
            if (parse_string(st, &p, end, &str, &slen, line) < 0)
                return -1;
            int idx = add_const(st, str, slen);
            free(str);
            if (idx < 0)
                return -1;
            op = OP_PUSH_STR;
            imm = idx;
        } else {
            if (m->arg == A_STR)
                return asm_fail(st, line, "'%s' needs a string", m->name);
            char *stop;
            long long v = strtoll(p, &stop, 0);
            if (stop == p)
                return asm_fail(st, line, "bad number for '%s'", m->name);
            if (m->arg == A_SLOT && (v < 0 || v >= ISO_VM_LOCALS))
                return asm_fail(st, line, "slot must be 0..%d", ISO_VM_LOCALS - 1);
            p = stop;
            imm = v;
        }
        break;
    case A_LABEL: {
        if (!have_arg)
            return asm_fail(st, line, "'%s' needs a label", m->name);
        const char *lt = p;
        while (p < end && ident_char((unsigned char)*p))
            p++;
        size_t ll = (size_t)(p - lt);
        if (ll == 0 || ll >= 64)
            return asm_fail(st, line, "bad label for '%s'", m->name);
        char name[64];
        memcpy(name, lt, ll);
        name[ll] = 0;
        if (add_fixup(st, st->s->ncode, name, line) < 0)
            return -1;
        imm = -1;
        break;
    }
    }

    while (p < end && isspace((unsigned char)*p))
        p++;
    if (p < end && *p != ';' && *p != '#')
        return asm_fail(st, line, "trailing characters after '%s'", m->name);

    return emit(st, op, imm);
}

int iso_assemble(const char *src, size_t len, iso_script **out,
                 char *err, size_t errlen)
{
    asm_state st = {0};
    st.err = err;
    st.errlen = errlen;
    if (errlen)
        err[0] = 0;

    iso_script *s = calloc(1, sizeof *s);
    if (!s)
        return -1;
    s->refs = 1;
    s->source = malloc(len + 1);
    if (!s->source) {
        free(s);
        return -1;
    }
    memcpy(s->source, src, len);
    s->source[len] = 0;
    s->source_len = len;
    st.s = s;

    int rc = 0;
    int line = 1;
    const char *p = src, *end = src + len;
    while (p < end && rc == 0) {
        const char *nl = memchr(p, '\n', (size_t)(end - p));
        const char *le = nl ? nl : end;
        rc = assemble_line(&st, p, le, line);
        p = nl ? nl + 1 : end;
        line++;
    }
    if (rc == 0) {
        for (int i = 0; i < st.nfixups; i++) {
            label *l = find_label(&st, st.fixups[i].name);
            if (!l) {
                rc = asm_fail(&st, st.fixups[i].line, "undefined label '%s'",
                              st.fixups[i].name);
                break;
            }
            s->code[st.fixups[i].insn].imm = l->target;
        }
    }
    if (rc == 0 && s->ncode == 0)
        rc = asm_fail(&st, 1, "script has no instructions");
    if (rc == 0 && s->code[s->ncode - 1].op != OP_HALT &&
        s->code[s->ncode - 1].op != OP_JMP && s->code[s->ncode - 1].op != OP_RET)
        emit(&st, OP_HALT, 0); /* implicit halt at the end */

    free(st.labels);
    free(st.fixups);
    if (rc != 0) {
        iso_script_unref(s);
        *out = NULL;
        return -1;
    }
    *out = s;
    return 0;
}

void iso_script_ref(iso_script *s)
{
    if (s)
        s->refs++;
}

void iso_script_unref(iso_script *s)
{
    if (!s || --s->refs > 0)
        return;
    for (uint32_t i = 0; i < s->nconsts; i++)
        free((char *)s->consts[i].p);
    free(s->consts);
    free(s->code);
    free(s->source);
    free(s);
}

/* ------------------------------------------------------------------ */
/* Interpreter                                                         */
/* ------------------------------------------------------------------ */
static void vm_fail(iso_fiber *f, int code, const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(f->error, sizeof f->error, fmt, ap);
    va_end(ap);
    f->error_code = code;
}

#define TRAP(...)                                       \
    do {                                                \
        vm_fail(f, ISO_ERR_TRAP, __VA_ARGS__);          \
        return -1;                                      \
    } while (0)
#define LIMIT(...)                                      \
    do {                                                \
        vm_fail(f, ISO_ERR_LIMITS, __VA_ARGS__);        \
        return -1;                                      \
    } while (0)
#define NEED(k)                                                          \
    do {                                                                 \
        if (vm->sp < (k))                                                \
            TRAP("stack underflow at pc %u (%s)", pc, iso_op_name(in.op)); \
    } while (0)
#define ROOM(k)                                                          \
    do {                                                                 \
        if (vm->sp + (k) > ISO_VM_STACK)                                 \
            TRAP("stack overflow at pc %u", pc);                         \
    } while (0)
#define POP()   (vm->stack[--vm->sp])
#define TOP()   (vm->stack[vm->sp - 1])
#define PUSHI(v)                                        \
    do {                                                \
        ROOM(1);                                        \
        vm->stack[vm->sp].t = V_INT;                    \
        vm->stack[vm->sp].i = (v);                      \
        vm->sp++;                                       \
    } while (0)
#define PUSHS(ptr, len)                                 \
    do {                                                \
        ROOM(1);                                        \
        vm->stack[vm->sp].t = V_STR;                    \
        vm->stack[vm->sp].s.p = (ptr);                  \
        vm->stack[vm->sp].s.n = (uint32_t)(len);        \
        vm->sp++;                                       \
    } while (0)
#define POPI(var)                                                         \
    int64_t var;                                                          \
    do {                                                                  \
        NEED(1);                                                          \
        iso_val v_ = POP();                                               \
        if (v_.t != V_INT)                                                \
            TRAP("type error at pc %u: %s expects an int", pc, iso_op_name(in.op)); \
        var = v_.i;                                                       \
    } while (0)
#define POPS(var)                                                         \
    iso_str var;                                                          \
    do {                                                                  \
        NEED(1);                                                          \
        iso_val v_ = POP();                                               \
        if (v_.t != V_STR)                                                \
            TRAP("type error at pc %u: %s expects a string", pc, iso_op_name(in.op)); \
        var = v_.s;                                                       \
    } while (0)

/* Allocate n+1 bytes in the fiber's arena (NUL terminated for convenience). */
static char *vm_alloc(iso_fiber *f, size_t n)
{
    char *p = iso_arena_alloc(&f->arena, n + 1);
    if (p)
        p[n] = 0;
    return p;
}

static const char *cstr(iso_fiber *f, iso_str s)
{
    /* Strings from constants and req.* are NUL terminated already; copy
     * substrings so that C callers get a terminated buffer. */
    if (s.p[s.n] == 0)
        return s.p;
    char *c = vm_alloc(f, s.n);
    if (!c)
        return NULL;
    memcpy(c, s.p, s.n);
    return c;
}

static int str_to_int(iso_str s, int64_t *out)
{
    char buf[32];
    if (s.n >= sizeof buf)
        return -1;
    memcpy(buf, s.p, s.n);
    buf[s.n] = 0;
    char *stop;
    long long v = strtoll(buf, &stop, 10);
    if (stop == buf)
        return -1;
    *out = v;
    return 0;
}

static bool val_truthy(const iso_val *v)
{
    return v->t == V_INT ? v->i != 0 : v->s.n != 0;
}

static int val_compare(const iso_val *a, const iso_val *b, int *out)
{
    if (a->t != b->t)
        return -1;
    if (a->t == V_INT) {
        *out = a->i < b->i ? -1 : a->i > b->i ? 1 : 0;
        return 0;
    }
    size_t n = a->s.n < b->s.n ? a->s.n : b->s.n;
    int c = memcmp(a->s.p, b->s.p, n);
    if (c == 0)
        c = a->s.n < b->s.n ? -1 : a->s.n > b->s.n ? 1 : 0;
    *out = c < 0 ? -1 : c > 0 ? 1 : 0;
    return 0;
}

int iso_vm_run(iso_fiber *f, uint64_t max_insns)
{
    iso_vm *vm = &f->vm;
    iso_script *s = f->script;
    iso_isolate *iso = f->iso;
    uint64_t n = 0;

    while (n < max_insns) {
        if (f->budget == 0)
            LIMIT("exceeded CPU limit of %llu instructions",
                  (unsigned long long)iso->cpu_limit);
        if (vm->pc >= s->ncode)
            TRAP("execution ran off the end of the script");
        uint32_t pc = vm->pc++;
        iso_insn in = s->code[pc];
        f->budget--;
        f->executed++;
        n++;

        switch ((enum iso_op)in.op) {
        case OP_NOP:
            break;
        case OP_PUSH_INT:
            PUSHI(in.imm);
            break;
        case OP_PUSH_STR:
            PUSHS(s->consts[in.imm].p, s->consts[in.imm].n);
            break;
        case OP_POP:
            NEED(1);
            vm->sp--;
            break;
        case OP_DUP:
            NEED(1);
            ROOM(1);
            vm->stack[vm->sp] = TOP();
            vm->sp++;
            break;
        case OP_SWAP: {
            NEED(2);
            iso_val t = vm->stack[vm->sp - 1];
            vm->stack[vm->sp - 1] = vm->stack[vm->sp - 2];
            vm->stack[vm->sp - 2] = t;
            break;
        }
        case OP_OVER:
            NEED(2);
            ROOM(1);
            vm->stack[vm->sp] = vm->stack[vm->sp - 2];
            vm->sp++;
            break;
        case OP_ADD: case OP_SUB: case OP_MUL: case OP_DIV: case OP_MOD: {
            POPI(b);
            POPI(a);
            int64_t r = 0;
            switch (in.op) {
            case OP_ADD: r = (int64_t)((uint64_t)a + (uint64_t)b); break;
            case OP_SUB: r = (int64_t)((uint64_t)a - (uint64_t)b); break;
            case OP_MUL: r = (int64_t)((uint64_t)a * (uint64_t)b); break;
            case OP_DIV:
                if (b == 0)
                    TRAP("division by zero at pc %u", pc);
                r = (b == -1) ? (int64_t)(0 - (uint64_t)a) : a / b;
                break;
            case OP_MOD:
                if (b == 0)
                    TRAP("modulo by zero at pc %u", pc);
                r = (b == -1) ? 0 : a % b;
                break;
            }
            PUSHI(r);
            break;
        }
        case OP_NEG: {
            POPI(a);
            PUSHI((int64_t)(0 - (uint64_t)a));
            break;
        }
        case OP_EQ: case OP_NE: case OP_LT: case OP_LE: case OP_GT: case OP_GE: {
            NEED(2);
            iso_val b = POP();
            iso_val a = POP();
            int c;
            if (val_compare(&a, &b, &c) < 0) {
                if (in.op == OP_EQ) { PUSHI(0); break; }
                if (in.op == OP_NE) { PUSHI(1); break; }
                TRAP("type error at pc %u: cannot compare int with string", pc);
            }
            int r = 0;
            switch (in.op) {
            case OP_EQ: r = c == 0; break;
            case OP_NE: r = c != 0; break;
            case OP_LT: r = c < 0; break;
            case OP_LE: r = c <= 0; break;
            case OP_GT: r = c > 0; break;
            case OP_GE: r = c >= 0; break;
            }
            PUSHI(r);
            break;
        }
        case OP_NOT: {
            NEED(1);
            iso_val a = POP();
            PUSHI(!val_truthy(&a));
            break;
        }
        case OP_AND: case OP_OR: {
            NEED(2);
            iso_val b = POP();
            iso_val a = POP();
            bool ta = val_truthy(&a), tb = val_truthy(&b);
            PUSHI(in.op == OP_AND ? (ta && tb) : (ta || tb));
            break;
        }
        case OP_JMP:
            vm->pc = (uint32_t)in.imm;
            break;
        case OP_JZ: case OP_JNZ: {
            NEED(1);
            iso_val a = POP();
            bool t = val_truthy(&a);
            if ((in.op == OP_JZ && !t) || (in.op == OP_JNZ && t))
                vm->pc = (uint32_t)in.imm;
            break;
        }
        case OP_CALL:
            if (vm->csp >= ISO_VM_CALLS)
                TRAP("call stack overflow at pc %u", pc);
            vm->calls[vm->csp++] = vm->pc;
            vm->pc = (uint32_t)in.imm;
            break;
        case OP_RET:
            if (vm->csp == 0)
                TRAP("ret with empty call stack at pc %u", pc);
            vm->pc = vm->calls[--vm->csp];
            break;
        case OP_LOAD:
            ROOM(1);
            vm->stack[vm->sp++] = vm->locals[in.imm];
            break;
        case OP_STORE:
            NEED(1);
            vm->locals[in.imm] = POP();
            break;
        case OP_CONCAT: {
            NEED(2);
            iso_val b = POP();
            iso_val a = POP();
            char ta[24], tb[24];
            iso_str sa, sb;
            if (a.t == V_INT) {
                sa.n = (uint32_t)snprintf(ta, sizeof ta, "%lld", (long long)a.i);
                sa.p = ta;
            } else
                sa = a.s;
            if (b.t == V_INT) {
                sb.n = (uint32_t)snprintf(tb, sizeof tb, "%lld", (long long)b.i);
                sb.p = tb;
            } else
                sb = b.s;
            char *r = vm_alloc(f, (size_t)sa.n + sb.n);
            if (!r)
                LIMIT("exceeded memory limit of %zu bytes", iso->mem_limit);
            memcpy(r, sa.p, sa.n);
            memcpy(r + sa.n, sb.p, sb.n);
            PUSHS(r, sa.n + sb.n);
            break;
        }
        case OP_LEN: {
            POPS(a);
            PUSHI(a.n);
            break;
        }
        case OP_SUBSTR: {
            POPI(len);
            POPI(start);
            POPS(a);
            if (start < 0)
                start = 0;
            if (start > a.n)
                start = a.n;
            if (len < 0 || start + len > a.n)
                len = a.n - start;
            PUSHS(a.p + start, len);
            break;
        }
        case OP_ITOA: {
            POPI(a);
            char *r = vm_alloc(f, 24);
            if (!r)
                LIMIT("exceeded memory limit of %zu bytes", iso->mem_limit);
            int l = snprintf(r, 24, "%lld", (long long)a);
            PUSHS(r, l);
            break;
        }
        case OP_ATOI: {
            POPS(a);
            int64_t v;
            if (str_to_int(a, &v) < 0)
                v = 0;
            PUSHI(v);
            break;
        }
        case OP_UPPER: case OP_LOWER: {
            POPS(a);
            char *r = vm_alloc(f, a.n);
            if (!r)
                LIMIT("exceeded memory limit of %zu bytes", iso->mem_limit);
            for (uint32_t i = 0; i < a.n; i++)
                r[i] = (char)(in.op == OP_UPPER ? toupper((unsigned char)a.p[i])
                                                 : tolower((unsigned char)a.p[i]));
            PUSHS(r, a.n);
            break;
        }
        case OP_FIND: {
            POPS(needle);
            POPS(hay);
            int64_t idx = -1;
            if (needle.n == 0)
                idx = 0;
            else if (needle.n <= hay.n) {
                for (uint32_t i = 0; i + needle.n <= hay.n; i++)
                    if (memcmp(hay.p + i, needle.p, needle.n) == 0) {
                        idx = i;
                        break;
                    }
            }
            PUSHI(idx);
            break;
        }
        case OP_STARTS: {
            POPS(prefix);
            POPS(str);
            PUSHI(prefix.n <= str.n && memcmp(str.p, prefix.p, prefix.n) == 0);
            break;
        }
        case OP_HALT:
            return 1;
        case OP_SYS:
            switch ((enum iso_sys)in.imm) {
            case SYS_REQ_METHOD:
                PUSHS(f->req.method, strlen(f->req.method));
                break;
            case SYS_REQ_PATH:
                PUSHS(f->req.path, strlen(f->req.path));
                break;
            case SYS_REQ_QUERY:
                PUSHS(f->req.query, strlen(f->req.query));
                break;
            case SYS_REQ_BODY:
                PUSHS(f->req.body ? f->req.body : "", f->req.body_len);
                break;
            case SYS_REQ_HEADER: {
                POPS(name);
                const char *cn = cstr(f, name);
                if (!cn)
                    LIMIT("exceeded memory limit of %zu bytes", iso->mem_limit);
                const char *v = iso_request_header(&f->req, cn);
                PUSHS(v ? v : "", v ? strlen(v) : 0);
                break;
            }
            case SYS_RES_STATUS: {
                POPI(code);
                if (code < 100 || code > 599)
                    TRAP("res.status: invalid status %lld", (long long)code);
                f->res.status = (int)code;
                break;
            }
            case SYS_RES_HEADER: {
                POPS(value);
                POPS(name);
                if (name.n == 0)
                    TRAP("res.header: empty header name");
                if (iso_response_set_header(&f->res, name.p, name.n, value.p, value.n) < 0)
                    TRAP("res.header: too many headers (max %d)", ISO_MAX_HEADERS);
                break;
            }
            case SYS_RES_BODY: {
                NEED(1);
                iso_val v = POP();
                char tmp[24];
                if (v.t == V_INT) {
                    int l = snprintf(tmp, sizeof tmp, "%lld", (long long)v.i);
                    if (iso_response_append(&f->res, tmp, (size_t)l) < 0)
                        LIMIT("response body exceeds %d bytes", ISO_MAX_BODY);
                } else if (iso_response_append(&f->res, v.s.p, v.s.n) < 0)
                    LIMIT("response body exceeds %d bytes", ISO_MAX_BODY);
                break;
            }
            case SYS_KV_GET: {
                POPS(key);
                const iso_kv_entry *e = iso_kv_get(&iso->kv, key.p, key.n);
                if (!e) {
                    PUSHS("", 0);
                } else {
                    char *r = vm_alloc(f, e->vlen);
                    if (!r)
                        LIMIT("exceeded memory limit of %zu bytes", iso->mem_limit);
                    memcpy(r, e->value, e->vlen);
                    PUSHS(r, e->vlen);
                }
                break;
            }
            case SYS_KV_PUT: {
                NEED(2);
                iso_val v = POP();
                POPS(key);
                char tmp[24];
                const char *vp;
                size_t vn;
                if (v.t == V_INT) {
                    vn = (size_t)snprintf(tmp, sizeof tmp, "%lld", (long long)v.i);
                    vp = tmp;
                } else {
                    vp = v.s.p;
                    vn = v.s.n;
                }
                if (key.n == 0)
                    TRAP("kv.put: empty key");
                if (iso_kv_put(&iso->kv, key.p, key.n, vp, vn) < 0)
                    LIMIT("kv.put: namespace full (%d entries, %d bytes/value)",
                          ISO_KV_MAX_ENTRIES, ISO_KV_MAX_VALUE);
                break;
            }
            case SYS_KV_DEL: {
                POPS(key);
                iso_kv_del(&iso->kv, key.p, key.n);
                break;
            }
            case SYS_KV_HAS: {
                POPS(key);
                PUSHI(iso_kv_get(&iso->kv, key.p, key.n) != NULL);
                break;
            }
            case SYS_LOG: {
                NEED(1);
                iso_val v = POP();
                if (v.t == V_INT)
                    iso_isolate_log(iso, "%lld", (long long)v.i);
                else
                    iso_isolate_log(iso, "%.*s", (int)v.s.n, v.s.p);
                break;
            }
            case SYS_TIME:
                PUSHI((int64_t)iso_now_ms());
                break;
            case SYS_YIELD:
                return 0;
            case SYS_ENV: {
                POPS(name);
                const char *v = NULL;
                for (int i = 0; i < iso->nenv; i++)
                    if (strlen(iso->env[i].name) == name.n &&
                        memcmp(iso->env[i].name, name.p, name.n) == 0) {
                        v = iso->env[i].value;
                        break;
                    }
                PUSHS(v ? v : "", v ? strlen(v) : 0);
                break;
            }
            case SYS_RAND: {
                POPI(bound);
                if (bound <= 0)
                    TRAP("rand: bound must be positive");
                PUSHI((int64_t)(random() % bound));
                break;
            }
            case SYS_WORKER:
                PUSHS(iso->name, strlen(iso->name));
                break;
            case SYS_SPIN: {
                /* Burn `count` instructions of budget without doing work;
                 * handy for demonstrating CPU limits and fair scheduling. */
                POPI(count);
                if (count < 0)
                    count = 0;
                if ((uint64_t)count > f->budget) {
                    f->executed += f->budget;
                    f->budget = 0;
                    LIMIT("exceeded CPU limit of %llu instructions",
                          (unsigned long long)iso->cpu_limit);
                }
                f->budget -= (uint64_t)count;
                f->executed += (uint64_t)count;
                n += (uint64_t)count;
                break;
            }
            case SYS__COUNT:
                TRAP("bad syscall at pc %u", pc);
            }
            break;
        case OP__COUNT:
            TRAP("bad opcode at pc %u", pc);
        }
    }
    return 0;
}
