import 'package:flutter/material.dart';
import 'package:radar_ui/radar_ui.dart';

/// A minimal showcase of the radar_ui design system: the dark theme plus a few
/// of the dense dashboard primitives the Radar suite is built from.
void main() => runApp(const RadarUiExampleApp());

class RadarUiExampleApp extends StatelessWidget {
  const RadarUiExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: radarDarkTheme(),
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const RadarTag(label: 'CRITICAL', color: RadarColors.critical),
              const SizedBox(height: 16),
              const RadarMetricTile(
                label: 'jank frames',
                value: '3',
                color: RadarColors.warning,
              ),
              const SizedBox(height: 16),
              RadarFilterChip(
                label: 'hot / dup',
                selected: true,
                onSelected: () {},
              ),
            ],
          ),
        ),
      ),
    );
  }
}
