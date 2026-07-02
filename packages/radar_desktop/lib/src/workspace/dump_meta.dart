/// Where a dump came from.
enum DumpSource { file, capture }

/// Row metadata for a dump in the workspace table (derived from a
/// `SnapshotBundle`, kept alongside it so the table renders without recomputing).
class DumpMeta {
  const DumpMeta({
    required this.id,
    required this.label,
    required this.source,
    required this.capturedAt,
    required this.classCount,
    required this.retainedBytes,
  });

  final int id;
  final String label;
  final DumpSource source;
  final DateTime capturedAt;
  final int classCount;
  final int retainedBytes;
}
