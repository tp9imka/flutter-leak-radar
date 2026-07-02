import 'package:flutter/material.dart';
import 'package:radar_workbench/radar_workbench.dart';

import '../workspace/workspace_controller.dart';

/// The single-dump class histogram for the workspace's active dump. Reuses the
/// workbench `ClassHistogramView` unchanged — it reads `memory.focused`, which
/// the workspace points at the active dump via `MemoryController.focusOn`.
class HistogramScreen extends StatelessWidget {
  const HistogramScreen({super.key, required this.workspace});

  final WorkspaceController workspace;

  @override
  Widget build(BuildContext context) =>
      ClassHistogramView(controller: workspace.memory);
}
