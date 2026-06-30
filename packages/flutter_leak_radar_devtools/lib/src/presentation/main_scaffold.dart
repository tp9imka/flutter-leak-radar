import 'package:flutter/material.dart';
import 'package:radar_ui/radar_ui.dart';

import '../capture/snapshot_service.dart';
import '../connection/connection_state_notifier.dart';
import '../diff/diff_controller.dart';
import '../memory/class_histogram_view.dart';
import '../memory/memory_view.dart';
import '../memory/retaining_paths_view.dart';
import '../memory/snapshot_diff_view.dart';
import '../shell/connection_bar.dart';
import '../shell/left_rail.dart';

/// Root scaffold for the Leak Radar DevTools extension.
///
/// Owns [ConnectionStateNotifier] and [DiffController] lifetimes and
/// lays out the shell: a fixed [ConnectionBar] header + [LeftRail]
/// alongside a content pane that switches by [MemoryView].
///
/// Wraps the entire tree in [radarDarkTheme] so that DevTools' host theme
/// does not bleed into the extension chrome.
class LeakRadarMainScaffold extends StatefulWidget {
  const LeakRadarMainScaffold({super.key});

  @override
  State<LeakRadarMainScaffold> createState() => _LeakRadarMainScaffoldState();
}

class _LeakRadarMainScaffoldState extends State<LeakRadarMainScaffold> {
  late final ConnectionStateNotifier _connection;
  late final DiffController _diff;

  MemoryView _currentView = MemoryView.snapshotDiff;

  @override
  void initState() {
    super.initState();
    _connection = ConnectionStateNotifier();
    _diff = DiffController(
      snapshotService: const SnapshotService(),
      connection: _connection,
    );
    _connection.init();
  }

  @override
  void dispose() {
    _diff.dispose();
    _connection.dispose();
    super.dispose();
  }

  Widget _buildContent() {
    return switch (_currentView) {
      MemoryView.snapshotDiff => SnapshotDiffView(controller: _diff),
      MemoryView.classHistogram => ClassHistogramView(controller: _diff),
      MemoryView.retainingPaths => RetainingPathsView(controller: _diff),
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
