import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:leak_graph/leak_graph.dart';
import 'package:radar_ui/radar_ui.dart';

import '../diff/diff_controller.dart';
import '../presentation/retaining_path_tile.dart';

const _log = 'leakRadarDevTools.snapshotDiffView';

/// Fixed-width sort-header cell that scales the content down when the label
/// + sort arrow exceeds the column width (e.g. at high font scales in Chrome).
class _SortHeaderCell extends StatelessWidget {
  const _SortHeaderCell({required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Align(
        alignment: Alignment.centerRight,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: child,
        ),
      ),
    );
  }
}

/// Full snapshot-and-diff view: toolbar with stepper, content area that
/// transitions through the capture→act→capture→diff workflow phases.
class SnapshotDiffView extends StatelessWidget {
  const SnapshotDiffView({super.key, required this.controller});

  final DiffController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => _SnapshotDiffContent(controller: controller),
    );
  }
}

class _SnapshotDiffContent extends StatelessWidget {
  const _SnapshotDiffContent({required this.controller});

  final DiffController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Toolbar(controller: controller),
        Expanded(child: _ContentArea(controller: controller)),
      ],
    );
  }
}

// ── Toolbar ───────────────────────────────────────────────────────────────────

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.controller});

  final DiffController controller;

  @override
  Widget build(BuildContext context) {
    final phase = controller.phase;
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
      child: SizedBox(
        height: 44,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              _CaptureButton(controller: controller),
              const SizedBox(width: 8),
              _ForceGcButton(controller: controller),
              const SizedBox(width: 8),
              _NewDiffButton(controller: controller),
              const Spacer(),
              _Stepper(phase: phase),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _CaptureButton extends StatelessWidget {
  const _CaptureButton({required this.controller});

  final DiffController controller;

  @override
  Widget build(BuildContext context) {
    final enabled =
        controller.canCapture &&
        (controller.phase == CapturePhase.idle ||
            controller.phase == CapturePhase.readyForB);
    final label = controller.phase == CapturePhase.readyForB
        ? 'Capture B'
        : 'Capture';

    return FilledButton(
      onPressed: enabled
          ? () {
              if (controller.phase == CapturePhase.readyForB) {
                controller.captureB();
              } else {
                controller.captureA();
              }
            }
          : null,
      style: FilledButton.styleFrom(
        backgroundColor: RadarColors.accent,
        foregroundColor: const Color(0xFF001a0d),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        minimumSize: const Size(0, 30),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: RadarTypography.monoBody.copyWith(fontSize: 12),
      ),
      child: Text(label),
    );
  }
}

class _ForceGcButton extends StatelessWidget {
  const _ForceGcButton({required this.controller});

  final DiffController controller;

  @override
  Widget build(BuildContext context) {
    final enabled = controller.canCapture;
    return OutlinedButton(
      onPressed: enabled
          ? () {
              controller.forceGc().catchError((Object e) {
                developer.log('Force GC error', name: _log, error: e);
              });
            }
          : null,
      style: OutlinedButton.styleFrom(
        foregroundColor: RadarColors.text60,
        side: const BorderSide(
          color: RadarColors.hairline08,
          width: RadarDensity.hairline,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
        minimumSize: const Size(0, 30),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: RadarTypography.monoBody.copyWith(fontSize: 12),
      ),
      child: const Text('Force GC'),
    );
  }
}

class _NewDiffButton extends StatelessWidget {
  const _NewDiffButton({required this.controller});

  final DiffController controller;

  @override
  Widget build(BuildContext context) {
    final enabled = controller.phase == CapturePhase.done;
    return OutlinedButton(
      onPressed: enabled ? controller.reset : null,
      style: OutlinedButton.styleFrom(
        foregroundColor: RadarColors.text60,
        side: const BorderSide(
          color: RadarColors.hairline08,
          width: RadarDensity.hairline,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
        minimumSize: const Size(0, 30),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: RadarTypography.monoBody.copyWith(fontSize: 12),
      ),
      child: const Text('New diff'),
    );
  }
}

// ── Stepper ────────────────────────────────────────────────────────────────────

class _Stepper extends StatelessWidget {
  const _Stepper({required this.phase});

  final CapturePhase phase;

  // Map phase to how many steps are complete (0-based completed count).
  int get _completedSteps => switch (phase) {
    CapturePhase.idle => 0,
    CapturePhase.capturingA => 0,
    CapturePhase.readyForB => 1,
    CapturePhase.capturingB => 2,
    CapturePhase.done => 4,
  };

  int get _currentStep => switch (phase) {
    CapturePhase.idle => 0,
    CapturePhase.capturingA => 0,
    CapturePhase.readyForB => 1,
    CapturePhase.capturingB => 2,
    CapturePhase.done => -1,
  };

  bool get _isLoading =>
      phase == CapturePhase.capturingA || phase == CapturePhase.capturingB;

  @override
  Widget build(BuildContext context) {
    const labels = ['Capture A', 'Exercise app', 'Capture B', 'Diff'];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0) _StepConnector(done: i <= _completedSteps),
          _StepCircle(
            index: i,
            label: labels[i],
            completed: i < _completedSteps,
            current: i == _currentStep,
            loading: i == _currentStep && _isLoading,
          ),
        ],
      ],
    );
  }
}

class _StepConnector extends StatelessWidget {
  const _StepConnector({required this.done});

  final bool done;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 1,
      color: done ? RadarColors.accent : RadarColors.hairline08,
      margin: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}

class _StepCircle extends StatelessWidget {
  const _StepCircle({
    required this.index,
    required this.label,
    required this.completed,
    required this.current,
    required this.loading,
  });

  final int index;
  final String label;
  final bool completed;
  final bool current;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color borderColor;
    final Color textColor;

    if (completed) {
      bg = RadarColors.accent;
      borderColor = RadarColors.accent;
      textColor = const Color(0xFF001a0d);
    } else if (current) {
      bg = Colors.transparent;
      borderColor = RadarColors.text100;
      textColor = RadarColors.text100;
    } else {
      bg = Colors.transparent;
      borderColor = RadarColors.text25;
      textColor = RadarColors.text40;
    }

    return Tooltip(
      message: label,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: bg,
              shape: BoxShape.circle,
              border: Border.all(color: borderColor),
            ),
            child: loading
                ? const Padding(
                    padding: EdgeInsets.all(3),
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: RadarColors.text100,
                    ),
                  )
                : Center(
                    child: Text(
                      '${index + 1}',
                      style: RadarTypography.monoLabel.copyWith(
                        color: textColor,
                        fontSize: 9,
                        height: 1,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Content area ──────────────────────────────────────────────────────────────

class _ContentArea extends StatelessWidget {
  const _ContentArea({required this.controller});

  final DiffController controller;

  @override
  Widget build(BuildContext context) {
    return switch (controller.phase) {
      CapturePhase.idle => _IdleState(controller: controller),
      CapturePhase.capturingA => const _LoadingState(
        message: 'Capturing baseline heap snapshot…',
      ),
      CapturePhase.readyForB => _BaselineState(controller: controller),
      CapturePhase.capturingB => const _LoadingState(
        message: 'Capturing & diffing…',
      ),
      CapturePhase.done => _DiffedView(controller: controller),
    };
  }
}

class _IdleState extends StatelessWidget {
  const _IdleState({required this.controller});

  final DiffController controller;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Capture → act → capture → diff',
            style: RadarTypography.monoBody.copyWith(
              fontSize: 18,
              color: RadarColors.text60,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Baseline a snapshot, exercise the app, capture again and\n'
            'see exactly which classes grew — with retaining paths.',
            style: RadarTypography.caption,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: controller.canCapture ? controller.captureA : null,
            style: FilledButton.styleFrom(
              backgroundColor: RadarColors.accent,
              foregroundColor: const Color(0xFF001a0d),
              textStyle: RadarTypography.monoBody.copyWith(fontSize: 13),
            ),
            child: const Text('Capture snapshot'),
          ),
          if (!controller.canCapture)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Connect to a running debug / profile app first.',
                style: RadarTypography.caption,
              ),
            ),
        ],
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: RadarColors.accent),
          const SizedBox(height: 16),
          Text(message, style: RadarTypography.monoLabel),
        ],
      ),
    );
  }
}

class _BaselineState extends StatelessWidget {
  const _BaselineState({required this.controller});

  final DiffController controller;

  @override
  Widget build(BuildContext context) {
    final snap = controller.snapshotA;
    if (snap == null) return const SizedBox.shrink();

    final bytesMb =
        (snap.histogram.fold(0, (s, c) => s + c.shallowBytes) / (1024 * 1024))
            .toStringAsFixed(2);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: RadarColors.bgSurface,
              borderRadius: RadarDensity.inputRadius,
              border: Border.all(
                color: RadarColors.hairline08,
                width: RadarDensity.hairline,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    snap.label,
                    style: RadarTypography.monoBody.copyWith(
                      color: RadarColors.accent,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${snap.histogram.length} classes · $bytesMb MB shallow',
                    style: RadarTypography.monoLabel,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Captured ${_formatTime(snap.capturedAt)}',
                    style: RadarTypography.caption,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Now exercise the app, then capture again.',
            style: RadarTypography.monoLabel,
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

// ── Diffed view ───────────────────────────────────────────────────────────────

class _DiffedView extends StatefulWidget {
  const _DiffedView({required this.controller});

  final DiffController controller;

  @override
  State<_DiffedView> createState() => _DiffedViewState();
}

class _DiffedViewState extends State<_DiffedView> {
  ClassCountDiff? _selectedClass;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _DiffTable(
            controller: widget.controller,
            selected: _selectedClass,
            onSelected: (d) => setState(() => _selectedClass = d),
          ),
        ),
        const VerticalDivider(width: 1),
        SizedBox(
          width: 360,
          child: _RetainingPathPanel(
            controller: widget.controller,
            selected: _selectedClass,
          ),
        ),
      ],
    );
  }
}

// ── Diff table ────────────────────────────────────────────────────────────────

enum _DiffSortKey { className, library, instanceDelta, bytesDelta, live }

class _DiffTable extends StatefulWidget {
  const _DiffTable({
    required this.controller,
    required this.selected,
    required this.onSelected,
  });

  final DiffController controller;
  final ClassCountDiff? selected;
  final ValueChanged<ClassCountDiff?> onSelected;

  @override
  State<_DiffTable> createState() => _DiffTableState();
}

class _DiffTableState extends State<_DiffTable> {
  _DiffSortKey _sortKey = _DiffSortKey.bytesDelta;
  RadarSortDirection _direction = RadarSortDirection.descending;
  String _query = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ClassCountDiff> _sorted(List<ClassCountDiff> diffs) {
    final filtered = _query.isEmpty
        ? diffs
        : diffs
              .where(
                (d) => d.after.className.toLowerCase().contains(
                  _query.toLowerCase(),
                ),
              )
              .toList();

    filtered.sort((a, b) {
      final cmp = switch (_sortKey) {
        _DiffSortKey.className => a.after.className.compareTo(
          b.after.className,
        ),
        _DiffSortKey.library => a.after.libraryUri.toString().compareTo(
          b.after.libraryUri.toString(),
        ),
        _DiffSortKey.instanceDelta => a.instanceDelta.compareTo(
          b.instanceDelta,
        ),
        _DiffSortKey.bytesDelta => a.bytesDelta.compareTo(b.bytesDelta),
        _DiffSortKey.live => a.after.instanceCount.compareTo(
          b.after.instanceCount,
        ),
      };
      return _direction == RadarSortDirection.descending ? -cmp : cmp;
    });
    return filtered;
  }

  void _onSort(String key, RadarSortDirection dir) {
    final k = _DiffSortKey.values.firstWhere((e) => e.name == key);
    setState(() {
      _sortKey = k;
      _direction = dir;
    });
  }

  @override
  Widget build(BuildContext context) {
    final diff = widget.controller.diff ?? const [];
    final snapA = widget.controller.snapshotA;
    final snapB = widget.controller.snapshotB;
    final totalA = snapA?.histogram.fold(0, (s, c) => s + c.shallowBytes) ?? 0;
    final totalB = snapB?.histogram.fold(0, (s, c) => s + c.shallowBytes) ?? 0;
    final deltaBytes = totalB - totalA;
    final deltaSign = deltaBytes >= 0 ? '+' : '';
    final sorted = _sorted(diff);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Table sub-header
        DecoratedBox(
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
            child: Row(
              children: [
                Text(
                  'A ${_fmtMb(totalA)} → B ${_fmtMb(totalB)}',
                  style: RadarTypography.monoLabel,
                ),
                const SizedBox(width: 8),
                Text(
                  'Δ $deltaSign${_fmtMb(deltaBytes)}',
                  style: RadarTypography.monoLabel.copyWith(
                    color: deltaBytes > 0
                        ? RadarColors.critical
                        : RadarColors.accent,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: 220,
                  child: RadarSearchField(
                    controller: _searchController,
                    hint: 'filter classes…',
                    onChanged: (q) => setState(() => _query = q),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Column headers
        DecoratedBox(
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  flex: 4,
                  child: RadarSortHeader(
                    label: 'class',
                    sortKey: _DiffSortKey.className.name,
                    activeSortKey: _sortKey.name,
                    direction: _direction,
                    onSort: _onSort,
                    textAlign: TextAlign.left,
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: RadarSortHeader(
                    label: 'library',
                    sortKey: _DiffSortKey.library.name,
                    activeSortKey: _sortKey.name,
                    direction: _direction,
                    onSort: _onSort,
                    textAlign: TextAlign.left,
                  ),
                ),
                _SortHeaderCell(
                  width: 72,
                  child: RadarSortHeader(
                    label: 'Δ inst',
                    sortKey: _DiffSortKey.instanceDelta.name,
                    activeSortKey: _sortKey.name,
                    direction: _direction,
                    onSort: _onSort,
                  ),
                ),
                _SortHeaderCell(
                  width: 80,
                  child: RadarSortHeader(
                    label: 'Δ bytes',
                    sortKey: _DiffSortKey.bytesDelta.name,
                    activeSortKey: _sortKey.name,
                    direction: _direction,
                    onSort: _onSort,
                  ),
                ),
                _SortHeaderCell(
                  width: 60,
                  child: RadarSortHeader(
                    label: 'live',
                    sortKey: _DiffSortKey.live.name,
                    activeSortKey: _sortKey.name,
                    direction: _direction,
                    onSort: _onSort,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Rows
        Expanded(
          child: sorted.isEmpty
              ? Center(
                  child: Text(
                    _query.isEmpty
                        ? 'No diff data.'
                        : "No classes match '$_query'",
                    style: RadarTypography.caption,
                  ),
                )
              : ListView.builder(
                  itemCount: sorted.length,
                  itemExtent: 36,
                  itemBuilder: (context, i) => _DiffRow(
                    diff: sorted[i],
                    isSelected: widget.selected == sorted[i],
                    onTap: () {
                      final tapped = sorted[i];
                      widget.onSelected(
                        widget.selected == tapped ? null : tapped,
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  String _fmtMb(int bytes) {
    final mb = bytes.abs() / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }
}

class _DiffRow extends StatelessWidget {
  const _DiffRow({
    required this.diff,
    required this.isSelected,
    required this.onTap,
  });

  final ClassCountDiff diff;
  final bool isSelected;
  final VoidCallback onTap;

  Color _deltaColor(int v) {
    if (v > 0) return RadarColors.critical;
    if (v < 0) return RadarColors.accent;
    return RadarColors.text40;
  }

  String _fmtDelta(int v) => v > 0 ? '+$v' : '$v';
  String _fmtBytesDelta(int v) {
    if (v == 0) return '0';
    final kb = v.abs() / 1024;
    final sign = v > 0 ? '+' : '-';
    return kb < 1 ? '$sign${v.abs()} B' : '$sign${kb.toStringAsFixed(1)} KB';
  }

  String _libraryLabel() {
    final uri = diff.after.libraryUri;
    final s = uri.toString();
    if (s.startsWith('package:')) {
      final parts = s.substring('package:'.length).split('/');
      return parts.first;
    }
    if (s.contains('/')) {
      return s.split('/').last;
    }
    return s.isEmpty ? '--' : s;
  }

  @override
  Widget build(BuildContext context) {
    final instColor = _deltaColor(diff.instanceDelta);
    final bytesColor = _deltaColor(diff.bytesDelta);

    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isSelected
              ? RadarColors.accentSubtle
              : RadarColors.rowBgDefault,
          border: const Border(
            bottom: BorderSide(
              color: RadarColors.hairline08,
              width: RadarDensity.hairline,
            ),
            left: BorderSide(width: 0, color: Colors.transparent),
          ),
        ),
        child: Row(
          children: [
            // Left accent bar when selected
            Container(
              width: 3,
              height: 36,
              color: isSelected ? RadarColors.accent : Colors.transparent,
            ),
            const SizedBox(width: 9),
            Expanded(
              flex: 4,
              child: Text(
                diff.after.className,
                style: RadarTypography.monoBody.copyWith(fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                _libraryLabel(),
                style: RadarTypography.monoLabel.copyWith(fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(
              width: 72,
              child: Text(
                _fmtDelta(diff.instanceDelta),
                style: RadarTypography.monoNumber.copyWith(
                  color: instColor,
                  fontSize: 12,
                ),
                textAlign: TextAlign.right,
              ),
            ),
            SizedBox(
              width: 80,
              child: Text(
                _fmtBytesDelta(diff.bytesDelta),
                style: RadarTypography.monoNumber.copyWith(
                  color: bytesColor,
                  fontSize: 12,
                ),
                textAlign: TextAlign.right,
              ),
            ),
            SizedBox(
              width: 60,
              child: Text(
                '${diff.after.instanceCount}',
                style: RadarTypography.monoNumber.copyWith(fontSize: 12),
                textAlign: TextAlign.right,
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

// ── Retaining path panel ──────────────────────────────────────────────────────

class _RetainingPathPanel extends StatelessWidget {
  const _RetainingPathPanel({required this.controller, required this.selected});

  final DiffController controller;
  final ClassCountDiff? selected;

  @override
  Widget build(BuildContext context) {
    if (selected == null) {
      return const ColoredBox(
        color: RadarColors.bgSurface,
        child: Center(
          child: _EmptyPanelHint(
            message: 'Select a class to see retaining paths',
          ),
        ),
      );
    }

    final className = selected!.after.className;
    final clusters =
        controller.snapshotB?.analysisResult.clusters
            .where((c) => c.className == className)
            .toList() ??
        [];

    return ColoredBox(
      color: RadarColors.bgSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
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
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      RadarTag(
                        label:
                            'Δ ${selected!.instanceDelta > 0 ? '+' : ''}${selected!.instanceDelta}',
                        color: selected!.instanceDelta > 0
                            ? RadarColors.critical
                            : RadarColors.accent,
                      ),
                      const SizedBox(width: 6),
                      RadarTag(
                        label: _fmtBytes(selected!.bytesDelta),
                        color: selected!.bytesDelta > 0
                            ? RadarColors.critical
                            : RadarColors.accent,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: clusters.isEmpty
                ? const Center(
                    child: _EmptyPanelHint(
                      message: 'No retaining path data for this class.',
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: clusters.length,
                    itemBuilder: (context, i) => RetainingPathTile(
                      path: clusters[i].representativePath,
                      title: clusters[i].className,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  String _fmtBytes(int bytes) {
    final sign = bytes >= 0 ? '+' : '';
    final kb = bytes.abs() / 1024;
    return kb < 1 ? '$sign$bytes B' : '$sign${kb.toStringAsFixed(1)} KB';
  }
}

class _EmptyPanelHint extends StatelessWidget {
  const _EmptyPanelHint({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        message,
        style: RadarTypography.caption,
        textAlign: TextAlign.center,
      ),
    );
  }
}
