import '../capture/snapshot_bundle.dart';

/// Writes a [SnapshotBundle] out of the app: a browser download in DevTools,
/// a native save dialog on desktop.
abstract interface class SnapshotExporter {
  Future<void> export(SnapshotBundle bundle, {String? suggestedName});
}
