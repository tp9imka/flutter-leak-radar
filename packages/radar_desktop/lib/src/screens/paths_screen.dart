import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:radar_ui/radar_ui.dart';
import 'package:radar_workbench/radar_workbench.dart';

import '../workspace/workspace_controller.dart';

/// Retaining-paths master–detail for the active dump. Reuses the workbench
/// `RetainingPathsView` (reads `memory.focused`), plus a desktop-only project
/// folder picker that powers "yours" attribution and open-in-editor.
class PathsScreen extends StatelessWidget {
  const PathsScreen({super.key, required this.workspace});

  final WorkspaceController workspace;

  Future<void> _pickFolder() async {
    final dir = await getDirectoryPath();
    if (dir != null) workspace.setProjectRoot(dir);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: workspace,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ProjectFolderBar(
            projectRoot: workspace.projectRoot,
            onPick: _pickFolder,
            onClear: () => workspace.setProjectRoot(null),
          ),
          Expanded(
            child: RetainingPathsView(
              controller: workspace.memory,
              projectContext: workspace.projectContext,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectFolderBar extends StatelessWidget {
  const _ProjectFolderBar({
    required this.projectRoot,
    required this.onPick,
    required this.onClear,
  });

  final String? projectRoot;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final root = projectRoot;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: RadarColors.bgPanel,
        border: Border(
          bottom: BorderSide(
            color: RadarColors.hairline08,
            width: RadarDensity.hairline,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            const Icon(Icons.folder_open, size: 14, color: RadarColors.text60),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                root ??
                    'No project folder — open one to attribute & jump to '
                        'source',
                style: RadarTypography.monoLabel.copyWith(
                  color: root == null ? RadarColors.text40 : RadarColors.text80,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (root != null)
              TextButton(onPressed: onClear, child: const Text('Clear')),
            TextButton(
              onPressed: onPick,
              child: Text(root == null ? 'Set project folder' : 'Change'),
            ),
          ],
        ),
      ),
    );
  }
}
