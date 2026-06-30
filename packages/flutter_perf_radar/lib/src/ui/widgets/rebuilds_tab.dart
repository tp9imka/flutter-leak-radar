// lib/src/ui/widgets/rebuilds_tab.dart
import 'package:flutter/material.dart';
import 'package:radar_trace/radar_trace.dart';
import 'package:radar_ui/radar_ui.dart';

// ── EXCESSIVE rebuild threshold ───────────────────────────────────────────────

/// A subtree is flagged EXCESSIVE when its rebuild count exceeds this
/// in the observed window.
const int _kExcessiveThreshold = 50;

// ── Public widget ─────────────────────────────────────────────────────────────

/// Rebuilds tab: per-label rebuild count rows with EXCESSIVE tagging.
///
/// Sortable by count (descending default). Shows a proportional bar
/// and an EXCESSIVE tag for flagged subtrees.
class RebuildsTab extends StatefulWidget {
  /// Creates a [RebuildsTab] from [snapshot].
  const RebuildsTab({super.key, required this.snapshot});

  /// The trace snapshot providing rebuild span counts.
  final TraceSnapshot snapshot;

  @override
  State<RebuildsTab> createState() => _RebuildsTabState();
}

class _RebuildsTabState extends State<RebuildsTab> {
  RadarSortDirection _sortDir = RadarSortDirection.descending;

  List<_RebuildEntry> get _entries {
    final raw = widget.snapshot.stats.entries
        .where((e) => e.key.name.startsWith('rebuild:'))
        .map(
          (e) => _RebuildEntry(
            label: e.key.name.substring('rebuild:'.length),
            count: e.value.count,
          ),
        )
        .toList();

    raw.sort((a, b) {
      final cmp = a.count.compareTo(b.count);
      return _sortDir == RadarSortDirection.descending ? -cmp : cmp;
    });

    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          sortDir: _sortDir,
          onSort: (dir) => setState(() => _sortDir = dir),
        ),
        if (entries.isEmpty)
          Expanded(child: _EmptyState())
        else
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.only(
                top: 8,
                bottom: 8 + MediaQuery.of(context).padding.bottom,
              ),
              itemCount: entries.length,
              itemBuilder: (ctx, i) {
                final maxCount = entries.isNotEmpty ? entries.first.count : 1;
                return _RebuildRow(entry: entries[i], maxCount: maxCount);
              },
            ),
          ),
      ],
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.sortDir, required this.onSort});

  final RadarSortDirection sortDir;
  final ValueChanged<RadarSortDirection> onSort;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: RadarColors.bgTableHeader,
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: RadarDensity.rowVPad,
      ),
      child: Row(
        children: [
          Expanded(child: Text('label', style: RadarTypography.monoLabel)),
          RadarSortHeader(
            label: 'count',
            sortKey: 'count',
            activeSortKey: 'count',
            direction: sortDir,
            onSort: (_, dir) => onSort(dir),
          ),
        ],
      ),
    );
  }
}

// ── Row ───────────────────────────────────────────────────────────────────────

class _RebuildRow extends StatelessWidget {
  const _RebuildRow({required this.entry, required this.maxCount});

  final _RebuildEntry entry;
  final int maxCount;

  bool get _isExcessive => entry.count >= _kExcessiveThreshold;

  @override
  Widget build(BuildContext context) {
    final fraction = maxCount > 0 ? (entry.count / maxCount) : 0.0;
    final barColor = _isExcessive ? RadarColors.critical : RadarColors.accent;
    final countColor = _isExcessive
        ? RadarColors.critical
        : RadarColors.text100;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: _isExcessive
              ? RadarColors.critical.withValues(alpha: 0.05)
              : RadarColors.bgSurface,
          borderRadius: RadarDensity.rowRadius,
          border: Border.all(
            color: _isExcessive
                ? RadarColors.critical.withValues(alpha: 0.20)
                : RadarColors.hairline08,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          entry.label,
                          style: RadarTypography.monoBody,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      if (_isExcessive) ...[
                        const SizedBox(width: 6),
                        const RadarTag(
                          label: 'EXCESSIVE',
                          color: RadarColors.critical,
                        ),
                      ],
                    ],
                  ),
                ),
                Text(
                  '${entry.count}×',
                  style: RadarTypography.monoNumber.copyWith(color: countColor),
                ),
              ],
            ),
            const SizedBox(height: 5),
            // Proportional bar
            ClipRRect(
              borderRadius: const BorderRadius.all(Radius.circular(2)),
              child: SizedBox(
                height: 3,
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: fraction.clamp(0.01, 1.0),
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: barColor),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '◌',
              style: RadarTypography.metricValue.copyWith(
                color: RadarColors.text15,
                fontSize: 40,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'No rebuild spans recorded.\n'
              'Wrap subtrees with TracedSubtree() to track rebuilds.',
              textAlign: TextAlign.center,
              style: RadarTypography.caption,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Data class ────────────────────────────────────────────────────────────────

class _RebuildEntry {
  const _RebuildEntry({required this.label, required this.count});

  final String label;
  final int count;
}
