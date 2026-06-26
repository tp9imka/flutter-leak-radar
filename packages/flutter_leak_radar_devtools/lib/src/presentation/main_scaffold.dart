import 'package:flutter/material.dart';

import '../capture/snapshot_service.dart';
import '../connection/connection_state_notifier.dart';
import '../diff/diff_controller.dart';
import 'capture_panel.dart';
import 'clusters_view.dart';
import 'connection_banner.dart';
import 'diff_view.dart';
import 'histogram_table.dart';

/// Root scaffold for the Leak Radar DevTools extension.
///
/// Initialises [ConnectionStateNotifier] and [DiffController], wires them
/// together, and hosts the three-tab layout: Histogram / Diff / Clusters.
class LeakRadarMainScaffold extends StatefulWidget {
  const LeakRadarMainScaffold({super.key});

  @override
  State<LeakRadarMainScaffold> createState() => _LeakRadarMainScaffoldState();
}

class _LeakRadarMainScaffoldState extends State<LeakRadarMainScaffold>
    with SingleTickerProviderStateMixin {
  late final ConnectionStateNotifier _connection;
  late final DiffController _diff;
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _connection = ConnectionStateNotifier();
    _diff = DiffController(
      snapshotService: const SnapshotService(),
      connection: _connection,
    );
    _tabs = TabController(length: 3, vsync: this);
    _connection.init();
  }

  @override
  void dispose() {
    _connection.dispose();
    _diff.dispose();
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Leak Radar'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Histogram'),
            Tab(text: 'Diff'),
            Tab(text: 'Clusters'),
          ],
        ),
      ),
      body: Column(
        children: [
          ConnectionBanner(notifier: _connection),
          CapturePanel(controller: _diff),
          Expanded(
            child: ListenableBuilder(
              listenable: _diff,
              builder: (context, _) {
                final snapshot = _diff.snapshotB ?? _diff.snapshotA;
                return TabBarView(
                  controller: _tabs,
                  children: [
                    HistogramTable(histogram: snapshot?.histogram ?? const []),
                    DiffView(controller: _diff),
                    ClustersView(controller: _diff),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
