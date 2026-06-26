import 'package:leak_graph/leak_graph.dart';

/// Immutable result of a single heap snapshot capture + analysis.
///
/// Contains all data needed by the histogram, diff, and clusters views,
/// bundled together so the UI never holds partial state.
final class SnapshotBundle {
  /// Wall-clock time when this snapshot was captured.
  final DateTime capturedAt;

  /// Human-readable label chosen by the user (e.g. "Before", "After").
  final String label;

  /// Per-class instance counts derived from the snapshot.
  final List<ClassCount> histogram;

  /// Leak cluster analysis result for the snapshot.
  final GraphAnalysisResult analysisResult;

  const SnapshotBundle({
    required this.capturedAt,
    required this.label,
    required this.histogram,
    required this.analysisResult,
  });
}
