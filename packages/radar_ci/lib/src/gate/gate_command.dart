import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:leak_graph/leak_graph.dart';
import 'package:radar_native/radar_native.dart';
import 'package:radar_trace/radar_trace.dart';

import '../model/run_document.dart';
import 'verdict_gate.dart';

/// Reads the whole contents of a text file at [path].
typedef TextReader = Future<String> Function(String path);

/// Writes [contents] to a text file at [path].
typedef TextWriter = Future<void> Function(String path, String contents);

/// Exit codes for the gate verb, per the initiative-wide contract.
///
/// 0 ok / 1 usage error / 2 tool failure / 3 gate failed.
abstract final class GateExit {
  /// The gate passed (or `--help`).
  static const int ok = 0;

  /// A command-line usage error.
  static const int usage = 1;

  /// A tool failure — including a requested gate that could not be evaluated.
  static const int toolFailure = 2;

  /// A gate threshold/verdict was violated.
  static const int gateFailed = 3;
}

/// Builds the argument parser for the `gate` verb.
ArgParser buildGateArgParser() => ArgParser()
  ..addOption(
    'baseline',
    help: 'Compare the last checkpoint analysis against this baseline JSON.',
  )
  ..addOption(
    'write-baseline',
    help: 'Write a fresh baseline from the last analysis to this path.',
  )
  ..addOption(
    'min-confidence',
    allowed: ['heuristic', 'confirmed'],
    defaultsTo: 'heuristic',
    help: 'Minimum leak confidence a new project-anchor cluster must meet.',
  )
  ..addOption(
    'max-new-clusters',
    help: 'Byte-absolute opt-in: fail above this many new clusters.',
  )
  ..addOption(
    'max-total-clusters',
    help: 'Byte-absolute opt-in: fail above this many total clusters.',
  )
  ..addOption(
    'max-class-growth',
    help: 'Byte-absolute opt-in: fail above this per-class instance growth.',
  )
  ..addOption(
    'max-heap-growth',
    help: 'Byte-absolute opt-in: fail above this shallow-byte growth.',
  )
  ..addFlag(
    'allow-partial',
    negatable: false,
    help: 'Gate a partial (completed:false) run instead of refusing it.',
  )
  ..addFlag(
    'gate-native',
    negatable: false,
    help:
        'Also fail on monotonic growth of any measured native (Lane A) column '
        'from a --native-package co-drive.',
  )
  ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage.');

/// Runs the `gate` verb and returns its process exit code.
///
/// All I/O is injectable ([readText]/[writeText]/[now]/[assess]) so the verb is
/// unit-testable over synthesised in-memory run documents. Verdict lines — one
/// per gated signal plus the baseline and any byte-absolute violations — go to
/// [out] so a stdout-only CI reader always sees the decision; diagnostics go to
/// [err]. A requested gate that cannot be evaluated exits [GateExit.toolFailure]
/// with a distinct `⛔` verdict line, never a silent pass.
Future<int> runGate(
  List<String> argv, {
  required StringSink out,
  required StringSink err,
  TextReader readText = _readTextFromFile,
  TextWriter writeText = _writeTextToFile,
  DateTime Function() now = _nowUtc,
  SeriesAssessment Function(MetricSeries) assess = _assessDefault,
}) async {
  final parser = buildGateArgParser();
  final ArgResults args;
  try {
    args = parser.parse(argv);
  } on FormatException catch (e) {
    err.writeln('${e.message}\n\n${parser.usage}');
    return GateExit.usage;
  }

  if (args['help'] as bool) {
    out.writeln(
      'radar_ci gate — verdict-based CI gate over a run.json.\n\n'
      'Usage: radar_ci gate <run.json> [--baseline <file>] [options]\n\n'
      '${parser.usage}',
    );
    return GateExit.ok;
  }

  final rest = args.rest;
  if (rest.length != 1) {
    err.writeln('Expected exactly one run.json path.\n\n${parser.usage}');
    return GateExit.usage;
  }
  final runPath = rest.first;

  final thresholds = _parseThresholds(args, err);
  if (thresholds == null) return GateExit.usage;
  final minConfidence = LeakConfidence.values.byName(
    args['min-confidence'] as String,
  );

  final run = await _readRun(runPath, readText, out, err);
  if (run == null) return GateExit.toolFailure;

  if (!run.metadata.completed && !(args['allow-partial'] as bool)) {
    final reason = run.metadata.abortReason ?? 'partial run';
    err.writeln(
      'Refusing to certify a partial run ($reason). Pass --allow-partial '
      'to gate it anyway.',
    );
    out.writeln(
      '⛔ gate not evaluated: run is partial (completed:false, $reason) — '
      'pass --allow-partial to gate it anyway',
    );
    return GateExit.toolFailure;
  }

  final series = assessGatedSeries(run, assess);

  // Native (Lane A) gate — opt-in. A --gate-native on a run that never
  // co-drove the native lane is a requested-but-unevaluable gate: refuse
  // rather than pass silently (a CI expecting native coverage must not read
  // green off a run with no native data). Likewise a co-driven run whose
  // native lane measured ZERO samples (every column empty — the device was
  // unreachable throughout) is green-off-no-data: refuse it too. Only PARTIAL
  // coverage (at least one column has a measured sample) is an honest
  // insufficientData-pass — triage reads insufficientData there, never a fail.
  final gateNative = args['gate-native'] as bool;
  final nativeTimeline = run.nativeTimeline;
  if (gateNative && nativeTimeline == null) {
    err.writeln(
      '--gate-native was requested but this run carries no native timeline '
      '(was it run with --native-package?).',
    );
    out.writeln(
      '⛔ gate not evaluated: --gate-native requested but this run has no '
      'native lane to gate',
    );
    return GateExit.toolFailure;
  }
  if (gateNative &&
      nativeTimeline != null &&
      !nativeTimeline.columns.values.any((s) => s.samples.isNotEmpty)) {
    err.writeln(
      "--gate-native was requested but this run's native lane measured no "
      'samples (every native column is empty) — refusing rather than passing '
      'green off no native data.',
    );
    out.writeln(
      '⛔ gate not evaluated: --gate-native requested but the native lane '
      'measured zero samples',
    );
    return GateExit.toolFailure;
  }
  final nativeVerdict = nativeTimeline == null ? null : triage(nativeTimeline);

  final baselinePath = args['baseline'] as String?;
  final writeBaselinePath = args['write-baseline'] as String?;
  final byteGate = GateOptions(
    maxNewClusters: thresholds.maxNew,
    maxTotalClusters: thresholds.maxTotal,
    maxClassGrowthInstances: thresholds.maxGrowth,
    maxHeapGrowthBytes: thresholds.maxHeap,
    minConfidence: minConfidence,
  );
  final byteGateRequested =
      thresholds.maxNew != null ||
      thresholds.maxTotal != null ||
      thresholds.maxGrowth != null ||
      thresholds.maxHeap != null;
  final needsAnalysis =
      baselinePath != null || byteGateRequested || writeBaselinePath != null;

  GraphAnalysisResult? analysis;
  String? analysisStaleNote;
  if (needsAnalysis) {
    final selection = selectAnalysisCheckpoint(run);
    final checkpoint = selection.checkpoint;
    if (checkpoint == null) {
      err.writeln(
        'A baseline/threshold/--write-baseline gate was requested but no '
        'checkpoint carries a heap analysis.',
      );
      out.writeln(
        '⛔ gate not evaluated: no heap analysis in this run to compare or '
        'threshold against',
      );
      return GateExit.toolFailure;
    }
    analysisStaleNote = selection.staleNote;
    analysis = await _readAnalysis(
      checkpoint.analysisPath!,
      readText,
      out,
      err,
    );
    if (analysis == null) return GateExit.toolFailure;
  }

  BaselineComparison? comparison;
  if (baselinePath != null) {
    final built = await _buildComparison(
      baselinePath,
      analysis!,
      readText,
      out,
      err,
    );
    if (built == null) return GateExit.toolFailure;
    comparison = built;
  } else if (needsAnalysis) {
    comparison = BaselineComparison.withoutBaseline(analysis!);
  }

  if (byteGateRequested &&
      byteGate.requiresBaseline &&
      (comparison == null || !comparison.baselineComparable)) {
    err.writeln(
      'A baseline-dependent threshold (--max-new-clusters/--max-class-growth/'
      '--max-heap-growth) was requested without a comparable --baseline.',
    );
    out.writeln(
      '⛔ gate not evaluated: that byte-absolute threshold needs a comparable '
      '--baseline',
    );
    return GateExit.toolFailure;
  }

  final gate = evaluateVerdictGate(
    series: series,
    comparison: comparison,
    analysis: analysis,
    minConfidence: minConfidence,
    byteGate: byteGate,
    byteGateRequested: byteGateRequested,
    nativeVerdict: nativeVerdict,
    gateNative: gateNative,
  );

  if (writeBaselinePath != null) {
    final baseline = LeakBaseline.fromResult(analysis!, createdAt: now());
    try {
      await writeText(
        writeBaselinePath,
        const JsonEncoder.withIndent('  ').convert(baseline.toJson()),
      );
    } on FileSystemException catch (e) {
      err.writeln('Error writing baseline: ${e.message} — ${e.path}');
      return GateExit.toolFailure;
    }
    err.writeln(
      'Wrote baseline (${analysis.clusters.length} clusters) to '
      '$writeBaselinePath',
    );
    if (!gate.passed) {
      err.writeln(
        'warning: this baseline includes clusters from a FAILING run — later '
        'runs will treat them as known and stop flagging them.',
      );
    }
  }

  _printVerdict(
    out,
    gate,
    minConfidence: minConfidence,
    baselineProvided: baselinePath != null,
    analysisStaleNote: analysisStaleNote,
    nativeVerdict: gateNative ? nativeVerdict : null,
  );
  return gate.passed ? GateExit.ok : GateExit.gateFailed;
}

/// Parsed byte-absolute threshold flags, or null on a usage error (already
/// reported to [err]).
({int? maxNew, int? maxTotal, int? maxGrowth, int? maxHeap})? _parseThresholds(
  ArgResults args,
  StringSink err,
) {
  final values = <String, int?>{};
  for (final name in const [
    'max-new-clusters',
    'max-total-clusters',
    'max-class-growth',
    'max-heap-growth',
  ]) {
    final raw = args[name] as String?;
    if (raw == null) {
      values[name] = null;
      continue;
    }
    final parsed = int.tryParse(raw);
    if (parsed == null || parsed < 0) {
      err.writeln('--$name must be a non-negative integer: "$raw"');
      return null;
    }
    values[name] = parsed;
  }
  return (
    maxNew: values['max-new-clusters'],
    maxTotal: values['max-total-clusters'],
    maxGrowth: values['max-class-growth'],
    maxHeap: values['max-heap-growth'],
  );
}

Future<RadarRunDocument?> _readRun(
  String path,
  TextReader readText,
  StringSink out,
  StringSink err,
) async {
  final String raw;
  try {
    raw = await readText(path);
  } on FileSystemException catch (e) {
    err.writeln('Error reading run.json: ${e.message} — ${e.path}');
    out.writeln('⛔ gate not evaluated: could not read $path');
    return null;
  } catch (e) {
    err.writeln('Error reading run.json "$path": $e');
    out.writeln('⛔ gate not evaluated: could not read $path');
    return null;
  }
  try {
    return RadarRunDocument.fromJson(
      (jsonDecode(raw) as Map).cast<String, Object?>(),
    );
  } catch (e) {
    err.writeln('Error parsing run.json "$path": $e');
    out.writeln('⛔ gate not evaluated: $path is not a readable run document');
    return null;
  }
}

Future<GraphAnalysisResult?> _readAnalysis(
  String path,
  TextReader readText,
  StringSink out,
  StringSink err,
) async {
  final String raw;
  try {
    raw = await readText(path);
  } catch (e) {
    err.writeln('Error reading analysis "$path": $e');
    out.writeln('⛔ gate not evaluated: could not read analysis $path');
    return null;
  }
  try {
    return GraphAnalysisResult.fromJson(
      (jsonDecode(raw) as Map).cast<String, Object?>(),
    );
  } catch (e) {
    err.writeln('Error parsing analysis "$path": $e');
    out.writeln('⛔ gate not evaluated: analysis $path is unreadable');
    return null;
  }
}

/// Builds the baseline comparison, or null on a refusal (reported to [out]/
/// [err]) — an unreadable, unparseable, or incomparable baseline never becomes
/// an all-NEW gate failure.
Future<BaselineComparison?> _buildComparison(
  String baselinePath,
  GraphAnalysisResult analysis,
  TextReader readText,
  StringSink out,
  StringSink err,
) async {
  final String raw;
  try {
    raw = await readText(baselinePath);
  } catch (e) {
    err.writeln('Error reading baseline "$baselinePath": $e');
    out.writeln('⛔ gate not evaluated: could not read baseline $baselinePath');
    return null;
  }
  final LeakBaseline baseline;
  try {
    baseline = LeakBaseline.fromJson(
      (jsonDecode(raw) as Map).cast<String, Object?>(),
    );
  } catch (e) {
    err.writeln('Error parsing baseline "$baselinePath": $e');
    out.writeln('⛔ gate not evaluated: baseline $baselinePath is unreadable');
    return null;
  }
  if (!isBaselineComparable(baseline.schemaVersion)) {
    err.writeln(
      'baseline not comparable (schemaVersion ${baseline.schemaVersion}) — '
      'refusing rather than flagging every cluster as new.',
    );
    out.writeln(
      '⛔ gate not evaluated: baseline schemaVersion ${baseline.schemaVersion} '
      'is not comparable',
    );
    return null;
  }
  return compareToBaseline(analysis, baseline);
}

void _printVerdict(
  StringSink out,
  VerdictGateResult gate, {
  required LeakConfidence minConfidence,
  required bool baselineProvided,
  String? analysisStaleNote,
  TriageVerdict? nativeVerdict,
}) {
  for (final signal in gate.series) {
    out.writeln(_seriesVerdictLine(signal));
  }
  if (nativeVerdict != null) {
    for (final column in nativeVerdict.assessments) {
      out.writeln(_nativeVerdictLine(column));
    }
  }
  if (analysisStaleNote != null) {
    out.writeln('cluster gate: $analysisStaleNote');
  }
  if (!baselineProvided) {
    out.writeln('baseline: not compared (no --baseline provided)');
  } else if (gate.newProjectClusters.isEmpty) {
    out.writeln(
      'baseline: ok — no new project-anchor clusters at '
      '>= ${minConfidence.name} confidence',
    );
  } else {
    out.writeln(
      'baseline: FAIL — ${gate.newProjectClusters.length} new project-anchor '
      'cluster(s) at >= ${minConfidence.name} confidence',
    );
    for (final cluster in gate.newProjectClusters) {
      out.writeln(
        '  - ${cluster.className} (${cluster.instanceCount} instances, '
        '${cluster.retainedShallowBytes} B shallow)',
      );
    }
  }
  for (final violation in gate.byteViolations) {
    out.writeln('threshold: FAIL — $violation');
  }
  out.writeln(gate.passed ? '✅ GATE PASSED' : '❌ GATE FAILED');
}

String _seriesVerdictLine(SeriesGateOutcome signal) {
  final assessment = signal.assessment;
  if (assessment == null) {
    return '${signal.name}: absent from run (not assessed)';
  }
  final tag = switch (assessment.verdict) {
    SeriesVerdict.monotonicGrowth => 'FAIL',
    SeriesVerdict.insufficientData => 'not assessed',
    SeriesVerdict.plateau || SeriesVerdict.noisy => 'ok',
  };
  return '${signal.name}: ${assessment.verdict.name} ($tag) — '
      '${assessment.detail}';
}

/// One native column's gate line — a growing measured column reads FAIL, a
/// not-measured / insufficientData column never does.
String _nativeVerdictLine(TriageColumnAssessment column) {
  final assessment = column.assessment;
  final grows =
      assessment.verdict == SeriesVerdict.monotonicGrowth &&
      (assessment.slopePerHour ?? 0) > 0;
  final tag = switch (assessment.verdict) {
    SeriesVerdict.monotonicGrowth => grows ? 'FAIL' : 'ok',
    SeriesVerdict.insufficientData => 'not measured',
    SeriesVerdict.plateau || SeriesVerdict.noisy => 'ok',
  };
  return 'native ${column.column.name}: ${assessment.verdict.name} ($tag) — '
      '${assessment.detail}';
}

SeriesAssessment _assessDefault(MetricSeries series) => assessSeries(series);

Future<String> _readTextFromFile(String path) => File(path).readAsString();

Future<void> _writeTextToFile(String path, String contents) =>
    File(path).writeAsString(contents);

DateTime _nowUtc() => DateTime.now().toUtc();
