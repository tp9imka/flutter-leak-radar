import 'package:flutter/material.dart';
import 'package:radar_native/radar_native.dart';
import 'package:radar_ui/radar_ui.dart';
import 'package:radar_workbench/radar_workbench.dart';

import '../android/native_profiling_controller.dart';
import 'android_native_module_row.dart';

/// Sortable columns of the still-live table.
enum _NativeSortKey { stillLive, allocs, growth }

/// Still-live table for the selected native-heap checkpoint, rolled up by
/// module and symbolized when a symbol store has been imported. The Android
/// still-live "workhorse" view: a checkpoint picker over a ranked,
/// expandable module table (see `docs/flutter_radar_android_profiling`
/// §4.2). Row rendering lives in `android_native_module_row.dart`.
class AndroidNativeScreen extends StatefulWidget {
  const AndroidNativeScreen({
    super.key,
    required this.controller,
    this.onOpenDetail,
  });

  final NativeProfilingController controller;

  /// Opens the detail view for a callsite. Nullable — wired in a later task;
  /// the trailing `›` button no-ops until then.
  final ValueChanged<NativeCallsite>? onOpenDetail;

  @override
  State<AndroidNativeScreen> createState() => _AndroidNativeScreenState();
}

class _AndroidNativeScreenState extends State<AndroidNativeScreen> {
  _NativeSortKey _sortKey = _NativeSortKey.stillLive;
  RadarSortDirection _direction = RadarSortDirection.descending;

  void _onSort(String key, RadarSortDirection dir) {
    setState(() {
      _sortKey = _NativeSortKey.values.firstWhere((e) => e.name == key);
      _direction = dir;
    });
  }

  List<NativeModuleSummary> _sorted(
    List<NativeModuleSummary> summaries,
    Map<String, int> deltaByModule,
  ) {
    final sorted = [...summaries];
    sorted.sort((a, b) {
      final cmp = switch (_sortKey) {
        _NativeSortKey.stillLive => a.stillLiveBytes.compareTo(
          b.stillLiveBytes,
        ),
        _NativeSortKey.allocs => a.stillLiveCount.compareTo(b.stillLiveCount),
        _NativeSortKey.growth => (deltaByModule[a.module] ?? 0).compareTo(
          deltaByModule[b.module] ?? 0,
        ),
      };
      return _direction == RadarSortDirection.descending ? -cmp : cmp;
    });
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (controller.checkpoints.isEmpty) return const _EmptyState();
        if (controller.state == NativeImportState.loading) {
          return const _LoadingState();
        }

        final deltaByModule = <String, int>{};
        if (controller.selectedIndex > 0) {
          for (final diff in controller.diffCheckpoints(
            controller.selectedIndex - 1,
            controller.selectedIndex,
          )) {
            deltaByModule[diff.module] = diff.deltaBytes;
          }
        }
        final summaries = _sorted(controller.selectedSummaries, deltaByModule);
        final showDelta = controller.selectedIndex > 0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CheckpointHeader(controller: controller),
            _ColumnHeader(
              sortKey: _sortKey,
              direction: _direction,
              onSort: _onSort,
            ),
            const Divider(height: 1, color: RadarColors.hairline08),
            Expanded(
              child: summaries.isEmpty
                  ? Center(
                      child: Text(
                        'No native allocations in this checkpoint.',
                        style: RadarTypography.caption,
                      ),
                    )
                  : ListView.builder(
                      itemCount: summaries.length,
                      itemBuilder: (context, i) => AndroidNativeModuleRow(
                        summary: summaries[i],
                        deltaBytes: showDelta
                            ? (deltaByModule[summaries[i].module] ?? 0)
                            : null,
                        isSymbolized: controller.isSymbolized,
                        onOpenDetail: widget.onOpenDetail,
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'No native checkpoints yet — import a heapprofd trace in '
        'Capture / import to see still-live data.',
        style: RadarTypography.caption,
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const RadarLinearProgress(),
        const SizedBox(height: 12),
        Text('Importing native trace…', style: RadarTypography.caption),
      ],
    );
  }
}

class _CheckpointHeader extends StatelessWidget {
  const _CheckpointHeader({required this.controller});

  final NativeProfilingController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
      child: Row(
        children: [
          Text('Native still-live', style: RadarTypography.appBarTitle),
          const SizedBox(width: 16),
          DropdownButton<int>(
            value: controller.selectedIndex,
            dropdownColor: RadarColors.bgSurface,
            style: RadarTypography.monoBody,
            items: [
              for (final (i, checkpoint) in controller.checkpoints.indexed)
                DropdownMenuItem(value: i, child: Text(checkpoint.label)),
            ],
            onChanged: (i) {
              if (i != null) controller.selectCheckpoint(i);
            },
          ),
        ],
      ),
    );
  }
}

class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader({
    required this.sortKey,
    required this.direction,
    required this.onSort,
  });

  final _NativeSortKey sortKey;
  final RadarSortDirection direction;
  final void Function(String key, RadarSortDirection dir) onSort;

  Widget _header(String label, _NativeSortKey key) {
    return RadarSortHeader(
      label: label,
      sortKey: key.name,
      activeSortKey: sortKey.name,
      direction: direction,
      onSort: onSort,
    );
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: RadarColors.bgTableHeader),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'module ▸ call site',
                style: RadarTypography.monoLabel,
              ),
            ),
            SortHeaderCell(
              width: nativeColStillLiveWidth,
              child: _header('still-live', _NativeSortKey.stillLive),
            ),
            SortHeaderCell(
              width: nativeColAllocsWidth,
              child: _header('allocs', _NativeSortKey.allocs),
            ),
            SortHeaderCell(
              width: nativeColGrowthWidth,
              child: _header('Δ', _NativeSortKey.growth),
            ),
          ],
        ),
      ),
    );
  }
}
