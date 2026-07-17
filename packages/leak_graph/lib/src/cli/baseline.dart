/// Baseline capture, comparison, and CI gate evaluation for leak analysis.
///
/// A [LeakBaseline] is a durable, signature-keyed snapshot of an analysis run.
/// [compareToBaseline] classifies each current cluster against it and
/// [evaluateGate] turns a comparison plus [GateOptions] into a pass/fail
/// verdict a CI pipeline can trust. Every function here is pure so the same
/// logic can back the `analyze` CLI now and `radar_ci` later.
library;

import '../model/graph_analysis_result.dart';
import '../model/graph_leak_cluster.dart';
import '../model/root_kind.dart';

/// Serialization version stamped into [LeakBaseline.toJson].
///
/// A baseline without the `schemaVersion` key is treated as this version
/// (legacy-tolerant): version 1 is the first and only baseline format.
const int kLeakBaselineSchemaVersion = 1;

/// Whether a baseline stamped [schemaVersion] can be compared against a current
/// run by this tool version.
///
/// Comparable when the version equals the known [kLeakBaselineSchemaVersion].
/// A newer major version (from a future tool) or a nonsensical older one is
/// NOT comparable — callers must then treat the baseline as absent rather than
/// classifying every current cluster as new (the "never all-NEW" contract).
bool isBaselineComparable(int schemaVersion) =>
    schemaVersion == kLeakBaselineSchemaVersion;

/// One cluster recorded in a [LeakBaseline], keyed by its path [signature].
final class BaselineCluster {
  final String signature;
  final String className;
  final int instanceCount;
  final int retainedShallowBytes;

  const BaselineCluster({
    required this.signature,
    required this.className,
    required this.instanceCount,
    required this.retainedShallowBytes,
  });

  /// Records [cluster] as a baseline entry.
  factory BaselineCluster.fromCluster(GraphLeakCluster cluster) =>
      BaselineCluster(
        signature: cluster.signature,
        className: cluster.className,
        instanceCount: cluster.instanceCount,
        retainedShallowBytes: cluster.retainedShallowBytes,
      );

  factory BaselineCluster.fromJson(Map<String, Object?> json) =>
      BaselineCluster(
        signature: json['signature'] as String,
        className: json['className'] as String,
        instanceCount: json['instanceCount'] as int,
        retainedShallowBytes: json['retainedShallowBytes'] as int,
      );

  Map<String, Object?> toJson() => {
    'signature': signature,
    'className': className,
    'instanceCount': instanceCount,
    'retainedShallowBytes': retainedShallowBytes,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BaselineCluster &&
          signature == other.signature &&
          className == other.className &&
          instanceCount == other.instanceCount &&
          retainedShallowBytes == other.retainedShallowBytes;

  @override
  int get hashCode =>
      Object.hash(signature, className, instanceCount, retainedShallowBytes);
}

/// A durable snapshot of a prior analysis run, keyed by cluster signature.
///
/// Baselines key on [GraphLeakCluster.signature], the byte-stable path
/// signature pinned by the analysis signature tripwire. Later runs compare
/// against this to surface new or grown clusters.
final class LeakBaseline {
  final int schemaVersion;
  final DateTime createdAt;
  final Map<String, BaselineCluster> clustersBySignature;

  const LeakBaseline({
    required this.schemaVersion,
    required this.createdAt,
    required this.clustersBySignature,
  });

  /// Builds a baseline from an analysis [result] captured at [createdAt].
  ///
  /// When two clusters share a signature (should not happen for a normal run)
  /// the last one wins, matching map-insertion semantics.
  factory LeakBaseline.fromResult(
    GraphAnalysisResult result, {
    required DateTime createdAt,
  }) => LeakBaseline(
    schemaVersion: kLeakBaselineSchemaVersion,
    createdAt: createdAt,
    clustersBySignature: {
      for (final c in result.clusters)
        c.signature: BaselineCluster.fromCluster(c),
    },
  );

  /// Parses a baseline from JSON, tolerating a missing `schemaVersion`.
  ///
  /// An absent version defaults to [kLeakBaselineSchemaVersion] (legacy
  /// tolerance). This does not itself reject incompatible versions — callers
  /// gate on [isBaselineComparable] so an incomparable baseline can be reported
  /// and treated as absent instead of silently mis-compared.
  factory LeakBaseline.fromJson(Map<String, Object?> json) {
    final clusters = (json['clusters'] as List? ?? const [])
        .map(
          (c) => BaselineCluster.fromJson((c as Map).cast<String, Object?>()),
        )
        .toList();
    return LeakBaseline(
      schemaVersion:
          json['schemaVersion'] as int? ?? kLeakBaselineSchemaVersion,
      createdAt: DateTime.parse(json['createdAt'] as String),
      clustersBySignature: {for (final c in clusters) c.signature: c},
    );
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'createdAt': createdAt.toIso8601String(),
    'clusters': [for (final c in clustersBySignature.values) c.toJson()],
  };
}

/// Whether a current cluster is new, unchanged, or grown vs a baseline.
enum ClusterNovelty { newCluster, known, grown }

/// A single current cluster classified against a baseline.
final class ClusterDelta {
  final GraphLeakCluster cluster;
  final ClusterNovelty novelty;

  /// Current instance count minus the baseline's (full count when new).
  final int instanceDelta;

  /// Current retained shallow bytes minus the baseline's (full when new).
  final int bytesDelta;

  /// For a [ClusterNovelty.newCluster]: the closest baseline signature by
  /// shared-hop-token overlap, or null when the best overlap is below 0.5.
  /// Always null for known/grown clusters (they already matched a baseline).
  final String? nearestKnownSignature;

  const ClusterDelta({
    required this.cluster,
    required this.novelty,
    required this.instanceDelta,
    required this.bytesDelta,
    required this.nearestKnownSignature,
  });
}

/// The result of classifying a current run against a baseline.
final class BaselineComparison {
  /// True when a comparable baseline was supplied. When false the baseline was
  /// absent or incomparable: [deltas]/[gone] make no novelty claims and only
  /// baseline-independent gates may be evaluated (the "never all-NEW" rule).
  final bool baselineComparable;

  /// One delta per current cluster. Empty when [baselineComparable] is false —
  /// no novelty is asserted without a comparable baseline.
  final List<ClusterDelta> deltas;

  /// Baseline clusters absent from the current run. Empty when incomparable.
  final List<BaselineCluster> gone;

  /// Summed retained shallow bytes of the CURRENT run's clusters.
  final int currentTotalShallowBytes;

  /// Summed retained shallow bytes recorded in the baseline (0 when absent).
  final int baselineTotalShallowBytes;

  /// The current run's clusters, always available for baseline-independent
  /// gates (e.g. total cluster count) regardless of [baselineComparable].
  final List<GraphLeakCluster> currentClusters;

  const BaselineComparison({
    required this.baselineComparable,
    required this.deltas,
    required this.gone,
    required this.currentTotalShallowBytes,
    required this.baselineTotalShallowBytes,
    required this.currentClusters,
  });

  /// A comparison for when no comparable baseline exists.
  ///
  /// Carries the current clusters so baseline-independent gates still run, but
  /// asserts nothing about novelty or growth.
  factory BaselineComparison.withoutBaseline(GraphAnalysisResult current) =>
      BaselineComparison(
        baselineComparable: false,
        deltas: const [],
        gone: const [],
        currentTotalShallowBytes: _sumShallow(current.clusters),
        baselineTotalShallowBytes: 0,
        currentClusters: current.clusters,
      );

  /// Total retained-shallow-byte growth of the current run over the baseline.
  int get heapGrowthBytes =>
      currentTotalShallowBytes - baselineTotalShallowBytes;
}

/// Classifies each cluster in [current] against [baseline].
///
/// Known clusters (matched by signature) carry their instance/byte deltas;
/// unmatched current clusters are new and carry their full count as growth,
/// annotated with the nearest baseline signature when the overlap is high
/// enough (see [nearestKnownSignature]). Baseline clusters with no current
/// match are listed in [BaselineComparison.gone].
BaselineComparison compareToBaseline(
  GraphAnalysisResult current,
  LeakBaseline baseline,
) {
  final knownSignatures = baseline.clustersBySignature.keys.toList();
  final seen = <String>{};
  final deltas = <ClusterDelta>[];

  for (final cluster in current.clusters) {
    final match = baseline.clustersBySignature[cluster.signature];
    if (match == null) {
      deltas.add(
        ClusterDelta(
          cluster: cluster,
          novelty: ClusterNovelty.newCluster,
          instanceDelta: cluster.instanceCount,
          bytesDelta: cluster.retainedShallowBytes,
          nearestKnownSignature: nearestKnownSignature(
            cluster.signature,
            knownSignatures,
          ),
        ),
      );
      continue;
    }
    seen.add(cluster.signature);
    final instanceDelta = cluster.instanceCount - match.instanceCount;
    deltas.add(
      ClusterDelta(
        cluster: cluster,
        novelty: instanceDelta > 0
            ? ClusterNovelty.grown
            : ClusterNovelty.known,
        instanceDelta: instanceDelta,
        bytesDelta: cluster.retainedShallowBytes - match.retainedShallowBytes,
        nearestKnownSignature: null,
      ),
    );
  }

  final gone = [
    for (final entry in baseline.clustersBySignature.entries)
      if (!seen.contains(entry.key)) entry.value,
  ];

  return BaselineComparison(
    baselineComparable: true,
    deltas: deltas,
    gone: gone,
    currentTotalShallowBytes: _sumShallow(current.clusters),
    baselineTotalShallowBytes: baseline.clustersBySignature.values.fold(
      0,
      (sum, c) => sum + c.retainedShallowBytes,
    ),
    currentClusters: current.clusters,
  );
}

/// The [known] signature with the highest shared-hop-token overlap to
/// [signature], or null when the best overlap is below 0.5.
///
/// Signatures are split on `>` into hop tokens and compared with a multiset
/// Jaccard index (min-over-max on per-token counts). This is the cheapest
/// honest "closest known leak" metric: it never fabricates a match, only
/// reports one when at least half the token mass is shared. Ties resolve to the
/// lexicographically smallest signature so the choice is deterministic.
String? nearestKnownSignature(String signature, Iterable<String> known) {
  final target = _tokenCounts(signature);
  String? best;
  var bestScore = -1.0;
  for (final candidate in known) {
    final score = _multisetJaccard(target, _tokenCounts(candidate));
    if (score > bestScore ||
        (score == bestScore &&
            (best == null || candidate.compareTo(best) < 0))) {
      bestScore = score;
      best = candidate;
    }
  }
  if (best == null || bestScore < 0.5) return null;
  return best;
}

Map<String, int> _tokenCounts(String signature) {
  final counts = <String, int>{};
  for (final token in signature.split('>')) {
    counts[token] = (counts[token] ?? 0) + 1;
  }
  return counts;
}

double _multisetJaccard(Map<String, int> a, Map<String, int> b) {
  final keys = {...a.keys, ...b.keys};
  var intersection = 0;
  var union = 0;
  for (final key in keys) {
    final ca = a[key] ?? 0;
    final cb = b[key] ?? 0;
    intersection += ca < cb ? ca : cb;
    union += ca > cb ? ca : cb;
  }
  return union == 0 ? 0 : intersection / union;
}

/// Threshold configuration for a CI gate.
///
/// A null threshold is not gated. [minConfidence] restricts every count to
/// clusters at or above that confidence. Baseline-dependent thresholds
/// ([maxNewClusters], [maxClassGrowthInstances], [maxHeapGrowthBytes]) require
/// a comparable baseline; [maxTotalClusters] does not.
final class GateOptions {
  final int? maxNewClusters;
  final int? maxTotalClusters;
  final int? maxClassGrowthInstances;
  final int? maxHeapGrowthBytes;
  final LeakConfidence minConfidence;

  const GateOptions({
    this.maxNewClusters,
    this.maxTotalClusters,
    this.maxClassGrowthInstances,
    this.maxHeapGrowthBytes,
    this.minConfidence = LeakConfidence.heuristic,
  });

  /// Whether any threshold requires a comparable baseline to evaluate.
  bool get requiresBaseline =>
      maxNewClusters != null ||
      maxClassGrowthInstances != null ||
      maxHeapGrowthBytes != null;
}

/// The verdict of a gate evaluation.
final class GateResult {
  final bool passed;
  final List<String> violations;

  const GateResult({required this.passed, required this.violations});
}

/// Evaluates [opts] against [cmp], returning a pass/fail verdict with a
/// human-readable list of every threshold that was exceeded.
///
/// Throws [StateError] when a baseline-dependent threshold is requested against
/// a comparison whose baseline is not comparable — callers must resolve that to
/// their own refusal (never a silent pass or an all-NEW gate failure) before
/// calling. The baseline-independent [GateOptions.maxTotalClusters] is always
/// evaluable.
GateResult evaluateGate(BaselineComparison cmp, GateOptions opts) {
  if (opts.requiresBaseline && !cmp.baselineComparable) {
    throw StateError(
      'baseline-dependent gate requested without a comparable baseline',
    );
  }

  final violations = <String>[];
  bool atOrAbove(GraphLeakCluster c) =>
      c.confidence.index >= opts.minConfidence.index;

  final maxTotal = opts.maxTotalClusters;
  if (maxTotal != null) {
    final total = cmp.currentClusters.where(atOrAbove).length;
    if (total > maxTotal) {
      violations.add('total clusters $total exceeds limit $maxTotal');
    }
  }

  final maxNew = opts.maxNewClusters;
  if (maxNew != null) {
    final newCount = cmp.deltas
        .where(
          (d) => d.novelty == ClusterNovelty.newCluster && atOrAbove(d.cluster),
        )
        .length;
    if (newCount > maxNew) {
      violations.add('new clusters $newCount exceeds limit $maxNew');
    }
  }

  final maxGrowth = opts.maxClassGrowthInstances;
  if (maxGrowth != null) {
    var worst = 0;
    for (final d in cmp.deltas) {
      if (!atOrAbove(d.cluster)) continue;
      if (d.novelty == ClusterNovelty.newCluster) continue;
      if (d.instanceDelta > worst) worst = d.instanceDelta;
    }
    if (worst > maxGrowth) {
      violations.add('class instance growth $worst exceeds limit $maxGrowth');
    }
  }

  final maxHeap = opts.maxHeapGrowthBytes;
  if (maxHeap != null) {
    final growth = cmp.heapGrowthBytes;
    if (growth > maxHeap) {
      violations.add('heap growth $growth bytes exceeds limit $maxHeap');
    }
  }

  return GateResult(passed: violations.isEmpty, violations: violations);
}

int _sumShallow(List<GraphLeakCluster> clusters) =>
    clusters.fold(0, (sum, c) => sum + c.retainedShallowBytes);
