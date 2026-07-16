import 'package:flutter/material.dart';
import 'package:leak_graph/leak_graph.dart';
import 'package:radar_ui/radar_ui.dart';

import 'mem_format.dart';

/// Label for the single merged framework + sdk group. Parenthesized so it can
/// never collide with a real dependency literally named `runtime`.
const String kRuntimeGroupPackage = '(runtime)';

/// Label used when a row's owning package cannot be resolved.
const String kUnknownGroupPackage = '(unknown)';

/// One package's worth of grouped rows, shared by the histogram and diff
/// tables so both surface the same ownership grouping.
///
/// Grouping keys on the ANCHOR package (who retains the class), falling back to
/// the declaring package when a row has no attribution anchor. Framework and
/// SDK rows collapse into one [kRuntimeGroupPackage] group.
final class PackageGroup<T> {
  const PackageGroup({
    required this.package,
    required this.origin,
    required this.rows,
    required this.totalBytes,
    required this.totalDelta,
    required this.hasAnchoredMember,
  });

  /// Package label, e.g. `my_app`, `livekit`, `(unknown)`, or `(runtime)`.
  final String package;

  /// Ownership bucket of [package] (the runtime group reports as framework).
  final RadarOrigin origin;

  /// Member rows, already sorted by metric descending.
  final List<T> rows;

  /// Summed shallow (own) bytes of [rows].
  final int totalBytes;

  /// Summed byte delta of [rows] (0 when no delta accessor was supplied).
  final int totalDelta;

  /// True when at least one member row landed here via a real attribution
  /// anchor (not just declared-package fallback). Drives honest header
  /// wording: `retained via X` when anchored, `declared in X` otherwise.
  final bool hasAnchoredMember;

  /// Project-owned ("yours") code. Pinned first and expanded by default.
  bool get isProject => origin == RadarOrigin.project;

  /// The single merged framework + sdk group. Visible but collapsed by
  /// default; never auto-hidden.
  bool get isRuntime => package == kRuntimeGroupPackage;
}

/// Groups [rows] by their anchor package into ordered [PackageGroup]s.
///
/// Order is the S1 default: project groups first (by metric descending), then
/// dependency / unknown groups, then the one merged runtime group last.
/// [anchorLibraryOf] may return the declared library when a row has no anchor;
/// [deltaOf] is optional — omit it (histogram) to order and total by bytes.
List<PackageGroup<T>> groupRowsByPackage<T>(
  List<T> rows, {
  required Uri? Function(T) declaredLibraryOf,
  required Uri? Function(T) anchorLibraryOf,
  required int Function(T) bytesOf,
  required Set<String> projectPackages,
  int Function(T)? deltaOf,
}) {
  final buckets = <String, _Bucket<T>>{};
  for (final row in rows) {
    final anchor = anchorLibraryOf(row);
    final anchorLib = anchor ?? declaredLibraryOf(row);
    final origin = originOf(anchorLib, projectPackages: projectPackages);
    final isRuntime =
        origin == RadarOrigin.framework || origin == RadarOrigin.sdk;
    final key = isRuntime
        ? kRuntimeGroupPackage
        : (packageLabelOf(anchorLib) ?? kUnknownGroupPackage);
    final groupOrigin = isRuntime ? RadarOrigin.framework : origin;
    final bucket = buckets.putIfAbsent(key, () => _Bucket<T>(key, groupOrigin));
    bucket.rows.add(row);
    bucket.totalBytes += bytesOf(row);
    if (deltaOf != null) bucket.totalDelta += deltaOf(row);
    if (anchor != null) bucket.hasAnchoredMember = true;
  }

  int rowMetric(T r) => deltaOf != null ? deltaOf(r) : bytesOf(r);
  int groupMetric(_Bucket<T> b) =>
      deltaOf != null ? b.totalDelta : b.totalBytes;

  for (final b in buckets.values) {
    b.rows.sort((a, c) => rowMetric(c).compareTo(rowMetric(a)));
  }

  final project = <_Bucket<T>>[];
  final deps = <_Bucket<T>>[];
  _Bucket<T>? runtime;
  for (final b in buckets.values) {
    if (b.origin == RadarOrigin.project) {
      project.add(b);
    } else if (b.key == kRuntimeGroupPackage) {
      runtime = b;
    } else {
      deps.add(b);
    }
  }

  int byMetricDesc(_Bucket<T> a, _Bucket<T> b) {
    final cmp = groupMetric(b).compareTo(groupMetric(a));
    return cmp != 0 ? cmp : a.key.compareTo(b.key);
  }

  project.sort(byMetricDesc);
  deps.sort(byMetricDesc);

  final ordered = <_Bucket<T>>[...project, ...deps];
  if (runtime != null) ordered.add(runtime);

  return [
    for (final b in ordered)
      PackageGroup<T>(
        package: b.key,
        origin: b.origin,
        rows: b.rows,
        totalBytes: b.totalBytes,
        totalDelta: b.totalDelta,
        hasAnchoredMember: b.hasAnchoredMember,
      ),
  ];
}

class _Bucket<T> {
  _Bucket(this.key, this.origin);

  final String key;
  final RadarOrigin origin;
  final List<T> rows = [];
  int totalBytes = 0;
  int totalDelta = 0;
  bool hasAnchoredMember = false;
}

/// The EFFECTIVE ownership origin for a row: the anchor library when one
/// exists ([anchorLibrary] non-null), else the [declaredLibrary]. Mirrors the
/// `origin:` filter's effective-origin rule so a row's chip and its filter
/// classification always agree.
RadarOrigin effectiveOriginOf(
  Uri? declaredLibrary,
  Uri? anchorLibrary, {
  required Set<String> projectPackages,
}) => originOf(
  anchorLibrary ?? declaredLibrary,
  projectPackages: projectPackages,
);

/// Grouped / flat toggle plus the "hide framework" preset chip, shared by the
/// histogram and diff toolbars.
class PackageGroupControls extends StatelessWidget {
  const PackageGroupControls({
    super.key,
    required this.grouped,
    required this.onGroupedChanged,
    required this.hideFramework,
    required this.onHideFrameworkChanged,
  });

  final bool grouped;
  final ValueChanged<bool> onGroupedChanged;
  final bool hideFramework;
  final ValueChanged<bool> onHideFrameworkChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Segment(
          label: 'grouped',
          selected: grouped,
          onTap: () => onGroupedChanged(true),
        ),
        _Segment(
          label: 'flat',
          selected: !grouped,
          onTap: () => onGroupedChanged(false),
        ),
        const SizedBox(width: 10),
        _PresetChip(
          label: 'hide framework',
          active: hideFramework,
          onTap: () => onHideFrameworkChanged(!hideFramework),
        ),
      ],
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          style: RadarTypography.monoLabel.copyWith(
            color: selected ? RadarColors.accent : RadarColors.text40,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: active ? RadarColors.accentSubtle : Colors.transparent,
          border: Border.all(
            color: active ? RadarColors.accent : RadarColors.hairline08,
            width: RadarDensity.hairline,
          ),
          borderRadius: const BorderRadius.all(Radius.circular(4)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Text(
            label,
            style: RadarTypography.monoLabel.copyWith(
              color: active ? RadarColors.accent : RadarColors.text60,
            ),
          ),
        ),
      ),
    );
  }
}

/// A 34px-tall collapsible header for a [PackageGroup]: caret, origin chip, an
/// ownership label, a shallow-bytes honesty affordance, and a trailing rollup
/// metric.
///
/// The label reads `retained via <package>` only when [anchored] (the group has
/// real attribution membership); a declared-fallback-only group reads
/// `declared in <package>` so the header never overclaims retention it doesn't
/// know.
class PackageGroupHeader extends StatelessWidget {
  const PackageGroupHeader({
    super.key,
    required this.package,
    required this.origin,
    required this.expanded,
    required this.onToggle,
    required this.trailing,
    this.anchored = true,
  });

  final String package;
  final RadarOrigin origin;
  final bool expanded;
  final VoidCallback onToggle;
  final bool anchored;

  /// Rollup metric widget (e.g. the group's Δbytes or total bytes).
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final label = anchored ? 'retained via $package' : 'declared in $package';
    return GestureDetector(
      onTap: onToggle,
      behavior: HitTestBehavior.opaque,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: RadarColors.bgTableHeader,
          border: Border(
            bottom: BorderSide(
              color: RadarColors.hairline08,
              width: RadarDensity.hairline,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Icon(
                expanded
                    ? Icons.keyboard_arrow_down
                    : Icons.keyboard_arrow_right,
                size: 16,
                color: RadarColors.text60,
              ),
              const SizedBox(width: 6),
              OriginChip(origin: origin),
              const SizedBox(width: 8),
              Flexible(
                child: Tooltip(
                  message: label,
                  child: Text(
                    label,
                    style: RadarTypography.monoLabel.copyWith(
                      color: RadarColors.text80,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const _ShallowBytesAffordance(),
              const Spacer(),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}

class _ShallowBytesAffordance extends StatelessWidget {
  const _ShallowBytesAffordance();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Shallow (own) bytes — not a retained-graph size.',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 12,
            color: RadarColors.text40,
          ),
          const SizedBox(width: 3),
          Text(
            'shallow',
            style: RadarTypography.monoLabel.copyWith(
              color: RadarColors.text40,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

/// Honesty banner shown atop a grouped table when NO project group is present,
/// so an empty "yours" section is never silent.
///
/// [attributionResolved] true → the analysis resolved a project set and there
/// simply are no project-attributed rows (a clean, positive result).
/// False → attribution itself is unavailable (legacy export or detection off),
/// a warning that ownership grouping can't be trusted.
class PackageGroupBanner extends StatelessWidget {
  const PackageGroupBanner({
    super.key,
    required this.attributionResolved,
    this.subject = 'diff',
  });

  final bool attributionResolved;

  /// Noun for the positive message, e.g. `diff` or `snapshot`.
  final String subject;

  @override
  Widget build(BuildContext context) {
    final color = attributionResolved
        ? RadarColors.accent
        : RadarColors.warning;
    final message = attributionResolved
        ? 'No project-attributed leaks in this $subject.'
        : 'Attribution unavailable — project packages unresolved '
              '(legacy export or detection off).';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: RadarColors.bgPanel,
        border: Border(
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
            Icon(
              attributionResolved
                  ? Icons.check_circle_outline
                  : Icons.warning_amber_rounded,
              size: 14,
              color: color,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                message,
                style: RadarTypography.monoLabel.copyWith(color: color),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Anchor-map memo, keyed by [GraphAnalysisResult] identity so the map is built
/// once per analysis and reused across the many rebuilds a controller triggers.
final Expando<Map<String, Uri?>> _anchorCache = Expando('classAnchors');

/// Memoized [classAnchorsFromClusters] for [result], cached on the result's
/// identity (immutable per snapshot, so identity is stable across rebuilds).
Map<String, Uri?> classAnchorsFor(GraphAnalysisResult result) =>
    _anchorCache[result] ??= classAnchorsFromClusters(result.clusters);

/// Builds a per-class anchor-library map from analysis [clusters].
///
/// For each class the dominant cluster (most retained shallow bytes) supplies
/// the anchor hop's library — the package that retains it. Classes with no
/// cluster, or a cluster with no app anchor, are absent so callers fall back to
/// the declared library.
Map<String, Uri?> classAnchorsFromClusters(List<GraphLeakCluster> clusters) {
  final anchors = <String, Uri?>{};
  _dominantAnchoredClusters(clusters).forEach((className, c) {
    anchors[className] =
        c.representativePath.hops[c.anchorHopIndex!].libraryUri;
  });
  return anchors;
}

/// A class's representative path plus the hop index app code holds it at.
typedef AnchorHop = ({GraphRetainingPath path, int index});

/// Anchor-hop memo, keyed by [GraphAnalysisResult] identity (see [_anchorCache]).
final Expando<Map<String, AnchorHop>> _anchorHopCache = Expando(
  'classAnchorHops',
);

/// Memoized [classAnchorHopsFromClusters] for [result].
Map<String, AnchorHop> classAnchorHopsFor(GraphAnalysisResult result) =>
    _anchorHopCache[result] ??= classAnchorHopsFromClusters(result.clusters);

/// Per-class dominant-cluster [AnchorHop] — the representative path and the hop
/// index its app owner retains it at.
///
/// Same dominant-cluster selection as [classAnchorsFromClusters]. A path
/// rendered elsewhere may use this index only when it STRUCTURALLY matches
/// [AnchorHop.path] (`GraphRetainingPath.==` ignores library uris), so the
/// "yours" highlight is never applied to a path the index doesn't describe.
Map<String, AnchorHop> classAnchorHopsFromClusters(
  List<GraphLeakCluster> clusters,
) {
  final hops = <String, AnchorHop>{};
  _dominantAnchoredClusters(clusters).forEach((className, c) {
    hops[className] = (path: c.representativePath, index: c.anchorHopIndex!);
  });
  return hops;
}

/// The dominant (most retained shallow bytes) app-anchored cluster per class,
/// keeping only clusters whose [GraphLeakCluster.anchorHopIndex] is in range.
Map<String, GraphLeakCluster> _dominantAnchoredClusters(
  List<GraphLeakCluster> clusters,
) {
  final byClass = <String, GraphLeakCluster>{};
  for (final c in clusters) {
    final i = c.anchorHopIndex;
    if (i == null || i < 0 || i >= c.representativePath.hops.length) continue;
    final existing = byClass[c.className];
    if (existing == null ||
        c.retainedShallowBytes > existing.retainedShallowBytes) {
      byClass[c.className] = c;
    }
  }
  return byClass;
}
