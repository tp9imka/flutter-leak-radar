// lib/src/ui/leak_radar_overlay.dart
import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/leak_radar_config.dart';
import '../model/leak_kind.dart';
import '../model/leak_report.dart';
import '../leak_radar.dart';
import 'leak_radar_screen.dart';
import 'theme/theme.dart';

/// Wraps [child] and floats a draggable pill badge showing the current worst
/// severity and finding count. Returns [child] unchanged when [show] is false.
///
/// Safe to place ABOVE [MaterialApp] — the overlay owns its own
/// [Directionality] and opens the inspector via a self-contained nested
/// [MaterialApp] layer, so it never calls [Navigator.of] on a context that
/// has no Navigator ancestor.
class LeakRadarOverlay extends StatefulWidget {
  const LeakRadarOverlay({
    super.key,
    required this.child,
    this.show = true,
    this.initialReport,
  });

  final Widget child;
  final bool show;

  /// Test seam; production reads from [LeakRadar.reports] and [LeakRadar.latest].
  final LeakReport? initialReport;

  @override
  State<LeakRadarOverlay> createState() => _LeakRadarOverlayState();
}

class _LeakRadarOverlayState extends State<LeakRadarOverlay>
    with SingleTickerProviderStateMixin {
  static const double _initialRight = 16.0;
  static const double _initialBottom = 100.0;

  double _right = _initialRight;
  double _bottom = _initialBottom;

  LeakReport? _report;
  StreamSubscription<LeakReport>? _sub;

  /// Whether the full-screen inspector layer is visible.
  bool _inspectorOpen = false;

  late final AnimationController _pulseController;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _opacityAnim;

  @override
  void initState() {
    super.initState();
    _report = widget.initialReport ?? LeakRadar.latest;
    _sub = LeakRadar.reports.listen((r) {
      if (mounted) setState(() => _report = r);
    });

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 1.18).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );
    _opacityAnim = Tween<double>(begin: 0.6, end: 0.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  /// Badge bg/border overlay colours per severity.
  ///
  /// These are intentionally hardcoded rgba values for the translucent badge
  /// overlay effect — they differ from the severity token sheet values.
  ({Color bg, Color border}) _badgeColors(LeakSeverity? severity) =>
      switch (severity) {
        LeakSeverity.critical => (
            bg: const Color.fromRGBO(255, 93, 108, 0.18),
            border: const Color.fromRGBO(255, 93, 108, 0.55),
          ),
        LeakSeverity.warning => (
            bg: const Color.fromRGBO(255, 189, 89, 0.18),
            border: const Color.fromRGBO(255, 189, 89, 0.55),
          ),
        LeakSeverity.info => (
            bg: const Color.fromRGBO(80, 200, 120, 0.18),
            border: const Color.fromRGBO(80, 200, 120, 0.55),
          ),
        null => (
            bg: const Color.fromRGBO(255, 255, 255, 0.06),
            border: const Color.fromRGBO(255, 255, 255, 0.15),
          ),
      };

  /// Dark [ThemeData] for the self-contained inspector [MaterialApp].
  ThemeData _buildInspectorTheme() => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: LeakRadarColors.pageBg,
        colorScheme: const ColorScheme.dark(
          primary: LeakRadarColors.accent,
          surface: LeakRadarColors.cardBg,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: LeakRadarColors.appBarBg,
          elevation: 0,
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (!widget.show) return widget.child;

    return ValueListenableBuilder<LeakRadarConfig>(
      valueListenable: LeakRadar.configListenable,
      builder: (context, config, _) {
        if (!config.showOverlay) return widget.child;
        return _buildOverlay(context);
      },
    );
  }

  Widget _buildOverlay(BuildContext context) {
    final report = _report;
    final count = report?.findings.length ?? 0;
    final hasFindings = count > 0;
    final severity = hasFindings ? report?.worstSeverity : null;
    final colors = _badgeColors(severity);

    // MediaQuery may not be available when placed above MaterialApp — guard.
    final animationsDisabled =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    if (hasFindings && !animationsDisabled) {
      if (!_pulseController.isAnimating) _pulseController.repeat();
    } else {
      if (_pulseController.isAnimating) {
        _pulseController
          ..stop()
          ..reset();
      }
    }

    final pill = ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 13),
          decoration: BoxDecoration(
            color: colors.bg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: colors.border),
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
              const RadarGlyph(size: 16),
              const SizedBox(width: 8),
              Text(
                '$count leaks',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '⣿',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    Widget badgeContent;
    if (hasFindings && !animationsDisabled) {
      badgeContent = AnimatedBuilder(
        key: const Key('leak_radar_pulse'),
        animation: _pulseController,
        builder: (context, _) {
          return Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Transform.scale(
                scale: _scaleAnim.value,
                child: Container(
                  height: 44,
                  width: 44,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: colors.border.withValues(
                        alpha: _opacityAnim.value * 0.55,
                      ),
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              pill,
            ],
          );
        },
      );
    } else {
      badgeContent = pill;
    }

    // Directionality is required by Stack/Text when placed above MaterialApp.
    // The host MaterialApp supplies its own Directionality internally —
    // wrapping it here does not affect the host app tree.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          widget.child,
          // Full-screen inspector layer — self-contained with its own
          // MaterialApp so Navigator / Theme / ScaffoldMessenger are available
          // for the entire inspector flow (sub-routes, sheets, snackbars).
          if (_inspectorOpen)
            Positioned.fill(
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: _buildInspectorTheme(),
                home: LeakRadarScreen(
                  onClose: () => setState(() => _inspectorOpen = false),
                ),
              ),
            ),
          // Badge is hidden while the inspector is open so it does not float
          // above the full-screen layer.
          if (!_inspectorOpen)
            Positioned(
              right: _right,
              bottom: _bottom,
              child: GestureDetector(
                key: const Key('leak_radar_badge'),
                onPanUpdate: (details) {
                  setState(() {
                    _right = (_right - details.delta.dx)
                        .clamp(0, double.infinity);
                    _bottom = (_bottom - details.delta.dy)
                        .clamp(0, double.infinity);
                  });
                },
                onTap: () => setState(() => _inspectorOpen = true),
                onLongPress: () {
                  LeakRadar.scan();
                },
                child: badgeContent,
              ),
            ),
        ],
      ),
    );
  }
}
