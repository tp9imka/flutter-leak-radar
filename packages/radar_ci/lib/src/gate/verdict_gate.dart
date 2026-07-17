/// Pure, `dart:io`-free heart of the `radar_ci gate`/`report` verbs.
///
/// The verdict-based gate answers one question honestly: did this run either
/// grow monotonically in a tracked memory signal, or introduce a NEW leak
/// cluster anchored in the app's own code? Both signals are derived from
/// already-computed inputs (radar_trace [SeriesAssessment]s and a leak_graph
/// [BaselineComparison]), so this logic is trivially unit-testable and shared
/// verbatim by the enforcing `gate` verb and the informational `report` verb.
library;

import 'package:leak_graph/leak_graph.dart';
import 'package:radar_native/radar_native.dart';
import 'package:radar_trace/radar_trace.dart';

import '../model/run_document.dart';

/// The memory signals the verdict gate certifies for monotonic growth.
///
/// Deliberately the three that map to a real leak surface: Dart heap, external
/// (native-backed) memory, and process RSS. `dart.heap.capacity` is excluded —
/// capacity tracks the allocator's high-water reservation, not live retention,
/// so it climbs and holds without a leak.
const List<String> kGatedSignals = <String>[
  'dart.heap.used',
  'dart.external',
  'process.rss',
];

/// One gated signal's assessment, paired with its metric name.
///
/// [assessment] is null when the run carried no series of that [name] — an
/// honest "not measured", never a fabricated verdict.
final class SeriesGateOutcome {
  /// The gated metric name (one of [kGatedSignals]).
  final String name;

  /// The source series, or null when absent from the run.
  final MetricSeries? series;

  /// The growth assessment, or null when the series was absent.
  final SeriesAssessment? assessment;

  /// Creates an outcome for [name].
  const SeriesGateOutcome({
    required this.name,
    required this.series,
    required this.assessment,
  });

  /// Whether this signal was certified as monotonic growth (the fail trigger).
  bool get isGrowth => assessment?.verdict == SeriesVerdict.monotonicGrowth;

  /// Whether a trustworthy verdict was reached (growth/plateau/noisy but not
  /// [SeriesVerdict.insufficientData] and not absent).
  bool get assessed =>
      assessment != null &&
      assessment!.verdict != SeriesVerdict.insufficientData;
}

/// The outcome of a verdict-based gate over a run and optional baseline.
final class VerdictGateResult {
  /// Per-signal growth assessments, in [kGatedSignals] order.
  final List<SeriesGateOutcome> series;

  /// NEW clusters anchored in the app's own code at or above the requested
  /// confidence — the baseline-driven fail trigger. Empty without a comparable
  /// baseline (never all-NEW).
  final List<GraphLeakCluster> newProjectClusters;

  /// Whether a comparable baseline actually backed the new-cluster check.
  final bool baselineCompared;

  /// Byte-absolute [GateOptions] violations, when opt-in thresholds were set.
  final List<String> byteViolations;

  /// The measured native (Lane A) columns certified as monotonic growth —
  /// always computed when a native timeline is present, so the report can show
  /// them, but only counted toward [passed] when [nativeGated] is true.
  final List<TriageColumnAssessment> nativeGrowth;

  /// Whether native growth counts toward the pass/fail decision (the gate's
  /// opt-in `--gate-native`; always true for the informational report).
  final bool nativeGated;

  /// Creates a gate result.
  const VerdictGateResult({
    required this.series,
    required this.newProjectClusters,
    required this.baselineCompared,
    required this.byteViolations,
    this.nativeGrowth = const [],
    this.nativeGated = false,
  });

  /// The gated signal names certified as monotonic growth.
  Iterable<String> get growthSignals => [
    for (final s in series)
      if (s.isGrowth) s.name,
  ];

  /// The growing native column names (empty unless a native timeline showed
  /// monotonic growth).
  Iterable<String> get nativeGrowthSignals => [
    for (final a in nativeGrowth) a.column.name,
  ];

  /// True when nothing failed: no Dart-series growth, no new project-anchor
  /// cluster, no byte-absolute violation, and — when [nativeGated] — no native
  /// column growth.
  bool get passed =>
      growthSignals.isEmpty &&
      newProjectClusters.isEmpty &&
      byteViolations.isEmpty &&
      !(nativeGated && nativeGrowth.isNotEmpty);
}

/// The measured native columns [nativeVerdict] certifies as monotonic growth
/// (a strictly positive slope) — the native gate's fail trigger.
///
/// Empty when [nativeVerdict] is null (no native lane) or nothing grows;
/// not-measured / insufficientData / plateau / noisy columns never appear, so
/// an unmeasured column can never fail the native gate.
List<TriageColumnAssessment> growingNativeColumns(
  TriageVerdict? nativeVerdict,
) {
  if (nativeVerdict == null) return const [];
  return [
    for (final a in nativeVerdict.assessments)
      if (a.assessment.verdict == SeriesVerdict.monotonicGrowth &&
          (a.assessment.slopePerHour ?? 0) > 0)
        a,
  ];
}

/// Assesses the three [kGatedSignals] in [run] via [assess].
///
/// A signal missing from the run yields a null-assessment outcome rather than
/// a guessed verdict.
List<SeriesGateOutcome> assessGatedSeries(
  RadarRunDocument run,
  SeriesAssessment Function(MetricSeries) assess,
) {
  final byName = {for (final s in run.series) s.name: s};
  return [
    for (final name in kGatedSignals)
      SeriesGateOutcome(
        name: name,
        series: byName[name],
        assessment: byName[name] == null ? null : assess(byName[name]!),
      ),
  ];
}

/// The freshest checkpoint carrying a heap analysis, plus an honest
/// [staleNote] when that analysis is NOT the run's final capture.
typedef AnalysisSelection = ({RunCheckpoint? checkpoint, String? staleNote});

/// Picks the analysis a cluster gate/report should read from [run].
///
/// Returns the last checkpoint that carries an `analysisPath`. When that
/// analysis is not the run's final capture — the last checkpoint failed to
/// analyze, or carries no analysis — [staleNote] explains that the cluster
/// picture reflects an earlier checkpoint, so certifying against it never
/// masquerades as a verdict on the run's tail. A run whose final capture is
/// clean returns a null note; a run with no analysis anywhere returns a null
/// checkpoint (the caller refuses).
AnalysisSelection selectAnalysisCheckpoint(RadarRunDocument run) {
  if (run.checkpoints.isEmpty) return (checkpoint: null, staleNote: null);
  RunCheckpoint? analyzed;
  for (final checkpoint in run.checkpoints.reversed) {
    if (checkpoint.analysisPath != null) {
      analyzed = checkpoint;
      break;
    }
  }
  if (analyzed == null) return (checkpoint: null, staleNote: null);

  final last = run.checkpoints.last;
  final finalIsClean = identical(analyzed, last) && last.captureStatus == 'ok';
  if (finalIsClean) return (checkpoint: analyzed, staleNote: null);

  final reason = last.captureStatus == 'ok'
      ? 'the final checkpoint carries no heap analysis'
      : 'the final capture failed '
            '(${last.captureError ?? 'status "${last.captureStatus}"'})';
  return (
    checkpoint: analyzed,
    staleNote: "evaluated against checkpoint '${analyzed.label}' — $reason",
  );
}

/// The origin of [cluster] under [analysis]'s resolved app-package set.
///
/// Classifies the cluster's own declaring package the same way the leak_graph
/// markdown report tiers its featured clusters, so the gate's "project-anchor"
/// notion and the report's above-the-fold clusters always agree. Returns
/// [ClassOrigin.unknown] when the library is absent or app ownership was never
/// resolved (empty [GraphAnalysisResult.resolvedAppPackages]) — honest, never
/// a project-ownership guess.
ClassOrigin clusterOrigin(
  GraphLeakCluster cluster,
  GraphAnalysisResult analysis,
) {
  final uri = cluster.libraryUri;
  if (uri == null) return ClassOrigin.unknown;
  return OriginClassifier(
    projectPackages: analysis.resolvedAppPackages.toSet(),
  ).classify(uri);
}

/// Evaluates the verdict-based gate over already-loaded inputs.
///
/// Fail conditions (any one fails the gate):
/// - a [kGatedSignals] series assessed as [SeriesVerdict.monotonicGrowth];
/// - a NEW project-anchor [comparison] delta at or above [minConfidence];
/// - a byte-absolute [byteGate] threshold exceeded (only when
///   [byteGateRequested]).
///
/// [SeriesVerdict.insufficientData]/[SeriesVerdict.noisy]/[SeriesVerdict
/// .plateau] never fail. Baseline-driven conditions are skipped entirely when
/// [comparison] is null or not comparable — the caller resolves a
/// requested-but-unevaluable baseline to its own refusal.
///
/// [nativeVerdict] (the Lane A router verdict over a co-driven timeline) feeds
/// [VerdictGateResult.nativeGrowth]; whether that growth fails the gate is
/// [gateNative] — opt-in for the enforcing gate, always on for the report.
VerdictGateResult evaluateVerdictGate({
  required List<SeriesGateOutcome> series,
  BaselineComparison? comparison,
  GraphAnalysisResult? analysis,
  LeakConfidence minConfidence = LeakConfidence.heuristic,
  GateOptions byteGate = const GateOptions(),
  bool byteGateRequested = false,
  TriageVerdict? nativeVerdict,
  bool gateNative = false,
}) {
  final newProject = <GraphLeakCluster>[];
  if (comparison != null && comparison.baselineComparable && analysis != null) {
    for (final delta in comparison.deltas) {
      if (delta.novelty != ClusterNovelty.newCluster) continue;
      if (delta.cluster.confidence.index < minConfidence.index) continue;
      if (clusterOrigin(delta.cluster, analysis) != ClassOrigin.project) {
        continue;
      }
      newProject.add(delta.cluster);
    }
  }

  var byteViolations = const <String>[];
  if (byteGateRequested &&
      comparison != null &&
      (!byteGate.requiresBaseline || comparison.baselineComparable)) {
    byteViolations = evaluateGate(comparison, byteGate).violations;
  }

  return VerdictGateResult(
    series: series,
    newProjectClusters: newProject,
    baselineCompared: comparison?.baselineComparable ?? false,
    byteViolations: byteViolations,
    nativeGrowth: growingNativeColumns(nativeVerdict),
    nativeGated: gateNative,
  );
}

/// Formats a per-hour byte rate for a report cell, or `—` when null.
String formatBytesPerHour(double? bytesPerHour) =>
    bytesPerHour == null ? '—' : '${humanBytes(bytesPerHour)}/h';

/// Formats [value] bytes as a compact signed magnitude (B/KB/MB/GB, base 1000).
String humanBytes(double value) {
  final magnitude = value.abs();
  final sign = value < 0 ? '-' : '';
  final (divisor, unit) = switch (magnitude) {
    >= 1e9 => (1e9, 'GB'),
    >= 1e6 => (1e6, 'MB'),
    >= 1e3 => (1e3, 'KB'),
    _ => (1.0, 'B'),
  };
  final scaled = magnitude / divisor;
  final digits = unit == 'B' ? 0 : 1;
  return '$sign${scaled.toStringAsFixed(digits)} $unit';
}
