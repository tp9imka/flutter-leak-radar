// lib/src/radar_overlay.dart
import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_leak_radar/flutter_leak_radar.dart';
import 'package:flutter_perf_radar/flutter_perf_radar.dart';
import 'package:radar_ui/radar_ui.dart';

import 'radar_screen.dart';

/// Wraps [child] with a unified draggable badge that reflects the
/// worst current severity across Leaks, Performance, and Stability.
///
/// Tapping the badge opens the [RadarScreen] on the Leaks tab.
/// Long-pressing (~480 ms) opens a quick-action menu anchored near the badge.
///
/// The badge is clamped to the device's safe area — it can never slide
/// under a notch, status bar, or home indicator.
///
/// When [show] is false, returns [child] unchanged with no subscriptions
/// started.
class RadarOverlay extends StatefulWidget {
  const RadarOverlay({super.key, this.show = true, required this.child});

  /// Whether the overlay badge and inspector are active.
  ///
  /// When false [child] is returned unchanged and no subscriptions or
  /// timers are started.
  final bool show;

  final Widget child;

  @override
  State<RadarOverlay> createState() => _RadarOverlayState();
}

class _RadarOverlayState extends State<RadarOverlay> {
  static const double _initialRight = 16.0;
  static const double _initialBottom = 160.0;

  double _right = _initialRight;
  double _bottom = _initialBottom;
  bool _inspectorOpen = false;
  bool _menuOpen = false;
  int _inspectorInitialTab = 0;

  LeakReport? _leakReport;
  FrameStatsSnapshot _frameStats = const FrameStatsSnapshot(
    frameCount: 0,
    jankCount: 0,
  );
  StabilitySnapshot _stability = const StabilitySnapshot(
    errorCount: 0,
    stallCount: 0,
    recentErrors: [],
    recentStalls: [],
  );

  StreamSubscription<LeakReport>? _leakSub;
  Timer? _perfTimer;

  @override
  void initState() {
    super.initState();
    if (!widget.show) return;
    _leakReport = LeakRadar.latest;
    _leakSub = LeakRadar.reports.listen((r) {
      if (mounted) setState(() => _leakReport = r);
    });
    _perfTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) {
        setState(() {
          _frameStats = PerfRadar.frameStats;
          _stability = PerfRadar.stabilitySnapshot;
        });
      }
    });
  }

  @override
  void dispose() {
    _leakSub?.cancel();
    _perfTimer?.cancel();
    super.dispose();
  }

  // ── Severity computation ─────────────────────────────────────────────────

  _BadgeSeverity get _badgeSeverity {
    final findings = _leakReport?.findings ?? const <LeakFinding>[];
    final hasCriticalLeak = findings.any(
      (f) => f.severity == LeakSeverity.critical,
    );
    final hasError = _stability.errorCount > 0;
    if (hasCriticalLeak || hasError) return _BadgeSeverity.critical;

    final hasWarningLeak = findings.any(
      (f) => f.severity == LeakSeverity.warning,
    );
    final hasJank = _frameStats.jankCount > 0;
    final hasStall = _stability.stallCount > 0;
    if (hasWarningLeak || hasJank || hasStall) return _BadgeSeverity.warning;

    return _BadgeSeverity.clean;
  }

  int get _leakCount => (_leakReport?.findings ?? const <LeakFinding>[]).length;

  String _badgeLabel(_BadgeSeverity sev) {
    switch (sev) {
      case _BadgeSeverity.clean:
        return 'All clear';
      case _BadgeSeverity.warning:
        final findings = _leakReport?.findings ?? const <LeakFinding>[];
        final warnCount = findings
            .where(
              (f) =>
                  f.severity == LeakSeverity.warning ||
                  f.severity == LeakSeverity.critical,
            )
            .length;
        final jankStr = _frameStats.jankCount > 0 ? '  ▲jank' : '';
        return '${warnCount > 0 ? warnCount : _leakCount}⚠$jankStr';
      case _BadgeSeverity.critical:
        final count = _leakCount + _stability.errorCount;
        return '${count > 0 ? count : '!'}⊘';
    }
  }

  // ── Theme helpers ─────────────────────────────────────────────────────────

  ThemeData _buildInspectorTheme() => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: RadarColors.bgPhone,
    colorScheme: const ColorScheme.dark(
      primary: RadarColors.accent,
      surface: RadarColors.bgSurface,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: RadarColors.bgPanel,
      elevation: 0,
    ),
  );

  // ── Drag + gesture handling ───────────────────────────────────────────────

  void _onPanUpdate(
    DragUpdateDetails details,
    Size screenSize,
    EdgeInsets safe,
  ) {
    // Badge approximate dimensions for clamping.
    const badgeWidth = 120.0;
    const badgeHeight = 40.0;
    setState(() {
      _right = (_right - details.delta.dx).clamp(
        safe.right,
        screenSize.width - badgeWidth - safe.left,
      );
      _bottom = (_bottom - details.delta.dy).clamp(
        safe.bottom,
        screenSize.height - badgeHeight - safe.top,
      );
    });
  }

  void _onTap() => setState(() {
    _inspectorInitialTab = 0;
    _inspectorOpen = true;
  });

  void _onLongPress() => setState(() => _menuOpen = true);

  void _closeMenu() => setState(() => _menuOpen = false);

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!widget.show) return widget.child;

    final sev = _badgeSeverity;
    final media = MediaQuery.of(context);
    final safe = media.padding;
    final size = media.size;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          widget.child,
          if (_inspectorOpen)
            Positioned.fill(
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: _buildInspectorTheme(),
                home: RadarScreen(
                  initialTab: _inspectorInitialTab,
                  onClose: () => setState(() => _inspectorOpen = false),
                ),
              ),
            ),
          if (!_inspectorOpen) ...[
            Positioned(
              right: _right,
              bottom: _bottom,
              child: GestureDetector(
                onTap: _onTap,
                onLongPress: _onLongPress,
                onPanUpdate: (d) => _onPanUpdate(d, size, safe),
                child: _BadgePill(severity: sev, label: _badgeLabel(sev)),
              ),
            ),
            if (_menuOpen)
              _QuickActionOverlay(
                right: _right,
                bottom: _bottom + 48,
                onDismiss: _closeMenu,
                onForceGc: () {
                  _closeMenu();
                  LeakRadar.forceGcAndScan();
                },
                onScanNow: () {
                  _closeMenu();
                  LeakRadar.scan();
                },
                onOpenLeaks: () {
                  _closeMenu();
                  setState(() {
                    _inspectorInitialTab = 0;
                    _inspectorOpen = true;
                  });
                },
                onOpenPerformance: () {
                  _closeMenu();
                  setState(() {
                    _inspectorInitialTab = 1;
                    _inspectorOpen = true;
                  });
                },
              ),
          ],
        ],
      ),
    );
  }
}

// ── Badge severity ────────────────────────────────────────────────────────────

enum _BadgeSeverity { clean, warning, critical }

extension _BadgeSeverityX on _BadgeSeverity {
  Color get color => switch (this) {
    _BadgeSeverity.clean => RadarColors.accent,
    _BadgeSeverity.warning => RadarColors.warning,
    _BadgeSeverity.critical => RadarColors.critical,
  };
}

// ── Badge pill ────────────────────────────────────────────────────────────────

class _BadgePill extends StatelessWidget {
  const _BadgePill({required this.severity, required this.label});

  final _BadgeSeverity severity;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = severity.color;
    final isCritical = severity == _BadgeSeverity.critical;

    return ClipRRect(
      borderRadius: BorderRadius.circular(RadarDensity.badgeRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: BoxDecoration(
            color: Color.fromRGBO(
              // ignore: deprecated_member_use
              color.red,
              // ignore: deprecated_member_use
              color.green,
              // ignore: deprecated_member_use
              color.blue,
              0.16,
            ),
            borderRadius: BorderRadius.circular(RadarDensity.badgeRadius),
            border: Border.all(
              color: Color.fromRGBO(
                // ignore: deprecated_member_use
                color.red,
                // ignore: deprecated_member_use
                color.green,
                // ignore: deprecated_member_use
                color.blue,
                0.5,
              ),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x44000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            key: const Key('radar_badge'),
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isCritical)
                RadarLivePulseDot(size: 8, color: color)
              else
                SizedBox(
                  width: 8,
                  height: 8,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              const SizedBox(width: 6),
              Text(
                label,
                style: RadarTypography.monoLabel.copyWith(
                  fontSize: 12.5,
                  color: RadarColors.text100,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Quick-action overlay ──────────────────────────────────────────────────────

class _QuickActionOverlay extends StatelessWidget {
  const _QuickActionOverlay({
    required this.right,
    required this.bottom,
    required this.onDismiss,
    required this.onForceGc,
    required this.onScanNow,
    required this.onOpenLeaks,
    required this.onOpenPerformance,
  });

  final double right;
  final double bottom;
  final VoidCallback onDismiss;
  final VoidCallback onForceGc;
  final VoidCallback onScanNow;
  final VoidCallback onOpenLeaks;
  final VoidCallback onOpenPerformance;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            key: const Key('quick_menu_scrim'),
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
          ),
        ),
        Positioned(
          right: right,
          bottom: bottom,
          child: _QuickMenu(
            onForceGc: onForceGc,
            onScanNow: onScanNow,
            onOpenLeaks: onOpenLeaks,
            onOpenPerformance: onOpenPerformance,
          ),
        ),
      ],
    );
  }
}

class _QuickMenu extends StatelessWidget {
  const _QuickMenu({
    required this.onForceGc,
    required this.onScanNow,
    required this.onOpenLeaks,
    required this.onOpenPerformance,
  });

  final VoidCallback onForceGc;
  final VoidCallback onScanNow;
  final VoidCallback onOpenLeaks;
  final VoidCallback onOpenPerformance;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      decoration: BoxDecoration(
        color: RadarColors.bgSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: RadarColors.hairline10),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _QuickMenuItem(
            key: const Key('quick_menu_force_gc'),
            label: 'Force GC',
            icon: Icons.delete_sweep_outlined,
            onTap: onForceGc,
          ),
          _MenuDivider(),
          _QuickMenuItem(
            key: const Key('quick_menu_scan_now'),
            label: 'Scan now',
            icon: Icons.radar_outlined,
            onTap: onScanNow,
          ),
          _MenuDivider(),
          _QuickMenuItem(
            key: const Key('quick_menu_open_leaks'),
            label: 'Open Leaks',
            icon: Icons.memory_outlined,
            onTap: onOpenLeaks,
          ),
          _MenuDivider(),
          _QuickMenuItem(
            key: const Key('quick_menu_open_perf'),
            label: 'Open Performance',
            icon: Icons.speed_outlined,
            onTap: onOpenPerformance,
          ),
        ],
      ),
    );
  }
}

class _QuickMenuItem extends StatelessWidget {
  const _QuickMenuItem({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: RadarColors.text60),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: RadarTypography.monoLabel.copyWith(
                fontSize: 12.5,
                color: RadarColors.text100,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _MenuDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: RadarColors.hairline04);
}
