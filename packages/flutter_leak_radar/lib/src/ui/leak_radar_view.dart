// lib/src/ui/leak_radar_view.dart
import 'dart:async';

import 'package:flutter/material.dart';

import '../engine/vm_service_status.dart';
import '../model/leak_finding.dart';
import '../model/leak_kind.dart';
import '../model/leak_report.dart';
import '../leak_radar.dart';
import 'finding_detail_screen.dart';
import 'growth_sparkline.dart';
import 'leak_kind_label.dart';
import 'theme/theme.dart';

/// Body-only view of the Leak Radar inspector.
///
/// Renders the summary row, filter chips, and findings list without any
/// [Scaffold], [AppBar], or [BottomNavigationBar]. Designed to be embedded
/// in a containing [Scaffold] (e.g. [LeakRadarScreen] or [RadarScreen]).
///
/// Listens to [LeakRadar.reports] and refreshes automatically.
class LeakRadarView extends StatefulWidget {
  const LeakRadarView({super.key});

  @override
  State<LeakRadarView> createState() => LeakRadarViewState();
}

// ── Filter chip enum ──────────────────────────────────────────────────────────

enum LeakFilter { all, critical, growing, tracked }

// ── State ────────────────────────────────────────────────────────────────────

/// State for [LeakRadarView]. Public so [LeakRadarScreen] can read the
/// current [report] for its bottom bar without duplicating subscription logic.
class LeakRadarViewState extends State<LeakRadarView> {
  LeakReport? _report;
  LeakFilter _activeFilter = LeakFilter.all;
  final Set<String> _dismissed = {};
  StreamSubscription<LeakReport>? _sub;

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
    super.dispose();
  }

  /// Filtered findings based on the active filter chip, excluding dismissed
  /// entries.
  List<LeakFinding> get filtered {
    final findings = _report?.findings ?? const <LeakFinding>[];
    final base = switch (_activeFilter) {
      LeakFilter.all => findings,
      LeakFilter.critical =>
        findings.where((f) => f.severity == LeakSeverity.critical).toList(),
      LeakFilter.growing => findings.where((f) => f.growth > 0).toList(),
      LeakFilter.tracked => findings.where((f) => f.tag != null).toList(),
    };
    return base.where((f) => !_dismissed.contains(f.className)).toList();
  }

  /// Clears the set of view-dismissed class names, causing all findings to
  /// reappear.
  void clearDismissed() => setState(() => _dismissed.clear());

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final findings = report?.findings ?? const <LeakFinding>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SummaryRow(report: report),
        _FilterRow(
          active: _activeFilter,
          total: findings.length,
          onSelected: (f) => setState(() => _activeFilter = f),
        ),
        Expanded(
          child: findings.isEmpty
              ? _EmptyState(status: report?.status ?? LeakRadar.status)
              : filtered.isEmpty
              ? Center(
                  child: Text(
                    'No findings match this filter',
                    style: LeakRadarText.label,
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final f = filtered[i];
                    return Dismissible(
                      key: ValueKey(
                        '${f.className}|${f.kind.name}|${f.tag ?? ''}',
                      ),
                      direction: DismissDirection.endToStart,
                      onDismissed: (_) =>
                          setState(() => _dismissed.add(f.className)),
                      background: const SizedBox.shrink(),
                      secondaryBackground: const _DismissBackground(),
                      child: _FindingRow(finding: f),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ── Summary row ───────────────────────────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.report});

  final LeakReport? report;

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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [
                if (criticalCount > 0)
                  _SeverityCount(
                    LeakSeverity.critical,
                    criticalCount,
                    'critical',
                  ),
                if (warningCount > 0)
                  _SeverityCount(LeakSeverity.warning, warningCount, 'warning'),
                if (infoCount > 0)
                  _SeverityCount(LeakSeverity.info, infoCount, 'info'),
                if (findings.isEmpty)
                  Text('No leaks', style: LeakRadarText.label),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const _VmConnectionChip(),
          const SizedBox(width: 8),
          const _GcButton(),
        ],
      ),
    );
  }
}

/// A single colored severity tally, e.g. `● 10 critical`.
class _SeverityCount extends StatelessWidget {
  const _SeverityCount(this.severity, this.count, this.label);

  final LeakSeverity severity;
  final int count;
  final String label;

  @override
  Widget build(BuildContext context) => Text(
    '● $count $label',
    style: monoFont(fontSize: 11.5, color: severityTokens(severity).text),
  );
}

/// "Force GC and rescan" pill — collects garbage so counts reflect live objects,
/// then rescans. Self-contained: the screen rebuilds via the report stream.
class _GcButton extends StatefulWidget {
  const _GcButton();

  @override
  State<_GcButton> createState() => _GcButtonState();
}

class _GcButtonState extends State<_GcButton> {
  bool _busy = false;

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    await LeakRadar.forceGcAndScan();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    const color = LeakRadarColors.accent;
    return Tooltip(
      message: 'Force GC and rescan',
      child: InkWell(
        onTap: _busy ? null : _run,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.45)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_busy)
                const SizedBox(
                  width: 9,
                  height: 9,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.4,
                    color: color,
                  ),
                )
              else
                const Icon(Icons.refresh, size: 12, color: color),
              const SizedBox(width: 5),
              Text('GC', style: monoFont(fontSize: 11, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

/// VM-service connection indicator + manual reconnect. A green dot means the
/// per-scan allocation-profile (growth) source is live; amber means growth is
/// running off the on-device snapshot histogram instead. Tap to reconnect.
/// Hidden when the probe is not VM-backed (release / unsupported).
class _VmConnectionChip extends StatefulWidget {
  const _VmConnectionChip();

  @override
  State<_VmConnectionChip> createState() => _VmConnectionChipState();
}

class _VmConnectionChipState extends State<_VmConnectionChip> {
  bool _busy = false;

  Future<void> _reconnect() async {
    if (_busy) return;
    setState(() => _busy = true);
    await LeakRadar.reconnectVmService();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final status = LeakRadar.vmServiceStatus;
    if (status == null) return const SizedBox.shrink();
    final connected = status is VmConnected;

    final tooltipMsg = switch (status) {
      VmConnected() =>
        'VM service connected — per-scan growth profile is live.\n'
            'Tap to reconnect.',
      VmNoServiceUri() =>
        'VM service URI unavailable (profile/release build or service not '
            'started).\nGrowth uses on-device snapshot histogram instead.\n'
            'Tap to retry.',
      VmSocketError(:final message) =>
        'VM service refused (DDS contention or socket error: $message).\n'
            'Growth uses on-device snapshot histogram instead.\nTap to retry.',
      VmDisabled() =>
        'VM service disabled — growth uses on-device snapshot histogram.',
      VmUnknown(:final message) =>
        'VM service status unknown'
            '${message != null ? ': $message' : ''}.\n'
            'Growth uses on-device snapshot histogram instead.\nTap to retry.',
    };

    final color = connected
        ? severityTokens(LeakSeverity.info).text
        : severityTokens(LeakSeverity.warning).text;

    return Tooltip(
      message: tooltipMsg,
      child: InkWell(
        onTap: _reconnect,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_busy)
                SizedBox(
                  width: 9,
                  height: 9,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.4,
                    color: color,
                  ),
                )
              else
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              const SizedBox(width: 6),
              Text(
                connected ? 'VM' : 'VM off',
                style: monoFont(fontSize: 11, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Filter chips ──────────────────────────────────────────────────────────────

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.active,
    required this.total,
    required this.onSelected,
  });

  final LeakFilter active;
  final int total;
  final ValueChanged<LeakFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _Chip(
            label: 'All·$total',
            active: active == LeakFilter.all,
            onTap: () => onSelected(LeakFilter.all),
          ),
          _Chip(
            label: 'Critical',
            active: active == LeakFilter.critical,
            onTap: () => onSelected(LeakFilter.critical),
          ),
          _Chip(
            label: 'Growing',
            active: active == LeakFilter.growing,
            onTap: () => onSelected(LeakFilter.growing),
          ),
          _Chip(
            label: 'Tracked',
            active: active == LeakFilter.tracked,
            onTap: () => onSelected(LeakFilter.tracked),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? LeakRadarColors.accent.withValues(alpha: 0.18)
              : const Color.fromRGBO(255, 255, 255, 0.05),
          border: Border.all(
            color: active
                ? LeakRadarColors.accent.withValues(alpha: 0.55)
                : const Color.fromRGBO(255, 255, 255, 0.10),
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: monoFont(
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            color: active ? LeakRadarColors.text100 : LeakRadarColors.text40,
          ),
        ),
      ),
    );
  }
}

// ── Finding row ───────────────────────────────────────────────────────────────

class _FindingRow extends StatelessWidget {
  const _FindingRow({required this.finding});

  final LeakFinding finding;

  @override
  Widget build(BuildContext context) {
    final isCritical = finding.severity == LeakSeverity.critical;
    final tokens = severityTokens(finding.severity);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => FindingDetailScreen(finding: finding),
            ),
          ),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: isCritical
                  ? tokens.rowBg
                  : const Color.fromRGBO(255, 255, 255, 0.03),
              border: Border.all(
                color: isCritical
                    ? tokens.rowBorder
                    : const Color.fromRGBO(255, 255, 255, 0.07),
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Severity colour bar
                  Container(
                    width: 5,
                    decoration: BoxDecoration(
                      color: tokens.text,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(10),
                        bottomLeft: Radius.circular(10),
                      ),
                    ),
                  ),
                  // Content
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Row 1: class name + growth delta
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  finding.className,
                                  overflow: TextOverflow.ellipsis,
                                  style: monoFont(
                                    fontSize: 13,
                                    color: LeakRadarColors.text100,
                                  ),
                                ),
                              ),
                              if (finding.growth > 0)
                                Text(
                                  '+${finding.growth}',
                                  style: monoFont(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: tokens.text,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          // Row 2: tag pill + kind label + live count + sparkline
                          Row(
                            children: [
                              _SeverityTag(severity: finding.severity),
                              const SizedBox(width: 6),
                              Text(
                                finding.kind.label,
                                style: monoFont(
                                  fontSize: 10,
                                  color: LeakRadarColors.text40,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  '${finding.liveCount} live',
                                  overflow: TextOverflow.ellipsis,
                                  style: monoFont(
                                    fontSize: 11,
                                    color: LeakRadarColors.text25,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              GrowthSparkline(
                                series: finding.series,
                                color: tokens.text,
                                width: 60,
                                height: 20,
                              ),
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
                      child: Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: LeakRadarColors.text40,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SeverityTag extends StatelessWidget {
  const _SeverityTag({required this.severity});

  final LeakSeverity severity;

  @override
  Widget build(BuildContext context) {
    final tokens = severityTokens(severity);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tokens.tagBg,
        border: Border.all(color: tokens.tagBorder),
        borderRadius: BorderRadius.circular(LeakRadarTheme.tagRadius),
      ),
      child: Text(
        severity.name.toUpperCase(),
        style: LeakRadarText.severityTag,
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

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

// ── Dismiss background ────────────────────────────────────────────────────────

class _DismissBackground extends StatelessWidget {
  const _DismissBackground();

  @override
  Widget build(BuildContext context) => Container(
    alignment: Alignment.centerRight,
    padding: const EdgeInsets.only(right: 20),
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    decoration: BoxDecoration(
      color: const Color.fromRGBO(239, 68, 68, 0.18),
      border: Border.all(color: const Color.fromRGBO(239, 68, 68, 0.40)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: const Icon(
      Icons.delete_outline,
      color: Color.fromRGBO(239, 68, 68, 0.80),
      size: 20,
    ),
  );
}
