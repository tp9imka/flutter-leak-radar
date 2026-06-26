import 'package:flutter/scheduler.dart';

import '../model/frame_stats.dart';

/// Subscribes to [WidgetsBinding.addTimingsCallback] and feeds each
/// [FrameTiming] into a [FrameStats] accumulator.
final class FrameCollector {
  FrameCollector({required this.stats});

  /// The stats accumulator this collector feeds into.
  final FrameStats stats;

  bool _registered = false;

  /// Starts listening to frame timings on [binding].
  void start(SchedulerBinding binding) {
    if (_registered) return;
    binding.addTimingsCallback(_onFrameTimings);
    _registered = true;
  }

  /// Stops listening to frame timings on [binding].
  void stop(SchedulerBinding binding) {
    if (!_registered) return;
    binding.removeTimingsCallback(_onFrameTimings);
    _registered = false;
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      stats.record(
        buildMicros: timing.buildDuration.inMicroseconds,
        rasterMicros: timing.rasterDuration.inMicroseconds,
        totalMicros: timing.totalSpan.inMicroseconds,
      );
    }
  }
}
