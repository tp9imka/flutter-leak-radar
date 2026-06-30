// lib/src/ui/stability_screen.dart
import 'package:flutter/material.dart';
import 'package:radar_ui/radar_ui.dart';

import 'stability_view.dart';

/// Full-screen Stability inspector — Scaffold + AppBar wrapping [StabilityView].
///
/// Push directly via [Navigator] or supply [onClose] for the overlay
/// inspector pattern.
class StabilityScreen extends StatelessWidget {
  /// Creates a [StabilityScreen].
  const StabilityScreen({super.key, this.onClose});

  /// Called when the user taps the leading close button.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RadarColors.bgPage,
      appBar: AppBar(
        backgroundColor: RadarColors.bgPanel,
        foregroundColor: RadarColors.text100,
        elevation: 0,
        leading: onClose != null
            ? IconButton(
                icon: const Icon(Icons.close, color: RadarColors.text100),
                tooltip: 'Close',
                onPressed: onClose,
              )
            : null,
        title: Text('Stability', style: RadarTypography.appBarTitle),
      ),
      body: const StabilityView(),
    );
  }
}
