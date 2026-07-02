import '../capture/snapshot_bundle.dart';

/// Produces a fully-analyzed [SnapshotBundle] from a live connection.
///
/// File import is NOT a [SnapshotSource] — it lives host-side and feeds
/// [SnapshotAnalyzer.fromBytes] directly. Implementations never throw; they
/// return a bundle carrying an error result on failure.
abstract interface class SnapshotSource {
  Future<SnapshotBundle> capture({String label = ''});
}
