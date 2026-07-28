// Package align is the Go↔C++ FFI boundary for femtosecond fixed-point
// timestamp alignment of transcript cues. The arithmetic lives in align.cpp
// and is called through cgo.
//
// Honesty note: YouTube timedtext reports cue times in milliseconds, so the
// femtosecond fields carry exact fixed-point representations of millisecond
// measurements — the encoding is femtosecond-resolution, the underlying
// measurement is not.
package align

/*
#cgo CXXFLAGS: -std=c++17 -O2
#include "align.h"
#include <stdlib.h>
*/
import "C"

// Instant is a femtosecond fixed-point time: Seconds + Femtos/1e15 seconds.
type Instant struct {
	Seconds int64 `toml:"seconds"`
	Femtos  int64 `toml:"femtoseconds"`
}

// String renders the instant as "S.FFFFFFFFFFFFFFF" via the C++ formatter.
func (t Instant) String() string {
	var buf [40]C.char
	n := C.align_format(C.fs_instant{seconds: C.int64_t(t.Seconds), femtos: C.int64_t(t.Femtos)}, &buf[0])
	return C.GoStringN(&buf[0], n)
}

// Interval snaps a [startMs, startMs+durMs) cue to femtosecond fixed point.
func Interval(startMs, durMs int64) (start, end Instant) {
	var cs, ce C.fs_instant
	C.align_interval(C.int64_t(startMs), C.int64_t(durMs), &cs, &ce)
	return Instant{int64(cs.seconds), int64(cs.femtos)},
		Instant{int64(ce.seconds), int64(ce.femtos)}
}
