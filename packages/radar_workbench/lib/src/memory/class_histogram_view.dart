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
const double _wInstances = 76;
const double _wBytes = 80;
const double _wPct = 92;

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
          classAnchors: classAnchorsFromClusters(analysis.clusters),
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
          ),
        )
        .toList();
  }

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
            const SizedBox(width: _wOrigin),
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
              _buildHeader(),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          'No classes match the filter.',
                          style: RadarTypography.caption,
                        ),
                      )
                    : _grouped
                    ? _groupedList(filtered)
                    : _flatList(_sorted(filtered)),
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

  Widget _flatList(List<ClassCount> rows) => ListView.builder(
    itemCount: rows.length,
    itemExtent: 34,
    itemBuilder: (context, i) => _HistRow(
      entry: rows[i],
      totalBytes: _totalBytes,
      origin: originOf(
        rows[i].libraryUri,
        projectPackages: widget.projectPackages,
      ),
      selected: rows[i].className == _selected,
      onTap: () => _select(rows[i].className),
    ),
  );

  Widget _groupedList(List<ClassCount> rows) {
    final groups = _groups(rows);
    final hasProject = groups.any((g) => g.isProject);
    final lines = <_HistLine>[];
    for (final g in groups) {
      final expanded = _isExpanded(g, hasProject: hasProject);
      lines.add(_HistHeaderLine(g, expanded));
      if (expanded) {
        for (final row in g.rows) {
          lines.add(_HistRowLine(row, g.origin));
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
          _HistRowLine(:final entry, :final origin) => _HistRow(
            entry: entry,
            totalBytes: _totalBytes,
            origin: origin,
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
  const _HistRowLine(this.entry, this.origin);
  final ClassCount entry;
  final RadarOrigin origin;
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
        child: Row(
          children: [
            Text('Class Histogram', style: RadarTypography.appBarTitle),
            const SizedBox(width: 12),
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
    required this.selected,
    required this.onTap,
  });

  final ClassCount entry;
  final int totalBytes;
  final RadarOrigin origin;
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
              SizedBox(
                width: _wOrigin,
                child: Row(
                  children: [
                    OriginChip(origin: origin),
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
