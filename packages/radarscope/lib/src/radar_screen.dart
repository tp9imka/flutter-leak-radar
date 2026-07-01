// lib/src/radar_screen.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_leak_radar/flutter_leak_radar.dart';
import 'package:flutter_perf_radar/flutter_perf_radar.dart';
import 'package:radar_trace/radar_trace.dart' show TraceSnapshot;
import 'package:radar_ui/radar_ui.dart';
import 'package:share_plus/share_plus.dart';

/// Unified inspector screen for the full Radar suite.
///
/// Presents a three-tab layout: **Leaks**, **Performance**, and **Stability**.
/// Each tab body is self-contained — it owns its own data subscription.
///
/// The trailing **Export** icon opens a domain-specific export sheet whose
/// scope follows the active tab. The trailing **Close** icon invokes
/// [onClose].
class RadarScreen extends StatefulWidget {
  const RadarScreen({super.key, this.onClose, this.initialTab = 0});

  /// Called when the user taps the close button.
  final VoidCallback? onClose;

  /// Zero-based index of the tab to activate on first build.
  final int initialTab;

  @override
  State<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends State<RadarScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  // Live snapshot data — updated via polling so the tab count badges refresh.
  LeakReport? _leakReport;
  StabilitySnapshot _stability = const StabilitySnapshot(
    errorCount: 0,
    stallCount: 0,
    recentErrors: [],
    recentStalls: [],
  );

  StreamSubscription<LeakReport>? _leakSub;
  Timer? _stabilityTimer;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 2),
    );
    _leakReport = LeakRadar.latest;
    _leakSub = LeakRadar.reports.listen((r) {
      if (mounted) setState(() => _leakReport = r);
    });
    _stabilityTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() => _stability = PerfRadar.stabilitySnapshot);
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _leakSub?.cancel();
    _stabilityTimer?.cancel();
    super.dispose();
  }

  int get _leakCount => (_leakReport?.findings ?? const <LeakFinding>[]).length;

  int get _stabilityCount => _stability.errorCount + _stability.stallCount;

  // ── Worst severity across Leaks ──────────────────────────────────────────

  RadarSeverity get _leakSeverity {
    final findings = _leakReport?.findings ?? const <LeakFinding>[];
    if (findings.any((f) => f.severity == LeakSeverity.critical)) {
      return RadarSeverity.critical;
    }
    if (findings.any((f) => f.severity == LeakSeverity.warning)) {
      return RadarSeverity.warning;
    }
    if (findings.isNotEmpty) return RadarSeverity.info;
    return RadarSeverity.healthy;
  }

  RadarSeverity get _perfSeverity {
    final fs = PerfRadar.frameStats;
    if (fs.jankCount > 0) return RadarSeverity.warning;
    return RadarSeverity.healthy;
  }

  RadarSeverity get _stabilitySeverity {
    if (_stability.errorCount > 0) return RadarSeverity.critical;
    if (_stability.stallCount > 0) return RadarSeverity.warning;
    return RadarSeverity.healthy;
  }

  // ── Close ────────────────────────────────────────────────────────────────

  /// Closes the inspector.
  ///
  /// Calls [widget.onClose] when provided; otherwise pops the route so
  /// the button also works when [RadarScreen] is pushed as a plain route
  /// (e.g. via [Radar.openInspector]) with no explicit close callback.
  void _close() {
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      Navigator.maybeOf(context)?.pop();
    }
  }

  // ── Export ───────────────────────────────────────────────────────────────

  void _onExport() {
    final tabIndex = _tabs.index;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: const Color.fromRGBO(0, 0, 0, 0.55),
      isScrollControlled: true,
      builder: (_) => _RadarExportSheet(
        scope: tabIndex == 0
            ? _ExportScope.leaks
            : tabIndex == 1
            ? _ExportScope.performance
            : _ExportScope.stability,
        leakReport: _leakReport,
        stability: _stability,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RadarColors.bgPhone,
      appBar: AppBar(
        backgroundColor: RadarColors.bgPanel,
        foregroundColor: RadarColors.text100,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _RadarGlyph(),
            const SizedBox(width: 8),
            Text(
              'Flutter Radar',
              key: const Key('radar_screen_title'),
              style: RadarTypography.appBarTitle,
            ),
          ],
        ),
        actions: [
          _AppBarIconButton(
            key: const Key('radar_export_btn'),
            icon: Icons.upload_outlined,
            tooltip: 'Export',
            onTap: _onExport,
          ),
          const SizedBox(width: 6),
          _AppBarIconButton(
            key: const Key('radar_close_btn'),
            icon: Icons.close,
            tooltip: 'Close',
            onTap: _close,
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(42),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(height: 1, color: RadarColors.hairline08),
              _RadarTabBar(
                controller: _tabs,
                leakSeverity: _leakSeverity,
                leakCount: _leakCount,
                perfSeverity: _perfSeverity,
                stabilitySeverity: _stabilitySeverity,
                stabilityCount: _stabilityCount,
              ),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        // Disable swipe so horizontal drags inside child views (e.g.
        // the Traces table) are not intercepted by the top-level tabs.
        // Tabs are tap-only via the _RadarTabBar.
        physics: const NeverScrollableScrollPhysics(),
        children: const [LeakRadarView(), PerfRadarView(), StabilityView()],
      ),
    );
  }
}

// ── App bar icon button ──────────────────────────────────────────────────────

class _AppBarIconButton extends StatelessWidget {
  const _AppBarIconButton({
    super.key,
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
          width: RadarDensity.iconButtonSize,
          height: RadarDensity.iconButtonSize,
          decoration: BoxDecoration(
            color: RadarColors.iconButtonBg,
            borderRadius: RadarDensity.iconButtonRadius,
            border: Border.all(color: RadarColors.iconButtonBorder),
          ),
          child: Icon(icon, size: 16, color: RadarColors.text100),
        ),
      ),
    );
  }
}

// ── Radar glyph ──────────────────────────────────────────────────────────────

class _RadarGlyph extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Text(
    '◎',
    style: TextStyle(fontSize: 16, color: RadarColors.accent, height: 1),
  );
}

// ── Tab bar ──────────────────────────────────────────────────────────────────

class _RadarTabBar extends StatelessWidget {
  const _RadarTabBar({
    required this.controller,
    required this.leakSeverity,
    required this.leakCount,
    required this.perfSeverity,
    required this.stabilitySeverity,
    required this.stabilityCount,
  });

  final TabController controller;
  final RadarSeverity leakSeverity;
  final int leakCount;
  final RadarSeverity perfSeverity;
  final RadarSeverity stabilitySeverity;
  final int stabilityCount;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final active = controller.index;
        return Row(
          children: [
            _RadarTab(
              label: 'Leaks',
              severity: leakSeverity,
              count: leakCount,
              isActive: active == 0,
              onTap: () => controller.animateTo(0),
            ),
            _RadarTab(
              label: 'Performance',
              severity: perfSeverity,
              isActive: active == 1,
              onTap: () => controller.animateTo(1),
            ),
            _RadarTab(
              label: 'Stability',
              severity: stabilitySeverity,
              count: stabilityCount,
              isActive: active == 2,
              onTap: () => controller.animateTo(2),
            ),
          ],
        );
      },
    );
  }
}

class _RadarTab extends StatelessWidget {
  const _RadarTab({
    required this.label,
    required this.severity,
    required this.isActive,
    required this.onTap,
    this.count,
  });

  final String label;
  final RadarSeverity severity;
  final bool isActive;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final textColor = isActive ? RadarColors.text100 : RadarColors.text40;
    final dotColor = severity.color;

    return Expanded(
      child: GestureDetector(
        key: Key('radar_tab_$label'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 41,
          decoration: isActive
              ? BoxDecoration(
                  color: const Color(0xFF151c20),
                  border: Border.all(
                    color: RadarColors.hairline12,
                    width: RadarDensity.hairline,
                  ),
                  borderRadius: BorderRadius.circular(6),
                )
              : null,
          margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _SeverityDot(color: dotColor, isActive: isActive),
              const SizedBox(width: 5),
              Text(
                label,
                style: RadarTypography.monoLabel.copyWith(
                  color: textColor,
                  fontSize: 12,
                ),
              ),
              if (count != null && count! > 0) ...[
                const SizedBox(width: 4),
                _CountBadge(count: count!, severity: severity),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SeverityDot extends StatelessWidget {
  const _SeverityDot({required this.color, required this.isActive});

  final Color color;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    if (isActive) {
      return RadarLivePulseDot(size: 7, color: color);
    }
    return SizedBox(
      width: 7,
      height: 7,
      child: DecoratedBox(
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, required this.severity});

  final int count;
  final RadarSeverity severity;

  @override
  Widget build(BuildContext context) {
    final bg = Color.fromRGBO(
      // ignore: deprecated_member_use
      severity.color.red,
      // ignore: deprecated_member_use
      severity.color.green,
      // ignore: deprecated_member_use
      severity.color.blue,
      0.20,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$count',
        style: RadarTypography.monoTag.copyWith(color: severity.color),
      ),
    );
  }
}

// ── Export sheet ─────────────────────────────────────────────────────────────

enum _ExportScope { leaks, performance, stability }

enum _ExportFormat { json, markdown }

/// Domain-aware export bottom sheet.
///
/// The [scope] follows the active tab: findings / trace report / errors.
/// Serialises the REAL snapshot data — never placeholders.
class _RadarExportSheet extends StatefulWidget {
  const _RadarExportSheet({
    required this.scope,
    required this.leakReport,
    required this.stability,
  });

  final _ExportScope scope;
  final LeakReport? leakReport;
  final StabilitySnapshot stability;

  @override
  State<_RadarExportSheet> createState() => _RadarExportSheetState();
}

class _RadarExportSheetState extends State<_RadarExportSheet> {
  _ExportFormat _format = _ExportFormat.json;
  bool _sharing = false;

  String get _scopeLabel => switch (widget.scope) {
    _ExportScope.leaks => 'findings',
    _ExportScope.performance => 'trace report',
    _ExportScope.stability => 'errors',
  };

  String _previewText() {
    return switch (widget.scope) {
      _ExportScope.leaks => _leakPreview(),
      _ExportScope.performance => _perfPreview(),
      _ExportScope.stability => _stabilityPreview(),
    };
  }

  // ── Leak export ───────────────────────────────────────────────────────────

  String _leakPreview() {
    final report = widget.leakReport;
    if (report == null) return 'No findings to export yet.';
    if (_format == _ExportFormat.markdown) return report.toMarkdown();
    return const JsonEncoder.withIndent('  ').convert(report.toJson());
  }

  // ── Performance (trace) export ────────────────────────────────────────────

  String _perfPreview() {
    final snapshot = PerfRadar.snapshot();
    if (snapshot.stats.isEmpty) return 'No trace data recorded yet.';
    if (_format == _ExportFormat.markdown) {
      return _traceToMarkdown(snapshot);
    }
    return const JsonEncoder.withIndent('  ').convert(_traceToJson(snapshot));
  }

  Map<String, Object?> _traceToJson(TraceSnapshot snapshot) {
    final rows = snapshot.stats.entries.map((e) {
      final k = e.key;
      final v = e.value;
      return {
        'operation': k.name,
        if (k.category != null) 'category': k.category,
        'count': v.count,
        'avgMicros': v.meanMicros,
        'totalMicros': v.totalMicros,
        'maxMicros': v.maxMicros,
        'errorCount': v.errorCount,
      };
    }).toList();
    return {
      'generatedAt': DateTime.now().toIso8601String(),
      'dropCount': snapshot.totalDropCount,
      'operations': rows,
    };
  }

  String _traceToMarkdown(TraceSnapshot snapshot) {
    final b = StringBuffer()
      ..writeln('# Trace report — ${DateTime.now().toIso8601String()}')
      ..writeln()
      ..writeln('| Operation | Count | Avg (µs) | Total (µs) | Errors |')
      ..writeln('|---|---|---|---|---|');
    for (final e in snapshot.stats.entries) {
      final k = e.key;
      final v = e.value;
      final op = k.category != null ? '${k.category}/${k.name}' : k.name;
      b.writeln(
        '| $op | ${v.count} | ${v.meanMicros} |'
        ' ${v.totalMicros} | ${v.errorCount} |',
      );
    }
    if (snapshot.totalDropCount > 0) {
      b.writeln();
      b.writeln('> ${snapshot.totalDropCount} span(s) dropped (key limit).');
    }
    return b.toString();
  }

  // ── Stability export ──────────────────────────────────────────────────────

  String _stabilityPreview() {
    final snap = widget.stability;
    if (snap.errorCount == 0 && snap.stallCount == 0) {
      return 'No errors or stalls recorded yet.';
    }
    if (_format == _ExportFormat.markdown) {
      return _stabilityToMarkdown(snap);
    }
    return const JsonEncoder.withIndent('  ').convert(_stabilityToJson(snap));
  }

  Map<String, Object?> _stabilityToJson(StabilitySnapshot snap) => {
    'generatedAt': DateTime.now().toIso8601String(),
    'errorCount': snap.errorCount,
    'stallCount': snap.stallCount,
    'recentErrors': snap.recentErrors
        .map(
          (e) => {
            'message': e.message,
            if (e.context != null) 'context': e.context,
            'clockMicros': e.clockMicros,
            if (e.stackTraceString != null) 'stack': e.stackTraceString,
          },
        )
        .toList(),
    'recentStalls': snap.recentStalls
        .map(
          (s) => {
            'durationMicros': s.durationMicros,
            'clockMicros': s.clockMicros,
          },
        )
        .toList(),
  };

  String _stabilityToMarkdown(StabilitySnapshot snap) {
    final b = StringBuffer()
      ..writeln('# Stability report — ${DateTime.now().toIso8601String()}')
      ..writeln()
      ..writeln('Errors: ${snap.errorCount} · Stalls: ${snap.stallCount}')
      ..writeln();
    if (snap.recentErrors.isNotEmpty) {
      b.writeln('## Errors');
      for (final e in snap.recentErrors) {
        final ctx = e.context != null ? ' [${e.context}]' : '';
        b.writeln('- $ctx ${e.message}');
        if (e.stackTraceString != null) {
          b.writeln('  ```');
          b.writeln(
            '  ${e.stackTraceString!.split('\n').take(5).join('\n  ')}',
          );
          b.writeln('  ```');
        }
      }
    }
    if (snap.recentStalls.isNotEmpty) {
      b.writeln('## Stalls');
      b.writeln('| Duration (ms) |');
      b.writeln('|---|');
      for (final s in snap.recentStalls) {
        b.writeln('| ${(s.durationMicros / 1000).toStringAsFixed(1)} |');
      }
    }
    return b.toString();
  }

  // ── Share ─────────────────────────────────────────────────────────────────

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final text = _previewText();
      final ext = _format == _ExportFormat.json ? '.json' : '.md';
      final name = 'radar_${widget.scope.name}_export$ext';
      final bytes = const Utf8Encoder().convert(text);
      final file = XFile.fromData(
        bytes,
        name: name,
        mimeType: _format == _ExportFormat.json
            ? 'application/json'
            : 'text/markdown',
      );
      await SharePlus.instance.share(
        ShareParams(files: [file], text: 'Flutter Radar — $_scopeLabel'),
      );
    } catch (_) {
      // Never throw into host.
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _previewText();
    final hasData = !preview.endsWith('yet.');
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: RadarColors.bgSurface,
          border: Border(top: BorderSide(color: RadarColors.hairline10)),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(RadarDensity.sheetRadius),
            topRight: Radius.circular(RadarDensity.sheetRadius),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _GrabHandle(),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Text(
                'Export $_scopeLabel',
                style: RadarTypography.appBarTitle.copyWith(fontSize: 16),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _FormatToggle(
                selected: _format,
                onChanged: (f) => setState(() => _format = f),
              ),
            ),
            const SizedBox(height: 12),
            _PreviewBox(text: preview),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _ShareButton(
                format: _format,
                hasData: hasData,
                sharing: _sharing,
                onTap: _share,
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class _GrabHandle extends StatelessWidget {
  const _GrabHandle();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Center(
      child: Container(
        width: 38,
        height: 4,
        decoration: BoxDecoration(
          color: RadarColors.hairline12,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    ),
  );
}

class _FormatToggle extends StatelessWidget {
  const _FormatToggle({required this.selected, required this.onChanged});

  final _ExportFormat selected;
  final ValueChanged<_ExportFormat> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: RadarColors.bgInput,
      borderRadius: RadarDensity.inputRadius,
      border: Border.all(color: RadarColors.hairline10),
    ),
    child: Row(
      children: [
        _FormatSegment(
          label: 'JSON',
          active: selected == _ExportFormat.json,
          onTap: () => onChanged(_ExportFormat.json),
        ),
        const SizedBox(width: 4),
        _FormatSegment(
          label: 'Markdown',
          active: selected == _ExportFormat.markdown,
          onTap: () => onChanged(_ExportFormat.markdown),
        ),
      ],
    ),
  );
}

class _FormatSegment extends StatelessWidget {
  const _FormatSegment({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: active ? RadarColors.accent : Colors.transparent,
          borderRadius: RadarDensity.inputRadius,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: RadarTypography.monoLabel.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: active ? RadarColors.bgPhone : RadarColors.text40,
          ),
        ),
      ),
    ),
  );
}

class _PreviewBox extends StatelessWidget {
  const _PreviewBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Container(
      constraints: const BoxConstraints(maxHeight: 160),
      decoration: BoxDecoration(
        color: RadarColors.bgCode,
        borderRadius: RadarDensity.inputRadius,
        border: Border.all(color: RadarColors.hairline08),
      ),
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        child: Text(
          text,
          style: RadarTypography.monoCode.copyWith(
            fontSize: 11.5,
            color: RadarColors.text60,
          ),
        ),
      ),
    ),
  );
}

class _ShareButton extends StatelessWidget {
  const _ShareButton({
    required this.format,
    required this.hasData,
    required this.sharing,
    required this.onTap,
  });

  final _ExportFormat format;
  final bool hasData;
  final bool sharing;
  final VoidCallback onTap;

  String get _label {
    if (!hasData) return 'Nothing to export yet';
    return format == _ExportFormat.markdown ? 'Share .md' : 'Share .json';
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    key: const Key('radar_export_share_btn'),
    onTap: hasData && !sharing ? onTap : null,
    child: Container(
      height: 48,
      decoration: BoxDecoration(
        color: hasData ? RadarColors.accent : RadarColors.text25,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (sharing)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: RadarColors.bgPhone,
              ),
            )
          else ...[
            Icon(Icons.upload_outlined, size: 18, color: RadarColors.bgPhone),
            const SizedBox(width: 8),
            Text(
              _label,
              style: RadarTypography.monoLabel.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: RadarColors.bgPhone,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
