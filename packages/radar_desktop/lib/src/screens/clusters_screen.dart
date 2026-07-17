import 'package:flutter/material.dart';
import 'package:radar_workbench/radar_workbench.dart';

import '../workspace/workspace_controller.dart';

/// Ranked leak clusters + capture warnings for the workspace's active dump.
/// Reuses the workbench `LeakClustersView` (reads `memory.focused`) and the
/// workspace `projectContext` so "yours" attribution and open-in-editor honor
/// any project folder set on the Retaining paths screen.
class ClustersScreen extends StatelessWidget {
  const ClustersScreen({super.key, required this.workspace});

  final WorkspaceController workspace;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: workspace,
    builder: (context, _) => LeakClustersView(
      controller: workspace.memory,
      projectContext: workspace.projectContext,
    ),
  );
}
