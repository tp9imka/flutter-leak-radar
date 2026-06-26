// lib/src/radar_overlay.dart
import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_leak_radar/flutter_leak_radar.dart';
import 'package:flutter_perf_radar/flutter_perf_radar.dart';

import 'radar_screen.dart';

/// Wraps [child] with a unified draggable badge for both Leak Radar and
/// Perf Radar.
///
/// The badge shows a leak count and a perf-health indicator. Tapping it
/// opens [RadarScreen]. Safe to place above [MaterialApp] — it owns its own
/// [Directionality] and opens the inspector via a self-contained nested
/// [MaterialApp] so it never requires a Navigator ancestor.
///
/// When [show] is false, returns [child] unchanged with no subscriptions
/// started.
class RadarOverlay extends StatefulWidget {
  const RadarOverlay({super.key, this.show = true, required this.child});

  /// Whether the overlay badge and inspector are active.
  ///
  /// When false, [child] is returned unchanged and no subscriptions or
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

  /// Badge accent colour reflecting the worst signal across both domains.
  Color get _accentColor {
    final findings = _leakReport?.findings ?? const <LeakFinding>[];
    final hasCritical = findings.any(
      (f) => f.severity == LeakSeverity.critical,
    );
    if (hasCritical) return const Color.fromRGBO(255, 93, 108, 1);
    final hasJankOrError =
        _frameStats.jankCount > 0 || _stability.errorCount > 0;
    if (hasJankOrError) return const Color.fromRGBO(255, 189, 89, 1);
    return const Color.fromRGBO(47, 227, 155, 1);
  }

  int get _leakCount {
    return (_leakReport?.findings ?? const <LeakFinding>[])
        .where(
          (f) =>
              f.severity == LeakSeverity.critical ||
              f.kind == LeakKind.notGced ||
              f.kind == LeakKind.notDisposed ||
              f.kind == LeakKind.retainedByNonLiveRoot,
        )
        .length;
  }

  ThemeData _buildInspectorTheme() => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF0a0d0e),
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFF2fe39b),
      surface: Color(0xFF0e1316),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF0c1012),
      elevation: 0,
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (!widget.show) return widget.child;

    final accent = _accentColor;
    final leakCount = _leakCount;
    final hasJank = _frameStats.jankCount > 0;
    final hasError = _stability.errorCount > 0;

    final pill = ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 13),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: accent.withValues(alpha: 0.45)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x44000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('◉', style: TextStyle(fontSize: 12, color: accent)),
              const SizedBox(width: 6),
              Text(
                '$leakCount leaks',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              if (hasJank || hasError) ...[
                const SizedBox(width: 6),
                Container(width: 1, height: 14, color: Colors.white24),
                const SizedBox(width: 6),
                Text(
                  hasError ? '${_stability.errorCount}err' : 'jank',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: accent,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

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
                  onClose: () => setState(() => _inspectorOpen = false),
                ),
              ),
            ),
          if (!_inspectorOpen)
            Positioned(
              right: _right,
              bottom: _bottom,
              child: GestureDetector(
                key: const Key('radar_badge'),
                onPanUpdate: (details) {
                  setState(() {
                    _right = (_right - details.delta.dx).clamp(
                      0,
                      double.infinity,
                    );
                    _bottom = (_bottom - details.delta.dy).clamp(
                      0,
                      double.infinity,
                    );
                  });
                },
                onTap: () => setState(() => _inspectorOpen = true),
                child: pill,
              ),
            ),
        ],
      ),
    );
  }
}
