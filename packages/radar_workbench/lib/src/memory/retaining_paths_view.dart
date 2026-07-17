import 'package:flutter/material.dart';
import 'package:leak_graph/leak_graph.dart';
import 'package:radar_ui/radar_ui.dart';

import '../core/project_context.dart';
import '../filter/filter_bar.dart';
import '../filter/filter_expression.dart';
import 'class_detail_panel.dart';
import 'filter_target.dart';
import 'memory_controller.dart';
import 'package_group_scaffold.dart';
import 'root_kind_ui.dart';

/// Browsable retaining-path explorer for the focused snapshot.
///
/// Every reachable class has a root profile (not just leak candidates), so
/// this is populated whenever a snapshot exists. Classes are grouped by the
/// bucket of their dominant closest-root kind — separating live-tree-retained
/// objects from leak-prone ones — and selecting one shows its full root
/// breakdown + representative path with per-hop origin and a "yours" anchor.
class RetainingPathsView extends StatelessWidget {
  const RetainingPathsView({
    super.key,
    required this.controller,
    this.projectContext = const NoProjectContext(),
  });

  final MemoryController controller;

  /// Host project identity: resolves which packages are "yours" (with an
  /// optional manual override) and — on desktop — opens hop sources.
  final ProjectContext projectContext;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final snapshot = controller.focused;
        final profiles = snapshot?.analysisResult.classRootProfiles ?? const [];
        if (snapshot == null || profiles.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                snapshot == null
                    ? 'Capture a snapshot to explore retaining paths.'
                    : 'No reachable classes to profile in this snapshot.',
                style: RadarTypography.caption,
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return _RetainingPathsBody(
          key: ValueKey(snapshot.id),
          analysis: snapshot.analysisResult,
          projectContext: projectContext,
        );
      },
    );
  }
}

RootKind _dominantKind(ClassRootProfile p) {
  if (p.byRoot.isEmpty) return RootKind.other;
  RootKind best = RootKind.other;
  var bestCount = -1;
  for (final e in p.byRoot.entries) {
    final wins =
        e.value > bestCount ||
        (e.value == bestCount && rootBucket(e.key) == RootBucket.leakProne);
    if (wins) {
      best = e.key;
      bestCount = e.value;
    }
  }
  return best;
}

class _RetainingPathsBody extends StatefulWidget {
  const _RetainingPathsBody({
    super.key,
    required this.analysis,
    required this.projectContext,
  });

  final GraphAnalysisResult analysis;
  final ProjectContext projectContext;

  @override
  State<_RetainingPathsBody> createState() => _RetainingPathsBodyState();
}

class _RetainingPathsBodyState extends State<_RetainingPathsBody> {
  FilterExpression _filter = FilterExpression.empty;
  String? _selected;
  Set<String> _manualPackages = const {};

  /// Effective project set + its honest source label. Seeded synchronously
  /// from the analysis, then refined once the host [ProjectContext] resolves.
  late Set<String> _effective;
  late String _sourceLabel;

  // Groups in surfacing order: suspicious first, live last.
  static const _order = [
    RootBucket.leakProne,
    RootBucket.other,
    RootBucket.live,
  ];

  List<ClassRootProfile> get _profiles => widget.analysis.classRootProfiles;

  Set<String> get _analysisPackages =>
      widget.analysis.resolvedAppPackages.toSet();

  Map<String, Uri?> get _anchors => classAnchorsFor(widget.analysis);
  Map<String, AnchorHop> get _anchorHops => classAnchorHopsFor(widget.analysis);

  @override
  void initState() {
    super.initState();
    _effective = _analysisPackages;
    _sourceLabel = _analysisPackages.isEmpty ? 'none' : 'analysis';
    _resolveProjectPackages();
  }

  @override
  void didUpdateWidget(_RetainingPathsBody old) {
    super.didUpdateWidget(old);
    // A host swapping the project context (e.g. the desktop folder picker)
    // must re-resolve who counts as "yours".
    if (!identical(widget.projectContext, old.projectContext)) {
      _resolveProjectPackages();
    }
  }

  /// Resolves the effective project set through an [OverridableProjectContext]
  /// (manual override trumps host detection), falling back to the analysis's
  /// own resolved packages. The label always names the winning source, never a
  /// detection that didn't happen.
  Future<void> _resolveProjectPackages() async {
    final context = OverridableProjectContext(
      widget.projectContext,
      manualPackages: _manualPackages,
    );
    final resolved = await context.projectPackages();
    if (!mounted) return;
    setState(() {
      if (resolved.isNotEmpty) {
        _effective = resolved;
        _sourceLabel = context.sourceLabel;
      } else if (_analysisPackages.isNotEmpty) {
        _effective = _analysisPackages;
        _sourceLabel = 'analysis';
      } else {
        _effective = const {};
        _sourceLabel = context.sourceLabel;
      }
    });
  }

  void _setManualPackages(String raw) {
    final packages = {
      for (final part in raw.split(','))
        if (part.trim().isNotEmpty) part.trim(),
    };
    setState(() => _manualPackages = packages);
    _resolveProjectPackages();
  }

  Map<RootBucket, List<ClassRootProfile>> _grouped() {
    final visible = _filter.isEmpty
        ? _profiles
        : _profiles.where(
            (p) => _filter.matches(
              ClassRow(className: p.className, libraryUri: p.libraryUri),
              projectPackages: _effective,
              anchorLibraryUri: _anchors[p.className],
            ),
          );
    final groups = {for (final b in _order) b: <ClassRootProfile>[]};
    for (final p in visible) {
      groups[rootBucket(_dominantKind(p))]!.add(p);
    }
    for (final list in groups.values) {
      list.sort(
        (a, b) => b.retainedShallowBytes.compareTo(a.retainedShallowBytes),
      );
    }
    return groups;
  }

  ClassRootProfile? _profileFor(String? className) {
    if (className == null) return null;
    for (final p in _profiles) {
      if (p.className == className) return p;
    }
    return null;
  }

  ClassPathDistribution? _distributionFor(String? className) {
    if (className == null) return null;
    for (final d in widget.analysis.classPathDistributions) {
      if (d.className == className) return d;
    }
    return null;
  }

  /// Anchor hop index for [profile]'s representative path — only when the
  /// dominant cluster's anchor path STRUCTURALLY matches it (never guessed).
  int? _representativeAnchor(ClassRootProfile? profile) {
    if (profile?.representativePath == null) return null;
    final anchor = _anchorHops[profile!.className];
    if (anchor == null) return null;
    return anchor.path == profile.representativePath ? anchor.index : null;
  }

  @override
  Widget build(BuildContext context) {
    final groups = _grouped();
    final anyRows = groups.values.any((l) => l.isNotEmpty);
    final selectedProfile = _profileFor(_selected);
    final canOpen = widget.projectContext.canOpenSource;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Toolbar(
                filter: _filter,
                sourceLabel: _sourceLabel,
                onFilter: (f) => setState(() => _filter = f),
                onManualPackages: _setManualPackages,
              ),
              Expanded(
                child: !anyRows
                    ? Center(
                        child: Text(
                          'No classes match the filter.',
                          style: RadarTypography.caption,
                        ),
                      )
                    : ListView(
                        children: [
                          for (final bucket in _order)
                            if (groups[bucket]!.isNotEmpty) ...[
                              _GroupHeader(
                                bucket: bucket,
                                count: groups[bucket]!.length,
                              ),
                              for (final p in groups[bucket]!)
                                _ProfileRow(
                                  profile: p,
                                  selected: p.className == _selected,
                                  onTap: () => setState(
                                    () => _selected = p.className == _selected
                                        ? null
                                        : p.className,
                                  ),
                                ),
                            ],
                        ],
                      ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        SizedBox(
          width: 340,
          child: ClassDetailPanel(
            className: _selected,
            profile: selectedProfile,
            distribution: _distributionFor(_selected),
            representativeAnchorHopIndex: _representativeAnchor(
              selectedProfile,
            ),
            projectPackages: _effective,
            onOpenSource: canOpen ? widget.projectContext.openSource : null,
          ),
        ),
      ],
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.filter,
    required this.sourceLabel,
    required this.onFilter,
    required this.onManualPackages,
  });

  final FilterExpression filter;
  final String sourceLabel;
  final ValueChanged<FilterExpression> onFilter;
  final ValueChanged<String> onManualPackages;

  @override
  Widget build(BuildContext context) {
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('Retaining Paths', style: RadarTypography.appBarTitle),
                const SizedBox(width: 16),
                Expanded(
                  child: FilterBar(expression: filter, onChanged: onFilter),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _ProjectPackagesRow(
              sourceLabel: sourceLabel,
              onSubmitted: onManualPackages,
            ),
          ],
        ),
      ),
    );
  }
}

/// The honesty row: names the project-package source and lets the developer
/// override it manually (which relabels the source to `manual`).
class _ProjectPackagesRow extends StatelessWidget {
  const _ProjectPackagesRow({
    required this.sourceLabel,
    required this.onSubmitted,
  });

  final String sourceLabel;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'project src: $sourceLabel',
          style: RadarTypography.monoLabel.copyWith(color: RadarColors.text60),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SizedBox(
            height: 28,
            child: TextField(
              key: const Key('projectPackagesField'),
              style: RadarTypography.monoLabel,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                hintText: 'override project packages (comma-separated)',
                border: OutlineInputBorder(),
              ),
              onSubmitted: onSubmitted,
            ),
          ),
        ),
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.bucket, required this.count});

  final RootBucket bucket;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: bucket.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            bucket.label.toUpperCase(),
            style: RadarTypography.monoLabel.copyWith(
              color: RadarColors.text60,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(width: 8),
          Text('$count', style: RadarTypography.monoLabel),
        ],
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.profile,
    required this.selected,
    required this.onTap,
  });

  final ClassRootProfile profile;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final leakProne = profile.byRoot.entries
        .where((e) => rootBucket(e.key) == RootBucket.leakProne)
        .fold(0, (s, e) => s + e.value);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? RadarColors.accentSubtle : RadarColors.rowBgDefault,
          border: const Border(
            bottom: BorderSide(
              color: RadarColors.hairline08,
              width: RadarDensity.hairline,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              RootDot(kind: _dominantKind(profile)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  profile.className,
                  style: RadarTypography.monoBody.copyWith(
                    fontSize: 12,
                    color: selected ? RadarColors.accent : null,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (leakProne > 0) ...[
                RadarTag(
                  label: '$leakProne leak-prone',
                  color: RadarColors.critical,
                ),
                const SizedBox(width: 8),
              ],
              Text(
                '${profile.totalInstances}',
                style: RadarTypography.monoNumber.copyWith(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
