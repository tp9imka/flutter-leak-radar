import 'class_path_distribution.dart';
import 'class_root_profile.dart';
import 'graph_leak_cluster.dart';
import 'package_rollup.dart';

/// Serialization version stamped into [GraphAnalysisResult.toJson].
///
/// Bumped to 2 when per-package rollups and the detection source were added.
/// An export without the `schemaVersion` key is treated as version 1.
const int kGraphAnalysisResultSchemaVersion = 2;

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

  /// Per-class distribution of instances across distinct shortest retaining
  /// paths, for a bounded set of classes. See [ClassPathDistribution].
  final List<ClassPathDistribution> classPathDistributions;

  /// Leaked instances grouped by the package that RETAINS them (attribution
  /// anchor, falling back to the declaring package when unanchored).
  final List<PackageRollup> anchorRollups;

  /// Leaked instances grouped by the package that DECLARES their class.
  final List<PackageRollup> declaredRollups;

  /// Which detection source resolved the app-package set for this run.
  ///
  /// Null on legacy exports predating package detection.
  final AppPackageSource? appPackageSource;

  /// The resolved project-owned package names for this run (e.g. `['my_app']`).
  ///
  /// Lets a UI classify a row's origin without re-deriving the app-package set:
  /// it is the same `AppPackageSet` the analysis already resolved, so
  /// `origin:project` / `origin:yours` filtering agrees with attribution.
  /// Empty when app filtering was disabled or no package resolved.
  final List<String> resolvedAppPackages;

  const GraphAnalysisResult({
    required this.clusters,
    required this.stats,
    this.classRootProfiles = const [],
    this.classPathDistributions = const [],
    this.anchorRollups = const [],
    this.declaredRollups = const [],
    this.appPackageSource,
    this.resolvedAppPackages = const [],
  });

  factory GraphAnalysisResult.fromJson(
    Map<String, Object?> json,
  ) => GraphAnalysisResult(
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
    classPathDistributions: json['classPathDistributions'] == null
        ? const []
        : [
            for (final d in json['classPathDistributions']! as List)
              ClassPathDistribution.fromJson(
                (d as Map).cast<String, Object?>(),
              ),
          ],
    anchorRollups: json['anchorRollups'] == null
        ? const []
        : [
            for (final r in json['anchorRollups']! as List)
              PackageRollup.fromJson((r as Map).cast<String, Object?>()),
          ],
    declaredRollups: json['declaredRollups'] == null
        ? const []
        : [
            for (final r in json['declaredRollups']! as List)
              PackageRollup.fromJson((r as Map).cast<String, Object?>()),
          ],
    appPackageSource: json['appPackageSource'] == null
        ? null
        : AppPackageSource.values.byName(json['appPackageSource'] as String),
    resolvedAppPackages: json['resolvedAppPackages'] == null
        ? const []
        : [for (final p in json['resolvedAppPackages']! as List) p as String],
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GraphAnalysisResult &&
          stats == other.stats &&
          appPackageSource == other.appPackageSource &&
          _listEquals(clusters, other.clusters) &&
          _listEquals(classRootProfiles, other.classRootProfiles) &&
          _listEquals(classPathDistributions, other.classPathDistributions) &&
          _listEquals(anchorRollups, other.anchorRollups) &&
          _listEquals(declaredRollups, other.declaredRollups) &&
          _listEquals(resolvedAppPackages, other.resolvedAppPackages);

  @override
  int get hashCode => Object.hash(
    stats,
    appPackageSource,
    Object.hashAll(clusters),
    Object.hashAll(classRootProfiles),
    Object.hashAll(classPathDistributions),
    Object.hashAll(anchorRollups),
    Object.hashAll(declaredRollups),
    Object.hashAll(resolvedAppPackages),
  );

  Map<String, Object?> toJson() => {
    'schemaVersion': kGraphAnalysisResultSchemaVersion,
    'clusters': [for (final c in clusters) c.toJson()],
    'stats': stats.toJson(),
    'classRootProfiles': [for (final p in classRootProfiles) p.toJson()],
    'classPathDistributions': [
      for (final d in classPathDistributions) d.toJson(),
    ],
    'anchorRollups': [for (final r in anchorRollups) r.toJson()],
    'declaredRollups': [for (final r in declaredRollups) r.toJson()],
    if (appPackageSource != null) 'appPackageSource': appPackageSource!.name,
    'resolvedAppPackages': [...resolvedAppPackages],
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
