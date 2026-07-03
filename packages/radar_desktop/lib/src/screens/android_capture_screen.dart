import 'package:flutter/material.dart';

import '../android/native_profiling_controller.dart';

/// Entry point for capturing a new heapprofd trace and importing on-disk
/// traces, symbol stores, and FFI allocation logs into the workspace.
///
/// Stub for now; filled in by a later task.
class AndroidCaptureScreen extends StatelessWidget {
  const AndroidCaptureScreen({super.key, required this.controller});

  final NativeProfilingController controller;

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Capture / import — coming soon'));
  }
}
