import 'package:flutter/material.dart';
import 'package:leak_graph/leak_graph.dart';
import 'package:radar_ui/radar_ui.dart';

import '../filter/filter_bar.dart';
import '../filter/filter_expression.dart';
import 'class_detail_panel.dart';
import 'filter_target.dart';
import 'mem_format.dart';
import 'memory_controller.dart';
import 'sort_header_cell.dart';

// Fixed column widths shared by header + data rows so nothing clips.
const double _wInstances = 84;
const double _wBytes = 88;
const double _wPct = 104;

/// Class histogram for the focused snapshot: sortable, filterable, and — new —
/// tap a row to inspect how that class is retained (root grouping + path).
class ClassHistogramView extends StatelessWidget {
  const ClassHistogramView({super.key, required this.controller});

  final MemoryController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final snapshot = controller.focused;
        if (snapshot == null) {
          return const Center(child: _EmptyState());
        }
        return _HistogramBody(
          key: ValueKey(snapshot.id),
          entries: snapshot.histogram,
          profiles: {
            for (final p in snapshot.analysisResult.classRootProfiles)
              p.className: p,
          },
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Text(
      'No snapshot captured yet — capture one in Snapshots & diff.',
      style: RadarTypography.caption,
      textAlign: TextAlign.center,
    );
  }
}

enum _HistSortKey { className, instances, bytes, pctHeap }

class _HistogramBody extends StatefulWidget {
  const _HistogramBody({
    super.key,
    required this.entries,
    required this.profiles,
  });

  final List<ClassCount> entries;
  final Map<String, ClassRootProfile> profiles;

  @override
  State<_HistogramBody> createState() => _HistogramBodyState();
}

class _HistogramBodyState extends State<_HistogramBody> {
  _HistSortKey _sortKey = _HistSortKey.bytes;
  RadarSortDirection _direction = RadarSortDirection.descending;
  FilterExpression _filter = FilterExpression.empty;
  String? _selected;

  int get _totalBytes => widget.entries.fold(0, (s, c) => s + c.shallowBytes);

  List<ClassCount> _visible() {
    final filtered = _filter.isEmpty
        ? [...widget.entries]
        : widget.entries
              .where(
                (c) => _filter.matches(
                  ClassRow(className: c.className, libraryUri: c.libraryUri),
                ),
              )
              .toList();
    filtered.sort((a, b) {
      final cmp = switch (_sortKey) {
        _HistSortKey.className => a.className.compareTo(b.className),
        _HistSortKey.instances => a.instanceCount.compareTo(b.instanceCount),
        _HistSortKey.bytes ||
        _HistSortKey.pctHeap => a.shallowBytes.compareTo(b.shallowBytes),
      };
      return _direction == RadarSortDirection.descending ? -cmp : cmp;
    });
    return filtered;
  }

  void _onSort(String key, RadarSortDirection dir) {
    setState(() {
      _sortKey = _HistSortKey.values.firstWhere((e) => e.name == key);
      _direction = dir;
    });
  }

  Widget _sortHeader(String label, _HistSortKey key, {TextAlign? align}) {
    return RadarSortHeader(
      label: label,
      sortKey: key.name,
      activeSortKey: _sortKey.name,
      direction: _direction,
      onSort: _onSort,
      textAlign: align ?? TextAlign.right,
    );
  }

  Widget _buildHeader() {
    return DecoratedBox(
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
              child: _sortHeader(
                'class',
                _HistSortKey.className,
                align: TextAlign.left,
              ),
            ),
            SortHeaderCell(
              width: _wInstances,
              child: _sortHeader('instances', _HistSortKey.instances),
            ),
            SortHeaderCell(
              width: _wBytes,
              child: _sortHeader('bytes', _HistSortKey.bytes),
            ),
            SortHeaderCell(
              width: _wPct,
              child: _sortHeader('% heap', _HistSortKey.pctHeap),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _visible();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Toolbar(
                filter: _filter,
                onFilter: (f) => setState(() => _filter = f),
              ),
              _buildHeader(),
              Expanded(
                child: rows.isEmpty
                    ? Center(
                        child: Text(
                          'No classes match the filter.',
                          style: RadarTypography.caption,
                        ),
                      )
                    : ListView.builder(
                        itemCount: rows.length,
                        itemExtent: 34,
                        itemBuilder: (context, i) => _HistRow(
                          entry: rows[i],
                          totalBytes: _totalBytes,
                          selected: rows[i].className == _selected,
                          onTap: () => setState(
                            () => _selected = rows[i].className == _selected
                                ? null
                                : rows[i].className,
                          ),
                        ),
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
            profile: _selected == null ? null : widget.profiles[_selected],
          ),
        ),
      ],
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.filter, required this.onFilter});

  final FilterExpression filter;
  final ValueChanged<FilterExpression> onFilter;

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
        child: Row(
          children: [
            Text('Class Histogram', style: RadarTypography.appBarTitle),
            const SizedBox(width: 16),
            Expanded(
              child: FilterBar(expression: filter, onChanged: onFilter),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistRow extends StatelessWidget {
  const _HistRow({
    required this.entry,
    required this.totalBytes,
    required this.selected,
    required this.onTap,
  });

  final ClassCount entry;
  final int totalBytes;
  final bool selected;
  final VoidCallback onTap;

  double get _pct => totalBytes == 0 ? 0 : entry.shallowBytes / totalBytes;

  @override
  Widget build(BuildContext context) {
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
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: Text(
                  entry.className,
                  style: RadarTypography.monoBody.copyWith(
                    fontSize: 12,
                    color: selected ? RadarColors.accent : null,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(
                width: _wInstances,
                child: Text(
                  '${entry.instanceCount}',
                  style: RadarTypography.monoNumber.copyWith(fontSize: 12),
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(
                width: _wBytes,
                child: Text(
                  fmtBytes(entry.shallowBytes),
                  style: RadarTypography.monoNumber.copyWith(fontSize: 12),
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(
                width: _wPct,
                child: _PctCell(pct: _pct),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PctCell extends StatelessWidget {
  const _PctCell({required this.pct});

  final double pct;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${(pct * 100).toStringAsFixed(1)}%',
            style: RadarTypography.monoNumber.copyWith(
              fontSize: 11,
              color: RadarColors.text60,
            ),
          ),
          const SizedBox(width: 6),
          ClipRRect(
            borderRadius: const BorderRadius.all(Radius.circular(3)),
            child: SizedBox(
              width: 34,
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
