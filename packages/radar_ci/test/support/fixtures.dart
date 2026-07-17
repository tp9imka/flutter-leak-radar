import 'package:leak_graph/leak_graph.dart';
import 'package:radar_ci/radar_ci.dart';
import 'package:radar_trace/radar_trace.dart';

/// In-memory fixtures for the gate/report command tests.
///
/// Everything here is synthesised so the tests never touch a real VM, heap
/// snapshot, or file system — an injected [InMemoryFiles] plays the disk.

/// A tiny fake file system for the injectable `readText`/`writeText` seams.
final class InMemoryFiles {
  InMemoryFiles([Map<String, String>? seed]) : store = {...?seed};

  /// Path → contents.
  final Map<String, String> store;

  /// A `TextReader` that throws when a path is unknown, mirroring a real
  /// [FileSystemException] the commands map to a tool failure.
  Future<String> read(String path) async {
    final contents = store[path];
    if (contents == null) {
      throw _MissingFile('no such file', path);
    }
    return contents;
  }

  /// A `TextWriter` capturing writes for later assertion.
  Future<void> write(String path, String contents) async {
    store[path] = contents;
  }
}

final class _MissingFile implements Exception {
  const _MissingFile(this.message, this.path);
  final String message;
  final String path;
  @override
  String toString() => 'FileSystemException: $message, path = $path';
}

/// A flat, strictly monotonic byte series that [assessSeries] certifies as
/// [SeriesVerdict.monotonicGrowth] (>= 12 post-settle samples, low noise).
MetricSeries growthSeries(String name) {
  const start = 1000000000000; // 1e12 micros
  const stepMicros = 20 * 1000000; // 20s between samples
  return MetricSeries(
    name: name,
    unit: 'bytes',
    samples: [
      for (var i = 0; i < 18; i++)
        MetricSample(
          tMicros: start + i * stepMicros,
          value: 100000000 + i * 2000000.0,
        ),
    ],
  );
}

/// A flat series [assessSeries] reads as a bounded [SeriesVerdict.plateau].
MetricSeries flatSeries(String name) {
  const start = 1000000000000;
  const stepMicros = 20 * 1000000;
  return MetricSeries(
    name: name,
    unit: 'bytes',
    samples: [
      for (var i = 0; i < 18; i++)
        MetricSample(tMicros: start + i * stepMicros, value: 100000000.0),
    ],
  );
}

/// A short series (< 8 post-settle samples) that reads insufficientData.
MetricSeries shortSeries(String name) {
  const start = 1000000000000;
  const stepMicros = 20 * 1000000;
  return MetricSeries(
    name: name,
    unit: 'bytes',
    samples: [
      for (var i = 0; i < 3; i++)
        MetricSample(tMicros: start + i * stepMicros, value: 100000000.0 + i),
    ],
  );
}

/// A leak cluster with a stable [signature], attributed to [package].
GraphLeakCluster cluster({
  required String signature,
  required String className,
  required String package,
  int instanceCount = 5,
  int retainedShallowBytes = 4096,
  LeakConfidence confidence = LeakConfidence.heuristic,
}) => GraphLeakCluster(
  className: className,
  libraryUri: Uri.parse('package:$package/$package.dart'),
  instanceCount: instanceCount,
  retainedShallowBytes: retainedShallowBytes,
  representativePath: GraphRetainingPath(
    hops: [GraphHop(className: className)],
    rootKind: RootKind.staticOrGlobal,
  ),
  rootKind: RootKind.staticOrGlobal,
  confidence: confidence,
  signature: signature,
);

/// An analysis result over [clusters] whose app-package set resolves
/// [projectPackages] as project-owned (drives origin classification).
GraphAnalysisResult analysis({
  required List<GraphLeakCluster> clusters,
  Set<String> projectPackages = const {'my_app'},
}) {
  final rollups = <String, PackageRollup>{};
  for (final c in clusters) {
    final pkg = c.libraryUri!.pathSegments.first;
    final origin = projectPackages.contains(pkg)
        ? ClassOrigin.project
        : ClassOrigin.dependency;
    final prior = rollups[pkg];
    rollups[pkg] = PackageRollup(
      package: pkg,
      origin: origin,
      classCount: (prior?.classCount ?? 0) + 1,
      instanceCount: (prior?.instanceCount ?? 0) + c.instanceCount,
      shallowBytes: (prior?.shallowBytes ?? 0) + c.retainedShallowBytes,
      clusterCount: (prior?.clusterCount ?? 0) + 1,
    );
  }
  return GraphAnalysisResult(
    clusters: clusters,
    stats: GraphAnalysisStats(
      totalObjects: 1000,
      reachableObjects: 900,
      leakCandidates: clusters.length,
      clusters: clusters.length,
      suppressedByAppFilter: 0,
      warnings: const [],
    ),
    anchorRollups: rollups.values.toList(),
    declaredRollups: rollups.values.toList(),
    appPackageSource: AppPackageSource.explicitConfig,
    resolvedAppPackages: projectPackages.toList()..sort(),
  );
}

/// A run document carrying [series] and a single end checkpoint that
/// references [analysisPath] when non-null.
RadarRunDocument runDoc({
  List<MetricSeries> series = const [],
  String? analysisPath,
  bool completed = true,
  String? abortReason,
}) => RadarRunDocument(
  metadata: RunMetadata(
    startedAt: DateTime.utc(2026),
    completed: completed,
    abortReason: abortReason,
  ),
  series: series,
  checkpoints: [
    RunCheckpoint(
      tMicros: 1000000000000,
      label: 'end',
      allocationTopN: const {'String': 3},
      analysisPath: analysisPath,
      snapshotPath: analysisPath == null ? null : 'end.data',
    ),
  ],
);
