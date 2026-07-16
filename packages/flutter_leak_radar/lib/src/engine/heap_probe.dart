// lib/src/engine/heap_probe.dart
import '../model/retaining_path.dart';
import 'class_sample.dart';
import 'vm_service_status.dart';

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

/// Optional capability for probes that can name the app's root-library
/// package via a VM-service RPC. Used by the engine's project-package
/// detection chain. Probes without a VM connection (e.g. [NoopHeapProbe]) do
/// not implement it, and the chain falls through to auto-detection.
abstract interface class RootLibrarySource {
  /// The first path segment of the app's root-library `package:` URI (one
  /// `getIsolate` RPC on the existing connection), or null when unreachable
  /// (common on physical devices), not a `package:` URI, or on any error.
  /// Never throws.
  Future<String?> rootLibraryPackage();
}

/// Optional capability for probes backed by a VM-service connection: live
/// connection state plus a manual reconnect. The engine surfaces these so the
/// dashboard can show whether the per-scan allocation-profile (growth) source
/// is live and let the user retry it. Probes without a VM connection (e.g.
/// [NoopHeapProbe]) simply do not implement it.
abstract interface class VmConnectable {
  /// Whether the probe currently holds a live VM-service connection.
  bool get isConnected;

  /// Typed status of the VM-service connection.
  VmServiceStatus get vmStatus;

  /// Attempts to connect now, bypassing the reconnect back-off. Returns whether
  /// the probe is connected afterwards. Never throws.
  Future<bool> reconnect();
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
