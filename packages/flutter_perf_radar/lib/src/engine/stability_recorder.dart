// Copyright (c) 2025, tp9imka. All rights reserved.

import 'package:radar_trace/radar_trace.dart';

import '../model/error_record.dart';
import '../model/stall_record.dart';
import '../model/stability_snapshot.dart';

/// Mutable ring-buffer recorder for errors and stalls.
///
/// Total counts are always incremented; retained lists are bounded by the
/// configured caps (oldest entry is evicted when at capacity).
final class StabilityRecorder {
  StabilityRecorder({
    required this.maxErrorsRetained,
    required this.maxStallsRetained,
    required this.stallThresholdMicros,
  });

  final int maxErrorsRetained;
  final int maxStallsRetained;
  final int stallThresholdMicros;

  int _errorCount = 0;
  int _stallCount = 0;

  final List<ErrorRecord> _errors = [];
  final List<StallRecord> _stalls = [];

  /// Total errors recorded (not just retained).
  int get errorCount => _errorCount;

  /// Total stalls detected (not just retained).
  int get stallCount => _stallCount;

  /// Records an error. Evicts the oldest when the retained list is full.
  void recordError(
    Object error,
    StackTrace? stackTrace, {
    String? context,
    int? clockMicros,
  }) {
    _errorCount++;
    final record = ErrorRecord(
      message: error.toString(),
      clockMicros: clockMicros ?? traceClockNowMicros(),
      context: context,
      stackTraceString: stackTrace?.toString(),
    );
    if (_errors.length >= maxErrorsRetained) {
      _errors.removeAt(0);
    }
    _errors.add(record);
  }

  /// Records a stall if [durationMicros] >= [stallThresholdMicros].
  void recordStall(int durationMicros, {int? clockMicros}) {
    if (durationMicros < stallThresholdMicros) return;
    _stallCount++;
    final record = StallRecord(
      durationMicros: durationMicros,
      clockMicros: clockMicros ?? traceClockNowMicros(),
    );
    if (_stalls.length >= maxStallsRetained) {
      _stalls.removeAt(0);
    }
    _stalls.add(record);
  }

  /// Returns an immutable snapshot of the current state.
  StabilitySnapshot snapshot() => StabilitySnapshot(
    errorCount: _errorCount,
    stallCount: _stallCount,
    recentErrors: List.unmodifiable(_errors),
    recentStalls: List.unmodifiable(_stalls),
  );

  /// Resets all counts and retained lists.
  void reset() {
    _errorCount = 0;
    _stallCount = 0;
    _errors.clear();
    _stalls.clear();
  }
}
