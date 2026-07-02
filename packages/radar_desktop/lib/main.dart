import 'package:flutter/material.dart';
import 'package:radar_ui/radar_ui.dart';

void main() {
  runApp(const RadarDesktopApp());
}

/// Placeholder app — the real window shell arrives in Task 7.
class RadarDesktopApp extends StatelessWidget {
  const RadarDesktopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: radarDarkTheme(),
      home: const Scaffold(body: Center(child: Text('Radar Desktop'))),
    );
  }
}
