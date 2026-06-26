import 'package:meta/meta.dart';
import 'package:radar_trace/radar_trace.dart';

/// Mutable accumulator for per-frame timing data.
///
/// Uses [LatencyHistogram] for each timing dimension to compute
/// honest percentiles. No fabricated ratios are stored.
final class FrameStats {
  FrameStats({required this.jankThresholdMicros});

  /// Frames longer than this are counted as jank.
  final int jankThresholdMicros;

  final LatencyHistogram _buildHist = LatencyHistogram();
  final LatencyHistogram _rasterHist = LatencyHistogram();
  final LatencyHistogram _totalHist = LatencyHistogram();

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
  );
}

/// Immutable snapshot of frame timing statistics.
///
/// All percentile fields are null when no frames have been recorded.
/// No fabricated ratios (e.g. cpuPercent) — unknown values are null.
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
}
