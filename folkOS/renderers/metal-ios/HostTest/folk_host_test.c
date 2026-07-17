// folk_host_test.c — host-side (Linux/macOS) harness for the embedded
// folk engine. Lets us test the exact C+Jim+Tcl stack the iOS app
// ships, without Xcode:
//
//   cc -O2 -o folkboy-host HostTest/folk_host_test.c CSources/folk_jim.c \
//      -ICSources/include -IVendor
//   ./folkboy-host Engine/folk-engine.tcl program.folk
//   echo 'Wish $this is outlined green' | ./folkboy-host Engine/folk-engine.tcl -
//
// Prints the JSON frame to stdout.

#include "folk_jim.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static char *read_all(FILE *f) {
    size_t cap = 8192, len = 0;
    char *buf = malloc(cap);
    size_t n;
    while ((n = fread(buf + len, 1, cap - len - 1, f)) > 0) {
        len += n;
        if (cap - len < 2) { cap *= 2; buf = realloc(buf, cap); }
    }
    buf[len] = '\0';
    return buf;
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: %s <folk-engine.tcl> <program.folk|->\n", argv[0]);
        return 2;
    }

    FILE *ef = fopen(argv[1], "rb");
    if (!ef) { perror(argv[1]); return 2; }
    char *engine = read_all(ef);
    fclose(ef);

    char *program;
    if (strcmp(argv[2], "-") == 0) {
        program = read_all(stdin);
    } else {
        FILE *pf = fopen(argv[2], "rb");
        if (!pf) { perror(argv[2]); return 2; }
        program = read_all(pf);
        fclose(pf);
    }

    if (folk_init(engine) != 0) {
        fprintf(stderr, "folk_init failed: %s\n", folk_last_error());
        return 1;
    }
    puts(folk_eval_program(program));

    folk_teardown();
    free(engine);
    free(program);
    return 0;
}
