import 'dart:async';

import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/material.dart';

import 'presentation/main_scaffold.dart';
import 'session/dtd_snapshot_store.dart';
import 'session/radar_session.dart';

/// Root widget of the Leak Radar DevTools extension.
///
/// Wraps the app in [DevToolsExtension] which wires up [serviceManager],
/// [extensionManager], and the DTD connection before the child tree builds.
/// On startup it attaches the durable [DtdSnapshotStore] so a session captured
/// before DevTools disposed this iframe (e.g. while another DevTools tab was
/// active) is restored on return.
class LeakRadarDevToolsExtension extends StatefulWidget {
  const LeakRadarDevToolsExtension({super.key});

  @override
  State<LeakRadarDevToolsExtension> createState() =>
      _LeakRadarDevToolsExtensionState();
}

class _LeakRadarDevToolsExtensionState
    extends State<LeakRadarDevToolsExtension> {
  @override
  void initState() {
    super.initState();
    unawaited(RadarSession.instance.attachStore(DtdSnapshotStore()));
  }

  @override
  Widget build(BuildContext context) {
    return const DevToolsExtension(child: LeakRadarMainScaffold());
  }
}
