// Copyright (c) 2025, tp9imka. All rights reserved.

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
}
