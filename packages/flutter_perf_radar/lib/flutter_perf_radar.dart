// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// On-device performance and stability tracer for Flutter.
///
/// Key entry points:
/// - [PerfRadar.init] — initialise once from `main()`.
/// - [PerfRadar.trace] / [PerfRadar.traceAsync] — instrument synchronous or
///   asynchronous operations.
/// - [PerfRadar.start] — manual start/stop span for callback-bounded code.
/// - [PerfRadar.overlay] — wrap your root widget to show the floating badge.
/// - [TracedSubtree] — counts widget subtree rebuilds via the span system.
library;

export 'src/config/perf_radar_config.dart';
export 'src/engine/stability_recorder.dart';
export 'src/engine/stall_watchdog.dart';
export 'src/facade/perf_radar.dart';
export 'src/model/error_record.dart';
export 'src/model/frame_stats.dart';
export 'src/model/stall_record.dart';
export 'src/model/stability_snapshot.dart';
export 'src/ui/perf_radar_overlay.dart';
export 'src/ui/perf_radar_screen.dart';
export 'src/ui/widgets/rebuild_counts_panel.dart';
export 'src/ui/widgets/traced_subtree.dart';
