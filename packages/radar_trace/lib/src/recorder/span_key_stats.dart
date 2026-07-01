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

  // Caller-supplied duplicate detection (see [Span.dedupKey]). Bounded so a
  // high-cardinality key cannot grow the set without limit.
  static const int _maxDedupSignatures = 1024;
  final Set<String> _seenDedupKeys = {};
  int _duplicateCount = 0;

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

  /// Number of spans whose [Span.dedupKey] was already seen for this key — i.e.
  /// repeated invocations with the same caller-supplied signature.
  int get duplicateCount => _duplicateCount;

  /// Records a finished span into the histogram and outlier ring.
  void record(Span span) {
    _histogram.record(span.durationMicros);
    _outlierRing.offer(span);
    if (span.status == SpanStatus.error) _errorCount++;

    final dedup = span.dedupKey;
    if (dedup != null) {
      if (_seenDedupKeys.contains(dedup)) {
        _duplicateCount++;
      } else if (_seenDedupKeys.length < _maxDedupSignatures) {
        _seenDedupKeys.add(dedup);
      }
      // Set full and signature unseen: neither counted nor stored (bounded).
    }

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
    duplicateCount: _duplicateCount,
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

  /// Count of spans whose [Span.dedupKey] repeated a previously-seen signature
  /// for this key — true duplicate invocations, distinct from the statistical
  /// "hot" heuristic in the UI. Zero when no caller supplied a dedup key.
  final int duplicateCount;

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
    this.duplicateCount = 0,
  });

  /// Serialises this snapshot to a JSON-encodable map.
  ///
  /// Shape:
  /// ```json
  /// {
  ///   "name": "db.query.rooms",
  ///   "category": "db",
  ///   "count": 42,
  ///   "meanMicros": 1200,
  ///   "maxMicros": 8000,
  ///   "totalMicros": 50400,
  ///   "p50": 1100,
  ///   "p95": 4000,
  ///   "p99": 7000,
  ///   "avgInterCallIntervalMicros": 500,
  ///   "callsPerSecond": 2.0,
  ///   "errorCount": 1,
  ///   "firstStartMicros": 1000000,
  ///   "lastStartMicros": 22000000
  /// }
  /// ```
  ///
  /// Nullable computed fields ([avgInterCallIntervalMicros],
  /// [callsPerSecond], percentiles) are serialised as JSON `null` when
  /// fewer than two spans have been recorded or no data is available.
  ///
  /// Pure function — no VM dependencies. Safe to call in unit tests.
  Map<String, Object?> toJson() => {
    'name': key.name,
    'category': key.category,
    'count': count,
    'meanMicros': meanMicros,
    'maxMicros': maxMicros,
    'totalMicros': totalMicros,
    'p50': histogram.percentile(0.50),
    'p95': histogram.percentile(0.95),
    'p99': histogram.percentile(0.99),
    'avgInterCallIntervalMicros': avgInterCallIntervalMicros,
    'callsPerSecond': callsPerSecond,
    'errorCount': errorCount,
    'duplicateCount': duplicateCount,
    'firstStartMicros': firstStartMicros,
    'lastStartMicros': lastStartMicros,
  };
}
