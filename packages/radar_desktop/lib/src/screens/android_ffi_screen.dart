import 'package:flutter/material.dart';

import '../android/native_profiling_controller.dart';

/// FFI allocation-log view: outstanding native allocations made through the
/// Dart FFI boundary, from the imported [NativeProfilingController.ffiLog].
///
/// Stub for now; filled in by a later task.
class AndroidFfiScreen extends StatelessWidget {
  const AndroidFfiScreen({super.key, required this.controller});

  final NativeProfilingController controller;

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('ffi allocations — coming soon'));
  }
}
