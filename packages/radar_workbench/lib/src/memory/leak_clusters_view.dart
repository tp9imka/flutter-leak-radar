import 'package:flutter/material.dart';
import 'package:leak_graph/leak_graph.dart';
import 'package:radar_ui/radar_ui.dart';

import '../core/project_context.dart';
import '../presentation/retaining_path_tile.dart';
import 'mem_format.dart';
import 'memory_controller.dart';
import 'package_group_scaffold.dart';
import 'root_kind_ui.dart';

/// The declaring library of the hop app code holds the leak at, or null when
/// [cluster] has no anchor (or the index is out of range — never guessed).
Uri? clusterAnchorLibrary(GraphLeakCluster cluster) {
  final index = cluster.anchorHopIndex;
  if (index == null) return null;
  final hops = cluster.representativePath.hops;
  if (index < 0 || index >= hops.length) return null;
  return hops[index].libraryUri;
}

/// The EFFECTIVE ownership origin for [cluster]: the anchor library when one
/// exists, else the declaring library. Mirrors [effectiveOriginOf] so a
/// cluster's chip and its rank agree on who owns it.
RadarOrigin clusterEffectiveOrigin(
  GraphLeakCluster cluster, {
  required Set<String> projectPackages,
}) => effectiveOriginOf(
  cluster.libraryUri,
  clusterAnchorLibrary(cluster),
  projectPackages: projectPackages,
);

bool _isProjectAnchored(
  GraphLeakCluster cluster,
  Set<String> projectPackages,
) =>
    clusterEffectiveOrigin(cluster, projectPackages: projectPackages) ==
    RadarOrigin.project;

int _weight(GraphLeakCluster cluster) =>
    cluster.retainedShallowBytes * cluster.instanceCount;

/// Ranks [clusters] highest-signal first: confidence descending (confirmed
/// before heuristic), then project-anchored before the rest, then
/// shallowBytes × instances descending. Exact ties break on [signature]
/// ascending so the order is fully deterministic and input-order independent.
List<GraphLeakCluster> rankLeakClusters(
  List<GraphLeakCluster> clusters, {
  required Set<String> projectPackages,
}) {
  final ranked = [...clusters];
  ranked.sort((a, b) {
    final byConfidence = b.confidence.index.compareTo(a.confidence.index);
    if (byConfidence != 0) return byConfidence;
    final aProject = _isProjectAnchored(a, projectPackages);
    final bProject = _isProjectAnchored(b, projectPackages);
    if (aProject != bProject) return aProject ? -1 : 1;
    final byWeight = _weight(b).compareTo(_weight(a));
    if (byWeight != 0) return byWeight;
    return a.signature.compareTo(b.signature);
  });
  return ranked;
}

/// The analyzer's highest-signal output made visible: ranked leak clusters for
/// the focused snapshot, each expandable to its representative retaining path,
/// with capture warnings surfaced in an alert strip so failures stop being
/// invisible.
///
/// Shares the focused-snapshot data source with the other memory views (reads
/// [MemoryController.focused]). [projectContext] refines which packages count
/// as "yours" (seeded from the analysis's own resolved set); it defaults to
/// [NoProjectContext] for hosts without a project folder.
class LeakClustersView extends StatelessWidget {
  const LeakClustersView({
    super.key,
    required this.controller,
    this.projectContext = const NoProjectContext(),
  });

  final MemoryController controller;
  final ProjectContext projectContext;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final snapshot = controller.focused;
        if (snapshot == null) {
          return const _CenteredHint(
            'Capture a snapshot to detect leak clusters.',
          );
        }
        return _LeakClustersBody(
          key: ValueKey(snapshot.id),
          analysis: snapshot.analysisResult,
          projectContext: projectContext,
        );
      },
    );
  }
}

class _LeakClustersBody extends StatefulWidget {
  const _LeakClustersBody({
    super.key,
    required this.analysis,
    required this.projectContext,
  });

  final GraphAnalysisResult analysis;
  final ProjectContext projectContext;

  @override
  State<_LeakClustersBody> createState() => _LeakClustersBodyState();
}

class _LeakClustersBodyState extends State<_LeakClustersBody> {
  /// Signature of the expanded cluster, or null when all rows are collapsed.
  String? _expanded;

  /// Effective project set, seeded synchronously from the analysis then
  /// refined once the host [ProjectContext] resolves.
  late Set<String> _effective;

  Set<String> get _analysisPackages =>
      widget.analysis.resolvedAppPackages.toSet();

  @override
  void initState() {
    super.initState();
    _effective = _analysisPackages;
    _resolveProjectPackages();
  }

  @override
  void didUpdateWidget(_LeakClustersBody old) {
    super.didUpdateWidget(old);
    if (!identical(widget.projectContext, old.projectContext)) {
      _resolveProjectPackages();
    }
  }

  Future<void> _resolveProjectPackages() async {
    final resolved = await widget.projectContext.projectPackages();
    if (!mounted) return;
    setState(() {
      _effective = resolved.isNotEmpty ? resolved : _analysisPackages;
    });
  }

  @override
  Widget build(BuildContext context) {
    final warnings = widget.analysis.stats.warnings;
    final clusters = rankLeakClusters(
      widget.analysis.clusters,
      projectPackages: _effective,
    );
    final canOpen = widget.projectContext.canOpenSource;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (warnings.isNotEmpty) _WarningsStrip(warnings: warnings),
        Expanded(
          child: clusters.isEmpty
              ? _EmptyState(stats: widget.analysis.stats)
              : ListView.builder(
                  itemCount: clusters.length,
                  itemBuilder: (context, i) {
                    final cluster = clusters[i];
                    return _ClusterRow(
                      cluster: cluster,
                      origin: clusterEffectiveOrigin(
                        cluster,
                        projectPackages: _effective,
                      ),
                      expanded: cluster.signature == _expanded,
                      projectPackages: _effective,
                      onOpenSource: canOpen
                          ? widget.projectContext.openSource
                          : null,
                      onTap: () => setState(
                        () => _expanded = cluster.signature == _expanded
                            ? null
                            : cluster.signature,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// The alert strip surfacing capture/analysis warnings above the cluster list.
class _WarningsStrip extends StatelessWidget {
  const _WarningsStrip({required this.warnings});

  final List<String> warnings;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: RadarColors.warning.withValues(alpha: 0.10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final warning in warnings)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 14,
                    color: RadarColors.warning,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      warning,
                      style: RadarTypography.monoLabel.copyWith(
                        color: RadarColors.warning,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Honest empty state: names how many leak candidates were suppressed (by the
/// app filter and the live-tree filter) rather than implying a clean heap.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.stats});

  final GraphAnalysisStats stats;

  @override
  Widget build(BuildContext context) {
    final suppressed = stats.suppressedByAppFilter + stats.suppressedByLiveTree;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('No leak clusters', style: RadarTypography.appBarTitle),
            const SizedBox(height: 6),
            Text(
              '$suppressed candidates suppressed',
              style: RadarTypography.caption,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ClusterRow extends StatelessWidget {
  const _ClusterRow({
    required this.cluster,
    required this.origin,
    required this.expanded,
    required this.projectPackages,
    required this.onTap,
    required this.onOpenSource,
  });

  final GraphLeakCluster cluster;
  final RadarOrigin origin;
  final bool expanded;
  final Set<String> projectPackages;
  final VoidCallback onTap;
  final Future<bool> Function(Uri libraryUri)? onOpenSource;

  @override
  Widget build(BuildContext context) {
    final packageLabel = packageLabelOf(
      clusterAnchorLibrary(cluster) ?? cluster.libraryUri,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: expanded ? RadarColors.accentSubtle : RadarColors.rowBgDefault,
        border: const Border(
          bottom: BorderSide(
            color: RadarColors.hairline08,
            width: RadarDensity.hairline,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      RootDot(kind: cluster.rootKind),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          cluster.className,
                          style: RadarTypography.monoBody.copyWith(
                            fontSize: 12,
                            color: expanded ? RadarColors.accent : null,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      OriginChip(origin: origin),
                      const SizedBox(width: 6),
                      _ConfidenceBadge(confidence: cluster.confidence),
                      const SizedBox(width: 4),
                      Icon(
                        expanded ? Icons.expand_less : Icons.expand_more,
                        size: 16,
                        color: RadarColors.text40,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  _MetaLine(
                    packageLabel: packageLabel,
                    instances: cluster.instanceCount,
                    shallowBytes: cluster.retainedShallowBytes,
                    rootKind: cluster.rootKind,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            _ExpandedDetail(
              cluster: cluster,
              projectPackages: projectPackages,
              onOpenSource: onOpenSource,
            ),
        ],
      ),
    );
  }
}

/// The overflow-safe secondary line: package, instance count, shallow-labeled
/// bytes, and the root kind.
class _MetaLine extends StatelessWidget {
  const _MetaLine({
    required this.packageLabel,
    required this.instances,
    required this.shallowBytes,
    required this.rootKind,
  });

  final String? packageLabel;
  final int instances;
  final int shallowBytes;
  final RootKind rootKind;

  @override
  Widget build(BuildContext context) {
    final style = RadarTypography.monoLabel.copyWith(color: RadarColors.text60);
    return Wrap(
      spacing: 14,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (packageLabel != null) Text(packageLabel!, style: style),
        Text('$instances×', style: style),
        Text('${fmtBytes(shallowBytes)} shallow', style: style),
        Text(rootKind.label, style: style),
      ],
    );
  }
}

class _ExpandedDetail extends StatelessWidget {
  const _ExpandedDetail({
    required this.cluster,
    required this.projectPackages,
    required this.onOpenSource,
  });

  final GraphLeakCluster cluster;
  final Set<String> projectPackages;
  final Future<bool> Function(Uri libraryUri)? onOpenSource;

  @override
  Widget build(BuildContext context) {
    final leaf = cluster.leafClassName;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (leaf != null) ...[
            Text(
              'leaf: $leaf',
              style: RadarTypography.monoLabel.copyWith(
                color: RadarColors.text60,
              ),
            ),
            const SizedBox(height: 8),
          ],
          RetainingPathTile(
            path: cluster.representativePath,
            title: 'Representative retaining path',
            anchorHopIndex: cluster.anchorHopIndex,
            projectPackages: projectPackages,
            onOpenSource: onOpenSource,
          ),
        ],
      ),
    );
  }
}

class _ConfidenceBadge extends StatelessWidget {
  const _ConfidenceBadge({required this.confidence});

  final LeakConfidence confidence;

  @override
  Widget build(BuildContext context) {
    final confirmed = confidence == LeakConfidence.confirmed;
    return RadarTag(
      label: confirmed ? 'CONFIRMED' : 'HEURISTIC',
      color: confirmed ? RadarColors.warning : RadarColors.text40,
    );
  }
}

class _CenteredHint extends StatelessWidget {
  const _CenteredHint(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          style: RadarTypography.caption,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
