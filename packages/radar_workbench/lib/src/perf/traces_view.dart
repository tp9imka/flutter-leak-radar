import 'package:flutter/material.dart';
import 'package:radar_ui/radar_ui.dart';

import 'perf_data_controller.dart';
import 'perf_snapshot_dto.dart';
import 'perf_state_views.dart';

/// Quick-filter modes for the traces table.
enum _TraceFilter { all, hot, errors }

/// Performance ▸ Traces — full 11-column sortable, searchable traces table.
///
/// Columns: operation · count · avg · p50 · p95 · p99 · max · total ·
///           intvl · rate · err
///
/// Renders only data that the JSON carries; null fields become "—".
/// Shows [PerfRadarNotDetectedView] when the extension is absent.
class TracesView extends StatefulWidget {
  const TracesView({super.key, required this.controller});

  final PerfDataController controller;

  @override
  State<TracesView> createState() => _TracesViewState();
}

class _TracesViewState extends State<TracesView> {
  String _sortKey = 'count';
  RadarSortDirection _sortDir = RadarSortDirection.descending;
  String _query = '';
  _TraceFilter _filter = _TraceFilter.all;
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<TraceKeyDto> _filtered(List<TraceKeyDto> keys) {
    var out = keys.where((k) {
      final q = _query.toLowerCase();
      if (q.isNotEmpty) {
        if (!k.name.toLowerCase().contains(q) &&
            !(k.category?.toLowerCase().contains(q) ?? false)) {
          return false;
        }
      }
      return switch (_filter) {
        _TraceFilter.all => true,
        _TraceFilter.hot => k.isHot,
        _TraceFilter.errors => k.errorCount > 0,
      };
    }).toList();

    out.sort((a, b) {
      int cmp;
      switch (_sortKey) {
        case 'operation':
          cmp = a.name.compareTo(b.name);
        case 'count':
          cmp = a.count.compareTo(b.count);
        case 'avg':
          cmp = a.meanMicros.compareTo(b.meanMicros);
        case 'p50':
          cmp = (a.p50 ?? -1).compareTo(b.p50 ?? -1);
        case 'p95':
          cmp = (a.p95 ?? -1).compareTo(b.p95 ?? -1);
        case 'p99':
          cmp = (a.p99 ?? -1).compareTo(b.p99 ?? -1);
        case 'max':
          cmp = a.maxMicros.compareTo(b.maxMicros);
        case 'total':
          cmp = a.totalMicros.compareTo(b.totalMicros);
        case 'intvl':
          cmp = (a.avgInterCallIntervalMicros ?? -1).compareTo(
            b.avgInterCallIntervalMicros ?? -1,
          );
        case 'rate':
          cmp = (a.callsPerSecond ?? -1).compareTo(b.callsPerSecond ?? -1);
        case 'err':
          cmp = a.errorCount.compareTo(b.errorCount);
        default:
          cmp = 0;
      }
      return _sortDir == RadarSortDirection.descending ? -cmp : cmp;
    });
    return out;
  }

  void _onSort(String key, RadarSortDirection dir) => setState(() {
    _sortKey = key;
    _sortDir = dir;
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final state = widget.controller.loadState;
        return switch (state) {
          PerfLoadState.idle => _buildIdle(),
          PerfLoadState.loading => const PerfLoadingView(),
          PerfLoadState.notAvailable => const PerfRadarNotDetectedView(),
          PerfLoadState.error => PerfErrorView(
            message: widget.controller.errorMessage ?? 'Unknown error',
            onRetry: widget.controller.refresh,
          ),
          PerfLoadState.loaded => _buildLoaded(
            widget.controller.snapshot!.traces,
          ),
        };
      },
    );
  }

  Widget _buildIdle() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Press Refresh to load performance data.',
            style: RadarTypography.body.copyWith(color: RadarColors.text40),
          ),
          const SizedBox(height: 12),
          PerfRefreshButton(onRefresh: widget.controller.refresh),
        ],
      ),
    );
  }

  Widget _buildLoaded(TracesDto traces) {
    final rows = _filtered(traces.keys);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TracesToolbar(
          query: _query,
          searchCtrl: _searchCtrl,
          filter: _filter,
          onQueryChanged: (q) => setState(() => _query = q),
          onFilterChanged: (f) => setState(() => _filter = f),
          onRefresh: widget.controller.refresh,
        ),
        _TracesHeaderRow(sortKey: _sortKey, sortDir: _sortDir, onSort: _onSort),
        Expanded(
          child: rows.isEmpty
              ? PerfEmptyFilterView(query: _query)
              : ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, i) =>
                      _TraceRow(key: ValueKey(rows[i].name), dto: rows[i]),
                ),
        ),
      ],
    );
  }
}

// ── Toolbar ───────────────────────────────────────────────────────────────────

class _TracesToolbar extends StatelessWidget {
  const _TracesToolbar({
    required this.query,
    required this.searchCtrl,
    required this.filter,
    required this.onQueryChanged,
    required this.onFilterChanged,
    required this.onRefresh,
  });

  final String query;
  final TextEditingController searchCtrl;
  final _TraceFilter filter;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<_TraceFilter> onFilterChanged;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Text(
              'Traces',
              style: RadarTypography.monoBody.copyWith(
                color: RadarColors.text80,
              ),
            ),
            const SizedBox(width: 12),
            RadarFilterChip(
              label: 'all',
              selected: filter == _TraceFilter.all,
              onSelected: () => onFilterChanged(_TraceFilter.all),
            ),
            const SizedBox(width: 6),
            RadarFilterChip(
              label: 'hot / dup',
              selected: filter == _TraceFilter.hot,
              onSelected: () => onFilterChanged(_TraceFilter.hot),
            ),
            const SizedBox(width: 6),
            RadarFilterChip(
              label: 'errors',
              selected: filter == _TraceFilter.errors,
              onSelected: () => onFilterChanged(_TraceFilter.errors),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 32,
                child: RadarSearchField(
                  controller: searchCtrl,
                  hint: 'filter operation / category',
                  onChanged: onQueryChanged,
                ),
              ),
            ),
            const SizedBox(width: 8),
            PerfRefreshButton(onRefresh: onRefresh),
          ],
        ),
      ),
    );
  }
}

// ── Header row ────────────────────────────────────────────────────────────────

class _TracesHeaderRow extends StatelessWidget {
  const _TracesHeaderRow({
    required this.sortKey,
    required this.sortDir,
    required this.onSort,
  });

  final String sortKey;
  final RadarSortDirection sortDir;
  final void Function(String, RadarSortDirection) onSort;

  RadarSortHeader _hdr(String key, String label, {TextAlign? align}) =>
      RadarSortHeader(
        label: label,
        sortKey: key,
        activeSortKey: sortKey,
        direction: sortDir,
        onSort: onSort,
        textAlign: align ?? TextAlign.right,
      );

  @override
  Widget build(BuildContext context) {
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
        padding: const EdgeInsets.symmetric(
          horizontal: RadarDensity.rowHPad,
          vertical: 6,
        ),
        child: Row(
          children: [
            // active dot placeholder
            const SizedBox(width: 16),
            const SizedBox(width: 8),
            Expanded(
              flex: 28,
              child: _hdr('operation', 'operation', align: TextAlign.left),
            ),
            _NumHdr('count', 'count', sortKey, sortDir, onSort),
            _NumHdr('avg', 'avg', sortKey, sortDir, onSort),
            _NumHdr('p50', 'p50', sortKey, sortDir, onSort),
            _NumHdr('p95', 'p95', sortKey, sortDir, onSort),
            _NumHdr('p99', 'p99', sortKey, sortDir, onSort),
            _NumHdr('max', 'max', sortKey, sortDir, onSort),
            _NumHdr('total', 'total', sortKey, sortDir, onSort),
            _NumHdr('intvl', 'intvl', sortKey, sortDir, onSort),
            _NumHdr('rate', 'rate', sortKey, sortDir, onSort),
            _NumHdr('err', 'err', sortKey, sortDir, onSort),
          ],
        ),
      ),
    );
  }
}

class _NumHdr extends StatelessWidget {
  const _NumHdr(
    this.sortKey,
    this.label,
    this.activeSortKey,
    this.dir,
    this.onSort, {
    int flex = 9,
  }) : _flex = flex;

  final String sortKey;
  final String label;
  final String activeSortKey;
  final RadarSortDirection dir;
  final void Function(String, RadarSortDirection) onSort;
  final int _flex;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: _flex,
      child: RadarSortHeader(
        label: label,
        sortKey: sortKey,
        activeSortKey: activeSortKey,
        direction: dir,
        onSort: onSort,
      ),
    );
  }
}

// ── Row ───────────────────────────────────────────────────────────────────────

class _TraceRow extends StatelessWidget {
  const _TraceRow({super.key, required this.dto});

  final TraceKeyDto dto;

  static String _us(int? v) => v == null ? '—' : _formatMicros(v);
  static String _rate(double? v) =>
      v == null ? '—' : '${v.toStringAsFixed(1)}/s';
  static String _interval(int? v) => v == null ? '—' : _formatMicros(v);

  static String _formatMicros(int us) {
    if (us < 1000) return '$usµs';
    if (us < 1000000) return '${(us / 1000).toStringAsFixed(1)}ms';
    return '${(us / 1000000).toStringAsFixed(2)}s';
  }

  @override
  Widget build(BuildContext context) {
    final hasError = dto.errorCount > 0;
    final activeNow = dto.lastStartMicros > dto.firstStartMicros;

    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: RadarColors.hairline04,
            width: RadarDensity.hairline,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: RadarDensity.rowHPad,
          vertical: RadarDensity.rowVPad,
        ),
        child: Row(
          children: [
            // Active pulse dot
            SizedBox(
              width: 16,
              child: activeNow
                  ? const RadarLivePulseDot(size: 6)
                  : const SizedBox(width: 6),
            ),
            const SizedBox(width: 8),
            // Operation + category + HOT tag
            Expanded(
              flex: 28,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      dto.name,
                      style: RadarTypography.monoBody.copyWith(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (dto.category != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      dto.category!,
                      style: RadarTypography.monoLabel.copyWith(
                        color: RadarColors.text25,
                        fontSize: 10,
                      ),
                    ),
                  ],
                  if (dto.isHot) ...[
                    const SizedBox(width: 6),
                    const RadarTag(label: 'HOT', color: RadarColors.warning),
                  ],
                ],
              ),
            ),
            _Num(dto.count.toString()),
            _Num(_us(dto.meanMicros), bold: true),
            _Num(_us(dto.p50)),
            _Num(_us(dto.p95)),
            _Num(_us(dto.p99)),
            _Num(_us(dto.maxMicros)),
            _Num(_us(dto.totalMicros), color: RadarColors.info),
            _Num(_interval(dto.avgInterCallIntervalMicros)),
            _Num(_rate(dto.callsPerSecond)),
            _Num(
              dto.errorCount == 0 ? '—' : dto.errorCount.toString(),
              color: hasError ? RadarColors.critical : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _Num extends StatelessWidget {
  const _Num(this.text, {this.bold = false, this.color});

  final String text;
  final bool bold;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: 9,
      child: Text(
        text,
        textAlign: TextAlign.right,
        style: RadarTypography.monoNumber.copyWith(
          fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
          color:
              color ?? (text == '—' ? RadarColors.text15 : RadarColors.text80),
          fontSize: 11.5,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
