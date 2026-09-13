/*-*- mode:c;indent-tabs-mode:nil;c-basic-offset:2;tab-width:8;coding:utf-8 -*-│
│ vi: set et ft=c ts=2 sts=2 sw=2 fenc=utf-8                               :vi │
╞══════════════════════════════════════════════════════════════════════════════╡
│ minibrowser engine                                                           │
│                                                                              │
│ A single-file, dependency-free web page engine written in portable C in      │
│ the spirit of redbean (https://redbean.dev): one translation unit, no        │
│ build system magic, compiles with cc, cosmocc (Actually Portable             │
│ Executable), MinGW and MSVC-compatible clang.                                │
│                                                                              │
│ It does four things:                                                         │
│                                                                              │
│   1. fetch    HTTP/1.1 client (chunked encoding, redirects; HTTPS when       │
│               compiled with -DMB_TLS_OPENSSL).                               │
│   2. parse    forgiving HTML5-ish tokenizer + tree builder with implicit     │
│               end tags, void elements, raw-text elements and entities.       │
│   3. style    a built-in user-agent stylesheet plus inline `style=` bits,    │
│               producing a flat list of block boxes holding inline runs       │
│               (text, links, images, form controls, line breaks).            │
│   4. render   either to JSON (consumed by the Flutter shell over dart:ffi,   │
│               which does real text layout and painting) or to plain text    │
│               for terminals and tests.                                       │
│                                                                              │
│ Permission to use, copy, modify, and/or distribute this software for         │
│ any purpose with or without fee is hereby granted.                           │
╚─────────────────────────────────────────────────────────────────────────────*/
#ifndef _WIN32
#define _POSIX_C_SOURCE 200809L
#define _DEFAULT_SOURCE 1
#define _DARWIN_C_SOURCE 1
#endif
#include <ctype.h>
#include <errno.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MB_VERSION "0.1.0"

#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
typedef SOCKET mb_sock_t;
#define MB_BAD_SOCK INVALID_SOCKET
#define mb_closesock closesocket
#define MB_EXPORT __declspec(dllexport)
#else
#include <netdb.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>
typedef int mb_sock_t;
#define MB_BAD_SOCK (-1)
#define mb_closesock close
#define MB_EXPORT __attribute__((visibility("default")))
#endif

#ifdef MB_TLS_OPENSSL
#include <openssl/err.h>
#include <openssl/ssl.h>
#endif

/*───────────────────────────────────────────────────────────────────────────│─╗
│ arena allocator                                                          ─╬─│
╚────────────────────────────────────────────────────────────────────────────│*/

typedef struct Chunk {
  struct Chunk *next;
  size_t used, cap;
  char data[1];
} Chunk;

typedef struct Arena {
  Chunk *head;
} Arena;

static void *arena_alloc(Arena *a, size_t n) {
  Chunk *c;
  size_t cap;
  n = (n + 15) & ~(size_t)15;
  if (!a->head || a->head->used + n > a->head->cap) {
    cap = n > 65536 ? n : 65536;
    c = (Chunk *)malloc(sizeof(Chunk) + cap);
    if (!c) {
      fprintf(stderr, "minibrowser: out of memory\n");
      abort();
    }
    c->next = a->head;
    c->used = 0;
    c->cap = cap;
    a->head = c;
  }
  c = a->head;
  {
    void *p = c->data + c->used;
    c->used += n;
    memset(p, 0, n);
    return p;
  }
}

static void arena_free(Arena *a) {
  Chunk *c, *n;
  for (c = a->head; c; c = n) {
    n = c->next;
    free(c);
  }
  a->head = 0;
}

static char *arena_strndup(Arena *a, const char *s, size_t n) {
  char *p = (char *)arena_alloc(a, n + 1);
  memcpy(p, s, n);
  p[n] = 0;
  return p;
}

static char *arena_strdup(Arena *a, const char *s) {
  return arena_strndup(a, s, strlen(s));
}

/*───────────────────────────────────────────────────────────────────────────│─╗
│ growable byte buffer                                                     ─╬─│
╚────────────────────────────────────────────────────────────────────────────│*/

typedef struct Buf {
  char *p;
  size_t n, cap;
} Buf;

static void buf_reserve(Buf *b, size_t extra) {
  if (b->n + extra + 1 > b->cap) {
    size_t cap = b->cap ? b->cap * 2 : 256;
    while (cap < b->n + extra + 1) cap *= 2;
    b->p = (char *)realloc(b->p, cap);
    if (!b->p) {
      fprintf(stderr, "minibrowser: out of memory\n");
      abort();
    }
    b->cap = cap;
  }
}

static void buf_append(Buf *b, const char *s, size_t n) {
  buf_reserve(b, n);
  memcpy(b->p + b->n, s, n);
  b->n += n;
  b->p[b->n] = 0;
}

static void buf_puts(Buf *b, const char *s) {
  buf_append(b, s, strlen(s));
}

static void buf_putc(Buf *b, char c) {
  buf_append(b, &c, 1);
}

static void buf_printf(Buf *b, const char *fmt, ...) {
  va_list ap;
  char tmp[512];
  int n;
  va_start(ap, fmt);
  n = vsnprintf(tmp, sizeof(tmp), fmt, ap);
  va_end(ap);
  if (n < 0) return;
  if ((size_t)n < sizeof(tmp)) {
    buf_append(b, tmp, (size_t)n);
  } else {
    buf_reserve(b, (size_t)n);
    va_start(ap, fmt);
    vsnprintf(b->p + b->n, (size_t)n + 1, fmt, ap);
    va_end(ap);
    b->n += (size_t)n;
  }
}

static void buf_free(Buf *b) {
  free(b->p);
  b->p = 0;
  b->n = b->cap = 0;
}

/*───────────────────────────────────────────────────────────────────────────│─╗
│ small string helpers                                                     ─╬─│
╚────────────────────────────────────────────────────────────────────────────│*/

static int mb_isspace(int c) {
  return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f';
}

static int mb_strcasecmp(const char *a, const char *b) {
  while (*a && *b) {
    int ca = tolower((unsigned char)*a), cb = tolower((unsigned char)*b);
    if (ca != cb) return ca - cb;
    a++, b++;
  }
  return tolower((unsigned char)*a) - tolower((unsigned char)*b);
}

static int mb_strncasecmp(const char *a, const char *b, size_t n) {
  size_t i;
  for (i = 0; i < n; i++) {
    int ca = tolower((unsigned char)a[i]), cb = tolower((unsigned char)b[i]);
    if (ca != cb) return ca - cb;
    if (!ca) return 0;
  }
  return 0;
}

static char *mb_strndup(const char *s, size_t n) {
  char *p = (char *)malloc(n + 1);
  if (!p) abort();
  memcpy(p, s, n);
  p[n] = 0;
  return p;
}

static char *mb_strdup(const char *s) {
  return mb_strndup(s, strlen(s));
}

static int str_in(const char *s, const char *const *list) {
  for (; *list; list++) {
    if (!strcmp(s, *list)) return 1;
  }
  return 0;
}

static void utf8_encode(Buf *b, unsigned cp) {
  char t[4];
  if (cp >= 0xD800 && cp <= 0xDFFF) cp = 0xFFFD;
  if (cp > 0x10FFFF) cp = 0xFFFD;
  if (cp < 0x80) {
    t[0] = (char)cp;
    buf_append(b, t, 1);
  } else if (cp < 0x800) {
    t[0] = (char)(0xC0 | (cp >> 6));
    t[1] = (char)(0x80 | (cp & 0x3F));
    buf_append(b, t, 2);
  } else if (cp < 0x10000) {
    t[0] = (char)(0xE0 | (cp >> 12));
    t[1] = (char)(0x80 | ((cp >> 6) & 0x3F));
    t[2] = (char)(0x80 | (cp & 0x3F));
    buf_append(b, t, 3);
  } else {
    t[0] = (char)(0xF0 | (cp >> 18));
    t[1] = (char)(0x80 | ((cp >> 12) & 0x3F));
    t[2] = (char)(0x80 | ((cp >> 6) & 0x3F));
    t[3] = (char)(0x80 | (cp & 0x3F));
    buf_append(b, t, 4);
  }
}

/*───────────────────────────────────────────────────────────────────────────│─╗
│ character references                                                     ─╬─│
╚────────────────────────────────────────────────────────────────────────────│*/

static const struct {
  const char *name;
  unsigned cp;
} kEntities[] = {
    {"AElig", 198},   {"Aacute", 193},  {"Acirc", 194},   {"Agrave", 192},
    {"Aring", 197},   {"Atilde", 195},  {"Auml", 196},    {"Ccedil", 199},
    {"Dagger", 8225}, {"ETH", 208},     {"Eacute", 201},  {"Ecirc", 202},
    {"Egrave", 200},  {"Euml", 203},    {"Iacute", 205},  {"Icirc", 206},
    {"Igrave", 204},  {"Iuml", 207},    {"Ntilde", 209},  {"OElig", 338},
    {"Oacute", 211},  {"Ocirc", 212},   {"Ograve", 210},  {"Oslash", 216},
    {"Otilde", 213},  {"Ouml", 214},    {"Scaron", 352},  {"THORN", 222},
    {"Uacute", 218},  {"Ucirc", 219},   {"Ugrave", 217},  {"Uuml", 220},
    {"Yacute", 221},  {"Yuml", 376},    {"aacute", 225},  {"acirc", 226},
    {"acute", 180},   {"aelig", 230},   {"agrave", 224},  {"alpha", 945},
    {"amp", 38},      {"and", 8743},    {"ang", 8736},    {"apos", 39},
    {"aring", 229},   {"asymp", 8776},  {"atilde", 227},  {"auml", 228},
    {"bdquo", 8222},  {"beta", 946},    {"brvbar", 166},  {"bull", 8226},
    {"cap", 8745},    {"ccedil", 231},  {"cedil", 184},   {"cent", 162},
    {"check", 10003}, {"chi", 967},     {"circ", 710},    {"clubs", 9827},
    {"cong", 8773},   {"copy", 169},    {"crarr", 8629},  {"cup", 8746},
    {"curren", 164},  {"dArr", 8659},   {"dagger", 8224}, {"darr", 8595},
    {"deg", 176},     {"delta", 948},   {"diams", 9830},  {"divide", 247},
    {"eacute", 233},  {"ecirc", 234},   {"egrave", 232},  {"empty", 8709},
    {"emsp", 8195},   {"ensp", 8194},   {"epsilon", 949}, {"equiv", 8801},
    {"eta", 951},     {"eth", 240},     {"euml", 235},    {"euro", 8364},
    {"exist", 8707},  {"fnof", 402},    {"forall", 8704}, {"frac12", 189},
    {"frac14", 188},  {"frac34", 190},  {"frasl", 8260},  {"gamma", 947},
    {"ge", 8805},     {"gt", 62},       {"hArr", 8660},   {"harr", 8596},
    {"hearts", 9829}, {"hellip", 8230}, {"iacute", 237},  {"icirc", 238},
    {"iexcl", 161},   {"igrave", 236},  {"infin", 8734},  {"int", 8747},
    {"iota", 953},    {"iquest", 191},  {"isin", 8712},   {"iuml", 239},
    {"kappa", 954},   {"lArr", 8656},   {"lambda", 955},  {"lang", 9001},
    {"laquo", 171},   {"larr", 8592},   {"lceil", 8968},  {"ldquo", 8220},
    {"le", 8804},     {"lfloor", 8970}, {"lowast", 8727}, {"loz", 9674},
    {"lrm", 8206},    {"lsaquo", 8249}, {"lsquo", 8216},  {"lt", 60},
    {"macr", 175},    {"mdash", 8212},  {"micro", 181},   {"middot", 183},
    {"minus", 8722},  {"mu", 956},      {"nabla", 8711},  {"nbsp", 160},
    {"ndash", 8211},  {"ne", 8800},     {"ni", 8715},     {"not", 172},
    {"notin", 8713},  {"nsub", 8836},   {"ntilde", 241},  {"nu", 957},
    {"oacute", 243},  {"ocirc", 244},   {"oelig", 339},   {"ograve", 242},
    {"oline", 8254},  {"omega", 969},   {"omicron", 959}, {"oplus", 8853},
    {"or", 8744},     {"ordf", 170},    {"ordm", 186},    {"oslash", 248},
    {"otilde", 245},  {"otimes", 8855}, {"ouml", 246},    {"para", 182},
    {"part", 8706},   {"permil", 8240}, {"perp", 8869},   {"phi", 966},
    {"pi", 960},      {"piv", 982},     {"plusmn", 177},  {"pound", 163},
    {"prime", 8242},  {"prod", 8719},   {"prop", 8733},   {"psi", 968},
    {"quot", 34},     {"rArr", 8658},   {"radic", 8730},  {"rang", 9002},
    {"raquo", 187},   {"rarr", 8594},   {"rceil", 8969},  {"rdquo", 8221},
    {"reg", 174},     {"rfloor", 8971}, {"rho", 961},     {"rlm", 8207},
    {"rsaquo", 8250}, {"rsquo", 8217},  {"sbquo", 8218},  {"scaron", 353},
    {"sdot", 8901},   {"sect", 167},    {"shy", 173},     {"sigma", 963},
    {"sigmaf", 962},  {"sim", 8764},    {"spades", 9824}, {"sub", 8834},
    {"sube", 8838},   {"sum", 8721},    {"sup", 8835},    {"sup1", 185},
    {"sup2", 178},    {"sup3", 179},    {"supe", 8839},   {"szlig", 223},
    {"tau", 964},     {"there4", 8756}, {"theta", 952},   {"thetasym", 977},
    {"thinsp", 8201}, {"thorn", 254},   {"tilde", 732},   {"times", 215},
    {"trade", 8482},  {"uArr", 8657},   {"uacute", 250},  {"uarr", 8593},
    {"ucirc", 251},   {"ugrave", 249},  {"uml", 168},     {"upsih", 978},
    {"upsilon", 965}, {"uuml", 252},    {"weierp", 8472}, {"xi", 958},
    {"yacute", 253},  {"yen", 165},     {"yuml", 255},    {"zeta", 950},
    {"zwj", 8205},    {"zwnj", 8204},
};

/* legacy names that browsers accept without the trailing semicolon */
static const char *const kLegacyEntities[] = {"amp",  "lt",   "gt",  "quot",
                                              "nbsp", "copy", "reg", 0};

static unsigned lookup_entity(const char *name, size_t n) {
  size_t lo = 0, hi = sizeof(kEntities) / sizeof(kEntities[0]);
  while (lo < hi) {
    size_t mid = (lo + hi) / 2;
    int c = strncmp(kEntities[mid].name, name, n);
    if (!c && kEntities[mid].name[n]) c = 1;
    if (!c) return kEntities[mid].cp;
    if (c < 0)
      lo = mid + 1;
    else
      hi = mid;
  }
  return 0;
}

/* Decodes &amp; &#123; &#x1f; style references from s[0..n) into out. */
static void decode_entities(Buf *out, const char *s, size_t n) {
  size_t i = 0;
  while (i < n) {
    if (s[i] != '&') {
      size_t j = i;
      while (j < n && s[j] != '&') j++;
      buf_append(out, s + i, j - i);
      i = j;
      continue;
    }
    if (i + 1 < n && s[i + 1] == '#') {
      size_t j = i + 2;
      unsigned cp = 0;
      int hex = 0, digits = 0;
      if (j < n && (s[j] == 'x' || s[j] == 'X')) hex = 1, j++;
      while (j < n) {
        int c = s[j];
        if (hex && isxdigit(c)) {
          cp = cp * 16 + (unsigned)(isdigit(c) ? c - '0' : (tolower(c) - 'a' + 10));
        } else if (!hex && isdigit(c)) {
          cp = cp * 10 + (unsigned)(c - '0');
        } else {
          break;
        }
        if (cp > 0x10FFFF) cp = 0xFFFD;
        digits++;
        j++;
      }
      if (digits) {
        if (j < n && s[j] == ';') j++;
        if (cp == 0) cp = 0xFFFD;
        if (cp >= 0x80 && cp <= 0x9F) {
          /* windows-1252 remap for the common ones */
          static const unsigned k1252[32] = {
              8364, 129,  8218, 402,  8222, 8230, 8224, 8225, 710,  8240, 352,
              8249, 338,  141,  381,  143,  144,  8216, 8217, 8220, 8221, 8226,
              8211, 8212, 732,  8482, 353,  8250, 339,  157,  382,  376};
          cp = k1252[cp - 0x80];
        }
        utf8_encode(out, cp);
        i = j;
        continue;
      }
      buf_putc(out, '&');
      i++;
      continue;
    } else {
      size_t j = i + 1;
      while (j < n && j - i - 1 < 32 && isalnum((unsigned char)s[j])) j++;
      if (j > i + 1) {
        size_t len = j - i - 1;
        unsigned cp = lookup_entity(s + i + 1, len);
        if (cp && j < n && s[j] == ';') {
          utf8_encode(out, cp);
          i = j + 1;
          continue;
        }
        if (cp) {
          /* no semicolon: only legacy names decode, longest prefix wins */
          size_t k;
          for (k = 0; kLegacyEntities[k]; k++) {
            size_t ln = strlen(kLegacyEntities[k]);
            if (ln <= len && !strncmp(s + i + 1, kLegacyEntities[k], ln)) {
              utf8_encode(out, lookup_entity(kLegacyEntities[k], ln));
              i = i + 1 + ln;
              goto next;
            }
          }
        }
      }
      buf_putc(out, '&');
      i++;
    next:;
    }
  }
}

/*───────────────────────────────────────────────────────────────────────────│─╗
│ document object model                                                    ─╬─│
╚────────────────────────────────────────────────────────────────────────────│*/

enum { NODE_DOCUMENT, NODE_ELEMENT, NODE_TEXT };

typedef struct Attr {
  char *name;
  char *value;
} Attr;

typedef struct Node {
  int type;
  char *tag;   /* lowercase element name */
  char *text;  /* decoded text for NODE_TEXT */
  Attr *attrs;
  int nattrs;
  struct Node **kids;
  int nkids, capkids;
  struct Node *parent;
} Node;

typedef struct Doc {
  Arena arena;
  Node *root;
} Doc;

static Node *node_new(Doc *d, int type) {
  Node *n = (Node *)arena_alloc(&d->arena, sizeof(Node));
  n->type = type;
  return n;
}

static void node_append(Doc *d, Node *parent, Node *kid) {
  if (parent->nkids == parent->capkids) {
    int cap = parent->capkids ? parent->capkids * 2 : 4;
    Node **nk = (Node **)arena_alloc(&d->arena, sizeof(Node *) * (size_t)cap);
    if (parent->nkids) memcpy(nk, parent->kids, sizeof(Node *) * (size_t)parent->nkids);
    parent->kids = nk;
    parent->capkids = cap;
  }
  parent->kids[parent->nkids++] = kid;
  kid->parent = parent;
}

static const char *node_attr(const Node *n, const char *name) {
  int i;
  for (i = 0; i < n->nattrs; i++) {
    if (!strcmp(n->attrs[i].name, name)) return n->attrs[i].value;
  }
  return 0;
}

static int node_has_attr(const Node *n, const char *name) {
  return node_attr(n, name) != 0;
}

/* Concatenates all descendant text into a buffer (used for <title>, <button>, <option>). */
static void node_text_content(const Node *n, Buf *out) {
  int i;
  if (n->type == NODE_TEXT) {
    buf_puts(out, n->text);
    return;
  }
  for (i = 0; i < n->nkids; i++) node_text_content(n->kids[i], out);
}

/*───────────────────────────────────────────────────────────────────────────│─╗
│ tokenizer and tree builder                                               ─╬─│
╚────────────────────────────────────────────────────────────────────────────│*/

static const char *const kVoidElements[] = {
    "area", "base",  "br",   "col",   "embed",  "hr",    "img", "input",
    "link", "meta",  "param", "source", "track", "wbr",  "keygen", 0};

static const char *const kRawTextElements[] = {"script", "style", "noscript",
                                               "template", "iframe", "xmp", 0};

static const char *const kEscapableRawText[] = {"textarea", "title", 0};

/* Elements whose start tag implicitly closes an open <p>. */
static const char *const kClosesP[] = {
    "address",  "article", "aside",   "blockquote", "center",  "details",
    "dialog",   "dir",     "div",     "dl",         "fieldset", "figcaption",
    "figure",   "footer",  "form",    "h1",         "h2",      "h3",
    "h4",       "h5",      "h6",      "header",     "hgroup",  "hr",
    "main",     "menu",    "nav",     "ol",         "p",       "pre",
    "section",  "summary", "table",   "ul",         "li",      "dd",
    "dt",       0};

/* Elements that stop the search for an implicitly closable ancestor. */
static const char *const kScopeBoundary[] = {"html", "body", "table", "td",
                                             "th",   "caption", "template", 0};

typedef struct Parser {
  Doc *doc;
  Node **stack;
  int depth, cap;
  Buf tmp;
} Parser;

static Node *p_top(Parser *p) {
  return p->stack[p->depth - 1];
}

static void p_push(Parser *p, Node *n) {
  if (p->depth == p->cap) {
    int cap = p->cap ? p->cap * 2 : 64;
    Node **ns = (Node **)arena_alloc(&p->doc->arena, sizeof(Node *) * (size_t)cap);
    if (p->depth) memcpy(ns, p->stack, sizeof(Node *) * (size_t)p->depth);
    p->stack = ns;
    p->cap = cap;
  }
  p->stack[p->depth++] = n;
}

/* Pops elements until (and including) the nearest ancestor with the tag. */
static int p_pop_to(Parser *p, const char *tag) {
  int i;
  for (i = p->depth - 1; i > 0; i--) {
    if (!strcmp(p->stack[i]->tag, tag)) {
      p->depth = i;
      return 1;
    }
    if (str_in(p->stack[i]->tag, kScopeBoundary) && strcmp(tag, p->stack[i]->tag)) {
      return 0;
    }
  }
  return 0;
}

static int p_has_open(Parser *p, const char *tag) {
  int i;
  for (i = p->depth - 1; i > 0; i--) {
    if (!strcmp(p->stack[i]->tag, tag)) return 1;
    if (str_in(p->stack[i]->tag, kScopeBoundary)) return 0;
  }
  return 0;
}

static void p_add_text(Parser *p, const char *s, size_t n, int decode) {
  Node *t;
  Buf b = {0};
  if (!n) return;
  if (decode) {
    decode_entities(&b, s, n);
  } else {
    buf_append(&b, s, n);
  }
  t = node_new(p->doc, NODE_TEXT);
  t->text = arena_strndup(&p->doc->arena, b.p ? b.p : "", b.n);
  buf_free(&b);
  node_append(p->doc, p_top(p), t);
}

static void p_start_tag(Parser *p, Node *el) {
  const char *tag = el->tag;
  /* implicit end tags */
  if (str_in(tag, kClosesP) && p_has_open(p, "p")) p_pop_to(p, "p");
  if (!strcmp(tag, "li")) {
    int i;
    for (i = p->depth - 1; i > 0; i--) {
      const char *t = p->stack[i]->tag;
      if (!strcmp(t, "li")) {
        p->depth = i;
        break;
      }
      if (!strcmp(t, "ul") || !strcmp(t, "ol") || !strcmp(t, "menu") ||
          str_in(t, kScopeBoundary))
        break;
    }
  } else if (!strcmp(tag, "dt") || !strcmp(tag, "dd")) {
    int i;
    for (i = p->depth - 1; i > 0; i--) {
      const char *t = p->stack[i]->tag;
      if (!strcmp(t, "dt") || !strcmp(t, "dd")) {
        p->depth = i;
        break;
      }
      if (!strcmp(t, "dl") || str_in(t, kScopeBoundary)) break;
    }
  } else if (!strcmp(tag, "option")) {
    if (p_has_open(p, "option")) p_pop_to(p, "option");
  } else if (!strcmp(tag, "optgroup")) {
    if (p_has_open(p, "option")) p_pop_to(p, "option");
    if (p_has_open(p, "optgroup")) p_pop_to(p, "optgroup");
  } else if (!strcmp(tag, "td") || !strcmp(tag, "th")) {
    int i;
    for (i = p->depth - 1; i > 0; i--) {
      const char *t = p->stack[i]->tag;
      if (!strcmp(t, "td") || !strcmp(t, "th")) {
        p->depth = i;
        break;
      }
      if (!strcmp(t, "tr") || !strcmp(t, "table") || !strcmp(t, "html") ||
          !strcmp(t, "body"))
        break;
    }
  } else if (!strcmp(tag, "tr")) {
    int i;
    for (i = p->depth - 1; i > 0; i--) {
      const char *t = p->stack[i]->tag;
      if (!strcmp(t, "tr")) {
        p->depth = i;
        break;
      }
      if (!strcmp(t, "table") || !strcmp(t, "thead") || !strcmp(t, "tbody") ||
          !strcmp(t, "tfoot") || !strcmp(t, "html") || !strcmp(t, "body"))
        break;
    }
  } else if (!strcmp(tag, "thead") || !strcmp(tag, "tbody") ||
             !strcmp(tag, "tfoot")) {
    int i;
    for (i = p->depth - 1; i > 0; i--) {
      const char *t = p->stack[i]->tag;
      if (!strcmp(t, "thead") || !strcmp(t, "tbody") || !strcmp(t, "tfoot")) {
        p->depth = i;
        break;
      }
      if (!strcmp(t, "table") || !strcmp(t, "html") || !strcmp(t, "body")) break;
    }
  } else if (!strcmp(tag, "body")) {
    if (p_has_open(p, "head")) p_pop_to(p, "head");
  }
  node_append(p->doc, p_top(p), el);
  if (!str_in(tag, kVoidElements)) p_push(p, el);
}

static void p_end_tag(Parser *p, const char *tag) {
  if (!strcmp(tag, "br")) {
    Node *el = node_new(p->doc, NODE_ELEMENT);
    el->tag = arena_strdup(&p->doc->arena, "br");
    node_append(p->doc, p_top(p), el);
    return;
  }
  if (!strcmp(tag, "body") || !strcmp(tag, "html")) return; /* keep open */
  {
    int i;
    for (i = p->depth - 1; i > 0; i--) {
      if (!strcmp(p->stack[i]->tag, tag)) {
        p->depth = i;
        return;
      }
    }
  }
}

static char *lower_dup(Arena *a, const char *s, size_t n) {
  char *p = arena_strndup(a, s, n);
  size_t i;
  for (i = 0; i < n; i++) p[i] = (char)tolower((unsigned char)p[i]);
  return p;
}

/* Parses attributes of a start tag; returns index just past '>' (or end). */
static size_t parse_attrs(Parser *p, Node *el, const char *s, size_t n, size_t i,
                          int *selfclose) {
  Attr tmp[128];
  int na = 0;
  *selfclose = 0;
  for (;;) {
    size_t ns, ne;
    while (i < n && mb_isspace(s[i])) i++;
    if (i >= n) break;
    if (s[i] == '>') {
      i++;
      break;
    }
    if (s[i] == '/') {
      i++;
      if (i < n && s[i] == '>') {
        *selfclose = 1;
        i++;
        break;
      }
      continue;
    }
    ns = i;
    while (i < n && !mb_isspace(s[i]) && s[i] != '=' && s[i] != '>' &&
           !(s[i] == '/' && i + 1 < n && s[i + 1] == '>'))
      i++;
    ne = i;
    while (i < n && mb_isspace(s[i])) i++;
    if (na < 128) {
      tmp[na].name = lower_dup(&p->doc->arena, s + ns, ne - ns);
      tmp[na].value = (char *)"";
    }
    if (i < n && s[i] == '=') {
      size_t vs, ve;
      i++;
      while (i < n && mb_isspace(s[i])) i++;
      if (i < n && (s[i] == '"' || s[i] == '\'')) {
        char q = s[i++];
        vs = i;
        while (i < n && s[i] != q) i++;
        ve = i;
        if (i < n) i++;
      } else {
        vs = i;
        while (i < n && !mb_isspace(s[i]) && s[i] != '>') i++;
        ve = i;
      }
      if (na < 128) {
        Buf b = {0};
        decode_entities(&b, s + vs, ve - vs);
        tmp[na].value = arena_strndup(&p->doc->arena, b.p ? b.p : "", b.n);
        buf_free(&b);
      }
    }
    if (na < 128 && ne > ns) na++;
  }
  if (na) {
    el->attrs = (Attr *)arena_alloc(&p->doc->arena, sizeof(Attr) * (size_t)na);
    memcpy(el->attrs, tmp, sizeof(Attr) * (size_t)na);
    el->nattrs = na;
  }
  return i;
}

static Doc *mb_parse(const char *s, size_t n) {
  Doc *d = (Doc *)calloc(1, sizeof(Doc));
  Parser ps = {0};
  Parser *p = &ps;
  size_t i = 0;
  if (!d) abort();
  d->root = node_new(d, NODE_DOCUMENT);
  p->doc = d;
  p_push(p, d->root);
  /* skip UTF-8 BOM */
  if (n >= 3 && (unsigned char)s[0] == 0xEF && (unsigned char)s[1] == 0xBB &&
      (unsigned char)s[2] == 0xBF)
    i = 3;
  while (i < n) {
    if (s[i] == '<') {
      if (i + 3 < n && s[i + 1] == '!' && s[i + 2] == '-' && s[i + 3] == '-') {
        const char *e = 0;
        size_t j;
        for (j = i + 4; j + 2 < n; j++) {
          if (s[j] == '-' && s[j + 1] == '-' && s[j + 2] == '>') {
            e = s + j + 3;
            break;
          }
        }
        i = e ? (size_t)(e - s) : n;
        continue;
      }
      if (i + 1 < n && (s[i + 1] == '!' || s[i + 1] == '?')) {
        while (i < n && s[i] != '>') i++;
        if (i < n) i++;
        continue;
      }
      if (i + 1 < n && s[i + 1] == '/') {
        size_t j = i + 2, ns = j;
        char *tag;
        while (j < n && !mb_isspace(s[j]) && s[j] != '>') j++;
        tag = lower_dup(&d->arena, s + ns, j - ns);
        while (j < n && s[j] != '>') j++;
        if (j < n) j++;
        i = j;
        if (*tag) p_end_tag(p, tag);
        continue;
      }
      if (i + 1 < n && isalpha((unsigned char)s[i + 1])) {
        size_t j = i + 1, ns = j;
        Node *el = node_new(d, NODE_ELEMENT);
        int selfclose;
        while (j < n && !mb_isspace(s[j]) && s[j] != '>' && s[j] != '/') j++;
        el->tag = lower_dup(&d->arena, s + ns, j - ns);
        j = parse_attrs(p, el, s, n, j, &selfclose);
        i = j;
        p_start_tag(p, el);
        if (str_in(el->tag, kRawTextElements) || str_in(el->tag, kEscapableRawText)) {
          /* raw text: everything up to the matching close tag */
          size_t k = i, tl = strlen(el->tag), end = n, close = n;
          int escapable = str_in(el->tag, kEscapableRawText);
          for (; k + tl + 2 <= n; k++) {
            if (s[k] == '<' && s[k + 1] == '/' &&
                !mb_strncasecmp(s + k + 2, el->tag, tl) &&
                (k + tl + 2 == n || mb_isspace(s[k + tl + 2]) || s[k + tl + 2] == '>')) {
              end = k;
              close = k;
              while (close < n && s[close] != '>') close++;
              if (close < n) close++;
              break;
            }
          }
          p_add_text(p, s + i, end - i, escapable);
          if (p_top(p) == el && p->depth > 1) p->depth--;
          i = close;
        } else if (selfclose && p_top(p) == el && p->depth > 1) {
          /* <div/> is not really self-closing in HTML, but foreign content
             like <svg><path/></svg> relies on it; honor it outside of the
             common block tags. */
          if (strcmp(el->tag, "div") && strcmp(el->tag, "span") &&
              strcmp(el->tag, "a") && strcmp(el->tag, "p"))
            p->depth--;
        }
        continue;
      }
      /* stray '<' */
      {
        size_t j = i + 1;
        while (j < n && s[j] != '<') j++;
        p_add_text(p, s + i, j - i, 1);
        i = j;
        continue;
      }
    } else {
      size_t j = i;
      while (j < n && s[j] != '<') j++;
      p_add_text(p, s + i, j - i, 1);
      i = j;
    }
  }
  buf_free(&p->tmp);
  return d;
}

static void mb_doc_free(Doc *d) {
  if (!d) return;
  arena_free(&d->arena);
  free(d);
}

/*───────────────────────────────────────────────────────────────────────────│─╗
│ url resolution (rfc 3986 lite)                                           ─╬─│
╚────────────────────────────────────────────────────────────────────────────│*/

static int url_has_scheme(const char *s) {
  const char *p = s;
  if (!isalpha((unsigned char)*p)) return 0;
  while (isalnum((unsigned char)*p) || *p == '+' || *p == '-' || *p == '.') p++;
  return *p == ':';
}

/* Removes ./ and ../ segments in place (RFC 3986 §5.2.4). */
static void remove_dot_segments(char *path) {
  char *out = path, *in = path;
  size_t n = strlen(path);
  char *buf = (char *)malloc(n + 2), *o = buf;
  if (!buf) return;
  in = path;
  while (*in) {
    if (!strncmp(in, "../", 3)) {
      in += 3;
    } else if (!strncmp(in, "./", 2)) {
      in += 2;
    } else if (!strncmp(in, "/./", 3)) {
      in += 2;
    } else if (!strcmp(in, "/.")) {
      in += 1;
      *in = '/';
    } else if (!strncmp(in, "/../", 4) || !strcmp(in, "/..")) {
      in += 3;
      if (!*in) {
        in[0] = '/';
        in[1] = 0;
      } else {
        in += 0;
      }
      while (o > buf && *(o - 1) != '/') o--;
      if (o > buf) o--;
    } else if (!strcmp(in, ".") || !strcmp(in, "..")) {
      in += strlen(in);
    } else {
      char *seg = in;
      if (*seg == '/') seg++;
      while (*seg && *seg != '/') seg++;
      memcpy(o, in, (size_t)(seg - in));
      o += seg - in;
      in = seg;
    }
  }
  *o = 0;
  memcpy(out, buf, (size_t)(o - buf) + 1);
  free(buf);
}

/* Resolves ref against base into a malloc'd absolute URL. */
static char *url_resolve(const char *base, const char *ref) {
  Buf b = {0};
  const char *scheme_end, *auth_start, *auth_end, *path_end, *q, *h;
  size_t plen;
  char *path, *res;
  while (mb_isspace(*ref)) ref++;
  if (url_has_scheme(ref) || !base || !*base) {
    return mb_strdup(ref);
  }
  if (!url_has_scheme(base)) return mb_strdup(ref);
  scheme_end = strchr(base, ':');
  if (ref[0] == '/' && ref[1] == '/') {
    buf_append(&b, base, (size_t)(scheme_end - base) + 1);
    buf_puts(&b, ref);
    return b.p;
  }
  auth_start = scheme_end + 1;
  if (auth_start[0] == '/' && auth_start[1] == '/') {
    auth_start += 2;
    auth_end = auth_start;
    while (*auth_end && *auth_end != '/' && *auth_end != '?' && *auth_end != '#')
      auth_end++;
  } else {
    auth_end = auth_start;
  }
  path_end = auth_end;
  while (*path_end && *path_end != '?' && *path_end != '#') path_end++;
  q = path_end;
  while (*q && *q != '#') q++;
  h = q;
  /* scheme://authority */
  buf_append(&b, base, (size_t)(auth_end - base));
  if (ref[0] == '#') {
    buf_append(&b, auth_end, (size_t)(h - auth_end));
    buf_puts(&b, ref);
    return b.p;
  }
  if (ref[0] == '?') {
    buf_append(&b, auth_end, (size_t)(path_end - auth_end));
    buf_puts(&b, ref);
    return b.p;
  }
  if (ref[0] == '/') {
    path = mb_strdup(ref);
  } else {
    /* merge: base path up to last '/' plus ref */
    const char *slash = path_end;
    Buf pb = {0};
    while (slash > auth_end && *(slash - 1) != '/') slash--;
    if (slash == auth_end) {
      buf_putc(&pb, '/');
    } else {
      buf_append(&pb, auth_end, (size_t)(slash - auth_end));
    }
    if (*ref) {
      buf_puts(&pb, ref);
    }
    path = pb.p ? pb.p : mb_strdup("/");
  }
  /* split query/fragment off before normalizing */
  plen = 0;
  while (path[plen] && path[plen] != '?' && path[plen] != '#') plen++;
  {
    char *rest = mb_strdup(path + plen);
    path[plen] = 0;
    if (plen) remove_dot_segments(path);
    buf_puts(&b, path);
    buf_puts(&b, rest);
    free(rest);
  }
  free(path);
  res = b.p;
  return res;
}

/*───────────────────────────────────────────────────────────────────────────│─╗
│ style and box tree                                                       ─╬─│
╚────────────────────────────────────────────────────────────────────────────│*/

enum { RUN_TEXT, RUN_BR, RUN_IMAGE, RUN_CONTROL };

typedef struct Run {
  int kind;
  char *text;       /* text, alt text or control label */
  char *href;       /* link target (absolute) */
  char *src;        /* image source (absolute) */
  char *ctl;        /* control kind: text password search submit button checkbox radio select textarea */
  char *name;       /* form field name */
  char *value;      /* form field value */
  char *placeholder;
  int form;         /* index into forms, -1 if none */
  int bold, italic, underline, mono, strike;
  int size;         /* font size in px */
  int color;        /* 0xRRGGBB or -1 for default */
  int bg;           /* 0xRRGGBB or -1 */
  int width, height;
} Run;

typedef struct Block {
  char *tag;
  Run *runs;
  int nruns, capruns;
  int indent;       /* left indent in px */
  int margin_top, margin_bottom;
  int align;        /* 0 left 1 center 2 right */
  int pre;
  int hr;
  int quote;        /* blockquote bar */
  int bg;           /* background color or -1 */
  char *marker;     /* list marker text or 0 */
} Block;

typedef struct Form {
  char *action;
  char *method;
} Form;

typedef struct Style {
  int display;      /* 0 inline 1 block 2 none 3 list-item */
  int bold, italic, underline, mono, strike;
  int size;
  int color, bg;
  int align;
  int pre;
  char *href;
  int form;
} Style;

typedef struct Ctx {
  int indent;
  int align;
  int margin_top, margin_bottom;
  int pending_top;  /* apply margin_top to the next created block */
  int pre;
  int quote;
  int bg;
  const char *tag;
  char *marker;
} Ctx;

typedef struct Layout {
  Arena arena;
  Doc *doc;
  char *base;
  char *title;
  Block *blocks;
  int nblocks, capblocks;
  Block *cur;
  Ctx *ctx;
  int depth, capctx;
  Form *forms;
  int nforms, capforms;
  int last_margin_bottom;
  int text_nodes_seen;
} Layout;

static int parse_hex_color(const char *s) {
  unsigned v = 0;
  size_t n;
  if (*s != '#') return -1;
  s++;
  n = strlen(s);
  if (n == 3) {
    int i;
    for (i = 0; i < 3; i++) {
      int c = tolower((unsigned char)s[i]), d;
      if (!isxdigit(c)) return -1;
      d = isdigit(c) ? c - '0' : c - 'a' + 10;
      v = v * 256 + (unsigned)(d * 17);
    }
    return (int)v;
  }
  if (n == 6) {
    int i;
    for (i = 0; i < 6; i++) {
      int c = tolower((unsigned char)s[i]), d;
      if (!isxdigit(c)) return -1;
      d = isdigit(c) ? c - '0' : c - 'a' + 10;
      v = v * 16 + (unsigned)d;
    }
    return (int)v;
  }
  return -1;
}

static int parse_css_color(const char *s) {
  static const struct {
    const char *n;
    int c;
  } kNamed[] = {{"black", 0x000000}, {"white", 0xFFFFFF},  {"red", 0xFF0000},
                {"green", 0x008000}, {"blue", 0x0000FF},   {"gray", 0x808080},
                {"grey", 0x808080},  {"silver", 0xC0C0C0}, {"yellow", 0xFFFF00},
                {"orange", 0xFFA500}, {"purple", 0x800080}, {"navy", 0x000080},
                {"teal", 0x008080},  {"maroon", 0x800000}, {"olive", 0x808000},
                {"lime", 0x00FF00},  {"aqua", 0x00FFFF},   {"fuchsia", 0xFF00FF},
                {"transparent", -1}, {0, 0}};
  int i;
  while (mb_isspace(*s)) s++;
  if (*s == '#') return parse_hex_color(s);
  if (!mb_strncasecmp(s, "rgb", 3)) {
    int r, g, b;
    const char *p = strchr(s, '(');
    if (p && sscanf(p + 1, "%d , %d , %d", &r, &g, &b) == 3) {
      return ((r & 255) << 16) | ((g & 255) << 8) | (b & 255);
    }
    if (p && sscanf(p + 1, "%d %d %d", &r, &g, &b) == 3) {
      return ((r & 255) << 16) | ((g & 255) << 8) | (b & 255);
    }
    return -1;
  }
  for (i = 0; kNamed[i].n; i++) {
    if (!mb_strcasecmp(s, kNamed[i].n)) return kNamed[i].c;
  }
  return -1;
}

/* Applies the handful of inline style properties we understand. */
static void apply_inline_style(Style *st, const char *css) {
  const char *p = css;
  while (*p) {
    const char *ns, *ne, *vs, *ve;
    char name[64], value[128];
    size_t n;
    while (*p && (mb_isspace(*p) || *p == ';')) p++;
    if (!*p) break;
    ns = p;
    while (*p && *p != ':' && *p != ';') p++;
    ne = p;
    if (*p != ':') continue;
    p++;
    while (mb_isspace(*p)) p++;
    vs = p;
    while (*p && *p != ';') p++;
    ve = p;
    while (ve > vs && mb_isspace(*(ve - 1))) ve--;
    while (ne > ns && mb_isspace(*(ne - 1))) ne--;
    n = (size_t)(ne - ns);
    if (n >= sizeof(name)) n = sizeof(name) - 1;
    memcpy(name, ns, n);
    name[n] = 0;
    n = (size_t)(ve - vs);
    if (n >= sizeof(value)) n = sizeof(value) - 1;
    memcpy(value, vs, n);
    value[n] = 0;
    {
      size_t k;
      for (k = 0; name[k]; k++) name[k] = (char)tolower((unsigned char)name[k]);
    }
    if (!strcmp(name, "display")) {
      if (!mb_strncasecmp(value, "none", 4)) st->display = 2;
      else if (!mb_strncasecmp(value, "block", 5) || !mb_strncasecmp(value, "flex", 4) ||
               !mb_strncasecmp(value, "grid", 4))
        st->display = st->display == 2 ? 2 : 1;
      else if (!mb_strncasecmp(value, "inline", 6) && st->display != 2)
        st->display = 0;
    } else if (!strcmp(name, "visibility")) {
      if (!mb_strcasecmp(value, "hidden")) st->display = 2;
    } else if (!strcmp(name, "font-weight")) {
      if (!mb_strcasecmp(value, "bold") || !mb_strcasecmp(value, "bolder") ||
          atoi(value) >= 600)
        st->bold = 1;
      else if (!mb_strcasecmp(value, "normal") || (atoi(value) && atoi(value) < 600))
        st->bold = 0;
    } else if (!strcmp(name, "font-style")) {
      st->italic = !mb_strcasecmp(value, "italic") || !mb_strcasecmp(value, "oblique");
    } else if (!strcmp(name, "text-decoration") || !strcmp(name, "text-decoration-line")) {
      if (strstr(value, "underline")) st->underline = 1;
      if (strstr(value, "line-through")) st->strike = 1;
      if (!strcmp(value, "none")) st->underline = st->strike = 0;
    } else if (!strcmp(name, "color")) {
      int c = parse_css_color(value);
      if (c >= 0) st->color = c;
    } else if (!strcmp(name, "background-color") || !strcmp(name, "background")) {
      int c = parse_css_color(value);
      if (c >= 0) st->bg = c;
    } else if (!strcmp(name, "font-size")) {
      double v = atof(value);
      if (strstr(value, "px") && v > 0) st->size = (int)(v + 0.5);
      else if (strstr(value, "em") && v > 0) st->size = (int)(st->size * v + 0.5);
      else if (strstr(value, "%") && v > 0) st->size = (int)(st->size * v / 100 + 0.5);
      else if (strstr(value, "pt") && v > 0) st->size = (int)(v * 4 / 3 + 0.5);
      else if (!strcmp(value, "larger")) st->size = st->size * 6 / 5;
      else if (!strcmp(value, "smaller")) st->size = st->size * 5 / 6;
      if (st->size < 8) st->size = 8;
      if (st->size > 96) st->size = 96;
    } else if (!strcmp(name, "text-align")) {
      if (!mb_strcasecmp(value, "center")) st->align = 1;
      else if (!mb_strcasecmp(value, "right")) st->align = 2;
      else if (!mb_strcasecmp(value, "left")) st->align = 0;
    } else if (!strcmp(name, "font-family")) {
      if (strstr(value, "monospace") || strstr(value, "Courier") || strstr(value, "Menlo"))
        st->mono = 1;
    } else if (!strcmp(name, "white-space")) {
      if (!mb_strncasecmp(value, "pre", 3)) st->pre = 1;
      else if (!mb_strcasecmp(value, "normal")) st->pre = 0;
    }
  }
}

static const char *const kBlockTags[] = {
    "html",    "body",     "div",     "p",        "article",  "section",
    "nav",     "header",   "footer",  "main",     "aside",    "address",
    "blockquote", "center", "figure", "figcaption", "form",   "fieldset",
    "legend",  "details",  "summary", "dialog",   "dir",      "menu",
    "table",   "thead",    "tbody",   "tfoot",    "tr",       "caption",
    "ul",      "ol",       "dl",      "dt",       "dd",       "h1",
    "h2",      "h3",       "h4",      "h5",       "h6",       "hr",
    "pre",     "hgroup",   "search",  "optgroup", "noframes", "frameset",
    "option",  0};

static const char *const kHiddenTags[] = {
    "head",  "script",   "style", "noscript", "template", "title", "meta",
    "link",  "base",     "svg",   "math",     "iframe",   "object", "embed",
    "canvas", "audio",   "video", "map",      "area",     "param",  "source",
    "track", "datalist", "dialog", "slot",    "portal",   "xmp",    0};

static void ui_style(const char *tag, const Node *el, Style *st) {
  if (str_in(tag, kHiddenTags)) {
    st->display = 2;
    return;
  }
  if (str_in(tag, kBlockTags)) st->display = 1;
  if (!strcmp(tag, "li")) st->display = 3;
  if (!strcmp(tag, "h1")) st->size = 32, st->bold = 1;
  else if (!strcmp(tag, "h2")) st->size = 24, st->bold = 1;
  else if (!strcmp(tag, "h3")) st->size = 19, st->bold = 1;
  else if (!strcmp(tag, "h4")) st->size = 16, st->bold = 1;
  else if (!strcmp(tag, "h5")) st->size = 13, st->bold = 1;
  else if (!strcmp(tag, "h6")) st->size = 11, st->bold = 1;
  else if (!strcmp(tag, "b") || !strcmp(tag, "strong") || !strcmp(tag, "th") ||
           !strcmp(tag, "dt") || !strcmp(tag, "legend") || !strcmp(tag, "summary"))
    st->bold = 1;
  else if (!strcmp(tag, "i") || !strcmp(tag, "em") || !strcmp(tag, "cite") ||
           !strcmp(tag, "var") || !strcmp(tag, "dfn") || !strcmp(tag, "address"))
    st->italic = 1;
  else if (!strcmp(tag, "u") || !strcmp(tag, "ins"))
    st->underline = 1;
  else if (!strcmp(tag, "s") || !strcmp(tag, "strike") || !strcmp(tag, "del"))
    st->strike = 1;
  else if (!strcmp(tag, "code") || !strcmp(tag, "kbd") || !strcmp(tag, "samp") ||
           !strcmp(tag, "tt"))
    st->mono = 1, st->size = st->size * 13 / 16 > 8 ? st->size * 13 / 16 : 8;
  else if (!strcmp(tag, "pre"))
    st->mono = 1, st->pre = 1, st->size = 13;
  else if (!strcmp(tag, "small"))
    st->size = st->size * 13 / 16;
  else if (!strcmp(tag, "big"))
    st->size = st->size * 19 / 16;
  else if (!strcmp(tag, "sub") || !strcmp(tag, "sup"))
    st->size = st->size * 12 / 16;
  else if (!strcmp(tag, "mark"))
    st->bg = 0xFFFF00, st->color = 0x000000;
  else if (!strcmp(tag, "center"))
    st->align = 1;
  else if (!strcmp(tag, "a")) {
    if (node_attr(el, "href")) {
      st->underline = 1;
      st->color = 0x1A0DAB;
    }
  } else if (!strcmp(tag, "option") || !strcmp(tag, "input") ||
             !strcmp(tag, "select") || !strcmp(tag, "textarea") ||
             !strcmp(tag, "button")) {
    /* handled as controls */
  }
  if (node_has_attr(el, "hidden")) st->display = 2;
  {
    const char *align = node_attr(el, "align");
    if (align) {
      if (!mb_strcasecmp(align, "center")) st->align = 1;
      else if (!mb_strcasecmp(align, "right")) st->align = 2;
    }
  }
  {
    const char *css = node_attr(el, "style");
    if (css) apply_inline_style(st, css);
  }
}

static Block *layout_new_block(Layout *L) {
  Block *b;
  Ctx *c = &L->ctx[L->depth - 1];
  if (L->nblocks == L->capblocks) {
    int cap = L->capblocks ? L->capblocks * 2 : 64;
    Block *nb = (Block *)arena_alloc(&L->arena, sizeof(Block) * (size_t)cap);
    if (L->nblocks) memcpy(nb, L->blocks, sizeof(Block) * (size_t)L->nblocks);
    L->blocks = nb;
    L->capblocks = cap;
  }
  b = &L->blocks[L->nblocks++];
  memset(b, 0, sizeof(*b));
  b->tag = (char *)c->tag;
  b->indent = c->indent;
  b->align = c->align;
  b->pre = c->pre;
  b->quote = c->quote;
  b->bg = c->bg;
  b->marker = c->marker;
  c->marker = 0;
  if (c->pending_top) {
    b->margin_top = c->margin_top;
    c->pending_top = 0;
  }
  L->cur = b;
  return b;
}

static void layout_flush(Layout *L) {
  if (L->cur) {
    /* trim trailing whitespace of the last text run */
    Block *b = L->cur;
    while (b->nruns) {
      Run *r = &b->runs[b->nruns - 1];
      if (r->kind == RUN_TEXT) {
        size_t n = strlen(r->text);
        while (n && mb_isspace((unsigned char)r->text[n - 1])) n--;
        r->text[n] = 0;
        if (!n && !b->pre) {
          b->nruns--;
          continue;
        }
      }
      break;
    }
    {
      int visible = 0, k;
      for (k = 0; k < b->nruns; k++) {
        if (b->runs[k].kind != RUN_CONTROL || strcmp(b->runs[k].ctl, "hidden")) visible = 1;
      }
      if (!visible && !b->hr && !b->marker) {
        /* only hidden fields: drop the block unless it carries form data */
        if (!b->nruns) L->nblocks--;
      }
    }
    L->cur = 0;
  }
}

static Run *block_add_run(Layout *L, Block *b) {
  Run *r;
  if (b->nruns == b->capruns) {
    int cap = b->capruns ? b->capruns * 2 : 8;
    Run *nr = (Run *)arena_alloc(&L->arena, sizeof(Run) * (size_t)cap);
    if (b->nruns) memcpy(nr, b->runs, sizeof(Run) * (size_t)b->nruns);
    b->runs = nr;
    b->capruns = cap;
  }
  r = &b->runs[b->nruns++];
  memset(r, 0, sizeof(*r));
  r->form = -1;
  r->color = -1;
  r->bg = -1;
  return r;
}

static Block *layout_cur(Layout *L) {
  return L->cur ? L->cur : layout_new_block(L);
}

static void run_set_style(Run *r, const Style *st) {
  r->bold = st->bold;
  r->italic = st->italic;
  r->underline = st->underline;
  r->mono = st->mono;
  r->strike = st->strike;
  r->size = st->size;
  r->color = st->color;
  r->bg = st->bg;
  r->href = st->href;
  r->form = st->form;
}

static int same_text_style(const Run *r, const Style *st) {
  return r->kind == RUN_TEXT && r->bold == st->bold && r->italic == st->italic &&
         r->underline == st->underline && r->mono == st->mono &&
         r->strike == st->strike && r->size == st->size && r->color == st->color &&
         r->bg == st->bg &&
         ((!r->href && !st->href) || (r->href && st->href && !strcmp(r->href, st->href)));
}

static void layout_text(Layout *L, const char *text, const Style *st) {
  Buf b = {0};
  Block *blk;
  int at_start;
  const char *p = text;
  if (st->pre) {
    /* preserve whitespace; split lines into separate blocks */
    const char *line = text;
    if (*line == '\n' && !L->cur) line++;  /* leading newline after <pre> is ignored */
    while (*line) {
      const char *nl = strchr(line, '\n');
      size_t n = nl ? (size_t)(nl - line) : strlen(line);
      Run *r;
      blk = layout_cur(L);
      blk->pre = 1;
      r = block_add_run(L, blk);
      r->kind = RUN_TEXT;
      run_set_style(r, st);
      r->text = arena_strndup(&L->arena, line, n);
      if (!nl) break;
      layout_flush(L);
      line = nl + 1;
    }
    return;
  }
  /* collapse whitespace */
  at_start = !L->cur || !L->cur->nruns;
  {
    int prev_space = 0;
    if (L->cur && L->cur->nruns) {
      Run *last = &L->cur->runs[L->cur->nruns - 1];
      if (last->kind == RUN_TEXT) {
        size_t n = strlen(last->text);
        prev_space = n && mb_isspace((unsigned char)last->text[n - 1]);
      } else if (last->kind == RUN_BR) {
        prev_space = 1;
      }
    }
    for (; *p; p++) {
      if (mb_isspace((unsigned char)*p)) {
        if (!prev_space && !at_start) buf_putc(&b, ' ');
        prev_space = 1;
      } else {
        buf_putc(&b, *p);
        prev_space = 0;
        at_start = 0;
      }
    }
  }
  if (!b.n) {
    buf_free(&b);
    return;
  }
  blk = layout_cur(L);
  if (blk->nruns && st->href && b.p[0] != ' ') {
    /* two different links butted together (menus styled with CSS margins):
       keep them readable by inserting a space, like a text browser does */
    Run *last = &blk->runs[blk->nruns - 1];
    if (last->kind == RUN_TEXT && last->href && strcmp(last->href, st->href)) {
      size_t ln = strlen(last->text);
      if (ln && !mb_isspace((unsigned char)last->text[ln - 1])) {
        char *nt = (char *)arena_alloc(&L->arena, ln + 2);
        memcpy(nt, last->text, ln);
        nt[ln] = ' ';
        nt[ln + 1] = 0;
        last->text = nt;
      }
    }
  }
  if (blk->nruns && same_text_style(&blk->runs[blk->nruns - 1], st)) {
    Run *r = &blk->runs[blk->nruns - 1];
    size_t on = strlen(r->text);
    char *nt = (char *)arena_alloc(&L->arena, on + b.n + 1);
    memcpy(nt, r->text, on);
    memcpy(nt + on, b.p, b.n + 1);
    r->text = nt;
  } else {
    Run *r = block_add_run(L, blk);
    r->kind = RUN_TEXT;
    run_set_style(r, st);
    r->text = arena_strndup(&L->arena, b.p, b.n);
  }
  buf_free(&b);
}

static void layout_push_ctx(Layout *L, const char *tag, int indent_delta,
                            int margin, const Style *st) {
  Ctx *c;
  Ctx *parent;
  layout_flush(L);
  parent = &L->ctx[L->depth - 1];
  if (L->depth == L->capctx) {
    int cap = L->capctx ? L->capctx * 2 : 32;
    Ctx *nc = (Ctx *)arena_alloc(&L->arena, sizeof(Ctx) * (size_t)cap);
    if (L->depth) memcpy(nc, L->ctx, sizeof(Ctx) * (size_t)L->depth);
    L->ctx = nc;
    L->capctx = cap;
  }
  c = &L->ctx[L->depth++];
  *c = *parent;
  c->tag = tag;
  c->indent = parent->indent + indent_delta;
  c->margin_top = c->margin_bottom = margin;
  c->pending_top = margin > 0;
  c->align = st->align;
  c->pre = st->pre;
  c->marker = 0;
  if (st->bg >= 0) c->bg = st->bg;
}

static void layout_pop_ctx(Layout *L) {
  Ctx *c = &L->ctx[L->depth - 1];
  layout_flush(L);
  if (L->nblocks && c->margin_bottom > L->blocks[L->nblocks - 1].margin_bottom) {
    L->blocks[L->nblocks - 1].margin_bottom = c->margin_bottom;
  }
  L->depth--;
  /* if the parent had a pending top margin it is now consumed */
  if (!L->ctx[L->depth - 1].pending_top) {
    /* nothing */
  }
}

static char *layout_abs_url(Layout *L, const char *ref) {
  char *u, *r;
  if (!ref) return 0;
  u = url_resolve(L->base, ref);
  r = arena_strdup(&L->arena, u);
  free(u);
  return r;
}

static int add_form(Layout *L, const Node *el) {
  Form *f;
  const char *action = node_attr(el, "action");
  const char *method = node_attr(el, "method");
  if (L->nforms == L->capforms) {
    int cap = L->capforms ? L->capforms * 2 : 8;
    Form *nf = (Form *)arena_alloc(&L->arena, sizeof(Form) * (size_t)cap);
    if (L->nforms) memcpy(nf, L->forms, sizeof(Form) * (size_t)L->nforms);
    L->forms = nf;
    L->capforms = cap;
  }
  f = &L->forms[L->nforms];
  f->action = layout_abs_url(L, action && *action ? action : L->base);
  f->method = arena_strdup(&L->arena, method && !mb_strcasecmp(method, "post") ? "post" : "get");
  return L->nforms++;
}

static void layout_node(Layout *L, const Node *n, const Style *inherited, int *li_counter);

static void layout_children(Layout *L, const Node *n, const Style *st) {
  int i, li = 0;
  for (i = 0; i < n->nkids; i++) layout_node(L, n->kids[i], st, &li);
}

static void layout_control(Layout *L, const Node *el, const Style *st, const char *kind) {
  Block *blk = layout_cur(L);
  Run *r = block_add_run(L, blk);
  const char *v;
  r->kind = RUN_CONTROL;
  run_set_style(r, st);
  r->ctl = arena_strdup(&L->arena, kind);
  v = node_attr(el, "name");
  r->name = v ? arena_strdup(&L->arena, v) : 0;
  v = node_attr(el, "value");
  r->value = v ? arena_strdup(&L->arena, v) : 0;
  v = node_attr(el, "placeholder");
  r->placeholder = v ? arena_strdup(&L->arena, v) : 0;
  r->text = r->value;
  if (!strcmp(el->tag, "button") || !strcmp(el->tag, "select") ||
      !strcmp(el->tag, "textarea")) {
    Buf b = {0};
    if (!strcmp(el->tag, "select")) {
      /* first option's text becomes the visible value; options list joined by \n */
      int i, j, count = 0;
      Buf opts = {0};
      for (i = 0; i < el->nkids; i++) {
        const Node *k = el->kids[i];
        const Node *grp[1];
        int ng = 0, g;
        if (k->type != NODE_ELEMENT) continue;
        if (!strcmp(k->tag, "optgroup")) {
          for (j = 0; j < k->nkids; j++) {
            if (k->kids[j]->type == NODE_ELEMENT && !strcmp(k->kids[j]->tag, "option")) {
              Buf t = {0};
              node_text_content(k->kids[j], &t);
              if (count++) buf_putc(&opts, '\n');
              buf_puts(&opts, t.p ? t.p : "");
              buf_free(&t);
            }
          }
          continue;
        }
        if (strcmp(k->tag, "option")) continue;
        grp[0] = k;
        ng = 1;
        for (g = 0; g < ng; g++) {
          Buf t = {0};
          node_text_content(grp[g], &t);
          if (count++) buf_putc(&opts, '\n');
          buf_puts(&opts, t.p ? t.p : "");
          if (!b.n || node_has_attr(grp[g], "selected")) {
            b.n = 0;
            buf_puts(&b, t.p ? t.p : "");
          }
          buf_free(&t);
        }
      }
      r->placeholder = opts.p ? arena_strdup(&L->arena, opts.p) : 0;
      buf_free(&opts);
    } else {
      node_text_content(el, &b);
    }
    if (b.p) {
      /* collapse whitespace in the label */
      Buf c = {0};
      int sp = 1;
      const char *p;
      for (p = b.p; *p; p++) {
        if (mb_isspace((unsigned char)*p)) {
          if (!sp) buf_putc(&c, ' ');
          sp = 1;
        } else {
          buf_putc(&c, *p);
          sp = 0;
        }
      }
      while (c.n && c.p[c.n - 1] == ' ') c.p[--c.n] = 0;
      r->text = c.n ? arena_strdup(&L->arena, c.p) : r->value;
      if (!strcmp(el->tag, "textarea")) r->value = r->text;
      buf_free(&c);
    }
    buf_free(&b);
  }
  if (!r->text && !strcmp(kind, "submit")) r->text = (char *)"Submit";
  if (!r->text && !strcmp(kind, "reset")) r->text = (char *)"Reset";
}

static void layout_node(Layout *L, const Node *n, const Style *inherited, int *li_counter) {
  Style st = *inherited;
  const char *tag;
  if (n->type == NODE_TEXT) {
    if (st.display == 2) return;
    layout_text(L, n->text, &st);
    return;
  }
  if (n->type == NODE_DOCUMENT) {
    layout_children(L, n, &st);
    return;
  }
  tag = n->tag;
  st.display = 0;
  ui_style(tag, n, &st);
  if (st.display == 2) return;
  if (!strcmp(tag, "title")) return;
  if (!strcmp(tag, "base")) return;
  if (!strcmp(tag, "br")) {
    Block *blk = layout_cur(L);
    Run *r = block_add_run(L, blk);
    r->kind = RUN_BR;
    run_set_style(r, &st);
    return;
  }
  if (!strcmp(tag, "wbr")) return;
  if (!strcmp(tag, "img") || !strcmp(tag, "picture")) {
    const Node *img = n;
    Block *blk;
    Run *r;
    const char *src, *alt, *w, *h;
    if (!strcmp(tag, "picture")) {
      int i;
      img = 0;
      for (i = 0; i < n->nkids; i++) {
        if (n->kids[i]->type == NODE_ELEMENT && !strcmp(n->kids[i]->tag, "img")) {
          img = n->kids[i];
          break;
        }
      }
      if (!img) return;
    }
    src = node_attr(img, "src");
    if (!src || !*src) src = node_attr(img, "data-src");
    alt = node_attr(img, "alt");
    w = node_attr(img, "width");
    h = node_attr(img, "height");
    if ((!src || !*src) && (!alt || !*alt)) return;
    if (alt && !*alt) return; /* alt="" marks a decorative image */
    blk = layout_cur(L);
    r = block_add_run(L, blk);
    r->kind = RUN_IMAGE;
    run_set_style(r, &st);
    r->src = src && *src && strncmp(src, "data:", 5) ? layout_abs_url(L, src) : 0;
    r->text = alt ? arena_strdup(&L->arena, alt) : 0;
    r->width = w ? atoi(w) : 0;
    r->height = h ? atoi(h) : 0;
    return;
  }
  if (!strcmp(tag, "input")) {
    const char *t = node_attr(n, "type");
    char kind[32];
    size_t i;
    if (!t || !*t) t = "text";
    for (i = 0; t[i] && i < sizeof(kind) - 1; i++) kind[i] = (char)tolower((unsigned char)t[i]);
    kind[i] = 0;
    if (!strcmp(kind, "image")) {
      strcpy(kind, "submit");
    }
    if (!strcmp(kind, "hidden")) {
      layout_control(L, n, &st, "hidden");
      return;
    }
    if (strcmp(kind, "submit") && strcmp(kind, "button") && strcmp(kind, "reset") &&
        strcmp(kind, "checkbox") && strcmp(kind, "radio") && strcmp(kind, "password") &&
        strcmp(kind, "search") && strcmp(kind, "email") && strcmp(kind, "url") &&
        strcmp(kind, "tel") && strcmp(kind, "number") && strcmp(kind, "file") &&
        strcmp(kind, "date") && strcmp(kind, "range") && strcmp(kind, "color"))
      strcpy(kind, "text");
    layout_control(L, n, &st, kind);
    return;
  }
  if (!strcmp(tag, "button")) {
    const char *t = node_attr(n, "type");
    layout_control(L, n, &st, t && !mb_strcasecmp(t, "button") ? "button" : "submit");
    return;
  }
  if (!strcmp(tag, "select")) {
    layout_control(L, n, &st, "select");
    return;
  }
  if (!strcmp(tag, "textarea")) {
    layout_control(L, n, &st, "textarea");
    return;
  }
  if (!strcmp(tag, "a")) {
    const char *href = node_attr(n, "href");
    if (href && *href && mb_strncasecmp(href, "javascript:", 11)) st.href = layout_abs_url(L, href);
    layout_children(L, n, &st);
    return;
  }
  if (!strcmp(tag, "q")) {
    layout_text(L, "\xe2\x80\x9c", &st);
    layout_children(L, n, &st);
    layout_text(L, "\xe2\x80\x9d", &st);
    return;
  }
  if (!strcmp(tag, "td") || !strcmp(tag, "th")) {
    /* cells are laid inline, separated by a gap, so simple rows stay rows */
    Block *blk;
    if (L->cur && L->cur->nruns) {
      blk = L->cur;
      {
        Run *last = &blk->runs[blk->nruns - 1];
        if (last->kind == RUN_TEXT) {
          size_t len = strlen(last->text);
          char *nt = (char *)arena_alloc(&L->arena, len + 4);
          memcpy(nt, last->text, len);
          memcpy(nt + len, "\xc2\xa0 ", 4); /* nbsp + space */
          last->text = nt;
        } else if (last->kind != RUN_BR) {
          Run *sep = block_add_run(L, blk);
          sep->kind = RUN_TEXT;
          run_set_style(sep, &st);
          sep->href = 0;
          sep->text = arena_strdup(&L->arena, "\xc2\xa0 ");
        }
      }
    }
    layout_children(L, n, &st);
    return;
  }
  if (st.display == 1 || st.display == 3) {
    int indent = 0, margin = 0;
    int is_li = st.display == 3;
    if (!strcmp(tag, "form")) st.form = add_form(L, n);
    if (!strcmp(tag, "p") || !strcmp(tag, "ul") || !strcmp(tag, "ol") ||
        !strcmp(tag, "dl") || !strcmp(tag, "pre") || !strcmp(tag, "blockquote") ||
        !strcmp(tag, "table") || !strcmp(tag, "figure") || !strcmp(tag, "fieldset") ||
        !strcmp(tag, "hr") || !strcmp(tag, "form") || !strcmp(tag, "address"))
      margin = 16;
    if (tag[0] == 'h' && tag[1] >= '1' && tag[1] <= '6' && !tag[2]) {
      static const int hm[6] = {21, 20, 19, 21, 22, 25};
      margin = hm[tag[1] - '1'];
    }
    if (!strcmp(tag, "ul") || !strcmp(tag, "ol") || !strcmp(tag, "menu") ||
        !strcmp(tag, "dir")) {
      indent = 24;
      /* nested lists keep list margin small */
      if (L->depth > 1 && L->ctx[L->depth - 1].tag &&
          !strcmp(L->ctx[L->depth - 1].tag, "li"))
        margin = 0;
    }
    if (!strcmp(tag, "blockquote") || !strcmp(tag, "dd") || !strcmp(tag, "figure"))
      indent = 40;
    if (!strcmp(tag, "li")) indent = 0;
    layout_push_ctx(L, tag, indent, margin, &st);
    if (!strcmp(tag, "blockquote")) L->ctx[L->depth - 1].quote = 1;
    if (!strcmp(tag, "hr")) {
      Block *b = layout_new_block(L);
      b->hr = 1;
      layout_flush(L);
      layout_pop_ctx(L);
      return;
    }
    if (is_li) {
      char m[32];
      const Node *parent = n->parent;
      int ordered = parent && parent->type == NODE_ELEMENT && !strcmp(parent->tag, "ol");
      if (ordered) {
        int start = 1;
        const char *sv = node_attr(parent, "start");
        const char *vv = node_attr(n, "value");
        if (sv) start = atoi(sv);
        if (vv) *li_counter = atoi(vv) - start;
        snprintf(m, sizeof(m), "%d.", start + (*li_counter)++);
      } else {
        snprintf(m, sizeof(m), "\xe2\x80\xa2");
        (*li_counter)++;
      }
      L->ctx[L->depth - 1].marker = arena_strdup(&L->arena, m);
      {
        int before = L->nblocks;
        layout_children(L, n, &st);
        if (L->ctx[L->depth - 1].marker && L->nblocks == before) {
          /* empty <li>: keep a block so the bullet still shows */
          layout_new_block(L);
        }
      }
      layout_pop_ctx(L);
      return;
    }
    layout_children(L, n, &st);
    layout_pop_ctx(L);
    return;
  }
  /* inline element */
  layout_children(L, n, &st);
}

static void find_meta(Layout *L, const Node *n) {
  int i;
  if (n->type == NODE_ELEMENT) {
    if (!strcmp(n->tag, "title") && !L->title) {
      Buf b = {0};
      Buf c = {0};
      const char *p;
      int sp = 1;
      node_text_content(n, &b);
      for (p = b.p ? b.p : ""; *p; p++) {
        if (mb_isspace((unsigned char)*p)) {
          if (!sp) buf_putc(&c, ' ');
          sp = 1;
        } else {
          buf_putc(&c, *p);
          sp = 0;
        }
      }
      while (c.n && c.p[c.n - 1] == ' ') c.p[--c.n] = 0;
      L->title = arena_strdup(&L->arena, c.p ? c.p : "");
      buf_free(&b);
      buf_free(&c);
    } else if (!strcmp(n->tag, "base")) {
      const char *href = node_attr(n, "href");
      if (href && *href) L->base = layout_abs_url(L, href);
    }
  }
  for (i = 0; i < n->nkids; i++) find_meta(L, n->kids[i]);
}

static Layout *mb_layout(Doc *doc, const char *base_url) {
  Layout *L = (Layout *)calloc(1, sizeof(Layout));
  Style st = {0};
  Ctx root = {0};
  int li = 0;
  if (!L) abort();
  L->doc = doc;
  L->base = arena_strdup(&L->arena, base_url ? base_url : "");
  find_meta(L, doc->root);
  st.size = 16;
  st.color = -1;
  st.bg = -1;
  st.form = -1;
  root.tag = "document";
  root.bg = -1;
  L->capctx = 32;
  L->ctx = (Ctx *)arena_alloc(&L->arena, sizeof(Ctx) * 32);
  L->ctx[0] = root;
  L->depth = 1;
  layout_node(L, doc->root, &st, &li);
  layout_flush(L);
  return L;
}

static void mb_layout_free(Layout *L) {
  if (!L) return;
  arena_free(&L->arena);
  free(L);
}

/*───────────────────────────────────────────────────────────────────────────│─╗
│ json output                                                              ─╬─│
╚────────────────────────────────────────────────────────────────────────────│*/

static void json_str(Buf *b, const char *s) {
  const unsigned char *p = (const unsigned char *)s;
  if (!s) {
    buf_puts(b, "null");
    return;
  }
  buf_putc(b, '"');
  while (*p) {
    unsigned c = *p;
    if (c == '"' || c == '\\') {
      buf_putc(b, '\\');
      buf_putc(b, (char)c);
      p++;
    } else if (c < 0x20) {
      if (c == '\n') buf_puts(b, "\\n");
      else if (c == '\t') buf_puts(b, "\\t");
      else if (c == '\r') buf_puts(b, "\\r");
      else buf_printf(b, "\\u%04x", c);
      p++;
    } else if (c < 0x80) {
      buf_putc(b, (char)c);
      p++;
    } else {
      /* validate the UTF-8 sequence; replace junk with U+FFFD */
      int len = c >= 0xF0 ? 4 : c >= 0xE0 ? 3 : c >= 0xC0 ? 2 : 0;
      int ok = len > 0, k;
      for (k = 1; ok && k < len; k++) {
        if ((p[k] & 0xC0) != 0x80) ok = 0;
      }
      if (ok) {
        buf_append(b, (const char *)p, (size_t)len);
        p += len;
      } else {
        buf_puts(b, "\xef\xbf\xbd");
        p++;
      }
    }
  }
  buf_putc(b, '"');
}

static void json_color(Buf *b, int c) {
  if (c < 0) {
    buf_puts(b, "null");
  } else {
    buf_printf(b, "\"#%06x\"", c & 0xFFFFFF);
  }
}

static char *mb_layout_to_json(const Layout *L) {
  Buf b = {0};
  int i, j;
  buf_puts(&b, "{\"engine\":\"minibrowser/" MB_VERSION "\",\"title\":");
  json_str(&b, L->title ? L->title : "");
  buf_puts(&b, ",\"base\":");
  json_str(&b, L->base);
  buf_puts(&b, ",\"forms\":[");
  for (i = 0; i < L->nforms; i++) {
    if (i) buf_putc(&b, ',');
    buf_puts(&b, "{\"action\":");
    json_str(&b, L->forms[i].action);
    buf_puts(&b, ",\"method\":");
    json_str(&b, L->forms[i].method);
    buf_putc(&b, '}');
  }
  buf_puts(&b, "],\"blocks\":[");
  for (i = 0; i < L->nblocks; i++) {
    const Block *blk = &L->blocks[i];
    if (i) buf_putc(&b, ',');
    buf_puts(&b, "{\"tag\":");
    json_str(&b, blk->tag ? blk->tag : "div");
    buf_printf(&b, ",\"indent\":%d,\"mt\":%d,\"mb\":%d,\"align\":%d", blk->indent,
               blk->margin_top, blk->margin_bottom, blk->align);
    if (blk->pre) buf_puts(&b, ",\"pre\":true");
    if (blk->hr) buf_puts(&b, ",\"hr\":true");
    if (blk->quote) buf_puts(&b, ",\"quote\":true");
    if (blk->bg >= 0) {
      buf_puts(&b, ",\"bg\":");
      json_color(&b, blk->bg);
    }
    if (blk->marker) {
      buf_puts(&b, ",\"marker\":");
      json_str(&b, blk->marker);
    }
    buf_puts(&b, ",\"runs\":[");
    for (j = 0; j < blk->nruns; j++) {
      const Run *r = &blk->runs[j];
      if (j) buf_putc(&b, ',');
      if (r->kind == RUN_BR) {
        buf_puts(&b, "{\"br\":true}");
        continue;
      }
      buf_putc(&b, '{');
      if (r->kind == RUN_IMAGE) {
        buf_puts(&b, "\"img\":");
        json_str(&b, r->src);
        buf_puts(&b, ",\"alt\":");
        json_str(&b, r->text ? r->text : "");
        buf_printf(&b, ",\"w\":%d,\"h\":%d", r->width, r->height);
      } else if (r->kind == RUN_CONTROL) {
        buf_puts(&b, "\"ctl\":");
        json_str(&b, r->ctl);
        buf_puts(&b, ",\"name\":");
        json_str(&b, r->name);
        buf_puts(&b, ",\"value\":");
        json_str(&b, r->value);
        buf_puts(&b, ",\"label\":");
        json_str(&b, r->text);
        buf_puts(&b, ",\"placeholder\":");
        json_str(&b, r->placeholder);
        buf_printf(&b, ",\"form\":%d", r->form);
      } else {
        buf_puts(&b, "\"t\":");
        json_str(&b, r->text);
      }
      if (r->href) {
        buf_puts(&b, ",\"href\":");
        json_str(&b, r->href);
      }
      if (r->bold) buf_puts(&b, ",\"b\":1");
      if (r->italic) buf_puts(&b, ",\"i\":1");
      if (r->underline) buf_puts(&b, ",\"u\":1");
      if (r->strike) buf_puts(&b, ",\"s\":1");
      if (r->mono) buf_puts(&b, ",\"mono\":1");
      buf_printf(&b, ",\"size\":%d", r->size);
      if (r->color >= 0) {
        buf_puts(&b, ",\"color\":");
        json_color(&b, r->color);
      }
      if (r->bg >= 0) {
        buf_puts(&b, ",\"bg\":");
        json_color(&b, r->bg);
      }
      buf_putc(&b, '}');
    }
    buf_puts(&b, "]}");
  }
  buf_puts(&b, "]}");
  return b.p;
}

/*───────────────────────────────────────────────────────────────────────────│─╗
│ plain text renderer                                                      ─╬─│
╚────────────────────────────────────────────────────────────────────────────│*/

typedef struct TextOut {
  Buf out;
  Buf line;
  int width, col, indent;
  int nlinks;
  Buf links;
  int show_links;
  int glue; /* last emitted text did not end in whitespace */
} TextOut;

static int utf8_cols(const char *s, size_t n) {
  int cols = 0;
  size_t i;
  for (i = 0; i < n; i++) {
    if (((unsigned char)s[i] & 0xC0) != 0x80) cols++;
  }
  return cols;
}

static void text_newline(TextOut *t) {
  size_t n = t->line.n;
  while (n && t->line.p[n - 1] == ' ') n--;
  if (t->line.p) buf_append(&t->out, t->line.p, n);
  buf_putc(&t->out, '\n');
  t->line.n = 0;
  if (t->line.p) t->line.p[0] = 0;
  t->col = 0;
}

static void text_word(TextOut *t, const char *w, size_t n, int glue) {
  int wc = utf8_cols(w, n);
  if (t->col == 0) {
    int i;
    for (i = 0; i < t->indent; i++) buf_putc(&t->line, ' ');
    t->col = t->indent;
  } else if (glue && t->col + wc <= t->width) {
    /* attach directly to the previous word */
  } else if (t->col + 1 + wc > t->width) {
    int i;
    text_newline(t);
    for (i = 0; i < t->indent; i++) buf_putc(&t->line, ' ');
    t->col = t->indent;
  } else {
    buf_putc(&t->line, ' ');
    t->col++;
  }
  buf_append(&t->line, w, n);
  t->col += wc;
}

static void text_words(TextOut *t, const char *s, int glue) {
  const char *p = s;
  if (*p == ' ') glue = 0;
  while (*p) {
    const char *ws;
    while (*p == ' ') p++;
    if (!*p) break;
    ws = p;
    while (*p && *p != ' ') p++;
    text_word(t, ws, (size_t)(p - ws), glue);
    glue = 0;
  }
  t->glue = s[0] && s[strlen(s) - 1] != ' ';
}

static char *mb_layout_to_text(const Layout *L, int width, int show_links) {
  TextOut t = {0};
  int i, j, prev_gap = 1;
  t.width = width > 20 ? width : 20;
  t.show_links = show_links;
  if (L->title && *L->title) {
    buf_puts(&t.out, L->title);
    buf_puts(&t.out, "\n");
    for (i = 0; i < utf8_cols(L->title, strlen(L->title)) && i < t.width; i++) buf_putc(&t.out, '=');
    buf_puts(&t.out, "\n\n");
  }
  for (i = 0; i < L->nblocks; i++) {
    const Block *b = &L->blocks[i];
    int indent = b->indent / 8;
    if ((b->margin_top > 0 || (i && L->blocks[i - 1].margin_bottom > 0)) && !prev_gap) {
      buf_putc(&t.out, '\n');
      prev_gap = 1;
    }
    t.indent = indent;
    t.col = 0;
    t.glue = 0;
    if (b->hr) {
      for (j = 0; j < t.width && j < 72; j++) buf_putc(&t.out, '-');
      buf_putc(&t.out, '\n');
      prev_gap = 0;
      continue;
    }
    if (b->quote) {
      text_word(&t, ">", 1, 0);
    }
    if (b->marker) {
      text_word(&t, b->marker, strlen(b->marker), 0);
    }
    for (j = 0; j < b->nruns; j++) {
      const Run *r = &b->runs[j];
      if (r->kind == RUN_BR) {
        text_newline(&t);
        t.glue = 0;
      } else if (r->kind == RUN_IMAGE) {
        Buf tmp = {0};
        buf_printf(&tmp, "[image%s%s]", r->text && *r->text ? ": " : "", r->text ? r->text : "");
        text_words(&t, tmp.p, 0);
        t.glue = 0;
        buf_free(&tmp);
      } else if (r->kind == RUN_CONTROL && !strcmp(r->ctl, "hidden")) {
        /* invisible */
      } else if (r->kind == RUN_CONTROL) {
        Buf tmp = {0};
        if (!strcmp(r->ctl, "submit") || !strcmp(r->ctl, "button") || !strcmp(r->ctl, "reset")) {
          buf_printf(&tmp, "[%s]", r->text ? r->text : "button");
        } else if (!strcmp(r->ctl, "checkbox") || !strcmp(r->ctl, "radio")) {
          buf_printf(&tmp, "[%s]", r->value && !strcmp(r->value, "on") ? "x" : " ");
        } else if (!strcmp(r->ctl, "select")) {
          buf_printf(&tmp, "[%s v]", r->text ? r->text : "");
        } else {
          buf_printf(&tmp, "[%s: %s]", r->ctl, r->placeholder ? r->placeholder
                                                : r->value ? r->value
                                                : r->name ? r->name : "");
        }
        text_words(&t, tmp.p, 0);
        t.glue = 0;
        buf_free(&tmp);
      } else if (b->pre) {
        if (t.col == 0) {
          int k;
          for (k = 0; k < t.indent; k++) buf_putc(&t.line, ' ');
          t.col = t.indent;
        }
        buf_puts(&t.line, r->text);
        t.col += utf8_cols(r->text, strlen(r->text));
      } else {
        text_words(&t, r->text, t.glue);
        if (r->href && show_links) {
          Buf tmp = {0};
          /* only number the first run of a link */
          if (j == 0 || !b->runs[j - 1].href || strcmp(b->runs[j - 1].href, r->href)) {
            t.nlinks++;
            buf_printf(&tmp, "[%d]", t.nlinks);
            buf_printf(&t.links, "%4d. %s\n", t.nlinks, r->href);
            /* glue to the previous word */
            buf_append(&t.line, tmp.p, tmp.n);
            t.col += (int)tmp.n;
          }
          buf_free(&tmp);
        }
      }
    }
    if (t.col > 0 || t.line.n) text_newline(&t);
    prev_gap = 0;
  }
  if (show_links && t.nlinks) {
    buf_puts(&t.out, "\nLinks:\n");
    buf_append(&t.out, t.links.p, t.links.n);
  }
  buf_free(&t.line);
  buf_free(&t.links);
  return t.out.p ? t.out.p : mb_strdup("");
}

/*───────────────────────────────────────────────────────────────────────────│─╗
│ http client                                                              ─╬─│
╚────────────────────────────────────────────────────────────────────────────│*/

typedef struct Url {
  char scheme[16];
  char host[256];
  char port[8];
  char *path; /* includes query */
} Url;

static int url_parse(const char *url, Url *u) {
  const char *p, *h, *he, *pe;
  size_t n;
  memset(u, 0, sizeof(*u));
  p = strchr(url, ':');
  if (!p || p - url >= (long)sizeof(u->scheme) - 1 || p[1] != '/' || p[2] != '/') return -1;
  n = (size_t)(p - url);
  memcpy(u->scheme, url, n);
  u->scheme[n] = 0;
  {
    size_t i;
    for (i = 0; i < n; i++) u->scheme[i] = (char)tolower((unsigned char)u->scheme[i]);
  }
  h = p + 3;
  he = h;
  while (*he && *he != '/' && *he != '?' && *he != '#' && *he != ':') he++;
  n = (size_t)(he - h);
  if (!n || n >= sizeof(u->host) - 1) return -1;
  memcpy(u->host, h, n);
  u->host[n] = 0;
  pe = he;
  if (*pe == ':') {
    const char *ps = ++pe;
    while (isdigit((unsigned char)*pe)) pe++;
    n = (size_t)(pe - ps);
    if (!n || n >= sizeof(u->port)) return -1;
    memcpy(u->port, ps, n);
    u->port[n] = 0;
  } else {
    strcpy(u->port, !strcmp(u->scheme, "https") ? "443" : "80");
  }
  {
    const char *frag = strchr(pe, '#');
    size_t plen = frag ? (size_t)(frag - pe) : strlen(pe);
    u->path = (char *)malloc(plen + 2);
    if (!u->path) return -1;
    if (!plen || *pe == '?') {
      u->path[0] = '/';
      memcpy(u->path + 1, pe, plen);
      u->path[plen + 1] = 0;
    } else {
      memcpy(u->path, pe, plen);
      u->path[plen] = 0;
    }
  }
  return 0;
}

typedef struct Conn {
  mb_sock_t fd;
#ifdef MB_TLS_OPENSSL
  SSL_CTX *ctx;
  SSL *ssl;
#endif
} Conn;

static int conn_write(Conn *c, const char *p, size_t n) {
  while (n) {
    long w;
#ifdef MB_TLS_OPENSSL
    if (c->ssl) {
      w = SSL_write(c->ssl, p, (int)n);
    } else
#endif
    {
      w = (long)send(c->fd, p, (int)n, 0);
    }
    if (w <= 0) return -1;
    p += w;
    n -= (size_t)w;
  }
  return 0;
}

static long conn_read(Conn *c, char *p, size_t n) {
#ifdef MB_TLS_OPENSSL
  if (c->ssl) {
    int r = SSL_read(c->ssl, p, (int)n);
    return r <= 0 ? 0 : r;
  }
#endif
  {
    long r = (long)recv(c->fd, p, (int)n, 0);
    return r < 0 ? 0 : r;
  }
}

static void conn_close(Conn *c) {
#ifdef MB_TLS_OPENSSL
  if (c->ssl) {
    SSL_shutdown(c->ssl);
    SSL_free(c->ssl);
  }
  if (c->ctx) SSL_CTX_free(c->ctx);
#endif
  if (c->fd != MB_BAD_SOCK) mb_closesock(c->fd);
}

static void net_init(void) {
#ifdef _WIN32
  static int done;
  if (!done) {
    WSADATA wsa;
    WSAStartup(MAKEWORD(2, 2), &wsa);
    done = 1;
  }
#endif
}

static int conn_open(Conn *c, const Url *u, char **err) {
  struct addrinfo hints, *res = 0, *ai;
  int rc;
  memset(c, 0, sizeof(*c));
  c->fd = MB_BAD_SOCK;
  net_init();
  memset(&hints, 0, sizeof(hints));
  hints.ai_family = AF_UNSPEC;
  hints.ai_socktype = SOCK_STREAM;
  rc = getaddrinfo(u->host, u->port, &hints, &res);
  if (rc) {
    Buf b = {0};
    buf_printf(&b, "could not resolve %s: %s", u->host, gai_strerror(rc));
    *err = b.p;
    return -1;
  }
  for (ai = res; ai; ai = ai->ai_next) {
    c->fd = socket(ai->ai_family, ai->ai_socktype, ai->ai_protocol);
    if (c->fd == MB_BAD_SOCK) continue;
    if (connect(c->fd, ai->ai_addr, (int)ai->ai_addrlen) == 0) break;
    mb_closesock(c->fd);
    c->fd = MB_BAD_SOCK;
  }
  freeaddrinfo(res);
  if (c->fd == MB_BAD_SOCK) {
    Buf b = {0};
    buf_printf(&b, "could not connect to %s:%s", u->host, u->port);
    *err = b.p;
    return -1;
  }
  if (!strcmp(u->scheme, "https")) {
#ifdef MB_TLS_OPENSSL
    static int inited;
    if (!inited) {
      SSL_library_init();
      SSL_load_error_strings();
      inited = 1;
    }
    c->ctx = SSL_CTX_new(TLS_client_method());
    if (!c->ctx) {
      *err = mb_strdup("SSL_CTX_new failed");
      conn_close(c);
      return -1;
    }
    SSL_CTX_set_default_verify_paths(c->ctx);
    SSL_CTX_set_verify(c->ctx, SSL_VERIFY_PEER, 0);
    c->ssl = SSL_new(c->ctx);
    SSL_set_tlsext_host_name(c->ssl, u->host);
    SSL_set1_host(c->ssl, u->host);
    SSL_set_fd(c->ssl, (int)c->fd);
    if (SSL_connect(c->ssl) != 1) {
      Buf b = {0};
      unsigned long e = ERR_get_error();
      buf_printf(&b, "TLS handshake with %s failed: %s", u->host,
                 e ? ERR_reason_error_string(e) : "unknown error");
      *err = b.p;
      conn_close(c);
      return -1;
    }
#else
    *err = mb_strdup("https:// needs a TLS build (make TLS=openssl); "
                  "the Flutter shell fetches https itself");
    conn_close(c);
    return -1;
#endif
  }
  return 0;
}

/* Reads one HTTP response; returns body (malloc'd) and status; headers in hdrs. */
static char *http_read_response(Conn *c, int *status, Buf *hdrs, size_t *bodylen, char **err) {
  Buf raw = {0};
  char tmp[16384];
  long r;
  size_t hend = 0;
  const char *body;
  int chunked = 0;
  long content_length = -1;
  while ((r = conn_read(c, tmp, sizeof(tmp))) > 0) {
    buf_append(&raw, tmp, (size_t)r);
    if (!hend) {
      char *p = strstr(raw.p, "\r\n\r\n");
      if (p) {
        hend = (size_t)(p - raw.p) + 4;
        /* parse status + headers */
        {
          char *line = raw.p, *nl;
          *status = 0;
          if (!strncmp(line, "HTTP/", 5)) {
            const char *sp = strchr(line, ' ');
            if (sp) *status = atoi(sp + 1);
          }
          buf_append(hdrs, raw.p, hend);
          while ((nl = strstr(line, "\r\n")) && (size_t)(nl - raw.p) < hend) {
            if (!mb_strncasecmp(line, "Transfer-Encoding:", 18) &&
                strstr(line, "chunked"))
              chunked = 1;
            if (!mb_strncasecmp(line, "Content-Length:", 15))
              content_length = atol(line + 15);
            line = nl + 2;
          }
        }
        if (content_length >= 0 && !chunked && raw.n - hend >= (size_t)content_length) break;
      }
    } else if (content_length >= 0 && !chunked && raw.n - hend >= (size_t)content_length) {
      break;
    } else if (chunked && raw.n >= hend + 5 && !memcmp(raw.p + raw.n - 5, "0\r\n\r\n", 5)) {
      break;
    }
    if (raw.n > 64u * 1024 * 1024) break;
  }
  if (!hend) {
    *err = mb_strdup(raw.n ? "malformed HTTP response" : "empty response from server");
    buf_free(&raw);
    return 0;
  }
  body = raw.p + hend;
  if (chunked) {
    Buf out = {0};
    const char *p = body, *end = raw.p + raw.n;
    while (p < end) {
      char *e;
      long len = strtol(p, &e, 16);
      if (e == p || len < 0) break;
      p = strstr(e, "\r\n");
      if (!p) break;
      p += 2;
      if (len == 0) break;
      if (p + len > end) len = (long)(end - p);
      buf_append(&out, p, (size_t)len);
      p += len;
      if (p + 2 <= end && p[0] == '\r' && p[1] == '\n') p += 2;
    }
    buf_free(&raw);
    *bodylen = out.n;
    return out.p ? out.p : mb_strdup("");
  } else {
    size_t n = raw.n - hend;
    char *out = (char *)malloc(n + 1);
    if (!out) abort();
    memcpy(out, body, n);
    out[n] = 0;
    buf_free(&raw);
    *bodylen = n;
    return out;
  }
}

static char *header_value(const Buf *hdrs, const char *name) {
  const char *line = hdrs->p;
  size_t nl = strlen(name);
  if (!line) return 0;
  while (line && *line) {
    const char *end = strstr(line, "\r\n");
    if (!end) break;
    if (!mb_strncasecmp(line, name, nl) && line[nl] == ':') {
      const char *v = line + nl + 1;
      while (v < end && mb_isspace(*v)) v++;
      return mb_strndup(v, (size_t)(end - v));
    }
    line = end + 2;
  }
  return 0;
}

/*
 * Fetches a URL over HTTP(S) following up to 10 redirects.
 * Returns a malloc'd body or NULL (with *err set).
 */
static char *mb_fetch_impl(const char *url, size_t *outlen, int *status, char **final_url,
                           char **content_type, char **err) {
  char *cur = mb_strdup(url);
  int hops;
  *err = 0;
  *outlen = 0;
  *status = 0;
  if (final_url) *final_url = 0;
  if (content_type) *content_type = 0;
  for (hops = 0; hops < 10; hops++) {
    Url u;
    Conn c;
    Buf req = {0}, hdrs = {0};
    char *body, *loc;
    size_t blen = 0;
    if (url_parse(cur, &u)) {
      Buf b = {0};
      buf_printf(&b, "unsupported or malformed url: %s", cur);
      *err = b.p;
      free(cur);
      return 0;
    }
    if (strcmp(u.scheme, "http") && strcmp(u.scheme, "https")) {
      Buf b = {0};
      buf_printf(&b, "unsupported scheme: %s", u.scheme);
      *err = b.p;
      free(u.path);
      free(cur);
      return 0;
    }
    if (conn_open(&c, &u, err)) {
      free(u.path);
      free(cur);
      return 0;
    }
    buf_printf(&req,
               "GET %s HTTP/1.1\r\n"
               "Host: %s%s%s\r\n"
               "User-Agent: Mozilla/5.0 (compatible; minibrowser/" MB_VERSION ")\r\n"
               "Accept: text/html,application/xhtml+xml,*/*;q=0.8\r\n"
               "Accept-Language: en\r\n"
               "Accept-Encoding: identity\r\n"
               "Connection: close\r\n\r\n",
               u.path, u.host,
               (!strcmp(u.port, "80") && !strcmp(u.scheme, "http")) ||
                       (!strcmp(u.port, "443") && !strcmp(u.scheme, "https"))
                   ? ""
                   : ":",
               (!strcmp(u.port, "80") && !strcmp(u.scheme, "http")) ||
                       (!strcmp(u.port, "443") && !strcmp(u.scheme, "https"))
                   ? ""
                   : u.port);
    if (conn_write(&c, req.p, req.n)) {
      *err = mb_strdup("failed to send request");
      buf_free(&req);
      conn_close(&c);
      free(u.path);
      free(cur);
      return 0;
    }
    buf_free(&req);
    body = http_read_response(&c, status, &hdrs, &blen, err);
    conn_close(&c);
    free(u.path);
    if (!body) {
      buf_free(&hdrs);
      free(cur);
      return 0;
    }
    loc = header_value(&hdrs, "Location");
    if ((*status == 301 || *status == 302 || *status == 303 || *status == 307 ||
         *status == 308) &&
        loc && *loc) {
      char *next = url_resolve(cur, loc);
      free(loc);
      free(body);
      buf_free(&hdrs);
      free(cur);
      cur = next;
      continue;
    }
    free(loc);
    if (content_type) *content_type = header_value(&hdrs, "Content-Type");
    buf_free(&hdrs);
    if (final_url) {
      *final_url = cur;
    } else {
      free(cur);
    }
    *outlen = blen;
    return body;
  }
  {
    Buf b = {0};
    buf_printf(&b, "too many redirects (last: %s)", cur);
    *err = b.p;
  }
  free(cur);
  return 0;
}

/*───────────────────────────────────────────────────────────────────────────│─╗
│ public api (exported for dart:ffi)                                       ─╬─│
╚────────────────────────────────────────────────────────────────────────────│*/

MB_EXPORT const char *mb_version(void) {
  return MB_VERSION;
}

MB_EXPORT void mb_free(void *p) {
  free(p);
}

/*
 * Parses and lays out an HTML document, returning a JSON display list.
 * The caller owns the returned string and must release it with mb_free().
 */
MB_EXPORT char *mb_render_json(const char *html, size_t len, const char *base_url) {
  Doc *d = mb_parse(html, len);
  Layout *L = mb_layout(d, base_url);
  char *json = mb_layout_to_json(L);
  mb_layout_free(L);
  mb_doc_free(d);
  return json;
}

/* Same as above but renders to wrapped plain text (lynx -dump style). */
MB_EXPORT char *mb_render_text(const char *html, size_t len, const char *base_url, int width,
                               int show_links) {
  Doc *d = mb_parse(html, len);
  Layout *L = mb_layout(d, base_url);
  char *text = mb_layout_to_text(L, width, show_links);
  mb_layout_free(L);
  mb_doc_free(d);
  return text;
}

/* Returns the <title> of a document (or "") as a malloc'd string. */
MB_EXPORT char *mb_title(const char *html, size_t len) {
  Doc *d = mb_parse(html, len);
  Layout *L = mb_layout(d, "");
  char *t = mb_strdup(L->title ? L->title : "");
  mb_layout_free(L);
  mb_doc_free(d);
  return t;
}

/* Resolves a possibly relative URL against a base; malloc'd result. */
MB_EXPORT char *mb_resolve_url(const char *base, const char *ref) {
  return url_resolve(base ? base : "", ref ? ref : "");
}

/*
 * Fetches a URL. On success returns the body (caller frees with mb_free)
 * and fills *outlen, *status, *final_url, *content_type (each malloc'd or
 * NULL). On failure returns NULL and sets *err (malloc'd).
 */
MB_EXPORT char *mb_fetch(const char *url, size_t *outlen, int *status, char **final_url,
                         char **content_type, char **err) {
  return mb_fetch_impl(url, outlen, status, final_url, content_type, err);
}

/*───────────────────────────────────────────────────────────────────────────│─╗
│ command line interface                                                   ─╬─│
╚────────────────────────────────────────────────────────────────────────────│*/

#ifndef MB_NO_MAIN

static char *read_file(const char *path, size_t *n) {
  FILE *f = strcmp(path, "-") ? fopen(path, "rb") : stdin;
  Buf b = {0};
  char tmp[65536];
  size_t r;
  if (!f) return 0;
  while ((r = fread(tmp, 1, sizeof(tmp), f)) > 0) buf_append(&b, tmp, r);
  if (f != stdin) fclose(f);
  *n = b.n;
  return b.p ? b.p : mb_strdup("");
}

static void usage(FILE *f) {
  fprintf(f,
          "usage: minibrowser [-t|-j|-T] [-w COLS] [-l] [-b BASE] URL|FILE|-\n"
          "\n"
          "  -t   render as plain text (default)\n"
          "  -j   render as a JSON display list (what the Flutter shell uses)\n"
          "  -T   print only the page title\n"
          "  -l   number links and list them at the end (text mode)\n"
          "  -w   text width in columns (default 80)\n"
          "  -b   base url for resolving links when reading a file\n"
          "  -v   print version\n"
          "\n"
          "minibrowser/" MB_VERSION " - a tiny portable web engine\n");
}

int main(int argc, char **argv) {
  int mode = 't', width = 80, links = 0, i;
  const char *base = 0, *src = 0;
  char *html = 0, *out, *err = 0, *final_url = 0, *ctype = 0;
  size_t len = 0;
  int status = 0;
  for (i = 1; i < argc; i++) {
    const char *a = argv[i];
    if (!strcmp(a, "-t") || !strcmp(a, "--text")) mode = 't';
    else if (!strcmp(a, "-j") || !strcmp(a, "--json")) mode = 'j';
    else if (!strcmp(a, "-T") || !strcmp(a, "--title")) mode = 'T';
    else if (!strcmp(a, "-l") || !strcmp(a, "--links")) links = 1;
    else if (!strcmp(a, "-w") && i + 1 < argc) width = atoi(argv[++i]);
    else if (!strcmp(a, "-b") && i + 1 < argc) base = argv[++i];
    else if (!strcmp(a, "-v") || !strcmp(a, "--version")) {
      printf("minibrowser %s\n", MB_VERSION);
      return 0;
    } else if (!strcmp(a, "-h") || !strcmp(a, "--help")) {
      usage(stdout);
      return 0;
    } else if (a[0] == '-' && a[1]) {
      usage(stderr);
      return 2;
    } else {
      src = a;
    }
  }
  if (!src) {
    usage(stderr);
    return 2;
  }
  if (!strncmp(src, "http://", 7) || !strncmp(src, "https://", 8)) {
    html = mb_fetch(src, &len, &status, &final_url, &ctype, &err);
    if (!html) {
      fprintf(stderr, "minibrowser: %s: %s\n", src, err ? err : "fetch failed");
      free(err);
      return 1;
    }
    if (!base) base = final_url;
  } else {
    const char *path = src;
    if (!strncmp(src, "file://", 7)) path = src + 7;
    html = read_file(path, &len);
    if (!html) {
      fprintf(stderr, "minibrowser: %s: %s\n", src, strerror(errno));
      return 1;
    }
    if (!base) base = "";
  }
  if (mode == 'j') {
    out = mb_render_json(html, len, base);
  } else if (mode == 'T') {
    out = mb_title(html, len);
  } else {
    out = mb_render_text(html, len, base, width, links);
  }
  fputs(out, stdout);
  if (mode != 't' || (out[0] && out[strlen(out) - 1] != '\n')) fputc('\n', stdout);
  free(out);
  free(html);
  free(final_url);
  free(ctype);
  return status >= 400 ? 3 : 0;
}

#endif /* MB_NO_MAIN */
