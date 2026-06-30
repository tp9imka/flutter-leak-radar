// lib/src/radar_config.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_leak_radar/flutter_leak_radar.dart';
import 'package:flutter_perf_radar/flutter_perf_radar.dart';

/// Unified configuration for [Radar.init].
///
/// Composes [LeakRadarConfig] and [PerfRadarConfig] into a single value.
/// Use [RadarConfig.standard] for typical wiring — it delegates to each
/// package's own `.standard()` factory.
@immutable
final class RadarConfig {
  /// Creates a [RadarConfig] from explicit domain configs.
  const RadarConfig({required this.leak, required this.perf});

  /// Recommended constructor.
  ///
  /// Enables both domains in debug and profile builds and applies each
  /// package's `.standard()` defaults.
  factory RadarConfig.standard({
    LeakRadarConfig? leak,
    PerfRadarConfig? perf,
  }) => RadarConfig(
    leak: leak ?? LeakRadarConfig.standard(),
    perf: perf ?? PerfRadarConfig.standard(),
  );

  /// Configuration forwarded to [LeakRadar.init].
  final LeakRadarConfig leak;

  /// Configuration forwarded to [PerfRadar.init].
  final PerfRadarConfig perf;

  /// Returns a copy with the given fields replaced.
  RadarConfig copyWith({LeakRadarConfig? leak, PerfRadarConfig? perf}) =>
      RadarConfig(leak: leak ?? this.leak, perf: perf ?? this.perf);

  @override
  bool operator ==(Object other) =>
      other is RadarConfig && other.leak == leak && other.perf == perf;

  @override
  int get hashCode => Object.hash(leak, perf);
}
