// lib/src/ui/leak_radar_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../model/leak_finding.dart';
import '../model/leak_kind.dart';
import '../model/leak_report.dart';
import '../leak_radar.dart';
import 'export_sheet.dart';
import 'finding_detail_screen.dart';
import 'growth_sparkline.dart';
import 'settings_screen.dart';
import 'theme/theme.dart';

/// Brand-themed results screen.
///
/// When used from a Navigator, push it directly:
/// `Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LeakRadarScreen()));`
///
/// When embedded in the overlay's self-contained [MaterialApp] layer, supply
/// [onClose] so the leading close button can dismiss the inspector.
class LeakRadarScreen extends StatefulWidget {
  const LeakRadarScreen({super.key, this.onClose});

  /// Called when the user taps the leading close button in the AppBar.
  /// When null, no close button is shown (normal Navigator-push usage).
  final VoidCallback? onClose;

  @override
  State<LeakRadarScreen> createState() => _LeakRadarScreenState();
}

// ── Filter chip enum ──────────────────────────────────────────────────────────

enum _Filter { all, critical, growing, tracked }

// ── State ────────────────────────────────────────────────────────────────────

class _LeakRadarScreenState extends State<LeakRadarScreen> {
  LeakReport? _report;
  bool _scanning = false;
  bool _collectingHeap = false;
  _Filter _activeFilter = _Filter.all;

  // Tracks classes dismissed by swipe in the current view. The engine still
  // detects these leaks — a fresh scan re-adds them if still leaking.
  final Set<String> _dismissed = {};

  @override
  void initState() {
    super.initState();
    _report = LeakRadar.latest;
  }

  // ── Data ──────────────────────────────────────────────────────────────────

  List<LeakFinding> get _filtered {
    final findings = _report?.findings ?? const <LeakFinding>[];
    final base = switch (_activeFilter) {
      _Filter.all => findings,
      _Filter.critical =>
        findings.where((f) => f.severity == LeakSeverity.critical).toList(),
      _Filter.growing => findings.where((f) => f.growth > 0).toList(),
      _Filter.tracked => findings.where((f) => f.tag != null).toList(),
    };
    return base.where((f) => !_dismissed.contains(f.className)).toList();
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  /// Runs a scan and returns the new [LeakReport]. The caller is responsible
  /// for showing feedback so this method stays testable.
  Future<LeakReport?> _scan() async {
    setState(() => _scanning = true);
    final report = await LeakRadar.scan();
    if (!mounted) return null;
    setState(() {
      _report = report;
      _scanning = false;
      _dismissed.clear(); // fresh scan re-shows swiped rows
    });
    return report;
  }

  void _showExportSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: const Color.fromRGBO(0, 0, 0, 0.55),
      isScrollControlled: true,
      builder: (_) => const LeakExportSheet(),
    );
  }

  Future<void> _collectHeapSnapshot() async {
    setState(() => _collectingHeap = true);
    final path = await LeakRadar.captureHeapSnapshotToFile();
    if (!mounted) return;
    setState(() => _collectingHeap = false);
    if (path != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Heap snapshot: $path'),
          action: SnackBarAction(
            label: 'Share',
            onPressed: () async {
              try {
                await SharePlus.instance.share(
                  ShareParams(
                    files: [XFile(path)],
                    text: 'Leak Radar heap snapshot',
                  ),
                );
              } catch (_) {
                // Never throw into host — swallow share errors silently.
              }
            },
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Heap snapshot unavailable')),
      );
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final findings = report?.findings ?? const <LeakFinding>[];
    final filtered = _filtered;

    return Scaffold(
      backgroundColor: LeakRadarColors.pageBg,
      appBar: _buildAppBar(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SummaryRow(report: report, formatTime: _formatTime),
          _FilterRow(
            active: _activeFilter,
            total: findings.length,
            onSelected: (f) => setState(() => _activeFilter = f),
          ),
          Expanded(
            child: findings.isEmpty
                ? _EmptyState(
                    status: report?.status ?? LeakRadar.status,
                  )
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
                              '${f.className}|'
                              '${f.kind.name}|'
                              '${f.tag ?? ''}',
                            ),
                            direction: DismissDirection.endToStart,
                            // View-level dismiss: engine still detects;
                            // re-adds on next scan.
                            onDismissed: (_) => setState(
                              () => _dismissed.add(f.className),
                            ),
                            background: const SizedBox.shrink(),
                            secondaryBackground:
                                const _DismissBackground(),
                            child: _FindingRow(finding: f),
                          );
                        },
                      ),
          ),
        ],
      ),
      bottomNavigationBar: _BottomBar(
        filteredFindings: filtered,
        scanning: _scanning,
        onScanTap: () async {
          final messenger = ScaffoldMessenger.of(context);
          final newReport = await _scan();
          if (!mounted) return;
          final count = newReport?.findings.length ?? 0;
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'Heap captured · $count findings',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 13,
                  color: LeakRadarColors.pageBg,
                ),
              ),
              backgroundColor: LeakRadarColors.accent,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(milliseconds: 1900),
            ),
          );
        },
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: LeakRadarColors.appBarBg,
      elevation: 0,
      leading: widget.onClose != null
          ? IconButton(
              icon: const Icon(Icons.close, color: LeakRadarColors.text100),
              tooltip: 'Close',
              onPressed: widget.onClose,
            )
          : null,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const RadarGlyph(size: 20),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'Leak Radar',
              style: LeakRadarText.title,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      actions: [
        _IconBtn(
          icon: Icons.download_outlined,
          tooltip: 'Export',
          onTap: _scanning
              ? null
              : () => _showExportSheet(context),
        ),
        _IconBtn(
          icon: Icons.settings_outlined,
          tooltip: 'Settings',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const SettingsScreen(),
            ),
          ),
        ),
        PopupMenuButton<_HeapMenuAction>(
          icon: _collectingHeap
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.more_vert),
          tooltip: 'More',
          color: LeakRadarColors.appBarBg,
          onSelected: (action) {
            switch (action) {
              case _HeapMenuAction.heapSnapshot:
                if (!_scanning && !_collectingHeap) _collectHeapSnapshot();
              case _HeapMenuAction.share:
                if (!_scanning) _showExportSheet(context);
              case _HeapMenuAction.clearLeaks:
                LeakRadar.clearLeaks();
                if (mounted) {
                  setState(() {
                    _dismissed.clear();
                    _report = LeakRadar.latest;
                  });
                }
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: _HeapMenuAction.heapSnapshot,
              child: Text(
                'Collect heap snapshot',
                style: LeakRadarText.label.copyWith(
                  color: LeakRadarColors.text100,
                ),
              ),
            ),
            PopupMenuItem(
              value: _HeapMenuAction.share,
              child: Text(
                'Share report',
                style: LeakRadarText.label.copyWith(
                  color: LeakRadarColors.text100,
                ),
              ),
            ),
            PopupMenuItem(
              value: _HeapMenuAction.clearLeaks,
              child: Text(
                'Clear leaks',
                style: LeakRadarText.label.copyWith(
                  color: LeakRadarColors.text100,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

enum _HeapMenuAction { heapSnapshot, share, clearLeaks }

// ── Icon button ───────────────────────────────────────────────────────────────

class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.icon,
    required this.tooltip,
    this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: LeakRadarDimens.iconButtonSize,
          height: LeakRadarDimens.iconButtonSize,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: LeakRadarDimens.iconButtonBg,
            border: Border.all(color: LeakRadarDimens.iconButtonBorder),
            borderRadius:
                BorderRadius.circular(LeakRadarDimens.iconButtonRadius),
          ),
          child: Icon(
            icon,
            size: 18,
            color: onTap != null
                ? LeakRadarColors.text100
                : LeakRadarColors.text25,
          ),
        ),
      ),
    );
  }
}

// ── Summary row ───────────────────────────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.report, required this.formatTime});

  final LeakReport? report;
  final String Function(DateTime) formatTime;

  @override
  Widget build(BuildContext context) {
    final findings = report?.findings ?? const <LeakFinding>[];
    final criticalCount =
        findings.where((f) => f.severity == LeakSeverity.critical).length;
    final warningCount =
        findings.where((f) => f.severity == LeakSeverity.warning).length;
    final infoCount =
        findings.where((f) => f.severity == LeakSeverity.info).length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          if (criticalCount > 0) ...[
            Text(
              '● $criticalCount critical',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11.5,
                color: severityTokens(LeakSeverity.critical).text,
              ),
            ),
            if (warningCount > 0 || infoCount > 0)
              const SizedBox(width: 12),
          ],
          if (warningCount > 0) ...[
            Text(
              '● $warningCount warning',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11.5,
                color: severityTokens(LeakSeverity.warning).text,
              ),
            ),
            if (infoCount > 0) const SizedBox(width: 12),
          ],
          if (infoCount > 0)
            Text(
              '● $infoCount info',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11.5,
                color: severityTokens(LeakSeverity.info).text,
              ),
            ),
          if (criticalCount == 0 && warningCount == 0 && infoCount == 0)
            Text('—', style: LeakRadarText.label),
          const Spacer(),
          if (report != null)
            Text(
              'scan ${formatTime(report!.capturedAt)}',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                color: LeakRadarColors.text40,
              ),
            ),
        ],
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

  final _Filter active;
  final int total;
  final ValueChanged<_Filter> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _Chip(
            label: 'All·$total',
            active: active == _Filter.all,
            onTap: () => onSelected(_Filter.all),
          ),
          _Chip(
            label: 'Critical',
            active: active == _Filter.critical,
            onTap: () => onSelected(_Filter.critical),
          ),
          _Chip(
            label: 'Growing',
            active: active == _Filter.growing,
            onTap: () => onSelected(_Filter.growing),
          ),
          _Chip(
            label: 'Tracked',
            active: active == _Filter.tracked,
            onTap: () => onSelected(_Filter.tracked),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
          style: GoogleFonts.jetBrainsMono(
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            color: active
                ? LeakRadarColors.text100
                : LeakRadarColors.text40,
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
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 13,
                                    color: LeakRadarColors.text100,
                                  ),
                                ),
                              ),
                              if (finding.growth > 0)
                                Text(
                                  '+${finding.growth}',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: tokens.text,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          // Row 2: tag pill + live count + sparkline
                          Row(
                            children: [
                              _SeverityTag(severity: finding.severity),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  '${finding.liveCount} live',
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.jetBrainsMono(
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
          border: Border.all(
            color: const Color.fromRGBO(239, 68, 68, 0.40),
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(
          Icons.delete_outline,
          color: Color.fromRGBO(239, 68, 68, 0.80),
          size: 20,
        ),
      );
}

// ── Bottom bar ────────────────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.filteredFindings,
    required this.scanning,
    required this.onScanTap,
  });

  final List<LeakFinding> filteredFindings;
  final bool scanning;
  final VoidCallback onScanTap;

  @override
  Widget build(BuildContext context) {
    final instanceTotal =
        filteredFindings.fold(0, (sum, f) => sum + f.liveCount);

    return Container(
      color: LeakRadarColors.appBarBg,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${filteredFindings.length} classes · $instanceTotal instances',
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    color: LeakRadarColors.text25,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                key: const Key('leak_radar_scan_btn'),
                onTap: scanning ? null : onScanTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: scanning
                        ? LeakRadarColors.accent.withValues(alpha: 0.5)
                        : LeakRadarColors.accent,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: LeakRadarColors.accent.withValues(alpha: 0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.refresh,
                        size: 16,
                        color: LeakRadarColors.pageBg,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Scan now',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: LeakRadarColors.pageBg,
                        ),
                      ),
                    ],
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
