import 'package:flutter/material.dart';
import 'package:leak_graph/leak_graph.dart';
import 'package:radar_ui/radar_ui.dart';

import '../filter/filter_bar.dart';
import '../filter/filter_expression.dart';
import 'class_detail_panel.dart';
import 'filter_target.dart';
import 'mem_format.dart';
import 'memory_controller.dart';
import 'package_group_scaffold.dart';
import 'sort_header_cell.dart';

// Fixed column widths shared by header + data rows so nothing clips.
const double _wOrigin = 132;
const double _wOriginChipOnly = 116;
const double _wInstances = 76;
const double _wBytes = 80;
const double _wPct = 92;

// Row horizontal padding (12 each side) + a minimum class column reserved
// before the origin column is allowed any width.
const double _rowHPadding = 24;
const double _minClassWidth = 40;

// Below this content width the toolbar drops its title so the controls +
// filter always fit.
const double _titleMinWidth = 640;

/// Responsive width for the origin/package column: the full chip+label width
/// when there is room, a chip-only width when tighter, or 0 (column dropped)
/// on the narrowest hosts so the row never overflows.
double _originColumnWidth(double contentWidth) {
  final leftover =
      contentWidth -
      _rowHPadding -
      _wInstances -
      _wBytes -
      _wPct -
      _minClassWidth;
  if (leftover >= _wOrigin) return _wOrigin;
  if (leftover >= _wOriginChipOnly) return _wOriginChipOnly;
  return 0;
}

/// Class histogram for the focused snapshot: sortable, filterable, and — new —
/// tap a row to inspect how that class is retained (root grouping + path).
///
/// Rows carry an origin chip + package label (there is no library column), and
/// default to grouping by anchor package (project first) with a grouped/flat
/// toggle and a "hide framework" preset.
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
        final analysis = snapshot.analysisResult;
        return _HistogramBody(
          key: ValueKey(snapshot.id),
          entries: snapshot.histogram,
          profiles: {
            for (final p in analysis.classRootProfiles) p.className: p,
          },
          distributions: {
            for (final d in analysis.classPathDistributions) d.className: d,
          },
          classAnchors: classAnchorsFor(analysis),
          projectPackages: analysis.resolvedAppPackages.toSet(),
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
    required this.distributions,
    required this.classAnchors,
    required this.projectPackages,
  });

  final List<ClassCount> entries;
  final Map<String, ClassRootProfile> profiles;
  final Map<String, ClassPathDistribution> distributions;
  final Map<String, Uri?> classAnchors;
  final Set<String> projectPackages;

  @override
  State<_HistogramBody> createState() => _HistogramBodyState();
}

class _HistogramBodyState extends State<_HistogramBody> {
  _HistSortKey _sortKey = _HistSortKey.bytes;
  RadarSortDirection _direction = RadarSortDirection.descending;
  FilterExpression _filter = FilterExpression.empty;
  String? _selected;
  bool _grouped = true;
  final Map<String, bool> _expanded = {};

  static final String _presetText = FilterExpression.parse(
    kHideFrameworkFilter,
  ).text;

  int get _totalBytes => widget.entries.fold(0, (s, c) => s + c.shallowBytes);

  List<ClassCount> _filtered() {
    if (_filter.isEmpty) return [...widget.entries];
    return widget.entries
        .where(
          (c) => _filter.matches(
            ClassRow(className: c.className, libraryUri: c.libraryUri),
            projectPackages: widget.projectPackages,
            anchorLibraryUri: widget.classAnchors[c.className],
          ),
        )
        .toList();
  }

  /// Effective (anchor-aware) origin for a row's chip, matching the `origin:`
  /// filter so the chip and filter never disagree.
  RadarOrigin _originFor(ClassCount c) => effectiveOriginOf(
    c.libraryUri,
    widget.classAnchors[c.className],
    projectPackages: widget.projectPackages,
  );

  List<ClassCount> _sorted(List<ClassCount> rows) {
    rows.sort((a, b) {
      final cmp = switch (_sortKey) {
        _HistSortKey.className => a.className.compareTo(b.className),
        _HistSortKey.instances => a.instanceCount.compareTo(b.instanceCount),
        _HistSortKey.bytes ||
        _HistSortKey.pctHeap => a.shallowBytes.compareTo(b.shallowBytes),
      };
      return _direction == RadarSortDirection.descending ? -cmp : cmp;
    });
    return rows;
  }

  List<PackageGroup<ClassCount>> _groups(List<ClassCount> rows) =>
      groupRowsByPackage<ClassCount>(
        rows,
        declaredLibraryOf: (c) => c.libraryUri,
        anchorLibraryOf: (c) => widget.classAnchors[c.className],
        bytesOf: (c) => c.shallowBytes,
        projectPackages: widget.projectPackages,
      );

  List<PackageGroup<ClassCount>>? _cachedGroups;
  Object? _cacheKey;

  /// Memoized grouping — reused across expand/select setState, recomputed only
  /// when the entries or filter change.
  List<PackageGroup<ClassCount>> _groupsMemo(List<ClassCount> rows) {
    final key = (identityHashCode(widget.entries), _filter.text);
    if (_cachedGroups != null && _cacheKey == key) return _cachedGroups!;
    final groups = _groups(rows);
    _cachedGroups = groups;
    _cacheKey = key;
    return groups;
  }

  bool _isExpanded(PackageGroup<ClassCount> g, {required bool hasProject}) =>
      _expanded[g.package] ?? (g.isProject || !hasProject);

  void _onSort(String key, RadarSortDirection dir) {
    setState(() {
      _sortKey = _HistSortKey.values.firstWhere((e) => e.name == key);
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

  void _select(String className) {
    setState(() => _selected = className == _selected ? null : className);
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

  Widget _buildHeader(double originWidth) {
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
            if (originWidth > 0)
              SizedBox(
                width: originWidth,
                child: Text(
                  originWidth >= _wOrigin ? 'origin / package' : 'origin',
                  style: RadarTypography.monoLabel.copyWith(
                    color: RadarColors.text40,
                  ),
                  overflow: TextOverflow.ellipsis,
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
    final filtered = _filtered();
    final groups = (_grouped && filtered.isNotEmpty)
        ? _groupsMemo(filtered)
        : const <PackageGroup<ClassCount>>[];
    final hasProject = groups.any((g) => g.isProject);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Toolbar(
                filter: _filter,
                grouped: _grouped,
                hideFramework: _filter.text == _presetText,
                onGrouped: (g) => setState(() => _grouped = g),
                onHideFramework: _setHideFramework,
                onFilter: (f) => setState(() => _filter = f),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final originWidth = _originColumnWidth(
                      constraints.maxWidth,
                    );
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHeader(originWidth),
                        Expanded(
                          child: filtered.isEmpty
                              ? Center(
                                  child: Text(
                                    'No classes match the filter.',
                                    style: RadarTypography.caption,
                                  ),
                                )
                              : _grouped
                              ? Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (!hasProject)
                                      PackageGroupBanner(
                                        attributionResolved:
                                            widget.projectPackages.isNotEmpty,
                                        subject: 'snapshot',
                                      ),
                                    Expanded(
                                      child: _groupedList(
                                        groups,
                                        hasProject,
                                        originWidth,
                                      ),
                                    ),
                                  ],
                                )
                              : _flatList(_sorted(filtered), originWidth),
                        ),
                      ],
                    );
                  },
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
            distribution: _selected == null
                ? null
                : widget.distributions[_selected],
          ),
        ),
      ],
    );
  }

  Widget _flatList(List<ClassCount> rows, double originWidth) =>
      ListView.builder(
        itemCount: rows.length,
        itemExtent: 34,
        itemBuilder: (context, i) => _HistRow(
          entry: rows[i],
          totalBytes: _totalBytes,
          origin: _originFor(rows[i]),
          originWidth: originWidth,
          selected: rows[i].className == _selected,
          onTap: () => _select(rows[i].className),
        ),
      );

  Widget _groupedList(
    List<PackageGroup<ClassCount>> groups,
    bool hasProject,
    double originWidth,
  ) {
    final lines = <_HistLine>[];
    for (final g in groups) {
      final expanded = _isExpanded(g, hasProject: hasProject);
      lines.add(_HistHeaderLine(g, expanded));
      if (expanded) {
        for (final row in g.rows) {
          lines.add(_HistRowLine(row));
        }
      }
    }
    return ListView.builder(
      itemCount: lines.length,
      itemExtent: 34,
      itemBuilder: (context, i) {
        final line = lines[i];
        return switch (line) {
          _HistHeaderLine(:final group, :final expanded) => PackageGroupHeader(
            package: group.package,
            origin: group.origin,
            anchored: group.hasAnchoredMember,
            expanded: expanded,
            onToggle: () =>
                setState(() => _expanded[group.package] = !expanded),
            trailing: Text(
              fmtBytes(group.totalBytes),
              style: RadarTypography.monoNumber.copyWith(
                fontSize: 12,
                color: RadarColors.text60,
              ),
            ),
          ),
          _HistRowLine(:final entry) => _HistRow(
            entry: entry,
            totalBytes: _totalBytes,
            origin: _originFor(entry),
            originWidth: originWidth,
            selected: entry.className == _selected,
            onTap: () => _select(entry.className),
          ),
        };
      },
    );
  }
}

sealed class _HistLine {
  const _HistLine();
}

class _HistHeaderLine extends _HistLine {
  const _HistHeaderLine(this.group, this.expanded);
  final PackageGroup<ClassCount> group;
  final bool expanded;
}

class _HistRowLine extends _HistLine {
  const _HistRowLine(this.entry);
  final ClassCount entry;
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.filter,
    required this.grouped,
    required this.hideFramework,
    required this.onGrouped,
    required this.onHideFramework,
    required this.onFilter,
  });

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
            final showTitle = constraints.maxWidth >= _titleMinWidth;
            return Row(
              children: [
                if (showTitle) ...[
                  Flexible(
                    child: Text(
                      'Class Histogram',
                      style: RadarTypography.appBarTitle,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
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

class _HistRow extends StatelessWidget {
  const _HistRow({
    required this.entry,
    required this.totalBytes,
    required this.origin,
    required this.originWidth,
    required this.selected,
    required this.onTap,
  });

  final ClassCount entry;
  final int totalBytes;
  final RadarOrigin origin;

  /// Responsive width of the origin/package column: full chip+label, a
  /// chip-only width, or 0 (column dropped) on the narrowest hosts.
  final double originWidth;
  final bool selected;
  final VoidCallback onTap;

  double get _pct => totalBytes == 0 ? 0 : entry.shallowBytes / totalBytes;

  @override
  Widget build(BuildContext context) {
    final package = packageLabelOf(entry.libraryUri) ?? '--';
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
              if (originWidth > 0)
                SizedBox(
                  width: originWidth,
                  child: Row(
                    children: [
                      OriginChip(origin: origin),
                      if (originWidth >= _wOrigin) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Tooltip(
                            message: package,
                            child: Text(
                              package,
                              style: RadarTypography.monoLabel.copyWith(
                                fontSize: 11,
                                color: RadarColors.text60,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ],
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
