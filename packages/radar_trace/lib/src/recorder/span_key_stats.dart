import 'package:meta/meta.dart';

import '../histogram/latency_histogram.dart';
import '../histogram/outlier_ring.dart';
import '../model/span.dart';
import '../model/trace_key.dart';

/// Mutable per-key aggregate: one histogram + one outlier ring.
///
/// Not thread-safe — single-isolate use only.
class SpanKeyStats {
  /// The trace key identifying this aggregate bucket.
  final TraceKey key;

  final LatencyHistogram _histogram;
  final OutlierRing _outlierRing;
  int _errorCount = 0;

  /// Creates a [SpanKeyStats] for [key] with the given
  /// [outlierCapacity] for the retained outlier ring.
  SpanKeyStats({required this.key, required int outlierCapacity})
    : _histogram = LatencyHistogram(),
      _outlierRing = OutlierRing(capacity: outlierCapacity);

  /// Total number of spans recorded for this key.
  int get count => _histogram.count;

  /// Number of spans that completed with [SpanStatus.error].
  int get errorCount => _errorCount;

  /// Records a finished span into the histogram and outlier ring.
  void record(Span span) {
    _histogram.record(span.durationMicros);
    _outlierRing.offer(span);
    if (span.status == SpanStatus.error) _errorCount++;
  }

  /// Returns an immutable snapshot of the current aggregate.
  SpanKeyStatsSnapshot snapshot() => SpanKeyStatsSnapshot(
    key: key,
    count: count,
    errorCount: _errorCount,
    histogram: _histogram.snapshot(),
    outliers: List.unmodifiable(_outlierRing.spans),
  );
}

/// Immutable per-key statistics snapshot.
@immutable
final class SpanKeyStatsSnapshot {
  /// The trace key identifying this group.
  final TraceKey key;

  /// Total span count.
  final int count;

  /// Count of spans with [SpanStatus.error].
  final int errorCount;

  /// Immutable latency histogram snapshot.
  final LatencyHistogramSnapshot histogram;

  /// Slowest-N retained exemplar spans, sorted slowest-first.
  /// Unmodifiable.
  final List<Span> outliers;

  /// Creates an immutable snapshot of per-key statistics.
  const SpanKeyStatsSnapshot({
    required this.key,
    required this.count,
    required this.errorCount,
    required this.histogram,
    required this.outliers,
  });
}
