// lib/src/engine/heap_probe.dart
import '../model/retaining_path.dart';
import 'class_sample.dart';

/// Abstraction over a heap source. Only [VmHeapProbe] talks to vm_service.
abstract interface class HeapProbe {
  Future<bool> get isAvailable;
  Future<HeapSnapshot> capture({required bool forceGc});
  Future<RetainingPathView?> retainingPath(
    String className, {
    int maxInstances,
  });
  Future<void> dispose();
}

/// Used when no VM service is reachable. The engine then runs precise-only.
class NoopHeapProbe implements HeapProbe {
  const NoopHeapProbe();

  @override
  Future<bool> get isAvailable async => false;

  @override
  Future<HeapSnapshot> capture({required bool forceGc}) async =>
      HeapSnapshot(samples: const <ClassSample>[], capturedAt: DateTime.now());

  @override
  Future<RetainingPathView?> retainingPath(
    String className, {
    int maxInstances = 10,
  }) async => null;

  @override
  Future<void> dispose() async {}
}
