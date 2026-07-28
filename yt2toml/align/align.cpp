#include "align.h"

#include <cinttypes>
#include <cstdio>

namespace {
constexpr int64_t kFsPerSecond = 1000000000000000LL; // 1e15
constexpr int64_t kFsPerMilli = 1000000000000LL;     // 1e12
}

extern "C" fs_instant align_from_millis(int64_t millis) {
    fs_instant t;
    int64_t sec = millis / 1000;
    int64_t rem = millis % 1000;
    if (rem < 0) { // keep the femto remainder non-negative
        sec -= 1;
        rem += 1000;
    }
    t.seconds = sec;
    t.femtos = rem * kFsPerMilli;
    return t;
}

extern "C" void align_interval(int64_t start_ms, int64_t dur_ms,
                               fs_instant *start, fs_instant *end) {
    if (dur_ms < 0) dur_ms = 0;
    *start = align_from_millis(start_ms);
    *end = align_from_millis(start_ms + dur_ms);
}

extern "C" int align_format(fs_instant t, char *buf) {
    // Normalize so femtos is in range before printing.
    int64_t carry = t.femtos / kFsPerSecond;
    t.seconds += carry;
    t.femtos -= carry * kFsPerSecond;
    if (t.femtos < 0) {
        t.seconds -= 1;
        t.femtos += kFsPerSecond;
    }
    return std::snprintf(buf, 40, "%" PRId64 ".%015" PRId64, t.seconds, t.femtos);
}
