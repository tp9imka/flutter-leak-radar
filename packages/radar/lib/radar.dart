/// Umbrella re-export for the Radar suite.
///
/// Import this single file to access both [LeakRadar] and [PerfRadar]
/// domain APIs plus the unified [Radar] facade, [RadarConfig],
/// [RadarScreen], and [RadarOverlay].
library;

// Domain packages — full re-export.
export 'package:flutter_leak_radar/flutter_leak_radar.dart';
export 'package:flutter_perf_radar/flutter_perf_radar.dart';
