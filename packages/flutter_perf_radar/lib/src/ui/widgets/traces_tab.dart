// lib/src/ui/widgets/traces_tab.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:radar_trace/radar_trace.dart';
import 'package:radar_ui/radar_ui.dart';

// ── HOT/duplicate detection thresholds ───────────────────────────────────────

/// A key is "hot" if it has this many calls or more…
const int _kHotCountMin = 10;

/// …AND its average inter-call interval is below this (500ms).
const int _kHotIntervalMaxMicros = 500000;

/// …OR its call rate is above this (2/s).
const double _kHotRateMin = 2.0;

/// Sort columns for the Traces table.
enum _TraceSort { op, count, avg, p95, total, intvl }

/// Quick-filter categories for the Traces table.
enum _TraceFilter { all, hot, errors }

// ── Public tab widget ─────────────────────────────────────────────────────────

/// Dense sortable Traces tab — the priority performance surface.
///
/// Renders a sticky column-header table of all [SpanKeyStatsSnapshot]s
/// with search, quick-filter chips, HOT tagging, and tap-to-detail.
class TracesTab extends StatefulWidget {
  /// Creates a [TracesTab] from the current [snapshot].
  const TracesTab({super.key, required this.snapshot});

  /// The trace snapshot to display.
  final TraceSnapshot snapshot;

  @override
  State<TracesTab> createState() => _TracesTabState();
}

class _TracesTabState extends State<TracesTab> {
  _TraceSort _sortKey = _TraceSort.total;
  RadarSortDirection _sortDir = RadarSortDirection.descending;
  _TraceFilter _filter = _TraceFilter.all;
  String _query = '';
  final TextEditingController _queryCtrl = TextEditingController();

  bool _isHot(SpanKeyStatsSnapshot s) {
    if (s.count < _kHotCountMin) return false;
    final interval = s.avgInterCallIntervalMicros;
    if (interval != null && interval < _kHotIntervalMaxMicros) return true;
    final rate = s.callsPerSecond;
    if (rate != null && rate > _kHotRateMin) return true;
    return false;
  }

  List<SpanKeyStatsSnapshot> get _filtered {
    final all = widget.snapshot.stats.values.toList();

    var base = switch (_filter) {
      _TraceFilter.all => all,
      _TraceFilter.hot => all.where(_isHot).toList(),
      _TraceFilter.errors => all.where((s) => s.errorCount > 0).toList(),
    };

    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      base = base
          .where(
            (s) =>
                s.key.name.toLowerCase().contains(q) ||
                (s.key.category ?? '').toLowerCase().contains(q),
          )
          .toList();
    }

    base.sort((a, b) {
      final cmp = switch (_sortKey) {
        _TraceSort.op => a.key.name.compareTo(b.key.name),
        _TraceSort.count => a.count.compareTo(b.count),
        _TraceSort.avg => a.meanMicros.compareTo(b.meanMicros),
        _TraceSort.p95 => (a.histogram.percentile(0.95) ?? 0).compareTo(
          b.histogram.percentile(0.95) ?? 0,
        ),
        _TraceSort.total => a.totalMicros.compareTo(b.totalMicros),
        _TraceSort.intvl => (a.avgInterCallIntervalMicros ?? 0).compareTo(
          b.avgInterCallIntervalMicros ?? 0,
        ),
      };
      return _sortDir == RadarSortDirection.descending ? -cmp : cmp;
    });

    return base;
  }

  void _onSort(String key, RadarSortDirection dir) {
    final parsed = _TraceSort.values.firstWhere(
      (e) => e.name == key,
      orElse: () => _TraceSort.total,
    );
    setState(() {
      _sortKey = parsed;
      _sortDir = dir;
    });
  }

  // Shared horizontal scroll controller so the header and list rows
  // scroll in sync.
  final ScrollController _hScroll = ScrollController();

  @override
  void dispose() {
    _queryCtrl.dispose();
    _hScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    // Compute the op-column width from the actual available screen width.
    // This avoids using LayoutBuilder inside a SingleChildScrollView (which
    // provides infinite horizontal constraints and triggers an assertion).
    final screenW = MediaQuery.of(context).size.width;
    final opWidth = math.max(_kOpColWidth, screenW - _kNumColWidth * 5 - 24);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SearchAndChips(
          controller: _queryCtrl,
          filter: _filter,
          onQuery: (q) => setState(() => _query = q),
          onFilter: (f) => setState(() => _filter = f),
        ),
        // Sticky column header — scrolls horizontally with the rows.
        SingleChildScrollView(
          controller: _hScroll,
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          child: _ColumnHeader(
            activeSortKey: _sortKey.name,
            direction: _sortDir,
            onSort: _onSort,
            opWidth: opWidth,
          ),
        ),
        const _HeaderDivider(),
        if (rows.isEmpty)
          _EmptyState(query: _query, filter: _filter)
        else
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.only(top: 4, bottom: 8 + bottomPad),
              itemCount: rows.length,
              itemBuilder: (ctx, i) => SingleChildScrollView(
                controller: _hScroll,
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(),
                child: _TraceRow(
                  stats: rows[i],
                  isHot: _isHot(rows[i]),
                  opWidth: opWidth,
                  onTap: () => _openDetail(ctx, rows[i]),
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _openDetail(BuildContext context, SpanKeyStatsSnapshot stats) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => TraceDetailScreen(stats: stats)),
    );
  }
}

// ── Search bar + filter chips ─────────────────────────────────────────────────

class _SearchAndChips extends StatelessWidget {
  const _SearchAndChips({
    required this.controller,
    required this.filter,
    required this.onQuery,
    required this.onFilter,
  });

  final TextEditingController controller;
  final _TraceFilter filter;
  final ValueChanged<String> onQuery;
  final ValueChanged<_TraceFilter> onFilter;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RadarSearchField(
            controller: controller,
            hint: 'filter operation / category…',
            onChanged: onQuery,
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                RadarFilterChip(
                  label: 'all',
                  selected: filter == _TraceFilter.all,
                  onSelected: () => onFilter(_TraceFilter.all),
                ),
                const SizedBox(width: 6),
                RadarFilterChip(
                  label: 'hot / dup',
                  selected: filter == _TraceFilter.hot,
                  onSelected: () => onFilter(_TraceFilter.hot),
                ),
                const SizedBox(width: 6),
                RadarFilterChip(
                  label: 'errors',
                  selected: filter == _TraceFilter.errors,
                  onSelected: () => onFilter(_TraceFilter.errors),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── Column header row ─────────────────────────────────────────────────────────

/// Minimum width for the op-name column.
const double _kOpColWidth = 140.0;

/// Width of each numeric metric column.
const double _kNumColWidth = 70.0;

class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader({
    required this.activeSortKey,
    required this.direction,
    required this.onSort,
    required this.opWidth,
  });

  final String activeSortKey;
  final RadarSortDirection direction;
  final void Function(String key, RadarSortDirection dir) onSort;

  /// Pre-computed width for the op column (passed from the parent so we
  /// avoid a LayoutBuilder inside a horizontally-scrolling view, which
  /// receives infinite constraints and triggers an assertion).
  final double opWidth;

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
          SizedBox(
            width: opWidth,
            child: RadarSortHeader(
              label: 'op',
              sortKey: _TraceSort.op.name,
              activeSortKey: activeSortKey,
              direction: direction,
              onSort: onSort,
              textAlign: TextAlign.left,
            ),
          ),
          _NumHeader(
            label: 'count',
            sortKey: _TraceSort.count.name,
            activeSortKey: activeSortKey,
            direction: direction,
            onSort: onSort,
          ),
          _NumHeader(
            label: 'avg',
            sortKey: _TraceSort.avg.name,
            activeSortKey: activeSortKey,
            direction: direction,
            onSort: onSort,
          ),
          _NumHeader(
            label: 'p95',
            sortKey: _TraceSort.p95.name,
            activeSortKey: activeSortKey,
            direction: direction,
            onSort: onSort,
          ),
          _NumHeader(
            label: 'total',
            sortKey: _TraceSort.total.name,
            activeSortKey: activeSortKey,
            direction: direction,
            onSort: onSort,
          ),
          _NumHeader(
            label: 'intvl',
            sortKey: _TraceSort.intvl.name,
            activeSortKey: activeSortKey,
            direction: direction,
            onSort: onSort,
          ),
        ],
      ),
    );
  }
}

class _NumHeader extends StatelessWidget {
  const _NumHeader({
    required this.label,
    required this.sortKey,
    required this.activeSortKey,
    required this.direction,
    required this.onSort,
  });

  final String label;
  final String sortKey;
  final String activeSortKey;
  final RadarSortDirection direction;
  final void Function(String, RadarSortDirection) onSort;

  @override
  Widget build(BuildContext context) {
    // 70px gives enough room for the label + space + sort arrow (↓/↑)
    // without overflowing. RadarSortHeader's inner Row is not flex-wrapped
    // so we widen the column to accommodate the arrow glyph when active.
    return SizedBox(
      width: 70,
      child: RadarSortHeader(
        label: label,
        sortKey: sortKey,
        activeSortKey: activeSortKey,
        direction: direction,
        onSort: onSort,
      ),
    );
  }
}

class _HeaderDivider extends StatelessWidget {
  const _HeaderDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      thickness: 1,
      color: RadarColors.hairline08,
    );
  }
}

// ── Table row ─────────────────────────────────────────────────────────────────

class _TraceRow extends StatelessWidget {
  const _TraceRow({
    required this.stats,
    required this.isHot,
    required this.opWidth,
    required this.onTap,
  });

  final SpanKeyStatsSnapshot stats;
  final bool isHot;

  /// Pre-computed op column width from the parent (matches [_ColumnHeader]).
  final double opWidth;
  final VoidCallback onTap;

  String _fmtMicros(int micros) {
    if (micros == 0) return '—';
    if (micros < 1000) return '$microsμs';
    if (micros < 1000000) {
      return '${(micros / 1000).toStringAsFixed(1)}ms';
    }
    return '${(micros / 1000000).toStringAsFixed(2)}s';
  }

  String _fmtInterval(int? micros) {
    if (micros == null) return '—';
    return _fmtMicros(micros);
  }

  @override
  Widget build(BuildContext context) {
    final p95 = stats.histogram.percentile(0.95);
    final interval = stats.avgInterCallIntervalMicros;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: RadarColors.accentSubtle,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: RadarDensity.rowVPad,
          ),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: RadarColors.hairline04)),
          ),
          child: Row(
            children: [
              // op column: name + tags — fixed width matching the header
              SizedBox(
                width: opWidth,
                child: _OpCell(stats: stats, isHot: isHot),
              ),
              // count
              _NumCell(text: '${stats.count}', color: RadarColors.text80),
              // avg (bold white, prominent)
              _NumCell(
                text: _fmtMicros(stats.meanMicros),
                color: RadarColors.text100,
                bold: true,
              ),
              // p95
              _NumCell(
                text: p95 == null ? '—' : _fmtMicros(p95),
                color: RadarColors.text60,
              ),
              // total (cyan)
              _NumCell(
                text: _fmtMicros(stats.totalMicros),
                color: RadarColors.info,
                bold: true,
              ),
              // interval
              _NumCell(text: _fmtInterval(interval), color: RadarColors.text40),
            ],
          ),
        ),
      ),
    );
  }
}

class _OpCell extends StatelessWidget {
  const _OpCell({required this.stats, required this.isHot});

  final SpanKeyStatsSnapshot stats;
  final bool isHot;

  @override
  Widget build(BuildContext context) {
    final category = stats.key.category;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                stats.key.name,
                style: RadarTypography.monoBody,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            if (isHot) ...[
              const SizedBox(width: 5),
              const RadarTag(label: 'HOT', color: RadarColors.warning),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            if (category != null) ...[
              Text(
                category,
                style: RadarTypography.caption,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              if (stats.errorCount > 0) const SizedBox(width: 6),
            ],
            if (stats.errorCount > 0)
              Text(
                '${stats.errorCount} err',
                style: RadarTypography.monoLabel.copyWith(
                  color: RadarColors.critical,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _NumCell extends StatelessWidget {
  const _NumCell({required this.text, required this.color, this.bold = false});

  final String text;
  final Color color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 70,
      child: Text(
        text,
        style: RadarTypography.monoNumber.copyWith(
          color: color,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          fontSize: 11,
        ),
        textAlign: TextAlign.right,
        maxLines: 1,
        overflow: TextOverflow.clip,
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.query, required this.filter});

  final String query;
  final _TraceFilter filter;

  @override
  Widget build(BuildContext context) {
    final bool hasFilter = query.isNotEmpty || filter != _TraceFilter.all;
    return Expanded(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                hasFilter ? '∅' : '◌',
                style: RadarTypography.metricValue.copyWith(
                  color: RadarColors.text15,
                  fontSize: 40,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                hasFilter
                    ? 'No operations match the filter.'
                    : 'No spans recorded yet.\n'
                          'Use PerfRadar.trace() to instrument code.',
                textAlign: TextAlign.center,
                style: RadarTypography.caption,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Trace detail screen ───────────────────────────────────────────────────────

/// Full-screen detail for a single [SpanKeyStatsSnapshot].
///
/// Shows: HOT tag, call stats, 6-tile metric grid, latency
/// distribution histogram, slowest exemplar calls, and span tree.
class TraceDetailScreen extends StatelessWidget {
  /// Creates a [TraceDetailScreen] for [stats].
  const TraceDetailScreen({super.key, required this.stats});

  /// The aggregate stats for the operation being detailed.
  final SpanKeyStatsSnapshot stats;

  bool get _isHot {
    if (stats.count < _kHotCountMin) return false;
    final interval = stats.avgInterCallIntervalMicros;
    if (interval != null && interval < _kHotIntervalMaxMicros) return true;
    final rate = stats.callsPerSecond;
    if (rate != null && rate > _kHotRateMin) return true;
    return false;
  }

  String _fmtMicros(int? micros) {
    if (micros == null || micros == 0) return '—';
    if (micros < 1000) return '$microsμs';
    if (micros < 1000000) {
      return '${(micros / 1000).toStringAsFixed(1)}ms';
    }
    return '${(micros / 1000000).toStringAsFixed(2)}s';
  }

  String get _rateLabel {
    final r = stats.callsPerSecond;
    if (r == null) return '';
    return ' · ${r.toStringAsFixed(1)}/s';
  }

  @override
  Widget build(BuildContext context) {
    final category = stats.key.category;
    final hist = stats.histogram;
    final p99 = hist.percentile(0.99);
    final max = stats.maxMicros;
    final interval = stats.avgInterCallIntervalMicros;

    return Scaffold(
      backgroundColor: RadarColors.bgPhone,
      appBar: AppBar(
        backgroundColor: RadarColors.bgPanel,
        foregroundColor: RadarColors.text100,
        elevation: 0,
        title: Text(
          stats.key.name,
          style: RadarTypography.appBarTitle,
          overflow: TextOverflow.ellipsis,
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: RadarColors.hairline08, height: 1),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          12,
          16,
          12,
          16 + MediaQuery.of(context).padding.bottom,
        ),
        children: [
          // Category + HOT tag + calls · rate
          Row(
            children: [
              if (category != null) ...[
                Text(category, style: RadarTypography.caption),
                const SizedBox(width: 8),
              ],
              if (_isHot) ...[
                const RadarTag(label: 'HOT', color: RadarColors.warning),
                const SizedBox(width: 8),
              ],
              Text(
                '${stats.count} calls$_rateLabel',
                style: RadarTypography.caption,
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 6-tile metric grid
          _MetricGrid(
            tiles: [
              _TileData(
                label: 'avg',
                value: _fmtMicros(stats.meanMicros),
                color: RadarColors.text100,
              ),
              _TileData(
                label: 'p95',
                value: _fmtMicros(hist.percentile(0.95)),
                color: RadarColors.text80,
              ),
              _TileData(
                label: 'total',
                value: _fmtMicros(stats.totalMicros),
                color: RadarColors.info,
              ),
              _TileData(
                label: 'p99',
                value: _fmtMicros(p99),
                color: RadarColors.text80,
              ),
              _TileData(
                label: 'max',
                value: _fmtMicros(max == 0 ? null : max),
                color: RadarColors.warning,
              ),
              _TileData(
                label: 'intvl',
                value: _fmtMicros(interval),
                color: RadarColors.text60,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Latency distribution histogram
          _SectionLabel(label: 'LATENCY DISTRIBUTION'),
          const SizedBox(height: 8),
          _LatencyHistogramChart(snapshot: hist),
          const SizedBox(height: 16),

          // Slowest exemplar calls
          if (stats.outliers.isNotEmpty) ...[
            _SectionLabel(label: 'SLOWEST CALLS'),
            const SizedBox(height: 8),
            _SlowCalls(spans: stats.outliers, fmtMicros: _fmtMicros),
            const SizedBox(height: 16),
          ],

          // Span tree (parent/child for nested traces)
          if (stats.outliers.length > 1) ...[
            _SectionLabel(label: 'SPAN TIMELINE'),
            const SizedBox(height: 8),
            _SpanTimeline(spans: stats.outliers),
          ],
        ],
      ),
    );
  }
}

// ── 6-tile metric grid ────────────────────────────────────────────────────────

class _TileData {
  const _TileData({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.tiles});

  final List<_TileData> tiles;

  @override
  Widget build(BuildContext context) {
    // Use a Wrap-based grid instead of GridView so tiles can grow to
    // fit their content rather than clipping long values (e.g. "1.09s").
    return Column(
      children: [
        Row(
          children: [
            for (int i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: _MetricTile(
                  label: tiles[i].label,
                  value: tiles[i].value,
                  color: tiles[i].color,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (int i = 3; i < 6; i++) ...[
              if (i > 3) const SizedBox(width: 6),
              Expanded(
                child: _MetricTile(
                  label: tiles[i].label,
                  value: tiles[i].value,
                  color: tiles[i].color,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// A compact metric tile that keeps its value legible on narrow phones.
///
/// Uses [FittedBox] so long formatted values (e.g. "1.09s") scale down
/// rather than being clipped.
class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      decoration: BoxDecoration(
        color: RadarColors.bgSurface,
        borderRadius: RadarDensity.inputRadius,
        border: Border.all(
          color: RadarColors.hairline08,
          width: RadarDensity.hairline,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: RadarTypography.monoLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: RadarTypography.metricValue.copyWith(color: color),
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: RadarTypography.monoLabel.copyWith(letterSpacing: 0.8),
    );
  }
}

// ── Latency histogram chart ───────────────────────────────────────────────────

/// Bar chart visualization of the latency distribution histogram.
///
/// Samples the CDF at [_kDisplayBars] evenly-spaced quantiles and derives
/// per-band counts by differencing consecutive CDF rank values.  This
/// produces a meaningful distribution shape even when the histogram has
/// only a few populated buckets.
class _LatencyHistogramChart extends StatelessWidget {
  const _LatencyHistogramChart({required this.snapshot});

  final LatencyHistogramSnapshot snapshot;

  static const int _kDisplayBars = 16;

  @override
  Widget build(BuildContext context) {
    if (snapshot.count == 0) {
      return Text('No data.', style: RadarTypography.caption);
    }
    final bars = _buildBars();
    if (bars.isEmpty) {
      return Text('No data.', style: RadarTypography.caption);
    }
    final maxVal = bars.fold(0, (m, b) => math.max(m, b.count));

    return SizedBox(
      height: 60,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: bars.map((b) {
          final fraction = maxVal > 0 ? b.count / maxVal : 0.0;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Tooltip(
                message: '≤${b.label}: ${b.count}',
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Expanded(
                      child: FractionallySizedBox(
                        heightFactor: fraction.clamp(0.04, 1.0),
                        alignment: Alignment.bottomCenter,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: _barColor(b.isSlow),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Color _barColor(bool isSlow) {
    if (isSlow) return RadarColors.warning;
    return RadarColors.accent.withValues(alpha: 0.6);
  }

  List<_Bar> _buildBars() {
    if (snapshot.count == 0) return [];

    // Derive actual counts per band by differencing consecutive CDF ranks.
    // percentile(p) returns the upper-bound µs of the bucket that holds
    // the p-th percentile. We convert p to a rank (observation index) and
    // subtract to get the count in the band [pLow, pHigh).
    //
    // This correctly handles concentrated distributions (where many
    // observations land in the same bucket) — unlike the uniform-count
    // approach that gives every bar the same height.
    final step = 1.0 / _kDisplayBars;
    final bars = <_Bar>[];
    int prevRank = 0;
    int? prevBound;

    for (var i = 0; i < _kDisplayBars; i++) {
      final pHigh = (i + 1) * step;
      final vHigh = snapshot.percentile(pHigh) ?? 0;

      // Count in this band = difference in CDF ranks at pHigh vs pLow.
      final rank = (snapshot.count * pHigh).round().clamp(0, snapshot.count);
      final bandCount = rank - prevRank;
      prevRank = rank;

      // Merge consecutive bands sharing the same upper bound into one bar.
      if (prevBound == vHigh && bars.isNotEmpty) {
        bars.last.count += bandCount;
        continue;
      }
      prevBound = vHigh;

      bars.add(
        _Bar(
          label: _fmtBound(vHigh),
          count: bandCount,
          isSlow: vHigh > 16000, // >16ms = jank territory
        ),
      );
    }
    return bars;
  }

  String _fmtBound(int micros) {
    if (micros < 1000) return '$microsμs';
    if (micros < 1000000) return '${micros ~/ 1000}ms';
    return '${(micros / 1000000).toStringAsFixed(1)}s';
  }
}

class _Bar {
  _Bar({required this.label, required this.count, required this.isSlow});

  final String label;
  int count;
  final bool isSlow;
}

// ── Slowest exemplar calls ────────────────────────────────────────────────────

class _SlowCalls extends StatelessWidget {
  const _SlowCalls({required this.spans, required this.fmtMicros});

  final List<Span> spans;
  final String Function(int?) fmtMicros;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final span in spans)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: RadarColors.bgSurface,
                borderRadius: RadarDensity.rowRadius,
                border: Border.all(color: RadarColors.hairline08),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      span.name,
                      style: RadarTypography.monoBody.copyWith(
                        color: RadarColors.text80,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    fmtMicros(span.durationMicros),
                    style: RadarTypography.monoNumber.copyWith(
                      color: span.durationMicros > 16000
                          ? RadarColors.warning
                          : RadarColors.text100,
                    ),
                  ),
                  if (span.status == SpanStatus.error) ...[
                    const SizedBox(width: 6),
                    const RadarTag(label: 'ERR', color: RadarColors.critical),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ── Span timeline ─────────────────────────────────────────────────────────────

/// Proportional bar timeline of slowest exemplar spans on a shared clock.
class _SpanTimeline extends StatelessWidget {
  const _SpanTimeline({required this.spans});

  final List<Span> spans;

  @override
  Widget build(BuildContext context) {
    if (spans.isEmpty) return const SizedBox.shrink();

    // Align to the earliest start
    final minStart = spans.fold(
      spans.first.startMicros,
      (m, s) => math.min(m, s.startMicros),
    );
    final maxEnd = spans.fold(
      0,
      (m, s) => math.max(m, s.startMicros + s.durationMicros),
    );
    final totalWindow = (maxEnd - minStart).toDouble();
    if (totalWindow <= 0) return const SizedBox.shrink();

    return Column(
      children: [
        for (final span in spans)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: _SpanBar(
              span: span,
              minStart: minStart,
              window: totalWindow,
            ),
          ),
      ],
    );
  }
}

class _SpanBar extends StatelessWidget {
  const _SpanBar({
    required this.span,
    required this.minStart,
    required this.window,
  });

  final Span span;
  final int minStart;
  final double window;

  @override
  Widget build(BuildContext context) {
    final offsetFraction = (span.startMicros - minStart) / window;
    final widthFraction = span.durationMicros / window;
    final isSlow = span.durationMicros > 16000;

    return SizedBox(
      height: 22,
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          final totalWidth = constraints.maxWidth;
          final left = (offsetFraction * totalWidth).clamp(0.0, totalWidth);
          final barWidth = (widthFraction * totalWidth).clamp(
            6.0,
            totalWidth - left,
          );

          return Stack(
            children: [
              // Row track (dark, not full-surface gray)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: RadarColors.bgSurface.withValues(alpha: 0.5),
                    borderRadius: const BorderRadius.all(Radius.circular(3)),
                  ),
                ),
              ),
              // Proportional bar positioned by start time
              Positioned(
                left: left,
                width: barWidth,
                top: 2,
                bottom: 2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: isSlow
                        ? RadarColors.warning.withValues(alpha: 0.7)
                        : RadarColors.accent.withValues(alpha: 0.5),
                    borderRadius: const BorderRadius.all(Radius.circular(3)),
                  ),
                ),
              ),
              // Label inside the bar (clipped to bar bounds when possible)
              Positioned(
                left: left + 4,
                width: barWidth > 40 ? barWidth - 8 : barWidth,
                top: 0,
                bottom: 0,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    span.name,
                    style: RadarTypography.monoLabel.copyWith(
                      color: isSlow ? RadarColors.bgPhone : RadarColors.text80,
                      fontSize: 9,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
