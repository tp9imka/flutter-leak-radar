import 'package:flutter/material.dart';

import 'perf_radar_view.dart';

/// Full-screen inspector — Scaffold + AppBar wrapping [PerfRadarView].
///
/// Push directly via [Navigator] or supply [onClose] for the overlay
/// inspector pattern.
class PerfRadarScreen extends StatelessWidget {
  /// Creates a [PerfRadarScreen].
  const PerfRadarScreen({super.key, this.onClose});

  /// Called when the user taps the leading close button.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
          'Perf Radar',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFFe7eef0),
          ),
        ),
      ),
      body: const PerfRadarView(),
    );
  }
}
