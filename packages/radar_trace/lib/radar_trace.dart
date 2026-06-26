/// Pure-Dart tracer framework for on-device performance measurement.
///
/// Provides monotonic microsecond spans, log-linear latency histograms
/// with lossless aggregate statistics, a bounded outlier ring for
/// exemplar retention, Zone-based async parent/child nesting, and a
/// [Tracer] façade that never throws into the host.
library;

export 'src/model/span.dart';
export 'src/model/trace_key.dart';
export 'src/histogram/latency_histogram.dart';
export 'src/histogram/outlier_ring.dart';
export 'src/recorder/span_key_stats.dart';
export 'src/recorder/trace_recorder.dart';
export 'src/snapshot/trace_snapshot.dart';
