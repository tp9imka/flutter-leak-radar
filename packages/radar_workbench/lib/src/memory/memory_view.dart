/// Navigation destinations within the Memory section of the rail.
enum MemoryView {
  /// Snapshot capture → exercise → capture → diff workflow.
  snapshotDiff,

  /// Full class histogram for the most recent snapshot.
  classHistogram,

  /// Retaining paths derived from the latest diff's grown classes.
  retainingPaths,
}
