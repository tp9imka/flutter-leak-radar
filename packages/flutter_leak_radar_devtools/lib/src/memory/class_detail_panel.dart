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
    this.headerTrailing,
  });

  final String? className;
  final ClassRootProfile? profile;

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
                : _ProfileBody(profile: profile!),
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
  const _ProfileBody({required this.profile});

  final ClassRootProfile profile;

  @override
  Widget build(BuildContext context) {
    final entries = profile.byRoot.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = profile.totalInstances;
    final leakProne = profile.byRoot.entries
        .where((e) => rootBucket(e.key) == RootBucket.leakProne)
        .fold(0, (s, e) => s + e.value);

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
        Text('Representative retaining path', style: RadarTypography.monoLabel),
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
