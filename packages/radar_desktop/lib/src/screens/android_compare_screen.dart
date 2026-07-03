import 'package:flutter/material.dart';
import 'package:radar_native/radar_native.dart';
import 'package:radar_ui/radar_ui.dart';
import 'package:radar_workbench/radar_workbench.dart';

import '../android/module_palette.dart';
import '../android/native_profiling_controller.dart';

/// Column widths for the diff table (module gets the remaining space).
const double _colStatusWidth = 84;
const double _colBytesWidth = 92;
const double _colDeltaWidth = 96;

/// Point-in-time diff between two imported native-heap checkpoints: pick two
/// checkpoints (A → B) and see, per module, what was added, grew, shrank, or
/// went away (see `docs/flutter_radar_android_profiling` §4.3). "Flat"
/// (zero-delta) modules are suppressed — this view only answers "is it
/// getting worse".
class AndroidCompareScreen extends StatefulWidget {
  const AndroidCompareScreen({super.key, required this.controller});

  final NativeProfilingController controller;

  @override
  State<AndroidCompareScreen> createState() => _AndroidCompareScreenState();
}

class _AndroidCompareScreenState extends State<AndroidCompareScreen> {
  /// `null` until the user picks explicitly; the effective index then
  /// defaults to the first ([_aIndex]) or last ([_bIndex]) checkpoint.
  int? _aIndex;
  int? _bIndex;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final checkpoints = controller.checkpoints;
        if (checkpoints.length < 2) return const _EmptyState();

        final lastIndex = checkpoints.length - 1;
        final aIndex = (_aIndex ?? 0).clamp(0, lastIndex);
        final bIndex = (_bIndex ?? lastIndex).clamp(0, lastIndex);

        final diffs = controller.diffCheckpoints(aIndex, bIndex);
        final visibleDiffs = [
          for (final diff in diffs)
            if (diff.status != NativeDiffStatus.flat) diff,
        ];
        final totalDeltaBytes = diffs.fold<int>(
          0,
          (sum, diff) => sum + diff.deltaBytes,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              checkpoints: checkpoints,
              aIndex: aIndex,
              bIndex: bIndex,
              totalDeltaBytes: totalDeltaBytes,
              onChangeA: (i) => setState(() => _aIndex = i),
              onChangeB: (i) => setState(() => _bIndex = i),
            ),
            const _ColumnHeader(),
            const Divider(height: 1, color: RadarColors.hairline08),
            Expanded(
              child: visibleDiffs.isEmpty
                  ? Center(
                      child: Text(
                        'No changes between these checkpoints.',
                        style: RadarTypography.caption,
                      ),
                    )
                  : ListView.builder(
                      itemCount: visibleDiffs.length,
                      itemBuilder: (context, i) =>
                          _CompareRow(diff: visibleDiffs[i]),
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// A status's badge label and severity — added/grew read as regressions
/// (red), shrank/gone as improvements (green). `flat` never reaches this
/// helper: [_AndroidCompareScreenState.build] filters it out beforehand.
({String label, RadarSeverity severity}) _badgeFor(
  NativeDiffStatus status,
) => switch (status) {
  NativeDiffStatus.added => (label: 'ADDED', severity: RadarSeverity.critical),
  NativeDiffStatus.grew => (label: 'GREW', severity: RadarSeverity.critical),
  NativeDiffStatus.shrank => (label: 'SHRANK', severity: RadarSeverity.healthy),
  NativeDiffStatus.gone => (label: 'GONE', severity: RadarSeverity.healthy),
  NativeDiffStatus.flat => (label: 'FLAT', severity: RadarSeverity.info),
};

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Import a second checkpoint in Capture / import to compare '
        'native still-live memory over time.',
        style: RadarTypography.caption,
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.checkpoints,
    required this.aIndex,
    required this.bIndex,
    required this.totalDeltaBytes,
    required this.onChangeA,
    required this.onChangeB,
  });

  final List<NativeHeapProfile> checkpoints;
  final int aIndex;
  final int bIndex;
  final int totalDeltaBytes;
  final ValueChanged<int> onChangeA;
  final ValueChanged<int> onChangeB;

  List<DropdownMenuItem<int>> get _items => [
    for (final (i, checkpoint) in checkpoints.indexed)
      DropdownMenuItem(value: i, child: Text(checkpoint.label)),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
      child: Row(
        children: [
          Text('Compare checkpoints', style: RadarTypography.appBarTitle),
          const SizedBox(width: 16),
          DropdownButton<int>(
            value: aIndex,
            dropdownColor: RadarColors.bgSurface,
            style: RadarTypography.monoBody,
            items: _items,
            onChanged: (i) {
              if (i != null) onChangeA(i);
            },
          ),
          const SizedBox(width: 8),
          Text('→', style: RadarTypography.monoLabel),
          const SizedBox(width: 8),
          DropdownButton<int>(
            value: bIndex,
            dropdownColor: RadarColors.bgSurface,
            style: RadarTypography.monoBody,
            items: _items,
            onChanged: (i) {
              if (i != null) onChangeB(i);
            },
          ),
          const Spacer(),
          Text('native Δ ', style: RadarTypography.monoLabel),
          _DeltaText(bytes: totalDeltaBytes, fontSize: 13),
        ],
      ),
    );
  }
}

class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: RadarColors.bgTableHeader),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            Expanded(child: Text('module', style: RadarTypography.monoLabel)),
            SizedBox(
              width: _colStatusWidth,
              child: Text('status', style: RadarTypography.monoLabel),
            ),
            SizedBox(
              width: _colBytesWidth,
              child: Text(
                'A',
                style: RadarTypography.monoLabel,
                textAlign: TextAlign.right,
              ),
            ),
            SizedBox(
              width: _colBytesWidth,
              child: Text(
                'B',
                style: RadarTypography.monoLabel,
                textAlign: TextAlign.right,
              ),
            ),
            SizedBox(
              width: _colDeltaWidth,
              child: Text(
                'Δ bytes',
                style: RadarTypography.monoLabel,
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single module's before/after row: dot + module name, status badge, A
/// bytes, B bytes, and the sign-colored Δ.
class _CompareRow extends StatelessWidget {
  const _CompareRow({required this.diff});

  final NativeModuleDiff diff;

  @override
  Widget build(BuildContext context) {
    final badge = _badgeFor(diff.status);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                RadarModuleDot(color: moduleKindColor(diff.kind)),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    diff.module,
                    style: RadarTypography.monoBody.copyWith(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: _colStatusWidth,
            child: RadarTag(label: badge.label, severity: badge.severity),
          ),
          SizedBox(
            width: _colBytesWidth,
            child: Text(
              fmtBytes(diff.beforeStillLiveBytes),
              style: RadarTypography.monoNumber.copyWith(fontSize: 11),
              textAlign: TextAlign.right,
            ),
          ),
          SizedBox(
            width: _colBytesWidth,
            child: Text(
              fmtBytes(diff.afterStillLiveBytes),
              style: RadarTypography.monoNumber.copyWith(fontSize: 11),
              textAlign: TextAlign.right,
            ),
          ),
          SizedBox(
            width: _colDeltaWidth,
            child: _DeltaText(bytes: diff.deltaBytes, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}

/// Sign-colored Δ bytes: red when it grew, green when it shrank — the same
/// convention as the still-live table's Δ column
/// (`android_native_module_row.dart`'s `_DeltaText`), reused here for both
/// the header total and per-row deltas.
class _DeltaText extends StatelessWidget {
  const _DeltaText({required this.bytes, required this.fontSize});

  final int bytes;
  final double fontSize;

  Color get _color {
    if (bytes > 0) return RadarColors.critical;
    if (bytes < 0) return RadarColors.accent;
    return RadarColors.text40;
  }

  String get _formatted {
    final sign = bytes > 0
        ? '+'
        : bytes < 0
        ? '-'
        : '';
    return '$sign${fmtBytes(bytes.abs())}';
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _formatted,
      style: RadarTypography.monoNumber.copyWith(
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
        color: _color,
      ),
      textAlign: TextAlign.right,
    );
  }
}
