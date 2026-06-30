import 'package:meta/meta.dart';

import 'error_record.dart';
import 'stall_record.dart';

/// Immutable point-in-time snapshot of stability counters and recent events.
@immutable
final class StabilitySnapshot {
  const StabilitySnapshot({
    required this.errorCount,
    required this.stallCount,
    required this.recentErrors,
    required this.recentStalls,
  });

  /// Total number of errors captured (not just retained).
  final int errorCount;

  /// Total number of stalls detected (not just retained).
  final int stallCount;

  /// Most recent retained errors (bounded by [PerfRadarConfig.maxErrorsRetained]).
  final List<ErrorRecord> recentErrors;

  /// Most recent retained stalls (bounded by [PerfRadarConfig.maxStallsRetained]).
  final List<StallRecord> recentStalls;

  /// Serialises this snapshot to a JSON-encodable map.
  ///
  /// Shape:
  /// ```json
  /// {
  ///   "errorCount": 2,
  ///   "stallCount": 1,
  ///   "recentErrors": [
  ///     {
  ///       "message": "Connection refused",
  ///       "context": "FlutterError",
  ///       "clockMicros": 123456789,
  ///       "stackTraceString": "..."
  ///     }
  ///   ],
  ///   "recentStalls": [
  ///     { "durationMicros": 320000, "clockMicros": 987654321 }
  ///   ]
  /// }
  /// ```
  ///
  /// [ErrorRecord.context] and [ErrorRecord.stackTraceString] are
  /// serialised as `null` when not set on the record. No fields are
  /// invented; only fields that exist on [ErrorRecord] and [StallRecord]
  /// are included.
  ///
  /// Pure function — no VM dependencies. Safe to call in unit tests.
  Map<String, Object?> toJson() => {
    'errorCount': errorCount,
    'stallCount': stallCount,
    'recentErrors': recentErrors
        .map(
          (e) => {
            'message': e.message,
            'context': e.context,
            'clockMicros': e.clockMicros,
            'stackTraceString': e.stackTraceString,
          },
        )
        .toList(),
    'recentStalls': recentStalls
        .map(
          (s) => {
            'durationMicros': s.durationMicros,
            'clockMicros': s.clockMicros,
          },
        )
        .toList(),
  };
}
