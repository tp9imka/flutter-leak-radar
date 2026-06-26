// Copyright (c) 2025, tp9imka. All rights reserved.

import 'package:flutter/foundation.dart';

/// Configuration for [PerfRadar.init].
///
/// Use [PerfRadarConfig.standard] for typical wiring — it enables the tracer
/// only in debug and profile builds (`kDebugMode || kProfileMode`).
@immutable
final class PerfRadarConfig {
  const PerfRadarConfig({
    required this.enabled,
    this.showOverlay = false,
    this.jankThresholdMicros = 16667,
    required this.stallThresholdMicros,
    this.maxStallsRetained = 50,
    this.maxErrorsRetained = 100,
  });

  /// Recommended constructor. Enables the engine in debug/profile only.
  factory PerfRadarConfig.standard() => PerfRadarConfig(
    enabled: kDebugMode || kProfileMode,
    stallThresholdMicros: 250000,
  );

  /// Master on/off switch.
  final bool enabled;

  /// Whether to show the draggable overlay pill.
  final bool showOverlay;

  /// Frames longer than this are counted as jank (default: ~60 fps = 16667µs).
  final int jankThresholdMicros;

  /// Main-thread delays longer than this trigger a stall event.
  final int stallThresholdMicros;

  /// Maximum number of stall records to retain in memory.
  final int maxStallsRetained;

  /// Maximum number of error records to retain in memory.
  final int maxErrorsRetained;

  /// Returns a copy with the given fields replaced.
  PerfRadarConfig copyWith({
    bool? enabled,
    bool? showOverlay,
    int? jankThresholdMicros,
    int? stallThresholdMicros,
    int? maxStallsRetained,
    int? maxErrorsRetained,
  }) => PerfRadarConfig(
    enabled: enabled ?? this.enabled,
    showOverlay: showOverlay ?? this.showOverlay,
    jankThresholdMicros: jankThresholdMicros ?? this.jankThresholdMicros,
    stallThresholdMicros: stallThresholdMicros ?? this.stallThresholdMicros,
    maxStallsRetained: maxStallsRetained ?? this.maxStallsRetained,
    maxErrorsRetained: maxErrorsRetained ?? this.maxErrorsRetained,
  );

  @override
  bool operator ==(Object other) =>
      other is PerfRadarConfig &&
      other.enabled == enabled &&
      other.showOverlay == showOverlay &&
      other.jankThresholdMicros == jankThresholdMicros &&
      other.stallThresholdMicros == stallThresholdMicros &&
      other.maxStallsRetained == maxStallsRetained &&
      other.maxErrorsRetained == maxErrorsRetained;

  @override
  int get hashCode => Object.hash(
    enabled,
    showOverlay,
    jankThresholdMicros,
    stallThresholdMicros,
    maxStallsRetained,
    maxErrorsRetained,
  );
}
