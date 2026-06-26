import 'dart:ui';

import 'package:flutter/material.dart';

import 'perf_radar_screen.dart';

/// Draggable pill badge that floats above the app and opens [PerfRadarScreen].
class PerfRadarOverlay extends StatefulWidget {
  const PerfRadarOverlay({super.key, required this.child});

  final Widget child;

  @override
  State<PerfRadarOverlay> createState() => _PerfRadarOverlayState();
}

class _PerfRadarOverlayState extends State<PerfRadarOverlay> {
  static const double _initialRight = 16.0;
  static const double _initialBottom = 100.0;

  double _right = _initialRight;
  double _bottom = _initialBottom;
  bool _inspectorOpen = false;

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
    final pill = ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 13),
          decoration: BoxDecoration(
            color: const Color.fromRGBO(47, 227, 155, 0.15),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color.fromRGBO(47, 227, 155, 0.45)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x44000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('⚡', style: TextStyle(fontSize: 14)),
              SizedBox(width: 6),
              Text(
                'Perf',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
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
                home: PerfRadarScreen(
                  onClose: () => setState(() => _inspectorOpen = false),
                ),
              ),
            ),
          if (!_inspectorOpen)
            Positioned(
              right: _right,
              bottom: _bottom,
              child: GestureDetector(
                key: const Key('perf_radar_badge'),
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
