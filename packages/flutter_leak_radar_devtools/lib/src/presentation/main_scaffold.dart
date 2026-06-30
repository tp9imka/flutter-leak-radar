import 'package:flutter/material.dart';
import 'package:radar_ui/radar_ui.dart';

import '../capture/snapshot_service.dart';
import '../connection/connection_state_notifier.dart';
import '../diff/diff_controller.dart';
import '../memory/class_histogram_view.dart';
import '../memory/retaining_paths_view.dart';
import '../memory/snapshot_diff_view.dart';
import '../perf/perf_data_controller.dart';
import '../perf/frames_view.dart';
import '../perf/traces_view.dart';
import '../shell/connection_bar.dart';
import '../shell/left_rail.dart';
import '../shell/radar_view.dart';
import '../stability/errors_view.dart';
import '../stability/stalls_view.dart';

/// Root scaffold for the Leak Radar DevTools extension.
///
/// Owns [ConnectionStateNotifier], [DiffController], and
/// [PerfDataController] lifetimes and lays out the shell: a fixed
/// [ConnectionBar] header + [LeftRail] alongside a content pane that
/// switches by [RadarView].
///
/// Wraps the entire tree in [radarDarkTheme] so that DevTools' host
/// theme does not bleed into the extension chrome.
class LeakRadarMainScaffold extends StatefulWidget {
  const LeakRadarMainScaffold({super.key});

  @override
  State<LeakRadarMainScaffold> createState() => _LeakRadarMainScaffoldState();
}

class _LeakRadarMainScaffoldState extends State<LeakRadarMainScaffold> {
  late final ConnectionStateNotifier _connection;
  late final DiffController _diff;
  late final PerfDataController _perf;

  RadarView _currentView = RadarView.snapshotDiff;

  @override
  void initState() {
    super.initState();
    _connection = ConnectionStateNotifier();
    _diff = DiffController(
      snapshotService: const SnapshotService(),
      connection: _connection,
    );
    _perf = PerfDataController();
    _connection.init();
  }

  @override
  void dispose() {
    _diff.dispose();
    _connection.dispose();
    _perf.dispose();
    super.dispose();
  }

  Widget _buildContent() {
    return switch (_currentView) {
      // Memory
      RadarView.snapshotDiff => SnapshotDiffView(controller: _diff),
      RadarView.classHistogram => ClassHistogramView(controller: _diff),
      RadarView.retainingPaths => RetainingPathsView(controller: _diff),
      // Performance
      RadarView.traces => TracesView(controller: _perf),
      RadarView.frames => FramesView(controller: _perf),
      // Stability
      RadarView.errors => ErrorsView(controller: _perf),
      RadarView.stalls => StallsView(controller: _perf),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: radarDarkTheme(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConnectionBar(notifier: _connection),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LeftRail(
                  currentView: _currentView,
                  onViewChanged: (v) => setState(() => _currentView = v),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: _buildContent()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
