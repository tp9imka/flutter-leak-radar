import 'package:meta/meta.dart';
import 'package:radar_trace/radar_trace.dart';

/// A single recorded frame's timing breakdown.
///
/// All durations are in microseconds. Instances are immutable; callers
/// should not hold references across [FrameStats.record] calls as the
/// ring buffer only keeps the most recent [FrameStats.maxRecentFrames].
@immutable
final class FrameSample {
  /// Creates a frame sample with the given timing breakdown.
  const FrameSample({
    required this.totalMicros,
    required this.buildMicros,
    required this.rasterMicros,
  });

  /// Wall-clock duration of the entire frame in microseconds.
  final int totalMicros;

  /// Build-phase duration in microseconds.
  final int buildMicros;

  /// Raster-phase duration in microseconds.
  final int rasterMicros;
}

/// Mutable accumulator for per-frame timing data.
///
/// Uses [LatencyHistogram] for each timing dimension to compute
/// honest percentiles. No fabricated ratios are stored.
///
/// The most recent [maxRecentFrames] samples are kept verbatim in the
/// [FrameStatsSnapshot.recentFrames] ring, enabling the UI to plot a
/// real timeline instead of synthesising one from percentiles.
final class FrameStats {
  FrameStats({required this.jankThresholdMicros});

  /// Maximum number of recent frames retained in the ring buffer.
  static const int maxRecentFrames = 120;

  /// Frames longer than this are counted as jank.
  final int jankThresholdMicros;

  final LatencyHistogram _buildHist = LatencyHistogram();
  final LatencyHistogram _rasterHist = LatencyHistogram();
  final LatencyHistogram _totalHist = LatencyHistogram();

  final List<FrameSample> _recent = [];

  int _frameCount = 0;
  int _jankCount = 0;

  /// Total frames recorded.
  int get frameCount => _frameCount;

  /// Frames that exceeded [jankThresholdMicros].
  int get jankCount => _jankCount;

  /// Records one frame's timing data.
  void record({
    required int buildMicros,
    required int rasterMicros,
    required int totalMicros,
  }) {
    _buildHist.record(buildMicros);
    _rasterHist.record(rasterMicros);
    _totalHist.record(totalMicros);
    _frameCount++;
    if (totalMicros > jankThresholdMicros) _jankCount++;

    _recent.add(
      FrameSample(
        totalMicros: totalMicros,
        buildMicros: buildMicros,
        rasterMicros: rasterMicros,
      ),
    );
    if (_recent.length > maxRecentFrames) _recent.removeAt(0);
  }

  /// Returns an immutable snapshot of all current statistics.
  FrameStatsSnapshot snapshot() => FrameStatsSnapshot(
    frameCount: _frameCount,
    jankCount: _jankCount,
    buildP50: _buildHist.percentile(0.50),
    buildP95: _buildHist.percentile(0.95),
    buildP99: _buildHist.percentile(0.99),
    rasterP50: _rasterHist.percentile(0.50),
    rasterP95: _rasterHist.percentile(0.95),
    rasterP99: _rasterHist.percentile(0.99),
    totalP50: _totalHist.percentile(0.50),
    totalP95: _totalHist.percentile(0.95),
    totalP99: _totalHist.percentile(0.99),
    recentFrames: List.unmodifiable(_recent),
  );
}

/// Immutable snapshot of frame timing statistics.
///
/// All percentile fields are null when no frames have been recorded.
/// No fabricated ratios (e.g. cpuPercent) — unknown values are null.
///
/// [recentFrames] contains up to [FrameStats.maxRecentFrames] real
/// recorded samples in chronological order.
@immutable
final class FrameStatsSnapshot {
  const FrameStatsSnapshot({
    required this.frameCount,
    required this.jankCount,
    this.buildP50,
    this.buildP95,
    this.buildP99,
    this.rasterP50,
    this.rasterP95,
    this.rasterP99,
    this.totalP50,
    this.totalP95,
    this.totalP99,
    this.recentFrames = const [],
  });

  /// Total frame count.
  final int frameCount;

  /// Frames that exceeded the jank threshold.
  final int jankCount;

  // Build-phase percentiles in microseconds (null if no frames recorded).
  final int? buildP50;
  final int? buildP95;
  final int? buildP99;

  // Raster-phase percentiles in microseconds (null if no frames recorded).
  final int? rasterP50;
  final int? rasterP95;
  final int? rasterP99;

  // Total-frame percentiles in microseconds (null if no frames recorded).
  final int? totalP50;
  final int? totalP95;
  final int? totalP99;

  /// The most recent [FrameStats.maxRecentFrames] frame samples in
  /// chronological order. Empty when no frames have been recorded.
  final List<FrameSample> recentFrames;

  /// Serialises this snapshot to a JSON-encodable map.
  ///
  /// Shape:
  /// ```json
  /// {
  ///   "frameCount": 300,
  ///   "jankCount": 4,
  ///   "buildP50": 800,
  ///   "buildP95": 3000,
  ///   "buildP99": 6000,
  ///   "rasterP50": 900,
  ///   "rasterP95": 3200,
  ///   "rasterP99": 6500,
  ///   "totalP50": 1800,
  ///   "totalP95": 6000,
  ///   "totalP99": 12000,
  ///   "recentFrames": [
  ///     { "totalMicros": 16200, "buildMicros": 800, "rasterMicros": 900 }
  ///   ]
  /// }
  /// ```
  ///
  /// Percentile fields are `null` when no frames have been recorded.
  /// [recentFrames] preserves chronological order.
  ///
  /// Pure function — no VM dependencies. Safe to call in unit tests.
  Map<String, Object?> toJson() => {
    'frameCount': frameCount,
    'jankCount': jankCount,
    'buildP50': buildP50,
    'buildP95': buildP95,
    'buildP99': buildP99,
    'rasterP50': rasterP50,
    'rasterP95': rasterP95,
    'rasterP99': rasterP99,
    'totalP50': totalP50,
    'totalP95': totalP95,
    'totalP99': totalP99,
    'recentFrames': recentFrames
        .map(
          (f) => {
            'totalMicros': f.totalMicros,
            'buildMicros': f.buildMicros,
            'rasterMicros': f.rasterMicros,
          },
        )
        .toList(),
  };
}
