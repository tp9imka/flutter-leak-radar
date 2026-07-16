import 'package:flutter/material.dart';
import 'package:leak_graph/leak_graph.dart';
import 'package:radar_ui/radar_ui.dart';

import 'mem_format.dart';

/// Label for the single merged framework + sdk group ("runtime").
const String kRuntimeGroupPackage = 'runtime';

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
  });

  /// Package label, e.g. `my_app`, `livekit`, `(unknown)`, or `runtime`.
  final String package;

  /// Ownership bucket of [package] (the runtime group reports as framework).
  final RadarOrigin origin;

  /// Member rows, already sorted by metric descending.
  final List<T> rows;

  /// Summed shallow (own) bytes of [rows].
  final int totalBytes;

  /// Summed byte delta of [rows] (0 when no delta accessor was supplied).
  final int totalDelta;

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
    final anchorLib = anchorLibraryOf(row) ?? declaredLibraryOf(row);
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
}

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

/// A 34px-tall collapsible header for a [PackageGroup]: caret, origin chip,
/// a `retained via <package>` label, a shallow-bytes honesty affordance, and a
/// trailing rollup metric.
class PackageGroupHeader extends StatelessWidget {
  const PackageGroupHeader({
    super.key,
    required this.package,
    required this.origin,
    required this.expanded,
    required this.onToggle,
    required this.trailing,
  });

  final String package;
  final RadarOrigin origin;
  final bool expanded;
  final VoidCallback onToggle;

  /// Rollup metric widget (e.g. the group's Δbytes or total bytes).
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
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
                  message: 'retained via $package',
                  child: Text(
                    'retained via $package',
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

/// Builds a per-class anchor-library map from analysis [clusters].
///
/// For each class the dominant cluster (most retained shallow bytes) supplies
/// the anchor hop's library — the package that retains it. Classes with no
/// cluster, or a cluster with no app anchor, are absent so callers fall back to
/// the declared library.
Map<String, Uri?> classAnchorsFromClusters(List<GraphLeakCluster> clusters) {
  final byClass = <String, GraphLeakCluster>{};
  for (final c in clusters) {
    if (c.anchorHopIndex == null) continue;
    final existing = byClass[c.className];
    if (existing == null ||
        c.retainedShallowBytes > existing.retainedShallowBytes) {
      byClass[c.className] = c;
    }
  }
  final anchors = <String, Uri?>{};
  for (final entry in byClass.entries) {
    final c = entry.value;
    final i = c.anchorHopIndex!;
    final hops = c.representativePath.hops;
    if (i >= 0 && i < hops.length) {
      anchors[entry.key] = hops[i].libraryUri;
    }
  }
  return anchors;
}
