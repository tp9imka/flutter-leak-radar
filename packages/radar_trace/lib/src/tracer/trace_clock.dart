/// Process-monotonic microsecond clock shared by every span.
///
/// Spans read their `startMicros` and compute their duration from this one
/// clock rather than a per-span [Stopwatch]. That makes [startMicros] a
/// comparable offset from a common origin (process load), so spans can be
/// ordered and positioned in a span tree / flame chart — while durations stay
/// precise and monotonic as the difference of two reads.
library;

final Stopwatch _clock = Stopwatch()..start();

/// Microseconds elapsed on the shared tracer clock since process load.
///
/// Monotonic and non-decreasing within a process. Not wall-clock time.
int traceClockNowMicros() => _clock.elapsedMicroseconds;
