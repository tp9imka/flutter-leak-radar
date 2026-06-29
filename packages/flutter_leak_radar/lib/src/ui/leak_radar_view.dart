// lib/src/ui/leak_radar_view.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:radar_ui/radar_ui.dart';

import '../engine/vm_service_status.dart';
import '../leak_radar.dart';
import '../model/leak_finding.dart';
import '../model/leak_kind.dart';
import '../model/leak_report.dart';
import 'finding_detail_screen.dart';
import 'leak_kind_label.dart';
import 'theme/theme.dart';

/// Body-only view of the Leak Radar inspector.
///
/// Renders the summary row, search field, sort row, kind-filter chips, and
/// findings list without any [Scaffold], [AppBar], or [BottomNavigationBar].
/// Designed to be embedded in a containing [Scaffold] (e.g. [LeakRadarScreen]
/// or [RadarScreen]).
///
/// Listens to [LeakRadar.reports] and refreshes automatically.
class LeakRadarView extends StatefulWidget {
  const LeakRadarView({super.key});

  @override
  State<LeakRadarView> createState() => LeakRadarViewState();
}

// ── Kind quick-filter ─────────────────────────────────────────────────────────

enum _KindFilter { all, notDisposed, notGced, retained, growth }

// ── Sort key ──────────────────────────────────────────────────────────────────

enum _SortKey { severity, growth, live, name }

// ── State ────────────────────────────────────────────────────────────────────

/// State for [LeakRadarView]. Public so [LeakRadarScreen] can read the
/// current [report] for its bottom bar without duplicating subscription logic.
class LeakRadarViewState extends State<LeakRadarView> {
  LeakReport? _report;
  _KindFilter _kindFilter = _KindFilter.all;
  _SortKey _sortKey = _SortKey.severity;
  RadarSortDirection _sortDir = RadarSortDirection.descending;
  String _searchQuery = '';
  final Set<String> _dismissed = {};
  StreamSubscription<LeakReport>? _sub;
  final TextEditingController _searchCtrl = TextEditingController();

  /// The most recent [LeakReport] received from [LeakRadar], or null
  /// before any scan.
  LeakReport? get report => _report;

  @override
  void initState() {
    super.initState();
    _report = LeakRadar.latest;
    _sub = LeakRadar.reports.listen((r) {
      if (mounted) setState(() => _report = r);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Filtered and sorted findings applying kind filter, search, and sort order,
  /// excluding view-dismissed entries.
  List<LeakFinding> get filtered {
    final findings = _report?.findings ?? const <LeakFinding>[];
    var base = findings
        .where((f) => !_dismissed.contains(f.className))
        .toList();

    // Kind filter
    base = switch (_kindFilter) {
      _KindFilter.all => base,
      _KindFilter.notDisposed =>
        base.where((f) => f.kind == LeakKind.notDisposed).toList(),
      _KindFilter.notGced =>
        base.where((f) => f.kind == LeakKind.notGced).toList(),
      _KindFilter.retained =>
        base.where((f) => f.kind == LeakKind.retainedByNonLiveRoot).toList(),
      _KindFilter.growth =>
        base.where((f) => f.kind == LeakKind.growth).toList(),
    };

    // Search filter
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      base = base
          .where(
            (f) =>
                f.className.toLowerCase().contains(q) ||
                (f.library ?? '').toLowerCase().contains(q) ||
                f.kind.label.toLowerCase().contains(q),
          )
          .toList();
    }

    // Sort
    int sevOrdinal(LeakSeverity s) => switch (s) {
      LeakSeverity.critical => 2,
      LeakSeverity.warning => 1,
      LeakSeverity.info => 0,
    };

    base.sort((a, b) {
      final cmp = switch (_sortKey) {
        _SortKey.severity => sevOrdinal(
          a.severity,
        ).compareTo(sevOrdinal(b.severity)),
        _SortKey.growth => a.growth.compareTo(b.growth),
        _SortKey.live => a.liveCount.compareTo(b.liveCount),
        _SortKey.name => a.className.compareTo(b.className),
      };
      return _sortDir == RadarSortDirection.descending ? -cmp : cmp;
    });

    return base;
  }

  /// Clears the set of view-dismissed class names, causing all findings to
  /// reappear.
  void clearDismissed() => setState(() => _dismissed.clear());

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final findings = report?.findings ?? const <LeakFinding>[];
    final vmStatus = LeakRadar.vmServiceStatus;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SummaryRow(report: report, vmStatus: vmStatus),
        if (vmStatus != null && vmStatus is! VmConnected)
          _VmDegradedBanner(status: vmStatus),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: RadarSearchField(
            controller: _searchCtrl,
            hint: 'filter class / library / kind…',
            onChanged: (q) => setState(() => _searchQuery = q),
          ),
        ),
        _SortRow(
          sortKey: _sortKey,
          sortDir: _sortDir,
          onSort: (key, dir) => setState(() {
            _sortKey = key;
            _sortDir = dir;
          }),
        ),
        _KindFilterRow(
          active: _kindFilter,
          onSelected: (f) => setState(() => _kindFilter = f),
        ),
        Expanded(
          child: findings.isEmpty
              ? _EmptyState(status: report?.status ?? LeakRadar.status)
              : filtered.isEmpty
              ? _SearchEmptyState(query: _searchQuery)
              : ListView.builder(
                  padding: EdgeInsets.only(
                    bottom: 8 + MediaQuery.of(context).padding.bottom,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) => _FindingRow(finding: filtered[i]),
                ),
        ),
      ],
    );
  }
}

// ── Summary row ───────────────────────────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.report, required this.vmStatus});

  final LeakReport? report;
  final VmServiceStatus? vmStatus;

  @override
  Widget build(BuildContext context) {
    final findings = report?.findings ?? const <LeakFinding>[];
    final criticalCount = findings
        .where((f) => f.severity == LeakSeverity.critical)
        .length;
    final warningCount = findings
        .where((f) => f.severity == LeakSeverity.warning)
        .length;
    final infoCount = findings
        .where((f) => f.severity == LeakSeverity.info)
        .length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [
                if (criticalCount > 0)
                  _SevCount(LeakSeverity.critical, criticalCount, 'critical'),
                if (warningCount > 0)
                  _SevCount(LeakSeverity.warning, warningCount, 'warning'),
                if (infoCount > 0)
                  _SevCount(LeakSeverity.info, infoCount, 'info'),
                if (findings.isEmpty)
                  Text(
                    'No leaks',
                    style: radarMonoStyle(
                      fontSize: 11,
                      color: RadarColors.text40,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (vmStatus != null) _VmChip(status: vmStatus!),
        ],
      ),
    );
  }
}

class _SevCount extends StatelessWidget {
  const _SevCount(this.severity, this.count, this.label);

  final LeakSeverity severity;
  final int count;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = severityTokens(severity).text;
    return Text(
      '● $count $label',
      style: radarMonoStyle(fontSize: 11.5, color: color),
    );
  }
}

// ── VM connection chip ────────────────────────────────────────────────────────

class _VmChip extends StatefulWidget {
  const _VmChip({required this.status});

  final VmServiceStatus status;

  @override
  State<_VmChip> createState() => _VmChipState();
}

class _VmChipState extends State<_VmChip> {
  bool _busy = false;

  Future<void> _reconnect() async {
    if (_busy) return;
    setState(() => _busy = true);
    await LeakRadar.reconnectVmService();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final connected = widget.status is VmConnected;
    final color = connected ? RadarColors.accent : RadarColors.warning;

    return GestureDetector(
      onTap: _busy ? null : _reconnect,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_busy)
                SizedBox(
                  width: 8,
                  height: 8,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.4,
                    color: color,
                  ),
                )
              else if (connected)
                RadarLivePulseDot(size: 7, color: color)
              else
                Icon(Icons.warning_amber_rounded, size: 12, color: color),
              const SizedBox(width: 5),
              Text(
                connected ? 'VM' : 'VM off',
                style: radarMonoStyle(fontSize: 11, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Degraded VM banner ────────────────────────────────────────────────────────

class _VmDegradedBanner extends StatelessWidget {
  const _VmDegradedBanner({required this.status});

  final VmServiceStatus status;

  String get _reason => switch (status) {
    VmConnected() => '',
    VmNoServiceUri() =>
      'No VM service URI available '
          '(profile/release build or service not started).',
    VmSocketError(:final message) => 'VM service refused: $message.',
    VmDisabled() => 'VM service disabled.',
    VmUnknown(:final message) =>
      'VM service status unknown'
          '${message != null ? ": $message" : ""}.',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: RadarColors.warning.withValues(alpha: 0.08),
        border: Border.all(color: RadarColors.warning.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 14,
            color: RadarColors.warning,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _reason,
                  style: radarMonoStyle(
                    fontSize: 11,
                    color: RadarColors.warning,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Fell back to on-device heap snapshot.',
                  style: radarMonoStyle(
                    fontSize: 10.5,
                    color: RadarColors.text40,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sort row ──────────────────────────────────────────────────────────────────

class _SortRow extends StatelessWidget {
  const _SortRow({
    required this.sortKey,
    required this.sortDir,
    required this.onSort,
  });

  final _SortKey sortKey;
  final RadarSortDirection sortDir;
  final void Function(_SortKey key, RadarSortDirection dir) onSort;

  String _keyId(_SortKey k) => k.name;

  void _handle(String key, RadarSortDirection dir) {
    final k = _SortKey.values.firstWhere((v) => v.name == key);
    onSort(k, dir);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        children: [
          Text(
            'sort:',
            style: radarMonoStyle(fontSize: 10.5, color: RadarColors.text25),
          ),
          const SizedBox(width: 8),
          for (final entry in [
            (_SortKey.severity, 'severity'),
            (_SortKey.growth, 'growth'),
            (_SortKey.live, 'live'),
            (_SortKey.name, 'name'),
          ]) ...[
            RadarSortHeader(
              label: entry.$2,
              sortKey: _keyId(entry.$1),
              activeSortKey: _keyId(sortKey),
              direction: sortDir,
              onSort: _handle,
              textAlign: TextAlign.left,
            ),
            const SizedBox(width: 12),
          ],
        ],
      ),
    );
  }
}

// ── Kind filter chips ─────────────────────────────────────────────────────────

class _KindFilterRow extends StatelessWidget {
  const _KindFilterRow({required this.active, required this.onSelected});

  final _KindFilter active;
  final ValueChanged<_KindFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          for (final entry in [
            (_KindFilter.all, 'all'),
            (_KindFilter.notDisposed, 'not disposed'),
            (_KindFilter.notGced, "not gc'd"),
            (_KindFilter.retained, 'retained'),
            (_KindFilter.growth, 'growth'),
          ]) ...[
            RadarFilterChip(
              label: entry.$2,
              selected: active == entry.$1,
              onSelected: () => onSelected(entry.$1),
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

// ── Finding row ───────────────────────────────────────────────────────────────

class _FindingRow extends StatelessWidget {
  const _FindingRow({required this.finding});

  final LeakFinding finding;

  String _kindTag(LeakKind k) => switch (k) {
    LeakKind.notDisposed => 'NOT DISPOSED',
    LeakKind.notGced => "NOT GC'D",
    LeakKind.gcedLate => "GC'D LATE",
    LeakKind.retainedByNonLiveRoot => 'RETAINED',
    LeakKind.growth => 'GROWTH',
  };

  RadarSeverity _radarSeverity(LeakSeverity s) => switch (s) {
    LeakSeverity.critical => RadarSeverity.critical,
    LeakSeverity.warning => RadarSeverity.warning,
    LeakSeverity.info => RadarSeverity.info,
  };

  @override
  Widget build(BuildContext context) {
    final isCritical = finding.severity == LeakSeverity.critical;
    final tokens = severityTokens(finding.severity);
    final radarSev = _radarSeverity(finding.severity);

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => FindingDetailScreen(finding: finding),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        decoration: BoxDecoration(
          color: isCritical ? tokens.rowBg : RadarColors.rowBgDefault,
          border: Border.all(
            color: isCritical ? tokens.rowBorder : RadarColors.hairline08,
          ),
          borderRadius: RadarDensity.rowRadius,
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 4px severity bar
              Container(
                width: RadarDensity.severityBarWidth,
                decoration: BoxDecoration(
                  color: tokens.text,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(11),
                    bottomLeft: Radius.circular(11),
                  ),
                ),
              ),
              // Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Line 1: class name · growth delta · sparkline
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              finding.className,
                              overflow: TextOverflow.ellipsis,
                              style: RadarTypography.monoBody.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (finding.growth > 0) ...[
                            const SizedBox(width: 6),
                            Text(
                              '+${finding.growth}',
                              style: RadarTypography.monoNumber.copyWith(
                                color: tokens.text,
                              ),
                            ),
                          ],
                          if (finding.series.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            RadarSparkline(
                              series: finding.series,
                              color: tokens.text,
                              width: RadarDensity.sparklineWidth,
                              height: RadarDensity.sparklineHeight,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Line 2: kind tag · "{n} live" · library
                      Row(
                        children: [
                          RadarTag(
                            label: _kindTag(finding.kind),
                            severity: radarSev,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${finding.liveCount} live',
                            style: radarMonoStyle(
                              fontSize: 11,
                              color: RadarColors.text40,
                            ),
                          ),
                          if (finding.library != null) ...[
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                finding.library!,
                                overflow: TextOverflow.ellipsis,
                                style: radarMonoStyle(
                                  fontSize: 10.5,
                                  color: RadarColors.text25,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              // Chevron
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    '›',
                    style: radarMonoStyle(
                      fontSize: 16,
                      color: RadarColors.text40,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Empty states ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.status});

  final LeakRadarStatus status;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const RadarGlyph(size: 64),
        const SizedBox(height: 16),
        Text('No leaks detected', style: LeakRadarText.title),
        const SizedBox(height: 8),
        Text('status: ${status.name}', style: LeakRadarText.label),
      ],
    ),
  );
}

class _SearchEmptyState extends StatelessWidget {
  const _SearchEmptyState({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.search_off, size: 40, color: RadarColors.text25),
        const SizedBox(height: 12),
        Text(
          'No findings match "$query"',
          style: radarMonoStyle(fontSize: 13, color: RadarColors.text40),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}
