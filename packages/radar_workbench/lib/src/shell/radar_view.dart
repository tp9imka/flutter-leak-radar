/// All navigation destinations in the Radar DevTools extension left rail.
///
/// Values in [memory] map to the existing memory views; values in
/// [performance] and [stability] map to the new PerfRadar views.
enum RadarView {
  // ── Memory ────────────────────────────────────────────────────────────────
  /// Snapshot capture → exercise → capture → diff workflow.
  snapshotDiff,

  /// Full class histogram for the most recent snapshot.
  classHistogram,

  /// Retaining paths derived from the latest diff's grown classes.
  retainingPaths,

  /// Ranked leak clusters (the analyzer's highest-signal output) + warnings.
  leakClusters,

  // ── Performance ───────────────────────────────────────────────────────────
  /// Dense sortable+searchable traces table.
  traces,

  /// Jank stats + frame-time timeline.
  frames,

  // ── Stability ─────────────────────────────────────────────────────────────
  /// Recent errors table with stack-trace detail.
  errors,

  /// Recent stalls list with duration colour-grading.
  stalls;

  /// Whether this destination belongs to the Performance section.
  bool get isPerf => this == traces || this == frames;

  /// Whether this destination belongs to the Stability section.
  bool get isStability => this == errors || this == stalls;

  /// Whether this destination requires PerfRadar data.
  bool get needsPerf => isPerf || isStability;
}
