import 'class_root_profile.dart';
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

  factory GraphAnalysisStats.fromJson(Map<String, Object?> json) =>
      GraphAnalysisStats(
        totalObjects: json['totalObjects'] as int,
        reachableObjects: json['reachableObjects'] as int,
        leakCandidates: json['leakCandidates'] as int,
        clusters: json['clusters'] as int,
        suppressedByAppFilter: json['suppressedByAppFilter'] as int,
        suppressedByLiveTree: json['suppressedByLiveTree'] as int? ?? 0,
        warnings: [for (final w in json['warnings']! as List) w as String],
      );

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

  /// Per-class root-kind breakdown for EVERY reachable class — not just the
  /// leak-prone-rooted ones in [clusters]. See [ClassRootProfile].
  final List<ClassRootProfile> classRootProfiles;

  const GraphAnalysisResult({
    required this.clusters,
    required this.stats,
    this.classRootProfiles = const [],
  });

  factory GraphAnalysisResult.fromJson(Map<String, Object?> json) =>
      GraphAnalysisResult(
        clusters: [
          for (final c in json['clusters']! as List)
            GraphLeakCluster.fromJson((c as Map).cast<String, Object?>()),
        ],
        stats: GraphAnalysisStats.fromJson(
          (json['stats']! as Map).cast<String, Object?>(),
        ),
        classRootProfiles: json['classRootProfiles'] == null
            ? const []
            : [
                for (final p in json['classRootProfiles']! as List)
                  ClassRootProfile.fromJson((p as Map).cast<String, Object?>()),
              ],
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GraphAnalysisResult &&
          stats == other.stats &&
          _listEquals(clusters, other.clusters) &&
          _listEquals(classRootProfiles, other.classRootProfiles);

  @override
  int get hashCode => Object.hash(
    stats,
    Object.hashAll(clusters),
    Object.hashAll(classRootProfiles),
  );

  Map<String, Object?> toJson() => {
    'clusters': [for (final c in clusters) c.toJson()],
    'stats': stats.toJson(),
    'classRootProfiles': [for (final p in classRootProfiles) p.toJson()],
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
