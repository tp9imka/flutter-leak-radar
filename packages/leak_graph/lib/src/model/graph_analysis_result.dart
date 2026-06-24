import 'graph_leak_cluster.dart';

/// Aggregate counts and diagnostics from a single analysis run.
final class GraphAnalysisStats {
  final int totalObjects;
  final int reachableObjects;
  final int leakCandidates;
  final int clusters;
  final int suppressedByAppFilter;
  final int suppressedByLiveTree;
  final List<String> warnings;

  const GraphAnalysisStats({
    required this.totalObjects,
    required this.reachableObjects,
    required this.leakCandidates,
    required this.clusters,
    required this.suppressedByAppFilter,
    this.suppressedByLiveTree = 0,
    required this.warnings,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GraphAnalysisStats &&
          totalObjects == other.totalObjects &&
          reachableObjects == other.reachableObjects &&
          leakCandidates == other.leakCandidates &&
          clusters == other.clusters &&
          suppressedByAppFilter == other.suppressedByAppFilter &&
          suppressedByLiveTree == other.suppressedByLiveTree &&
          _listEquals(warnings, other.warnings);

  @override
  int get hashCode => Object.hash(
    totalObjects,
    reachableObjects,
    leakCandidates,
    clusters,
    suppressedByAppFilter,
    suppressedByLiveTree,
    Object.hashAll(warnings),
  );

  Map<String, Object?> toJson() => {
    'totalObjects': totalObjects,
    'reachableObjects': reachableObjects,
    'leakCandidates': leakCandidates,
    'clusters': clusters,
    'suppressedByAppFilter': suppressedByAppFilter,
    'suppressedByLiveTree': suppressedByLiveTree,
    'warnings': [...warnings],
  };
}

/// Top-level output of a heap analysis: detected clusters and run statistics.
final class GraphAnalysisResult {
  final List<GraphLeakCluster> clusters;
  final GraphAnalysisStats stats;

  const GraphAnalysisResult({required this.clusters, required this.stats});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GraphAnalysisResult &&
          stats == other.stats &&
          _listEquals(clusters, other.clusters);

  @override
  int get hashCode => Object.hash(stats, Object.hashAll(clusters));

  Map<String, Object?> toJson() => {
    'clusters': [for (final c in clusters) c.toJson()],
    'stats': stats.toJson(),
  };
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
