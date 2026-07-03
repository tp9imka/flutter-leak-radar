import 'package:flutter/material.dart';

import '../android/native_profiling_controller.dart';

/// Still-live table for the selected native-heap checkpoint, rolled up by
/// module and symbolized when a symbol store has been imported.
///
/// Stub for now; filled in by a later task.
class AndroidNativeScreen extends StatelessWidget {
  const AndroidNativeScreen({super.key, required this.controller});

  final NativeProfilingController controller;

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Native still-live — coming soon'));
  }
}
