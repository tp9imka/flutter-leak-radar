import 'package:flutter/material.dart';

import '../android/native_profiling_controller.dart';

/// Android native-profiling session view: overview of imported heapprofd
/// checkpoints, symbol store, and FFI log for the active workspace.
///
/// Stub for now; filled in by a later task.
class AndroidSessionScreen extends StatelessWidget {
  const AndroidSessionScreen({super.key, required this.controller});

  final NativeProfilingController controller;

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Session — coming soon'));
  }
}
