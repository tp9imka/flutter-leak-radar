import 'package:flutter/material.dart';

import '../android/native_profiling_controller.dart';

/// Point-in-time diff between two imported native-heap checkpoints.
///
/// Stub for now; filled in by a later task.
class AndroidCompareScreen extends StatelessWidget {
  const AndroidCompareScreen({super.key, required this.controller});

  final NativeProfilingController controller;

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Compare — coming soon'));
  }
}
