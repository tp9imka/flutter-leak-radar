// lib/src/ui/leak_radar_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../model/leak_finding.dart';
import '../model/leak_report.dart';
import '../leak_radar.dart';
import 'export_sheet.dart';
import 'leak_radar_view.dart';
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

// ── State ────────────────────────────────────────────────────────────────────

class _LeakRadarScreenState extends State<LeakRadarScreen> {
  bool _scanning = false;
  bool _collectingHeap = false;

  final _viewKey = GlobalKey<LeakRadarViewState>();
  StreamSubscription<LeakReport>? _reportSub;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _reportSub = LeakRadar.reports.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _reportSub?.cancel();
    super.dispose();
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  /// Runs a scan and returns the new [LeakReport]. The caller is responsible
  /// for showing feedback so this method stays testable.
  Future<LeakReport?> _scan() async {
    setState(() => _scanning = true);
    final report = await LeakRadar.scan();
    if (!mounted) return null;
    setState(() => _scanning = false);
    _viewKey.currentState?.clearDismissed();
    return report;
  }

  /// Forces a GC, then rescans — surfaces precise (notGced / notDisposed)
  /// leaks immediately instead of waiting for an incidental GC.
  Future<void> _forceGcAndScan() async {
    setState(() => _scanning = true);
    await LeakRadar.forceGcAndScan();
    if (!mounted) return;
    setState(() => _scanning = false);
    _viewKey.currentState?.clearDismissed();
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
                // Portable across share_plus 10.x–13.x (see export_sheet.dart).
                // ignore: deprecated_member_use
                await Share.shareXFiles([
                  XFile(path),
                ], text: 'Leak Radar heap snapshot');
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
    final viewState = _viewKey.currentState;
    final report = viewState?.report;
    final filtered = viewState?.filtered ?? const [];

    return Scaffold(
      backgroundColor: LeakRadarColors.pageBg,
      appBar: _buildAppBar(),
      body: LeakRadarView(key: _viewKey),
      bottomNavigationBar: _BottomBar(
        filteredFindings: filtered,
        scanning: _scanning,
        scanTime: report != null ? _formatTime(report.capturedAt) : null,
        onScanTap: () async {
          final messenger = ScaffoldMessenger.of(context);
          final newReport = await _scan();
          if (!mounted) return;
          final count = newReport?.findings.length ?? 0;
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'Heap captured · $count findings',
                style: monoFont(fontSize: 13, color: LeakRadarColors.pageBg),
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
      foregroundColor: LeakRadarColors.text100,
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
          onTap: _scanning ? null : () => _showExportSheet(context),
        ),
        _IconBtn(
          icon: Icons.settings_outlined,
          tooltip: 'Settings',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
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
              case _HeapMenuAction.forceGc:
                if (!_scanning && !_collectingHeap) _forceGcAndScan();
              case _HeapMenuAction.heapSnapshot:
                if (!_scanning && !_collectingHeap) _collectHeapSnapshot();
              case _HeapMenuAction.share:
                if (!_scanning) _showExportSheet(context);
              case _HeapMenuAction.clearLeaks:
                LeakRadar.clearLeaks();
                if (mounted) {
                  _viewKey.currentState?.clearDismissed();
                  setState(() {});
                }
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: _HeapMenuAction.forceGc,
              child: Text(
                'Force GC & rescan',
                style: LeakRadarText.label.copyWith(
                  color: LeakRadarColors.text100,
                ),
              ),
            ),
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

enum _HeapMenuAction { forceGc, heapSnapshot, share, clearLeaks }

// ── Icon button ───────────────────────────────────────────────────────────────

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.tooltip, this.onTap});

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
            borderRadius: BorderRadius.circular(
              LeakRadarDimens.iconButtonRadius,
            ),
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

// ── Bottom bar ────────────────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.filteredFindings,
    required this.scanning,
    required this.onScanTap,
    this.scanTime,
  });

  final List<LeakFinding> filteredFindings;
  final bool scanning;
  final VoidCallback onScanTap;

  /// Formatted last-scan time (e.g. `17:17`), or null before any scan. Shown
  /// here only — the summary row no longer duplicates it.
  final String? scanTime;

  @override
  Widget build(BuildContext context) {
    final instanceTotal = filteredFindings.fold(
      0,
      (sum, f) => sum + f.liveCount,
    );

    return Container(
      color: LeakRadarColors.appBarBg,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${filteredFindings.length} classes · '
                      '$instanceTotal instances',
                      overflow: TextOverflow.ellipsis,
                      style: monoFont(
                        fontSize: 11,
                        color: LeakRadarColors.text25,
                      ),
                    ),
                    if (scanTime != null)
                      Text(
                        'scan $scanTime',
                        overflow: TextOverflow.ellipsis,
                        style: monoFont(
                          fontSize: 11,
                          color: LeakRadarColors.text25,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: LeakRadarColors.accent.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Material(
                  color: scanning
                      ? LeakRadarColors.accent.withValues(alpha: 0.5)
                      : LeakRadarColors.accent,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    key: const Key('leak_radar_scan_btn'),
                    onTap: scanning
                        ? null
                        : () {
                            HapticFeedback.selectionClick();
                            onScanTap();
                          },
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
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
                            style: monoFont(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: LeakRadarColors.pageBg,
                            ),
                          ),
                        ],
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
  }
}
