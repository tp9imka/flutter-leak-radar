import 'package:flutter/material.dart';
import 'package:radar_workbench/radar_workbench.dart';

import '../workspace/workspace_controller.dart';

/// Retaining-paths master–detail for the active dump. Reuses the workbench
/// `RetainingPathsView` (reads `memory.focused`).
class PathsScreen extends StatelessWidget {
  const PathsScreen({super.key, required this.workspace});

  final WorkspaceController workspace;

  @override
  Widget build(BuildContext context) =>
      RetainingPathsView(controller: workspace.memory);
}
