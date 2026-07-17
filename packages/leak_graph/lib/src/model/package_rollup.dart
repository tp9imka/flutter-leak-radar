import '../analysis/class_origin.dart';

/// Which detection source resolved the app-package set for an analysis run.
///
/// Reported so a consumer can label the attribution honestly instead of
/// treating an auto-detected guess as an explicit configuration.
enum AppPackageSource {
  /// `GraphAnalysisOptions.appPackages` was supplied non-empty.
  explicitConfig,

  /// The set was derived from the graph's library URIs.
  autoDetected,

  /// App filtering was disabled; no package was treated as project-owned.
  disabled,
}

/// A short human label for [source], for the "app packages" detection-source
/// line reports print so a reader never mistakes an auto-detected guess (or a
/// disabled filter that classified no ownership) for an explicit configuration.
String appPackageSourceLabel(AppPackageSource source) => switch (source) {
  AppPackageSource.explicitConfig => 'explicit config',
  AppPackageSource.autoDetected => 'auto-detected',
  AppPackageSource.disabled =>
    'disabled (--all: every class reported; ownership not classified)',
};

/// Per-package aggregation of leaked classes for one analysis run.
///
/// Produced twice per run, keyed two different ways (see
/// `GraphAnalysisResult.anchorRollups` / `declaredRollups`): the same leaked
/// set re-keyed by the package that RETAINS it versus the package that
/// DECLARES it. The distinction is what makes a rollup honest — a `dart:core`
/// String held alive by project code is retained by the project but declared
/// by the SDK.
///
/// Population: only leaked records belonging to a REPORTED cluster are rolled
/// up; candidates whose signature was dropped below `minClusterSize` are
/// excluded, so these totals match the run's emitted clusters.
final class PackageRollup {
  /// Package key, e.g. `livekit_client`, `dart:core`, or `(unknown)` when the
  /// declaring/retaining library URI could not be resolved to a package.
  final String package;

  /// Origin classification of [package].
  final ClassOrigin origin;

  /// Distinct leaked classes attributed to [package].
  final int classCount;

  /// RAW retained heap objects attributed to [package] — one per leaked record,
  /// NOT deduped by owner.
  ///
  /// This differs from `GraphLeakCluster.instanceCount`, which counts DISTINCT
  /// attribution owners. Several internal leaves retained by one owner each add
  /// a record here but fold into a single cluster instance, so an anchor
  /// rollup's [instanceCount] may EXCEED the summed `cluster.instanceCount`.
  /// Do not reconcile the two as equal.
  final int instanceCount;

  /// Summed SHALLOW (own) bytes of the attributed instances.
  ///
  /// Labeled shallow deliberately: this library computes no dominator tree, so
  /// it is never presented as a retained-graph size.
  final int shallowBytes;

  /// Distinct reported leak clusters at least one attributed record belongs to
  /// (counted by cluster signature) — unlike [instanceCount], never inflated by
  /// per-owner leaf fan-out.
  final int clusterCount;

  const PackageRollup({
    required this.package,
    required this.origin,
    required this.classCount,
    required this.instanceCount,
    required this.shallowBytes,
    required this.clusterCount,
  });

  factory PackageRollup.fromJson(Map<String, Object?> json) => PackageRollup(
    package: json['package'] as String,
    origin: ClassOrigin.values.byName(json['origin'] as String),
    classCount: json['classCount'] as int,
    instanceCount: json['instanceCount'] as int,
    shallowBytes: json['shallowBytes'] as int,
    clusterCount: json['clusterCount'] as int,
  );

  Map<String, Object?> toJson() => {
    'package': package,
    'origin': origin.name,
    'classCount': classCount,
    'instanceCount': instanceCount,
    'shallowBytes': shallowBytes,
    'clusterCount': clusterCount,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PackageRollup &&
          package == other.package &&
          origin == other.origin &&
          classCount == other.classCount &&
          instanceCount == other.instanceCount &&
          shallowBytes == other.shallowBytes &&
          clusterCount == other.clusterCount;

  @override
  int get hashCode => Object.hash(
    package,
    origin,
    classCount,
    instanceCount,
    shallowBytes,
    clusterCount,
  );
}
