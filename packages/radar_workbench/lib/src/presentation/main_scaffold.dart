import 'package:flutter/material.dart';
import 'package:radar_ui/radar_ui.dart';

import '../memory/class_histogram_view.dart';
import '../memory/retaining_paths_view.dart';
import '../memory/snapshots_view.dart';
import '../perf/frames_view.dart';
import '../perf/traces_view.dart';
import '../session/radar_session.dart';
import '../shell/connection_bar.dart';
import '../shell/left_rail.dart';
import '../shell/radar_view.dart';
import '../stability/errors_view.dart';
import '../stability/stalls_view.dart';

/// Root scaffold for the Leak Radar DevTools extension.
///
/// Reads its controllers and the active view from [RadarSession] (a
/// process-wide singleton) rather than owning them in this [State]. DevTools
/// disposes/rebuilds this tree on tab switches; keeping state on the session
/// means captured snapshots, the diff selection, and the active view survive.
///
/// Wraps the tree in [radarDarkTheme] so DevTools' host theme does not bleed
/// into the extension chrome.
class LeakRadarMainScaffold extends StatefulWidget {
  const LeakRadarMainScaffold({super.key});

  @override
  State<LeakRadarMainScaffold> createState() => _LeakRadarMainScaffoldState();
}

class _LeakRadarMainScaffoldState extends State<LeakRadarMainScaffold> {
  final RadarSession _session = RadarSession.instance;

  @override
  void initState() {
    super.initState();
    _session.ensureInitialized();
    // Rebuild when memory state changes so an async session restore (which
    // rehydrates on a freshly rebuilt, empty iframe) is reflected — including
    // the restored active view. The controller also forwards VM-connection
    // changes (see MemoryController), so the capture toolbar re-enables as soon
    // as the connection is ready.
    _session.memory.addListener(_onSessionChanged);
  }

  @override
  void dispose() {
    _session.memory.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    if (mounted) setState(() {});
  }

  // Controllers live on [RadarSession] and persist for the whole extension
  // session — deliberately NOT disposed here.

  Widget _buildContent() {
    return switch (_session.currentView) {
      // Memory
      RadarView.snapshotDiff => SnapshotsView(
        controller: _session.memory,
        onExport: (bundle) => _session.exporter.export(bundle),
      ),
      RadarView.classHistogram => ClassHistogramView(
        controller: _session.memory,
      ),
      RadarView.retainingPaths => RetainingPathsView(
        controller: _session.memory,
        projectContext: _session.projectContext,
      ),
      // Performance
      RadarView.traces => TracesView(controller: _session.perf),
      RadarView.frames => FramesView(controller: _session.perf),
      // Stability
      RadarView.errors => ErrorsView(controller: _session.perf),
      RadarView.stalls => StallsView(controller: _session.perf),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: radarDarkTheme(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConnectionBar(connection: _session.connection),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LeftRail(
                  currentView: _session.currentView,
                  onViewChanged: (v) => setState(() => _session.selectView(v)),
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
