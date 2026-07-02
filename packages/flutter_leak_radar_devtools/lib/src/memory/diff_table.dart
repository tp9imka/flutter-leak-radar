import 'package:flutter/material.dart';
import 'package:leak_graph/leak_graph.dart';
import 'package:radar_ui/radar_ui.dart';

import '../filter/filter_bar.dart';
import '../filter/filter_expression.dart';
import 'filter_target.dart';
import 'mem_format.dart';
import 'sort_header_cell.dart';

const double _wInst = 72;
const double _wBytes = 84;
const double _wLive = 64;

enum _DiffSortKey { className, library, instanceDelta, bytesDelta, live }

/// Ranked class-growth table for a diff between two snapshots. Sortable,
/// filterable, and selectable (tap a row to inspect the class).
class DiffTable extends StatefulWidget {
  const DiffTable({
    super.key,
    required this.diffs,
    required this.summary,
    required this.selected,
    required this.onSelected,
    this.absolute = false,
  });

  final List<ClassCountDiff> diffs;

  /// When true the diff is a single snapshot against an empty baseline, so the
  /// numeric columns are rendered as absolute totals (neutral, no sign/colour)
  /// rather than signed deltas.
  final bool absolute;

  /// Small A→B byte-delta summary shown in the sub-header.
  final Widget summary;

  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  State<DiffTable> createState() => _DiffTableState();
}

class _DiffTableState extends State<DiffTable> {
  _DiffSortKey _sortKey = _DiffSortKey.bytesDelta;
  RadarSortDirection _direction = RadarSortDirection.descending;
  FilterExpression _filter = FilterExpression.empty;

  List<ClassCountDiff> _visible() {
    final filtered = _filter.isEmpty
        ? [...widget.diffs]
        : widget.diffs
              .where(
                (d) => _filter.matches(
                  ClassRow(
                    className: d.after.className,
                    libraryUri: d.after.libraryUri,
                  ),
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
    setState(() {
      _sortKey = _DiffSortKey.values.firstWhere((e) => e.name == key);
      _direction = dir;
    });
  }

  Widget _sortHeader(String label, _DiffSortKey key, {TextAlign? align}) {
    return RadarSortHeader(
      label: label,
      sortKey: key.name,
      activeSortKey: _sortKey.name,
      direction: _direction,
      onSort: _onSort,
      textAlign: align ?? TextAlign.right,
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _visible();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Sub-header: A→B summary + filter.
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
                widget.summary,
                const SizedBox(width: 16),
                Expanded(
                  child: FilterBar(
                    expression: _filter,
                    onChanged: (f) => setState(() => _filter = f),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Column headers.
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
                  child: _sortHeader(
                    'class',
                    _DiffSortKey.className,
                    align: TextAlign.left,
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: _sortHeader(
                    'library',
                    _DiffSortKey.library,
                    align: TextAlign.left,
                  ),
                ),
                SortHeaderCell(
                  width: _wInst,
                  child: _sortHeader(
                    widget.absolute ? 'inst' : 'Δ inst',
                    _DiffSortKey.instanceDelta,
                  ),
                ),
                SortHeaderCell(
                  width: _wBytes,
                  child: _sortHeader(
                    widget.absolute ? 'bytes' : 'Δ bytes',
                    _DiffSortKey.bytesDelta,
                  ),
                ),
                SortHeaderCell(
                  width: _wLive,
                  child: _sortHeader('live', _DiffSortKey.live),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? Center(
                  child: Text(
                    widget.diffs.isEmpty
                        ? (widget.absolute
                              ? 'This snapshot has no classes.'
                              : 'No class-count changes between these snapshots.')
                        : 'No classes match the filter.',
                    style: RadarTypography.caption,
                  ),
                )
              : ListView.builder(
                  itemCount: rows.length,
                  itemExtent: 34,
                  itemBuilder: (context, i) => _DiffRow(
                    diff: rows[i],
                    absolute: widget.absolute,
                    selected: rows[i].after.className == widget.selected,
                    onTap: () => widget.onSelected(
                      rows[i].after.className == widget.selected
                          ? null
                          : rows[i].after.className,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _DiffRow extends StatelessWidget {
  const _DiffRow({
    required this.diff,
    required this.selected,
    required this.onTap,
    this.absolute = false,
  });

  final ClassCountDiff diff;
  final bool selected;
  final bool absolute;
  final VoidCallback onTap;

  Color _deltaColor(int v) {
    if (v > 0) return RadarColors.critical;
    if (v < 0) return RadarColors.accent;
    return RadarColors.text40;
  }

  String _fmtDelta(int v) => v > 0 ? '+$v' : '$v';

  String _fmtBytesDelta(int v) {
    final sign = v > 0
        ? '+'
        : v < 0
        ? '-'
        : '';
    return '$sign${fmtBytes(v.abs())}';
  }

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
        child: Row(
          children: [
            Container(
              width: 3,
              height: 34,
              color: selected ? RadarColors.accent : Colors.transparent,
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
                libraryLabel(diff.after.libraryUri),
                style: RadarTypography.monoLabel.copyWith(fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(
              width: _wInst,
              child: Text(
                absolute ? '${diff.after.instanceCount}' : _fmtDelta(diff.instanceDelta),
                style: absolute
                    ? RadarTypography.monoNumber.copyWith(fontSize: 12)
                    : RadarTypography.monoNumber.copyWith(
                        color: _deltaColor(diff.instanceDelta),
                        fontSize: 12,
                      ),
                textAlign: TextAlign.right,
              ),
            ),
            SizedBox(
              width: _wBytes,
              child: Text(
                absolute
                    ? fmtBytes(diff.after.shallowBytes)
                    : _fmtBytesDelta(diff.bytesDelta),
                style: absolute
                    ? RadarTypography.monoNumber.copyWith(fontSize: 12)
                    : RadarTypography.monoNumber.copyWith(
                        color: _deltaColor(diff.bytesDelta),
                        fontSize: 12,
                      ),
                textAlign: TextAlign.right,
              ),
            ),
            SizedBox(
              width: _wLive,
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
