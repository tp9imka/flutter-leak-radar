import 'package:flutter/material.dart';
import 'package:leak_graph/leak_graph.dart';

import '../diff/diff_controller.dart';
import 'retaining_path_tile.dart';

/// Shows leak clusters from the most recent snapshot (B if available, else A).
class ClustersView extends StatelessWidget {
  const ClustersView({super.key, required this.controller});

  final DiffController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final bundle = controller.snapshotB ?? controller.snapshotA;
        if (bundle == null) {
          return const Center(
            child: Text('Capture a snapshot to see leak clusters.'),
          );
        }
        final clusters = bundle.analysisResult.clusters;
        final stats = bundle.analysisResult.stats;

        if (clusters.isEmpty) {
          return Center(
            child: Text(
              'No leak clusters detected in ${bundle.label}.\n'
              '(${stats.reachableObjects} reachable objects scanned)',
              textAlign: TextAlign.center,
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StatsBar(stats: stats, label: bundle.label),
            Expanded(
              child: ListView.builder(
                itemCount: clusters.length,
                itemBuilder: (context, i) => _ClusterCard(cluster: clusters[i]),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StatsBar extends StatelessWidget {
  const _StatsBar({required this.stats, required this.label});

  final GraphAnalysisStats stats;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Text(
        '$label — ${stats.totalObjects} objects | '
        '${stats.reachableObjects} reachable | '
        '${stats.leakCandidates} candidates | '
        '${stats.clusters} cluster(s)',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class _ClusterCard extends StatelessWidget {
  const _ClusterCard({required this.cluster});

  final GraphLeakCluster cluster;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.warning_amber,
                  size: 16,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 6),
                Text(
                  cluster.className,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontFamily: 'monospace'),
                ),
                const Spacer(),
                Text(
                  '×${cluster.instanceCount}  '
                  '(${_bytes(cluster.retainedShallowBytes)})',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Root: ${cluster.rootKind.label}  '
              '| Confidence: ${cluster.confidence.name}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
            RetainingPathTile(
              path: cluster.representativePath,
              title: 'Representative retaining path',
            ),
          ],
        ),
      ),
    );
  }

  String _bytes(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
