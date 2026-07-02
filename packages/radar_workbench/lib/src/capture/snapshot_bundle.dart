import 'package:leak_graph/leak_graph.dart';

/// Immutable result of a single heap snapshot capture + analysis.
///
/// Contains all data the histogram, diff, retaining-path, and root-grouping
/// views need, bundled together so the UI never holds partial state. Bundles
/// are serialisable ([toJson]) so a capture can be exported to a file and
/// re-loaded ([fromJson]).
final class SnapshotBundle {
  /// Session-local id assigned by [MemoryController] on capture (0 = unset).
  final int id;

  /// Wall-clock time when this snapshot was captured.
  final DateTime capturedAt;

  /// Human-readable label (e.g. "Snapshot 1").
  final String label;

  /// Per-class instance counts derived from the snapshot.
  final List<ClassCount> histogram;

  /// Leak-cluster + per-class root-profile analysis for the snapshot.
  final GraphAnalysisResult analysisResult;

  const SnapshotBundle({
    this.id = 0,
    required this.capturedAt,
    required this.label,
    required this.histogram,
    required this.analysisResult,
  });

  /// Summed shallow (own) bytes across the whole histogram.
  int get shallowBytes => histogram.fold(0, (sum, c) => sum + c.shallowBytes);

  SnapshotBundle copyWith({int? id, String? label}) => SnapshotBundle(
    id: id ?? this.id,
    capturedAt: capturedAt,
    label: label ?? this.label,
    histogram: histogram,
    analysisResult: analysisResult,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'capturedAt': capturedAt.toIso8601String(),
    'label': label,
    'histogram': [for (final c in histogram) c.toJson()],
    'analysis': analysisResult.toJson(),
  };

  factory SnapshotBundle.fromJson(Map<String, Object?> json) => SnapshotBundle(
    id: (json['id'] as num?)?.toInt() ?? 0,
    capturedAt: DateTime.parse(json['capturedAt'] as String),
    label: json['label'] as String? ?? '',
    histogram: [
      for (final e in (json['histogram'] as List? ?? const []))
        ClassCount.fromJson((e as Map).cast<String, Object?>()),
    ],
    analysisResult: GraphAnalysisResult.fromJson(
      (json['analysis'] as Map).cast<String, Object?>(),
    ),
  );

  /// Builds a bundle representing a failed capture/analysis: empty histogram,
  /// empty clusters, and a single warning carrying [message]. Never throws.
  factory SnapshotBundle.failed({
    required String label,
    required String message,
    DateTime? capturedAt,
  }) => SnapshotBundle(
    capturedAt: capturedAt ?? DateTime.now(),
    label: label,
    histogram: const [],
    analysisResult: GraphAnalysisResult(
      clusters: const [],
      stats: GraphAnalysisStats(
        totalObjects: 0,
        reachableObjects: 0,
        leakCandidates: 0,
        clusters: 0,
        suppressedByAppFilter: 0,
        warnings: [message],
      ),
    ),
  );
}
