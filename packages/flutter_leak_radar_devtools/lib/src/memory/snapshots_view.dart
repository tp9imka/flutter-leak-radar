import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:leak_graph/leak_graph.dart';
import 'package:radar_ui/radar_ui.dart';

import '../capture/snapshot_bundle.dart';
import '../util/web_download.dart';
import 'class_detail_panel.dart';
import 'diff_table.dart';
import 'mem_format.dart';
import 'memory_controller.dart';

const _log = 'leakRadarDevTools.snapshotsView';

/// Capture-list Memory view: capture any number of heap snapshots, list them,
/// export each to JSON, and diff *any two*.
class SnapshotsView extends StatefulWidget {
  const SnapshotsView({super.key, required this.controller});

  final MemoryController controller;

  @override
  State<SnapshotsView> createState() => _SnapshotsViewState();
}

class _SnapshotsViewState extends State<SnapshotsView> {
  String? _selectedClass;

  MemoryController get _c => widget.controller;

  ClassCountDiff? _diffFor(String className) {
    for (final d in _c.diff ?? const <ClassCountDiff>[]) {
      if (d.after.className == className) return d;
    }
    return null;
  }

  ClassRootProfile? _profileFor(String? className, SnapshotBundle? snap) {
    if (className == null || snap == null) return null;
    for (final p in snap.analysisResult.classRootProfiles) {
      if (p.className == className) return p;
    }
    return null;
  }

  ClassPathDistribution? _distributionFor(String? className, SnapshotBundle? snap) {
    if (className == null || snap == null) return null;
    for (final d in snap.analysisResult.classPathDistributions) {
      if (d.className == className) return d;
    }
    return null;
  }

  void _export(SnapshotBundle b) {
    final safeLabel = b.label.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    try {
      downloadJson('heap_${b.id}_$safeLabel.json', b.toJson());
    } catch (e) {
      developer.log('export failed', name: _log, error: e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CaptureToolbar(controller: _c),
            if (_c.hasSnapshots)
              _CapturesStrip(controller: _c, onExport: _export),
            Expanded(child: _body()),
          ],
        );
      },
    );
  }

  Widget _body() {
    if (!_c.hasSnapshots) {
      return _IdleHint(canCapture: _c.canCapture);
    }
    final comparison = _c.comparison;
    if (comparison == null) {
      return Center(
        child: Text(
          'Select a snapshot to show all its classes, or two to diff them.',
          style: RadarTypography.caption,
          textAlign: TextAlign.center,
        ),
      );
    }
    final againstEmpty = _c.comparingAgainstEmpty;
    final diff = _c.diff ?? const <ClassCountDiff>[];
    final selectedDiff = _selectedClass == null
        ? null
        : _diffFor(_selectedClass!);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: DiffTable(
            diffs: diff,
            absolute: againstEmpty,
            summary: againstEmpty
                ? _ShowAllSummary(snapshot: comparison)
                : _DiffSummary(pair: _c.pair!),
            selected: _selectedClass,
            onSelected: (c) => setState(() => _selectedClass = c),
          ),
        ),
        const VerticalDivider(width: 1),
        SizedBox(
          width: 340,
          child: ClassDetailPanel(
            className: _selectedClass,
            profile: _profileFor(_selectedClass, comparison),
            distribution: _distributionFor(_selectedClass, comparison),
            headerTrailing: selectedDiff == null
                ? null
                : againstEmpty
                ? [
                    RadarTag(
                      label: '${selectedDiff.after.instanceCount} inst',
                      color: RadarColors.accent,
                    ),
                    RadarTag(
                      label: fmtBytes(selectedDiff.after.shallowBytes),
                      color: RadarColors.accent,
                    ),
                  ]
                : [
                    RadarTag(
                      label:
                          'Δ ${selectedDiff.instanceDelta > 0 ? '+' : ''}${selectedDiff.instanceDelta}',
                      color: selectedDiff.instanceDelta > 0
                          ? RadarColors.critical
                          : RadarColors.accent,
                    ),
                    RadarTag(
                      label:
                          '${selectedDiff.bytesDelta > 0 ? '+' : ''}${fmtBytes(selectedDiff.bytesDelta)}',
                      color: selectedDiff.bytesDelta > 0
                          ? RadarColors.critical
                          : RadarColors.accent,
                    ),
                  ],
          ),
        ),
      ],
    );
  }
}

// ── Toolbar ─────────────────────────────────────────────────────────────────

class _CaptureToolbar extends StatelessWidget {
  const _CaptureToolbar({required this.controller});

  final MemoryController controller;

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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          children: [
            FilledButton(
              onPressed: controller.canCapture && !controller.capturing
                  ? () => controller.capture()
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: RadarColors.accent,
                foregroundColor: const Color(0xFF001a0d),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: RadarTypography.monoBody.copyWith(fontSize: 12),
              ),
              child: controller.capturing
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: Color(0xFF001a0d),
                      ),
                    )
                  : const Text('Capture'),
            ),
            const SizedBox(width: 8),
            _SecondaryButton(
              label: 'Force GC',
              onPressed: controller.canCapture ? controller.forceGc : null,
            ),
            const SizedBox(width: 8),
            _SecondaryButton(
              label: 'Clear all',
              onPressed: controller.hasSnapshots ? controller.clearAll : null,
            ),
            const Spacer(),
            if (controller.error != null)
              Flexible(
                child: Text(
                  controller.error!,
                  style: RadarTypography.caption.copyWith(
                    color: RadarColors.critical,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              )
            else if (!controller.canCapture)
              Text(
                'Connect to a debug / profile app',
                style: RadarTypography.caption,
              )
            else
              Text(
                '${controller.snapshots.length} snapshot'
                '${controller.snapshots.length == 1 ? '' : 's'}'
                '${controller.restoredFromDisk ? ' · restored' : ''}',
                style: RadarTypography.monoLabel,
              ),
          ],
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: RadarColors.text60,
        side: const BorderSide(
          color: RadarColors.hairline08,
          width: RadarDensity.hairline,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        minimumSize: const Size(0, 30),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: RadarTypography.monoBody.copyWith(fontSize: 12),
      ),
      child: Text(label),
    );
  }
}

// ── Captures strip ────────────────────────────────────────────────────────────

class _CapturesStrip extends StatelessWidget {
  const _CapturesStrip({required this.controller, required this.onExport});

  final MemoryController controller;
  final ValueChanged<SnapshotBundle> onExport;

  @override
  Widget build(BuildContext context) {
    final pair = controller.pair;
    return Container(
      height: 116,
      decoration: const BoxDecoration(
        color: RadarColors.bgRail,
        border: Border(
          bottom: BorderSide(
            color: RadarColors.hairline08,
            width: RadarDensity.hairline,
          ),
        ),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(10),
        itemCount: controller.snapshots.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final b = controller.snapshots[i];
          final role = pair == null
              ? (controller.isSelected(b.id) ? '•' : null)
              : pair.baseline.id == b.id
              ? 'A'
              : pair.comparison.id == b.id
              ? 'B'
              : null;
          return _SnapshotCard(
            bundle: b,
            role: role,
            selected: controller.isSelected(b.id),
            onTap: () => controller.toggleSelection(b.id),
            onExport: () => onExport(b),
            onDelete: () => controller.remove(b.id),
          );
        },
      ),
    );
  }
}

class _SnapshotCard extends StatelessWidget {
  const _SnapshotCard({
    required this.bundle,
    required this.role,
    required this.selected,
    required this.onTap,
    required this.onExport,
    required this.onDelete,
  });

  final SnapshotBundle bundle;
  final String? role;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onExport;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 208,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: RadarColors.bgSurface,
          borderRadius: const BorderRadius.all(Radius.circular(8)),
          border: Border.all(
            color: selected ? RadarColors.accent : RadarColors.hairline08,
            width: selected ? 1.5 : RadarDensity.hairline,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                if (role != null) ...[
                  _RoleBadge(role: role!),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    bundle.label,
                    style: RadarTypography.monoBody.copyWith(fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _IconAction(
                  icon: Icons.download_outlined,
                  tooltip: 'Export JSON',
                  onPressed: onExport,
                ),
                _IconAction(
                  icon: Icons.close,
                  tooltip: 'Delete',
                  onPressed: onDelete,
                ),
              ],
            ),
            Text(
              'captured ${fmtTime(bundle.capturedAt)}',
              style: RadarTypography.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${bundle.histogram.length} classes · '
              '${fmtBytes(bundle.shallowBytes)}',
              style: RadarTypography.monoLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: RadarColors.accent,
        shape: BoxShape.circle,
      ),
      child: Text(
        role,
        style: RadarTypography.monoLabel.copyWith(
          color: const Color(0xFF001a0d),
          fontSize: 10,
          height: 1,
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onPressed,
        radius: 15,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Icon(icon, size: 14, color: RadarColors.text60),
        ),
      ),
    );
  }
}

// ── Sundry ─────────────────────────────────────────────────────────────────

class _DiffSummary extends StatelessWidget {
  const _DiffSummary({required this.pair});

  final DiffPair pair;

  @override
  Widget build(BuildContext context) {
    final delta = pair.comparison.shallowBytes - pair.baseline.shallowBytes;
    final sign = delta >= 0 ? '+' : '';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'A ${fmtBytes(pair.baseline.shallowBytes)} → '
          'B ${fmtBytes(pair.comparison.shallowBytes)}',
          style: RadarTypography.monoLabel,
        ),
        const SizedBox(width: 8),
        Text(
          'Δ $sign${fmtBytes(delta)}',
          style: RadarTypography.monoLabel.copyWith(
            color: delta > 0 ? RadarColors.critical : RadarColors.accent,
          ),
        ),
      ],
    );
  }
}

class _ShowAllSummary extends StatelessWidget {
  const _ShowAllSummary({required this.snapshot});

  final SnapshotBundle snapshot;

  @override
  Widget build(BuildContext context) {
    return Text(
      'all classes · ${snapshot.histogram.length} · '
      '${fmtBytes(snapshot.shallowBytes)} · no baseline',
      style: RadarTypography.monoLabel,
    );
  }
}

class _IdleHint extends StatelessWidget {
  const _IdleHint({required this.canCapture});

  final bool canCapture;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Capture heap snapshots',
            style: RadarTypography.monoBody.copyWith(
              fontSize: 18,
              color: RadarColors.text60,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Capture as many snapshots as you like, export any of them,\n'
            'and select any two to diff.',
            style: RadarTypography.caption,
            textAlign: TextAlign.center,
          ),
          if (!canCapture) ...[
            const SizedBox(height: 12),
            Text(
              'Connect to a running debug / profile app first.',
              style: RadarTypography.caption,
            ),
          ],
        ],
      ),
    );
  }
}
