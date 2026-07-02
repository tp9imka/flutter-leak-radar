import 'package:flutter/material.dart';
import 'package:leak_graph/leak_graph.dart';
import 'package:radar_ui/radar_ui.dart';

import '../presentation/retaining_path_tile.dart';
import 'mem_format.dart';
import 'root_kind_ui.dart';

/// Right-hand inspector for a single class in a snapshot.
///
/// Shows how the class's instances are retained — grouped by their closest
/// GC-root kind so live objects (retained by the Flutter tree) are visually
/// separated from leak-prone ones — plus a representative retaining path.
///
/// [profile] is looked up from the snapshot's
/// `GraphAnalysisResult.classRootProfiles` by the parent; null renders a hint.
class ClassDetailPanel extends StatelessWidget {
  const ClassDetailPanel({
    super.key,
    required this.className,
    required this.profile,
    this.distribution,
    this.headerTrailing,
  });

  final String? className;
  final ClassRootProfile? profile;

  /// How this class's instances distribute across distinct shortest retaining
  /// paths, when materialized for the class. Null falls back to the profile's
  /// single representative path.
  final ClassPathDistribution? distribution;

  /// Optional widgets shown on the header row (e.g. diff delta tags).
  final List<Widget>? headerTrailing;

  @override
  Widget build(BuildContext context) {
    if (className == null) {
      return ColoredBox(
        color: RadarColors.bgSurface,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Select a class to see how it is retained.',
              style: RadarTypography.caption,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return ColoredBox(
      color: RadarColors.bgSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(className: className!, trailing: headerTrailing),
          Expanded(
            child: profile == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No root profile for this class in the selected '
                        'snapshot.',
                        style: RadarTypography.caption,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : _ProfileBody(profile: profile!, distribution: distribution),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.className, this.trailing});

  final String className;
  final List<Widget>? trailing;

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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              className,
              style: RadarTypography.monoBody,
              overflow: TextOverflow.ellipsis,
            ),
            if (trailing != null && trailing!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4, children: trailing!),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProfileBody extends StatelessWidget {
  const _ProfileBody({required this.profile, this.distribution});

  final ClassRootProfile profile;
  final ClassPathDistribution? distribution;

  @override
  Widget build(BuildContext context) {
    final entries = profile.byRoot.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = profile.totalInstances;
    final leakProne = profile.byRoot.entries
        .where((e) => rootBucket(e.key) == RootBucket.leakProne)
        .fold(0, (s, e) => s + e.value);
    final dist = distribution;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _LiveLeakBanner(
          looksLive: profile.looksLive,
          total: total,
          leakProne: leakProne,
        ),
        const SizedBox(height: 12),
        Text('Retained by (closest root)', style: RadarTypography.monoLabel),
        const SizedBox(height: 6),
        for (final e in entries)
          _RootRow(kind: e.key, count: e.value, total: total),
        const SizedBox(height: 8),
        Text(
          '${fmtBytes(profile.retainedShallowBytes)} shallow · '
          '$total instance${total == 1 ? '' : 's'}',
          style: RadarTypography.caption,
        ),
        const Divider(height: 24, color: RadarColors.hairline08),
        if (dist != null && dist.paths.isNotEmpty)
          _PathDistributionSection(distribution: dist)
        else ...[
          Text(
            'Representative retaining path',
            style: RadarTypography.monoLabel,
          ),
          const SizedBox(height: 6),
          if (profile.representativePath != null)
            RetainingPathTile(path: profile.representativePath!)
          else
            Text(
              'Not captured for this class — only the busiest classes keep a '
              'materialised path to bound snapshot size.',
              style: RadarTypography.caption,
            ),
        ],
      ],
    );
  }
}

/// The distribution of a class's instances across distinct shortest retaining
/// paths (the "144 instances → 24 via path A, 20 via path B…" breakdown). Each
/// row expands on tap to the full hop-by-hop path.
class _PathDistributionSection extends StatelessWidget {
  const _PathDistributionSection({required this.distribution});

  final ClassPathDistribution distribution;

  @override
  Widget build(BuildContext context) {
    final d = distribution;
    final maxCount = d.paths.isEmpty ? 0 : d.paths.first.instanceCount;
    final subtitle = d.isSampled
        ? 'sampled ${d.sampledInstances} of ${d.totalInstances} instances · '
              '${d.paths.length} path${d.paths.length == 1 ? '' : 's'}'
        : '${d.totalInstances} instance${d.totalInstances == 1 ? '' : 's'} '
              'across ${d.paths.length} path${d.paths.length == 1 ? '' : 's'}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Retaining paths', style: RadarTypography.monoLabel),
        const SizedBox(height: 2),
        Text(subtitle, style: RadarTypography.caption),
        const SizedBox(height: 8),
        for (final bucket in d.paths)
          _PathBucketTile(bucket: bucket, maxCount: maxCount),
        if (d.otherPathCount > 0) ...[
          const SizedBox(height: 2),
          Text(
            '+${d.otherPathCount} instance'
            '${d.otherPathCount == 1 ? '' : 's'} in more paths',
            style: RadarTypography.caption,
          ),
        ],
      ],
    );
  }
}

class _PathBucketTile extends StatefulWidget {
  const _PathBucketTile({required this.bucket, required this.maxCount});

  final PathBucket bucket;
  final int maxCount;

  @override
  State<_PathBucketTile> createState() => _PathBucketTileState();
}

class _PathBucketTileState extends State<_PathBucketTile> {
  bool _expanded = false;

  String _label(GraphRetainingPath path) {
    if (path.hops.isEmpty) return '(root)';
    if (path.hops.length == 1) return path.hops.single.className;
    final first = path.hops.first.className;
    final last = path.hops.last.className;
    return path.hops.length == 2 ? '$first → $last' : '$first → … → $last';
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.bucket;
    final pct = widget.maxCount == 0 ? 0.0 : b.instanceCount / widget.maxCount;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: RadarColors.bgPanel,
        borderRadius: const BorderRadius.all(Radius.circular(6)),
        border: Border.all(
          color: RadarColors.hairline08,
          width: RadarDensity.hairline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  RootDot(kind: b.path.rootKind),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _label(b.path),
                      style: RadarTypography.monoBody.copyWith(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${b.instanceCount}',
                    style: RadarTypography.monoNumber.copyWith(fontSize: 12),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    fmtBytes(b.shallowBytes),
                    style: RadarTypography.caption,
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 14,
                    color: RadarColors.text40,
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ClipRRect(
              borderRadius: const BorderRadius.all(Radius.circular(2)),
              child: SizedBox(
                height: 3,
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: pct.clamp(0.0, 1.0),
                  child: ColoredBox(color: rootBucket(b.path.rootKind).color),
                ),
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.all(8),
              child: RetainingPathTile(path: b.path),
            ),
        ],
      ),
    );
  }
}

class _LiveLeakBanner extends StatelessWidget {
  const _LiveLeakBanner({
    required this.looksLive,
    required this.total,
    required this.leakProne,
  });

  final bool looksLive;
  final int total;
  final int leakProne;

  @override
  Widget build(BuildContext context) {
    final color = looksLive ? RadarColors.accent : RadarColors.critical;
    final text = looksLive
        ? 'Mostly live — retained by the widget tree'
        : leakProne > 0
        ? '$leakProne of $total via leak-prone roots'
        : 'Not dominated by the live tree';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: const BorderRadius.all(Radius.circular(6)),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
      ),
      child: Row(
        children: [
          Icon(
            looksLive ? Icons.verified_outlined : Icons.warning_amber_rounded,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: RadarTypography.monoLabel.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _RootRow extends StatelessWidget {
  const _RootRow({
    required this.kind,
    required this.count,
    required this.total,
  });

  final RootKind kind;
  final int count;
  final int total;

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0.0 : count / total;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          RootDot(kind: kind),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              kind.label,
              style: RadarTypography.monoBody.copyWith(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 56,
            child: Text(
              '$count',
              style: RadarTypography.monoNumber.copyWith(fontSize: 12),
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: 8),
          ClipRRect(
            borderRadius: const BorderRadius.all(Radius.circular(3)),
            child: SizedBox(
              width: 48,
              height: 6,
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: pct.clamp(0.0, 1.0),
                child: ColoredBox(color: rootBucket(kind).color),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
