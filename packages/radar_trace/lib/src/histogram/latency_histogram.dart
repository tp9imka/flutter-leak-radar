import 'dart:math' as math;

import 'package:meta/meta.dart';

/// Log-linear latency histogram covering 1µs–60s in fixed buckets.
///
/// Uses HdrHistogram-style sub-buckets: 8 linear sub-buckets per
/// power-of-two decade, yielding ~104 buckets total. Each `record`
/// call is O(1); `percentile` is O(buckets) = O(1).
///
/// Values outside [0, 60_000_000µs] are either clamped (below) or
/// counted as drops (above) — never silently discarded without an
/// accounting trace.
final class LatencyHistogram {
  // 60s in microseconds
  static const int _maxMicros = 60_000_000;

  // Sub-buckets per power-of-two decade
  static const int _subBuckets = 8;

  static final List<int> _upperBounds = _buildBounds();

  static List<int> _buildBounds() {
    final bounds = <int>[];
    // Generate sub-bucket upper bounds until we exceed _maxMicros.
    // Decade k covers [2^k, 2^(k+1)); sub-bucket j within it has
    // upper bound = 2^k + (j+1) * (2^k / _subBuckets).
    var k = 0;
    while (true) {
      final base = 1 << k; // 2^k
      final step = math.max(1, base ~/ _subBuckets);
      for (var j = 0; j < _subBuckets; j++) {
        final upper = base + (j + 1) * step;
        bounds.add(upper);
        if (upper >= _maxMicros) return bounds;
      }
      k++;
    }
  }

  final List<int> _counts =
      List<int>.filled(_upperBounds.length, 0);

  int _count = 0;
  int _sum = 0;
  int _min = 0;
  bool _hasMin = false;
  int _max = 0;
  int _dropCount = 0;

  /// Adds one observation of [micros] microseconds.
  ///
  /// Values ≤ 0 are clamped to bucket 0. Values > 60s increment
  /// [dropCount] and are excluded from [count], [sum], and percentiles.
  void record(int micros) {
    if (micros > _maxMicros) {
      _dropCount++;
      return;
    }
    final clamped = micros < 0 ? 0 : micros;
    final idx = _bucketIndex(clamped);
    _counts[idx]++;
    _count++;
    _sum += clamped;
    if (!_hasMin || clamped < _min) {
      _min = clamped;
      _hasMin = true;
    }
    if (clamped > _max) _max = clamped;
  }

  /// Total number of in-range observations.
  int get count => _count;

  /// Sum of all in-range observations in microseconds.
  int get sum => _sum;

  /// Minimum observed value in microseconds; null when [count] == 0.
  int? get min => _hasMin ? _min : null;

  /// Maximum observed value in microseconds; null when [count] == 0.
  int? get max => _hasMin ? _max : null;

  /// Arithmetic mean in microseconds; null when [count] == 0.
  double? get mean => _count == 0 ? null : _sum / _count;

  /// Number of observations that exceeded the 60s ceiling and were
  /// excluded from aggregates — never silently lost.
  int get dropCount => _dropCount;

  /// Returns the upper bound of the bucket at the [p]-th percentile
  /// (0.0–1.0), or null when [count] == 0.
  ///
  /// The result is an honest upper-bound approximation, not an exact
  /// value. The true observation lies within [lowerBound, result].
  int? percentile(double p) {
    if (_count == 0) return null;
    final target = (_count * p).ceil();
    var cumulative = 0;
    for (var i = 0; i < _counts.length; i++) {
      cumulative += _counts[i];
      if (cumulative >= target) return _upperBounds[i];
    }
    return _upperBounds.last;
  }

  /// Returns an immutable snapshot of the current state.
  LatencyHistogramSnapshot snapshot() => LatencyHistogramSnapshot._(
    count: _count,
    sum: _sum,
    min: min,
    max: max,
    dropCount: _dropCount,
    counts: List<int>.unmodifiable(_counts),
  );

  static int _bucketIndex(int micros) {
    if (micros <= 0) return 0;
    // Binary search the upper bounds list
    var lo = 0;
    var hi = _upperBounds.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (_upperBounds[mid] < micros) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }
}

/// Immutable snapshot of [LatencyHistogram] state.
@immutable
final class LatencyHistogramSnapshot {
  /// Total in-range observation count.
  final int count;

  /// Sum of all in-range observations in microseconds.
  final int sum;

  /// Minimum observed value; null when [count] == 0.
  final int? min;

  /// Maximum observed value; null when [count] == 0.
  final int? max;

  /// Arithmetic mean; null when [count] == 0.
  double? get mean => count == 0 ? null : sum / count;

  /// Out-of-range observation count (above 60s ceiling).
  final int dropCount;

  final List<int> _counts;

  const LatencyHistogramSnapshot._({
    required this.count,
    required this.sum,
    required this.min,
    required this.max,
    required this.dropCount,
    required List<int> counts,
  }) : _counts = counts;

  /// Returns the upper bound of the bucket at the [p]-th percentile,
  /// or null when [count] == 0.
  int? percentile(double p) {
    if (count == 0) return null;
    final target = (count * p).ceil();
    var cumulative = 0;
    for (var i = 0; i < _counts.length; i++) {
      cumulative += _counts[i];
      if (cumulative >= target) {
        return LatencyHistogram._upperBounds[i];
      }
    }
    return LatencyHistogram._upperBounds.last;
  }
}
