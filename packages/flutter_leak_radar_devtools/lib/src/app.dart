import 'dart:async';

import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/material.dart';
import 'package:radar_workbench/radar_workbench.dart';

import 'adapters/devtools_perf_call.dart';
import 'adapters/devtools_radar_connection.dart';
import 'adapters/devtools_snapshot_exporter.dart';
import 'adapters/devtools_snapshot_source.dart';
import 'connection/connection_state_notifier.dart';
import 'session/dtd_project_context.dart';
import 'session/dtd_snapshot_store.dart';

/// Root widget of the Leak Radar DevTools extension.
///
/// Builds the DevTools-specific adapters, installs the shared [RadarSession],
/// and attaches the durable [DtdSnapshotStore] so a session captured before
/// this iframe was disposed is restored on return.
class LeakRadarDevToolsExtension extends StatefulWidget {
  const LeakRadarDevToolsExtension({super.key});

  @override
  State<LeakRadarDevToolsExtension> createState() =>
      _LeakRadarDevToolsExtensionState();
}

class _LeakRadarDevToolsExtensionState
    extends State<LeakRadarDevToolsExtension> {
  // DevTools may recreate this State in-process (e.g. tab switches) without
  // tearing down the Dart context. Re-installing RadarSession on every
  // initState would discard the live in-memory session, so build + install
  // only runs once per process; a fresh Dart context (full iframe teardown)
  // resets this static and re-installs + restores from DTD, which is correct.
  static bool _installed = false;

  @override
  void initState() {
    super.initState();
    if (_installed) return;
    _installed = true;

    final notifier = ConnectionStateNotifier();
    final connection = DevToolsRadarConnection(notifier);
    final source = DevToolsSnapshotSource(connection, const SnapshotAnalyzer());
    RadarSession.install(
      RadarSession(
        connection: connection,
        memory: MemoryController(
          snapshotSource: source,
          connection: connection,
        ),
        perf: PerfDataController(callExtension: devtoolsPerfCallExtension),
        exporter: const DevToolsSnapshotExporter(),
        projectContext: DtdProjectContext(),
        onInit: notifier.init,
      ),
    );
    unawaited(RadarSession.instance.attachStore(DtdSnapshotStore()));
  }

  @override
  Widget build(BuildContext context) {
    return const DevToolsExtension(child: LeakRadarMainScaffold());
  }
}
