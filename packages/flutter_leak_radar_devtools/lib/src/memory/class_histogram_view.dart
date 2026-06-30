import 'package:flutter/material.dart';
import 'package:leak_graph/leak_graph.dart';
import 'package:radar_ui/radar_ui.dart';

import '../diff/diff_controller.dart';

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

/// Full-page class histogram view for the most recent snapshot.
///
/// Shows [DiffController.snapshotB] if available, else [snapshotA].
/// Supports search and column sorting.
class ClassHistogramView extends StatelessWidget {
  const ClassHistogramView({super.key, required this.controller});

  final DiffController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final snapshot = controller.snapshotB ?? controller.snapshotA;
        if (snapshot == null) {
          return const Center(child: _HistogramEmptyState());
        }
        return _HistogramTable(entries: snapshot.histogram);
      },
    );
  }
}

class _HistogramEmptyState extends StatelessWidget {
  const _HistogramEmptyState();

  @override
  Widget build(BuildContext context) {
    return Text(
      'No snapshot captured yet — use Snapshot & diff to capture.',
      style: RadarTypography.caption,
      textAlign: TextAlign.center,
    );
  }
}

// ── Sortable table ────────────────────────────────────────────────────────────

enum _HistSortKey { className, instances, bytes, pctHeap }

class _HistogramTable extends StatefulWidget {
  const _HistogramTable({required this.entries});

  final List<ClassCount> entries;

  @override
  State<_HistogramTable> createState() => _HistogramTableState();
}

class _HistogramTableState extends State<_HistogramTable> {
  _HistSortKey _sortKey = _HistSortKey.bytes;
  RadarSortDirection _direction = RadarSortDirection.descending;
  String _query = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  int get _totalBytes => widget.entries.fold(0, (s, c) => s + c.shallowBytes);

  List<ClassCount> _sorted() {
    final filtered = _query.isEmpty
        ? [...widget.entries]
        : widget.entries
              .where(
                (c) => c.className.toLowerCase().contains(_query.toLowerCase()),
              )
              .toList();

    filtered.sort((a, b) {
      final cmp = switch (_sortKey) {
        _HistSortKey.className => a.className.compareTo(b.className),
        _HistSortKey.instances => a.instanceCount.compareTo(b.instanceCount),
        _HistSortKey.bytes => a.shallowBytes.compareTo(b.shallowBytes),
        _HistSortKey.pctHeap => a.shallowBytes.compareTo(b.shallowBytes),
      };
      return _direction == RadarSortDirection.descending ? -cmp : cmp;
    });
    return filtered;
  }

  void _onSort(String key, RadarSortDirection dir) {
    final k = _HistSortKey.values.firstWhere((e) => e.name == key);
    setState(() {
      _sortKey = k;
      _direction = dir;
    });
  }

  @override
  Widget build(BuildContext context) {
    final sorted = _sorted();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Toolbar
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
          child: SizedBox(
            height: 44,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Text('Class Histogram', style: RadarTypography.appBarTitle),
                  const Spacer(),
                  SizedBox(
                    width: 280,
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
        ),
        // Header row
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
                    sortKey: _HistSortKey.className.name,
                    activeSortKey: _sortKey.name,
                    direction: _direction,
                    onSort: _onSort,
                    textAlign: TextAlign.left,
                  ),
                ),
                _SortHeaderCell(
                  width: 90,
                  child: RadarSortHeader(
                    label: 'instances',
                    sortKey: _HistSortKey.instances.name,
                    activeSortKey: _sortKey.name,
                    direction: _direction,
                    onSort: _onSort,
                  ),
                ),
                _SortHeaderCell(
                  width: 90,
                  child: RadarSortHeader(
                    label: 'bytes',
                    sortKey: _HistSortKey.bytes.name,
                    activeSortKey: _sortKey.name,
                    direction: _direction,
                    onSort: _onSort,
                  ),
                ),
                _SortHeaderCell(
                  width: 100,
                  child: RadarSortHeader(
                    label: '% heap',
                    sortKey: _HistSortKey.pctHeap.name,
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
                    "No classes match '$_query'",
                    style: RadarTypography.caption,
                  ),
                )
              : ListView.builder(
                  itemCount: sorted.length,
                  itemExtent: 36,
                  itemBuilder: (context, i) =>
                      _HistRow(entry: sorted[i], totalBytes: _totalBytes),
                ),
        ),
      ],
    );
  }
}

class _HistRow extends StatelessWidget {
  const _HistRow({required this.entry, required this.totalBytes});

  final ClassCount entry;
  final int totalBytes;

  String _fmtBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  double get _pct => totalBytes == 0 ? 0 : entry.shallowBytes / totalBytes;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: RadarColors.rowBgDefault,
        border: Border(
          bottom: BorderSide(
            color: RadarColors.hairline08,
            width: RadarDensity.hairline,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Expanded(
              flex: 4,
              child: Text(
                entry.className,
                style: RadarTypography.monoBody.copyWith(fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Flexible(
              child: Text(
                '${entry.instanceCount}',
                style: RadarTypography.monoNumber.copyWith(fontSize: 12),
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _fmtBytes(entry.shallowBytes),
                style: RadarTypography.monoNumber.copyWith(fontSize: 12),
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            _PctBar(pct: _pct),
          ],
        ),
      ),
    );
  }
}

class _PctBar extends StatelessWidget {
  const _PctBar({required this.pct});

  final double pct;

  @override
  Widget build(BuildContext context) {
    final label = '${(pct * 100).toStringAsFixed(1)}%';
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: RadarTypography.monoNumber.copyWith(
              fontSize: 11,
              color: RadarColors.text60,
            ),
          ),
          const SizedBox(width: 4),
          // Fixed-width mini bar: max 40px proportional to pct.
          ClipRRect(
            borderRadius: const BorderRadius.all(Radius.circular(3)),
            child: SizedBox(
              width: 40,
              height: 6,
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: pct.clamp(0.0, 1.0),
                child: const ColoredBox(color: RadarColors.accentSubtle),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
