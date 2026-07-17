// folk_jim.h — C API around an embedded Jim Tcl interpreter running
// the folkOS mini folk engine (Engine/folk-engine.tcl).
//
// Thread-safety: none. Call everything from one thread (the app calls
// from the main actor).

#ifndef FOLK_JIM_H
#define FOLK_JIM_H

#ifdef __cplusplus
extern "C" {
#endif

// Create the interpreter and evaluate the engine source (the contents
// of folk-engine.tcl). Returns 0 on success, -1 on failure (see
// folk_last_error). Idempotent: subsequent calls are no-ops.
int folk_init(const char *engine_source);

// Evaluate a folk program and return the resulting frame as JSON:
//   {"ok":bool,"error":string|null,"statementCount":int,
//    "display":[{"op":"outline","color":"green","thickness":3}, ...]}
// The returned pointer is owned by folk_jim and valid until the next
// folk_eval_program / folk_teardown call. Never returns NULL after a
// successful folk_init.
const char *folk_eval_program(const char *program_code);

// Last initialization/eval error message ("" if none).
const char *folk_last_error(void);

// Destroy the interpreter (mostly for tests; apps can skip this).
void folk_teardown(void);

#ifdef __cplusplus
}
#endif

#endif // FOLK_JIM_H
