import 'dart:collection';

import 'package:meta/meta.dart';

import '../model/trace_key.dart';
import '../recorder/span_key_stats.dart';

/// Immutable snapshot of all [TraceKey] aggregates at a point in time.
@immutable
final class TraceSnapshot {
  /// Per-key statistics, keyed by [TraceKey]. Unmodifiable.
  final Map<TraceKey, SpanKeyStatsSnapshot> stats;

  /// Number of spans dropped because the key limit was exceeded.
  ///
  /// A non-zero value means some data was honestly excluded.
  final int totalDropCount;

  /// Creates a [TraceSnapshot] wrapping [stats] in an unmodifiable view.
  TraceSnapshot({
    required Map<TraceKey, SpanKeyStatsSnapshot> stats,
    required this.totalDropCount,
  }) : stats = UnmodifiableMapView(stats);

  /// Serialises this snapshot to a JSON-encodable map.
  ///
  /// Shape:
  /// ```json
  /// {
  ///   "totalDropCount": 0,
  ///   "keys": [
  ///     { /* SpanKeyStatsSnapshot.toJson() */ }
  ///   ]
  /// }
  /// ```
  ///
  /// Pure function — no VM dependencies. Safe to call in unit tests.
  Map<String, Object?> toJson() => {
    'totalDropCount': totalDropCount,
    'keys': stats.values.map((s) => s.toJson()).toList(),
  };
}
