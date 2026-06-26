import 'dart:math' as math;

import '../model/span.dart';
import '../model/trace_key.dart';
import '../snapshot/trace_snapshot.dart';
import 'span_key_stats.dart';

/// Collects finished [Span]s, aggregates them per [TraceKey], and
/// exposes immutable [TraceSnapshot]s for inspection.
///
/// Single-isolate use only — not thread-safe.
class TraceRecorder {
  /// Whether recording is active.
  ///
  /// When false, [record] is a no-op and [snapshot] returns empty
  /// stats.
  final bool enabled;

  /// Fraction of spans to sample, in the range 0.0–1.0.
  ///
  /// A value of 1.0 records every span. Lower values reduce overhead
  /// on very hot paths. Sampling is probabilistic — no percentile
  /// scaling is applied, so results reflect only the sampled
  /// population.
  final double sampleRate;

  /// Maximum number of distinct [TraceKey]s to track.
  ///
  /// Spans for keys beyond this limit increment [dropCount] and are
  /// not recorded. Existing keys continue to accumulate regardless.
  final int maxKeys;

  /// Per-key outlier ring capacity (slowest-N spans to retain).
  final int outlierCapacity;

  final Map<TraceKey, SpanKeyStats> _stats = {};
  final math.Random _random = math.Random();
  int _dropCount = 0;

  /// Creates a [TraceRecorder] with the given parameters.
  ///
  /// [sampleRate] must be in [0.0, 1.0]. [maxKeys] and
  /// [outlierCapacity] must be positive.
  TraceRecorder({
    this.enabled = true,
    this.sampleRate = 1.0,
    this.maxKeys = 1024,
    this.outlierCapacity = 16,
  })  : assert(
          sampleRate >= 0.0 && sampleRate <= 1.0,
          'sampleRate must be in [0.0, 1.0]',
        ),
        assert(maxKeys > 0, 'maxKeys must be > 0'),
        assert(outlierCapacity > 0, 'outlierCapacity must be > 0');

  /// Number of distinct [TraceKey]s currently tracked.
  int get keyCount => _stats.length;

  /// Number of spans dropped because [maxKeys] was reached for a
  /// new key.
  int get dropCount => _dropCount;

  /// Records a finished [span].
  ///
  /// Ignored when [enabled] is false. Probabilistically skipped when
  /// [sampleRate] < 1.0. Dropped (with [dropCount] increment) when
  /// [maxKeys] is reached and the span's key is new.
  void record(Span span) {
    if (!enabled) return;
    if (sampleRate < 1.0 && _random.nextDouble() >= sampleRate) return;

    final key = TraceKey(name: span.name, category: span.category);
    var stats = _stats[key];
    if (stats == null) {
      if (_stats.length >= maxKeys) {
        _dropCount++;
        return;
      }
      stats = SpanKeyStats(key: key, outlierCapacity: outlierCapacity);
      _stats[key] = stats;
    }
    stats.record(span);
  }

  /// Returns an immutable snapshot of all current aggregates.
  ///
  /// Subsequent [record] calls do not mutate the returned snapshot.
  TraceSnapshot snapshot() {
    final snapshotMap = <TraceKey, SpanKeyStatsSnapshot>{
      for (final entry in _stats.entries)
        entry.key: entry.value.snapshot(),
    };
    return TraceSnapshot(
      stats: snapshotMap,
      totalDropCount: _dropCount,
    );
  }

  /// Resets all aggregates and drop counters.
  void reset() {
    _stats.clear();
    _dropCount = 0;
  }
}
