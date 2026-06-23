// lib/src/ui/leak_radar_overlay.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../model/leak_kind.dart';
import '../model/leak_report.dart';
import '../leak_radar.dart';
import 'leak_radar_screen.dart';

/// Wraps [child] and floats a draggable badge showing the current worst
/// severity and finding count. Returns [child] unchanged when [show] is false.
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

class _LeakRadarOverlayState extends State<LeakRadarOverlay> {
  static const double _badgeSize = 48.0;
  static const double _initialRight = 16.0;
  static const double _initialBottom = 100.0;

  double _right = _initialRight;
  double _bottom = _initialBottom;

  LeakReport? _report;
  StreamSubscription<LeakReport>? _sub;

  @override
  void initState() {
    super.initState();
    _report = widget.initialReport ?? LeakRadar.latest;
    _sub = LeakRadar.reports.listen((r) {
      if (mounted) setState(() => _report = r);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Color _badgeColor(LeakSeverity s) => switch (s) {
        LeakSeverity.critical => Colors.red,
        LeakSeverity.warning => Colors.orange,
        LeakSeverity.info => Colors.blue,
      };

  @override
  Widget build(BuildContext context) {
    if (!widget.show) return widget.child;

    return Stack(
      children: [
        widget.child,
        Positioned(
          right: _right,
          bottom: _bottom,
          child: GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                _right =
                    (_right - details.delta.dx).clamp(0, double.infinity);
                _bottom =
                    (_bottom - details.delta.dy).clamp(0, double.infinity);
              });
            },
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const LeakRadarScreen(),
                ),
              );
            },
            onLongPress: () {
              LeakRadar.scan();
            },
            child: _Badge(
              key: const Key('leak_radar_badge'),
              report: _report,
              badgeColor: _badgeColor,
              size: _badgeSize,
            ),
          ),
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    super.key,
    required this.report,
    required this.badgeColor,
    required this.size,
  });

  final LeakReport? report;
  final Color Function(LeakSeverity) badgeColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    final r = report;
    final count = r?.findings.length ?? 0;
    final severity = r?.worstSeverity ?? LeakSeverity.info;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: badgeColor(severity),
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        '$count',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
    );
  }
}
