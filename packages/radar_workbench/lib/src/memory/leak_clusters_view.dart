import 'package:flutter/material.dart';
import 'package:leak_graph/leak_graph.dart';
import 'package:radar_ui/radar_ui.dart';

import '../core/project_context.dart';
import '../presentation/retaining_path_tile.dart';
import '../session/triage_store.dart';
import 'mem_format.dart';
import 'memory_controller.dart';
import 'package_group_scaffold.dart';
import 'root_kind_ui.dart';

part 'cluster_triage_ui.dart';

/// The in-range anchor hop index for [cluster], or null when there is no
/// anchor (or the recorded index falls outside the representative path —
/// never trusted blindly). The single source of truth for anchor validity:
/// the "yours" highlight and the leaf disclosure both key off it so they can
/// only ever appear together.
int? clusterAnchorHopIndex(GraphLeakCluster cluster) {
  final index = cluster.anchorHopIndex;
  if (index == null) return null;
  final hops = cluster.representativePath.hops;
  if (index < 0 || index >= hops.length) return null;
  return index;
}

/// The declaring library of the hop app code holds the leak at, or null when
/// [cluster] has no in-range anchor.
Uri? clusterAnchorLibrary(GraphLeakCluster cluster) {
  final index = clusterAnchorHopIndex(cluster);
  return index == null
      ? null
      : cluster.representativePath.hops[index].libraryUri;
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
    this.initialTriage = TriageStore.empty,
    this.onTriageChanged,
    this.clock,
  });

  final MemoryController controller;
  final ProjectContext projectContext;

  /// The cross-session triage baseline to compare the current clusters against
  /// (the store loaded from disk plus prior ACKs). Defaults to empty, in which
  /// case every cluster reads as NEW and ACKs live only for the session.
  final TriageStore initialTriage;

  /// Called with the updated store after an ACK so the host can persist it.
  final ValueChanged<TriageStore>? onTriageChanged;

  /// Clock for `firstSeen` stamps on ACK. Injected for tests; defaults to
  /// [DateTime.now].
  final DateTime Function()? clock;

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
          initialTriage: initialTriage,
          onTriageChanged: onTriageChanged,
          clock: clock ?? DateTime.now,
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
    required this.initialTriage,
    required this.onTriageChanged,
    required this.clock,
  });

  final GraphAnalysisResult analysis;
  final ProjectContext projectContext;
  final TriageStore initialTriage;
  final ValueChanged<TriageStore>? onTriageChanged;
  final DateTime Function() clock;

  @override
  State<_LeakClustersBody> createState() => _LeakClustersBodyState();
}

class _LeakClustersBodyState extends State<_LeakClustersBody> {
  /// Signature of the expanded cluster, or null when all rows are collapsed.
  String? _expanded;

  /// Effective project set, seeded synchronously from the analysis then
  /// refined once the host [ProjectContext] resolves.
  late Set<String> _effective;

  /// In-session triage store (loaded baseline + ACKs made this session).
  late TriageStore _triage;

  /// When true, the cluster list is narrowed to signatures new since the last
  /// session; the GONE section stays visible regardless.
  bool _sinceLastSession = false;

  Set<String> get _analysisPackages =>
      widget.analysis.resolvedAppPackages.toSet();

  @override
  void initState() {
    super.initState();
    _effective = _analysisPackages;
    _triage = widget.initialTriage;
    _resolveProjectPackages();
  }

  @override
  void didUpdateWidget(_LeakClustersBody old) {
    super.didUpdateWidget(old);
    if (!identical(widget.projectContext, old.projectContext)) {
      _resolveProjectPackages();
    }
    // A new baseline pushed by the host (e.g. an async session restore)
    // replaces the in-session store. Keyed on identity so it doesn't clobber
    // an ACK the view just reported back.
    if (!identical(widget.initialTriage, old.initialTriage)) {
      _triage = widget.initialTriage;
    }
  }

  Future<void> _resolveProjectPackages() async {
    final resolved = await widget.projectContext.projectPackages();
    if (!mounted) return;
    setState(() {
      _effective = resolved.isNotEmpty ? resolved : _analysisPackages;
    });
  }

  Future<void> _acknowledge(GraphLeakCluster cluster) async {
    final result = await _promptForNote(context, cluster);
    if (!mounted || !result.confirmed) return;
    setState(() {
      _triage = _triage.acknowledge(
        cluster.signature,
        note: result.note,
        now: widget.clock(),
      );
    });
    widget.onTriageChanged?.call(_triage);
  }

  @override
  Widget build(BuildContext context) {
    final warnings = widget.analysis.stats.warnings;
    final clusters = rankLeakClusters(
      widget.analysis.clusters,
      projectPackages: _effective,
    );
    // GONE must be computed against the UNFILTERED current signature set: the
    // "since last session" toggle hides rows but must never make a still-present
    // cluster read as GONE. Feed displayFor every cluster's signature.
    final currentSignatures = clusters.map((c) => c.signature);
    final displays = _triage.displayFor(currentSignatures);
    final gone = [
      for (final entry in _triage.entries)
        if (displays[entry.signature] == TriageDisplay.gone) entry,
    ]..sort((a, b) => a.signature.compareTo(b.signature));
    final visible = _sinceLastSession
        ? [
            for (final c in clusters)
              if (displays[c.signature] == TriageDisplay.fresh) c,
          ]
        : clusters;
    final canOpen = widget.projectContext.canOpenSource;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (warnings.isNotEmpty) _WarningsStrip(warnings: warnings),
        _TriageToolbar(
          sinceLastSession: _sinceLastSession,
          onSinceLastSession: (on) => setState(() => _sinceLastSession = on),
        ),
        if (gone.isNotEmpty) _GoneSection(entries: gone),
        Expanded(
          child: clusters.isEmpty
              ? _EmptyState(stats: widget.analysis.stats)
              : visible.isEmpty
              ? const _CenteredHint('No new leak clusters since last session.')
              : ListView.builder(
                  itemCount: visible.length,
                  itemBuilder: (context, i) {
                    final cluster = visible[i];
                    return _ClusterRow(
                      cluster: cluster,
                      origin: clusterEffectiveOrigin(
                        cluster,
                        projectPackages: _effective,
                      ),
                      display:
                          displays[cluster.signature] ?? TriageDisplay.fresh,
                      expanded: cluster.signature == _expanded,
                      projectPackages: _effective,
                      onOpenSource: canOpen
                          ? widget.projectContext.openSource
                          : null,
                      onAcknowledge: () => _acknowledge(cluster),
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

  /// Height cap before the strip scrolls — keeps it from crowding out the
  /// cluster list even when a capture emits dozens of warnings.
  static const double _maxStripHeight = 148;

  final List<String> warnings;

  @override
  Widget build(BuildContext context) {
    // Bounded + scrollable: a capture can emit arbitrarily many warnings, and
    // this strip sits ABOVE the Expanded cluster list — an unbounded Column
    // here would hard-overflow the frame. Cap the height and let the overflow
    // scroll so every warning stays reachable.
    return Container(
      width: double.infinity,
      color: RadarColors.warning.withValues(alpha: 0.10),
      constraints: const BoxConstraints(maxHeight: _maxStripHeight),
      child: SingleChildScrollView(
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
            Text(
              suppressed > 0
                  ? 'No leak clusters'
                  : 'No leak clusters in this snapshot',
              style: RadarTypography.appBarTitle,
            ),
            // Only surface the suppressed count when it is real — a "0
            // candidates suppressed" line would imply filtering that did not
            // happen.
            if (suppressed > 0) ...[
              const SizedBox(height: 6),
              Text(
                '$suppressed candidates suppressed',
                style: RadarTypography.caption,
                textAlign: TextAlign.center,
              ),
            ],
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
    required this.display,
    required this.expanded,
    required this.projectPackages,
    required this.onTap,
    required this.onOpenSource,
    required this.onAcknowledge,
  });

  final GraphLeakCluster cluster;
  final RadarOrigin origin;
  final TriageDisplay display;
  final bool expanded;
  final Set<String> projectPackages;
  final VoidCallback onTap;
  final Future<bool> Function(Uri libraryUri)? onOpenSource;
  final VoidCallback onAcknowledge;

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
                      TriageChip(display: display),
                      const SizedBox(width: 6),
                      OriginChip(origin: origin),
                      const SizedBox(width: 6),
                      _ConfidenceBadge(confidence: cluster.confidence),
                      _AckMenuButton(
                        display: display,
                        onAcknowledge: onAcknowledge,
                      ),
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
    // Gate the leaf disclosure on the SAME in-range anchor the "yours"
    // highlight uses, so an unanchored (or out-of-range) cluster never shows a
    // leaf without the anchor that gives it meaning.
    final anchorIndex = clusterAnchorHopIndex(cluster);
    final leaf = anchorIndex == null ? null : cluster.leafClassName;
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
            anchorHopIndex: anchorIndex,
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
