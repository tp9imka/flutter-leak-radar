/// Umbrella re-export for the Radar suite.
///
/// A single import gives access to both domain packages and the unified
/// [Radar] facade:
///
/// ```dart
/// import 'package:radar/radar.dart';
///
/// await Radar.init(RadarConfig.standard());
/// runApp(Radar.overlay(child: MyApp()));
/// ```
library;

// Domain packages — full re-export so `import 'package:radar/radar.dart'`
// suffices in place of both individual package imports.
export 'package:flutter_leak_radar/flutter_leak_radar.dart';
export 'package:flutter_perf_radar/flutter_perf_radar.dart';

// Umbrella symbols.
export 'src/radar_config.dart';
export 'src/radar.dart';
export 'src/radar_screen.dart';
export 'src/radar_overlay.dart';

// Re-export radar_trace types needed by Radar.start() consumers.
export 'package:radar_trace/radar_trace.dart' show SpanHandle, TraceSnapshot;
