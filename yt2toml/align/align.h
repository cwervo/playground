#ifndef YT2TOML_ALIGN_H
#define YT2TOML_ALIGN_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* A time instant carried at femtosecond resolution without overflow:
 * whole seconds plus a femtosecond remainder in [0, 1e15). */
typedef struct {
    int64_t seconds;
    int64_t femtos; /* 0 <= femtos < 1_000_000_000_000_000 */
} fs_instant;

/* Convert a millisecond offset (as reported by YouTube timedtext)
 * into an exact femtosecond instant. */
fs_instant align_from_millis(int64_t millis);

/* Snap an interval [start_ms, start_ms+dur_ms) to femtosecond fixed-point
 * and guarantee end >= start even for zero/negative durations. */
void align_interval(int64_t start_ms, int64_t dur_ms,
                    fs_instant *start, fs_instant *end);

/* Render an fs_instant as a decimal string "S.FFFFFFFFFFFFFFF"
 * (15 fractional digits) into buf; returns chars written (excl. NUL).
 * buf must hold at least 40 bytes. */
int align_format(fs_instant t, char *buf);

#ifdef __cplusplus
}
#endif

#endif
