import 'package:radar_workbench/radar_workbench.dart';

/// Offline stand-in for a live capture source. `MemoryController` requires a
/// [SnapshotSource], but the offline desktop never calls `capture()` (it
/// imports pre-analyzed bundles via `MemoryController.addBundle`). If it is
/// called, it fails cleanly rather than throwing.
class OfflineSnapshotSource implements SnapshotSource {
  const OfflineSnapshotSource();

  @override
  Future<SnapshotBundle> capture({String label = ''}) async =>
      SnapshotBundle.failed(
        label: label,
        message: 'Offline — connect a VM service to capture live heaps.',
      );
}
