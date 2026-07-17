import 'package:flutter/material.dart';
import 'package:leak_graph/leak_graph.dart';
import 'package:radar_ui/radar_ui.dart';

import '../filter/filter_bar.dart';
import '../filter/filter_expression.dart';
import 'filter_target.dart';
import 'mem_format.dart';
import 'package_group_scaffold.dart';
import 'sort_header_cell.dart';

const double _wInst = 72;
const double _wBytes = 84;
const double _wLive = 64;

enum _DiffSortKey { className, library, instanceDelta, bytesDelta, live }

/// Ranked class-growth table for a diff between two snapshots. Sortable,
/// filterable, and selectable (tap a row to inspect the class).
///
/// Defaults to grouping rows by their ANCHOR package (the S1 "which are MINE"
/// view): the project group is pinned first and expanded, dependency groups and
/// one merged runtime group are collapsed showing rollup Δbytes. A grouped/flat
/// toggle and a "hide framework" preset chip sit in the sub-header.
class DiffTable extends StatefulWidget {
  const DiffTable({
    super.key,
    required this.diffs,
    required this.summary,
    required this.selected,
    required this.onSelected,
    this.absolute = false,
    this.classAnchors = const {},
    this.projectPackages = const {},
    this.triage = const {},
  });

  final List<ClassCountDiff> diffs;

  /// Cross-session status per class name. A row renders a [TriageChip] only for
  /// classes present here; empty (the default) means no chips, so the row
  /// layout is unchanged. Supplied by the host from the current clusters —
  /// never derived inside the table, to avoid inventing an identity a diff row
  /// cannot own.
  final Map<String, TriageDisplay> triage;

  /// When true the diff is a single snapshot against an empty baseline, so the
  /// numeric columns are rendered as absolute totals (neutral, no sign/colour)
  /// rather than signed deltas.
  final bool absolute;

  /// Small A→B byte-delta summary shown in the sub-header.
  final Widget summary;

  final String? selected;
  final ValueChanged<String?> onSelected;

  /// Per-class anchor library (who retains it). Absent → group by declared
  /// package. See [classAnchorsFromClusters].
  final Map<String, Uri?> classAnchors;

  /// Resolved project-owned package names, used to classify row origins and to
  /// evaluate `origin:` filter terms.
  final Set<String> projectPackages;

  @override
  State<DiffTable> createState() => _DiffTableState();
}

class _DiffTableState extends State<DiffTable> {
  _DiffSortKey _sortKey = _DiffSortKey.bytesDelta;
  RadarSortDirection _direction = RadarSortDirection.descending;
  FilterExpression _filter = FilterExpression.empty;
  bool _grouped = true;
  final Map<String, bool> _expanded = {};

  static final String _presetText = FilterExpression.parse(
    kHideFrameworkFilter,
  ).text;

  List<ClassCountDiff> _filtered() {
    if (_filter.isEmpty) return [...widget.diffs];
    return widget.diffs
        .where(
          (d) => _filter.matches(
            ClassRow(
              className: d.after.className,
              libraryUri: d.after.libraryUri,
            ),
            projectPackages: widget.projectPackages,
            anchorLibraryUri: widget.classAnchors[d.after.className],
          ),
        )
        .toList();
  }

  List<ClassCountDiff> _sorted(List<ClassCountDiff> rows) {
    rows.sort((a, b) {
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
    return rows;
  }

  List<PackageGroup<ClassCountDiff>> _groups(List<ClassCountDiff> rows) =>
      groupRowsByPackage<ClassCountDiff>(
        rows,
        declaredLibraryOf: (d) => d.after.libraryUri,
        anchorLibraryOf: (d) => widget.classAnchors[d.after.className],
        bytesOf: (d) => d.after.shallowBytes,
        deltaOf: (d) => d.bytesDelta,
        projectPackages: widget.projectPackages,
      );

  List<PackageGroup<ClassCountDiff>>? _cachedGroups;
  Object? _cacheKey;

  /// Grouping is stable across expand/select setState (which don't touch the
  /// diffs, filter, or sort), so memoize it keyed by those inputs.
  List<PackageGroup<ClassCountDiff>> _groupsMemo(List<ClassCountDiff> rows) {
    final key = (
      identityHashCode(widget.diffs),
      _filter.text,
      _sortKey.index,
      _direction.index,
    );
    if (_cachedGroups != null && _cacheKey == key) return _cachedGroups!;
    final groups = _groups(rows);
    _cachedGroups = groups;
    _cacheKey = key;
    return groups;
  }

  bool _isExpanded(
    PackageGroup<ClassCountDiff> g, {
    required bool hasProject,
  }) => _expanded[g.package] ?? (g.isProject || !hasProject);

  void _onSort(String key, RadarSortDirection dir) {
    setState(() {
      _sortKey = _DiffSortKey.values.firstWhere((e) => e.name == key);
      _direction = dir;
    });
  }

  void _setHideFramework(bool on) {
    setState(() {
      _filter = on
          ? FilterExpression.parse(kHideFrameworkFilter)
          : FilterExpression.empty;
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
    final filtered = _filtered();
    final groups = (_grouped && filtered.isNotEmpty)
        ? _groupsMemo(filtered)
        : const <PackageGroup<ClassCountDiff>>[];
    final hasProject = groups.any((g) => g.isProject);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SubHeader(
          summary: widget.summary,
          filter: _filter,
          grouped: _grouped,
          hideFramework: _filter.text == _presetText,
          onGrouped: (g) => setState(() => _grouped = g),
          onHideFramework: _setHideFramework,
          onFilter: (f) => setState(() => _filter = f),
        ),
        _columnHeader(),
        Expanded(
          child: filtered.isEmpty
              ? _emptyState()
              : _grouped
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!hasProject)
                      PackageGroupBanner(
                        attributionResolved: widget.projectPackages.isNotEmpty,
                      ),
                    Expanded(
                      child: _GroupedList(
                        groups: groups,
                        hasProject: hasProject,
                        absolute: widget.absolute,
                        selected: widget.selected,
                        onSelected: widget.onSelected,
                        triage: widget.triage,
                        isExpanded: _isExpanded,
                        onToggle: (g, expanded) =>
                            setState(() => _expanded[g.package] = !expanded),
                      ),
                    ),
                  ],
                )
              : _flatList(_sorted(filtered)),
        ),
      ],
    );
  }

  Widget _emptyState() => Center(
    child: Text(
      widget.diffs.isEmpty
          ? (widget.absolute
                ? 'This snapshot has no classes.'
                : 'No class-count changes between these snapshots.')
          : 'No classes match the filter.',
      style: RadarTypography.caption,
    ),
  );

  Widget _flatList(List<ClassCountDiff> rows) => ListView.builder(
    itemCount: rows.length,
    itemExtent: 34,
    itemBuilder: (context, i) => _DiffRow(
      diff: rows[i],
      absolute: widget.absolute,
      selected: rows[i].after.className == widget.selected,
      display: widget.triage[rows[i].after.className],
      onTap: () => widget.onSelected(
        rows[i].after.className == widget.selected
            ? null
            : rows[i].after.className,
      ),
    ),
  );

  Widget _columnHeader() {
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
    );
  }
}

class _SubHeader extends StatelessWidget {
  const _SubHeader({
    required this.summary,
    required this.filter,
    required this.grouped,
    required this.hideFramework,
    required this.onGrouped,
    required this.onHideFramework,
    required this.onFilter,
  });

  final Widget summary;
  final FilterExpression filter;
  final bool grouped;
  final bool hideFramework;
  final ValueChanged<bool> onGrouped;
  final ValueChanged<bool> onHideFramework;
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Drop the A→B summary when the row can't fit summary + controls +
            // a usable filter, so the sub-header never overflows.
            final showSummary = constraints.maxWidth >= _summaryMinWidth;
            return Row(
              children: [
                if (showSummary) ...[
                  // The summary is an arbitrary caller widget (a Row of Texts
                  // with no ellipsis); scaleDown lets it shrink to its share
                  // instead of overflowing when the row gets tight.
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: summary,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                PackageGroupControls(
                  grouped: grouped,
                  onGroupedChanged: onGrouped,
                  hideFramework: hideFramework,
                  onHideFrameworkChanged: onHideFramework,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilterBar(expression: filter, onChanged: onFilter),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// Below this sub-header width the A→B summary is dropped so the controls +
// filter always fit.
const double _summaryMinWidth = 620;

/// Flattened grouped rows (header + optional child rows) over a virtualized
/// list so grouping keeps the flat table's 34px itemExtent.
class _GroupedList extends StatelessWidget {
  const _GroupedList({
    required this.groups,
    required this.hasProject,
    required this.absolute,
    required this.selected,
    required this.onSelected,
    required this.triage,
    required this.isExpanded,
    required this.onToggle,
  });

  final List<PackageGroup<ClassCountDiff>> groups;
  final bool hasProject;
  final bool absolute;
  final String? selected;
  final ValueChanged<String?> onSelected;
  final Map<String, TriageDisplay> triage;
  final bool Function(PackageGroup<ClassCountDiff>, {required bool hasProject})
  isExpanded;
  final void Function(PackageGroup<ClassCountDiff>, bool expanded) onToggle;

  @override
  Widget build(BuildContext context) {
    final lines = <_Line>[];
    for (final g in groups) {
      final expanded = isExpanded(g, hasProject: hasProject);
      lines.add(_HeaderLine(g, expanded));
      if (expanded) {
        for (final row in g.rows) {
          lines.add(_RowLine(row));
        }
      }
    }
    return ListView.builder(
      itemCount: lines.length,
      itemExtent: 34,
      itemBuilder: (context, i) {
        final line = lines[i];
        return switch (line) {
          _HeaderLine(:final group, :final expanded) => PackageGroupHeader(
            package: group.package,
            origin: group.origin,
            anchored: group.hasAnchoredMember,
            expanded: expanded,
            onToggle: () => onToggle(group, expanded),
            trailing: _DeltaBytes(value: group.totalDelta, absolute: absolute),
          ),
          _RowLine(:final diff) => _DiffRow(
            diff: diff,
            absolute: absolute,
            selected: diff.after.className == selected,
            display: triage[diff.after.className],
            onTap: () => onSelected(
              diff.after.className == selected ? null : diff.after.className,
            ),
          ),
        };
      },
    );
  }
}

sealed class _Line {
  const _Line();
}

class _HeaderLine extends _Line {
  const _HeaderLine(this.group, this.expanded);
  final PackageGroup<ClassCountDiff> group;
  final bool expanded;
}

class _RowLine extends _Line {
  const _RowLine(this.diff);
  final ClassCountDiff diff;
}

class _DeltaBytes extends StatelessWidget {
  const _DeltaBytes({required this.value, required this.absolute});

  final int value;
  final bool absolute;

  @override
  Widget build(BuildContext context) {
    final sign = value > 0
        ? '+'
        : value < 0
        ? '-'
        : '';
    final color = absolute
        ? RadarColors.text60
        : value > 0
        ? RadarColors.critical
        : value < 0
        ? RadarColors.accent
        : RadarColors.text40;
    return Text(
      '$sign${fmtBytes(value.abs())}',
      style: RadarTypography.monoNumber.copyWith(fontSize: 12, color: color),
    );
  }
}

class _DiffRow extends StatelessWidget {
  const _DiffRow({
    required this.diff,
    required this.selected,
    required this.onTap,
    this.absolute = false,
    this.display,
  });

  final ClassCountDiff diff;
  final bool selected;
  final bool absolute;
  final VoidCallback onTap;

  /// Cross-session status chip for this class, or null to render none (and add
  /// no width) — the default for callers that do not supply triage.
  final TriageDisplay? display;

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
                absolute
                    ? '${diff.after.instanceCount}'
                    : _fmtDelta(diff.instanceDelta),
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
            if (display != null) ...[
              const SizedBox(width: 8),
              TriageChip(display: display!),
            ],
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}
