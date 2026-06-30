import 'package:flutter/material.dart';
import 'package:leak_graph/leak_graph.dart';
import 'package:radar_ui/radar_ui.dart';

import '../diff/diff_controller.dart';
import '../presentation/retaining_path_tile.dart';

/// Shows retaining-path cards for all classes that grew in the latest diff.
///
/// Empty state prompts the user to complete a snapshot diff first.
/// When diff data exists, grown classes are matched against clusters in
/// [DiffController.snapshotB]'s analysis result.
class RetainingPathsView extends StatelessWidget {
  const RetainingPathsView({super.key, required this.controller});

  final DiffController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => _RetainingPathsContent(controller: controller),
    );
  }
}

class _RetainingPathsContent extends StatelessWidget {
  const _RetainingPathsContent({required this.controller});

  final DiffController controller;

  @override
  Widget build(BuildContext context) {
    final diff = controller.diff;
    if (diff == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Complete a snapshot diff to see retaining paths.',
            style: TextStyle(color: RadarColors.text40, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final clusters = controller.snapshotB?.analysisResult.clusters ?? [];
    final grownClassNames = diff
        .where((d) => d.instanceDelta > 0)
        .map((d) => d.after.className)
        .toSet();

    final matchedClusters = clusters
        .where((c) => grownClassNames.contains(c.className))
        .toList();

    if (matchedClusters.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Retaining path data not available for grown classes. '
            'Try the in-app Inspector for path analysis.',
            style: TextStyle(color: RadarColors.text40, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: const BoxDecoration(
            color: RadarColors.bgPanel,
            border: Border(
              bottom: BorderSide(
                color: RadarColors.hairline08,
                width: RadarDensity.hairline,
              ),
            ),
          ),
          child: SizedBox(
            height: 44,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Text('Retaining Paths', style: RadarTypography.appBarTitle),
                  const SizedBox(width: 8),
                  Text(
                    '${matchedClusters.length} clusters',
                    style: RadarTypography.monoLabel,
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: matchedClusters.length,
            itemBuilder: (context, i) =>
                _ClusterCard(cluster: matchedClusters[i]),
          ),
        ),
      ],
    );
  }
}

class _ClusterCard extends StatelessWidget {
  const _ClusterCard({required this.cluster});

  final GraphLeakCluster cluster;

  String _fmtBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String _libraryLabel() {
    final uri = cluster.libraryUri;
    if (uri == null) return '--';
    final s = uri.toString();
    if (s.startsWith('package:')) {
      return s.substring('package:'.length).split('/').first;
    }
    return s.split('/').last;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: RadarColors.bgSurface,
        borderRadius: const BorderRadius.all(Radius.circular(8)),
        border: Border.all(
          color: RadarColors.hairline08,
          width: RadarDensity.hairline,
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  cluster.className,
                  style: RadarTypography.monoBody,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              RadarTag(
                label: '+${cluster.instanceCount}',
                color: RadarColors.critical,
              ),
              const SizedBox(width: 6),
              RadarTag(
                label: _fmtBytes(cluster.retainedShallowBytes),
                color: RadarColors.critical,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(_libraryLabel(), style: RadarTypography.monoLabel),
          const SizedBox(height: 8),
          RetainingPathTile(
            path: cluster.representativePath,
            title: 'Representative path',
          ),
        ],
      ),
    );
  }
}
