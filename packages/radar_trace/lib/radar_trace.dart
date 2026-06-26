/// Pure-Dart tracer framework for on-device performance measurement.
///
/// Provides monotonic microsecond spans, log-linear latency histograms
/// with lossless aggregate statistics, a bounded outlier ring for
/// exemplar retention, Zone-based async parent/child nesting, and a
/// [Tracer] façade that never throws into the host.
library;
