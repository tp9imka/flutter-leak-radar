// lib/src/radar_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_leak_radar/flutter_leak_radar.dart';
import 'package:flutter_perf_radar/flutter_perf_radar.dart';

/// Unified inspector screen for the full Radar suite.
///
/// Presents a two-tab layout: **Leaks** (powered by [LeakRadarView]) and
/// **Performance** (powered by [PerfRadarView]). Each tab body is fully
/// self-contained — it owns its own data subscription and refresh logic.
///
/// Use [onClose] when launching from an overlay to dismiss the inspector:
/// ```dart
/// Navigator.of(context).push(
///   MaterialPageRoute(builder: (_) => const RadarScreen()),
/// );
/// ```
class RadarScreen extends StatelessWidget {
  const RadarScreen({super.key, this.onClose});

  /// Called when the user taps the leading close button.
  /// When null, no close button is shown.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFF0a0d0e),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0c1012),
          foregroundColor: const Color(0xFFe7eef0),
          elevation: 0,
          leading: onClose != null
              ? IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFFe7eef0)),
                  tooltip: 'Close',
                  onPressed: onClose,
                )
              : null,
          title: const Text(
            'Radar',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFFe7eef0),
            ),
          ),
          bottom: const TabBar(
            labelColor: Color(0xFF2fe39b),
            unselectedLabelColor: Color(0xFF7d8e94),
            indicatorColor: Color(0xFF2fe39b),
            tabs: [
              Tab(text: 'Leaks'),
              Tab(text: 'Performance'),
            ],
          ),
        ),
        body: const TabBarView(children: [LeakRadarView(), PerfRadarView()]),
      ),
    );
  }
}
