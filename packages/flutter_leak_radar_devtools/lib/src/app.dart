import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/material.dart';

import 'presentation/main_scaffold.dart';

/// Root widget of the Leak Radar DevTools extension.
///
/// Wraps the app in [DevToolsExtension] which wires up [serviceManager] and
/// [extensionManager] before the child widget tree builds.
class LeakRadarDevToolsExtension extends StatelessWidget {
  const LeakRadarDevToolsExtension({super.key});

  @override
  Widget build(BuildContext context) {
    return const DevToolsExtension(child: LeakRadarMainScaffold());
  }
}
