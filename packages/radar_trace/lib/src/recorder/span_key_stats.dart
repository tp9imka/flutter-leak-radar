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

  // Exact running accumulators for call-timing metrics.
  // Separate from the histogram because we need min/max of startMicros
  // (call arrival times), not of durationMicros (execution times).
  int _firstStartMicros = 0;
  int _lastStartMicros = 0;
  bool _hasStart = false;

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

    final start = span.startMicros;
    if (!_hasStart) {
      _firstStartMicros = start;
      _lastStartMicros = start;
      _hasStart = true;
    } else {
      if (start < _firstStartMicros) _firstStartMicros = start;
      if (start > _lastStartMicros) _lastStartMicros = start;
    }
  }

  /// Returns an immutable snapshot of the current aggregate.
  SpanKeyStatsSnapshot snapshot() => SpanKeyStatsSnapshot(
    key: key,
    count: count,
    errorCount: _errorCount,
    histogram: _histogram.snapshot(),
    outliers: List.unmodifiable(_outlierRing.spans),
    firstStartMicros: _hasStart ? _firstStartMicros : 0,
    lastStartMicros: _hasStart ? _lastStartMicros : 0,
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

  /// Minimum [Span.startMicros] across all recorded spans for this key.
  ///
  /// Equals [lastStartMicros] when only one span has been recorded.
  /// Zero when [count] == 0.
  final int firstStartMicros;

  /// Maximum [Span.startMicros] across all recorded spans for this key.
  ///
  /// Equals [firstStartMicros] when only one span has been recorded.
  /// Zero when [count] == 0.
  final int lastStartMicros;

  /// Average time between successive calls in microseconds, or null
  /// when fewer than two spans have been recorded.
  ///
  /// Computed as `(lastStartMicros - firstStartMicros) ~/ (count - 1)`.
  /// This is the honest average gap over the observed window —
  /// no ordering assumptions are made about arrival order.
  int? get avgInterCallIntervalMicros {
    if (count < 2) return null;
    return (lastStartMicros - firstStartMicros) ~/ (count - 1);
  }

  /// Observed call rate in calls per second, or null when fewer than
  /// two spans have been recorded or the observed window is zero.
  ///
  /// Computed as `count / ((lastStartMicros - firstStartMicros) / 1e6)`.
  double? get callsPerSecond {
    if (count < 2) return null;
    final windowMicros = lastStartMicros - firstStartMicros;
    if (windowMicros == 0) return null;
    return count / (windowMicros / 1e6);
  }

  /// Exact average execution time in microseconds (`sum ~/ count`).
  ///
  /// Derived from the exact running sum tracked by [LatencyHistogram],
  /// not from bucket midpoints, so it is not subject to bucket
  /// approximation error.
  int get meanMicros => count == 0 ? 0 : histogram.sum ~/ count;

  /// Exact slowest single execution time in microseconds.
  ///
  /// Derived from the exact running max tracked by [LatencyHistogram].
  int get maxMicros => histogram.max ?? 0;

  /// Exact total execution time in microseconds across all spans.
  ///
  /// This is the key's aggregate cost: `sum(durationMicros)`.
  int get totalMicros => histogram.sum;

  /// Creates an immutable snapshot of per-key statistics.
  const SpanKeyStatsSnapshot({
    required this.key,
    required this.count,
    required this.errorCount,
    required this.histogram,
    required this.outliers,
    required this.firstStartMicros,
    required this.lastStartMicros,
  });
}
