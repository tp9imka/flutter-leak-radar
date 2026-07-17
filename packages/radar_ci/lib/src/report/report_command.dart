import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:leak_graph/leak_graph.dart';
import 'package:radar_trace/radar_trace.dart';

import '../gate/gate_command.dart';
import '../gate/verdict_gate.dart';
import '../model/run_document.dart';

/// Exit codes for the report verb.
///
/// 0 ok / 1 usage error / 2 tool failure. The report is informational: it
/// renders the verdict but never itself exits with the gate-failed code — the
/// `gate` verb is the enforcer.
abstract final class ReportExit {
  /// The report was produced.
  static const int ok = 0;

  /// A command-line usage error.
  static const int usage = 1;

  /// A tool failure (unreadable run.json, or a failed `--out` write).
  static const int toolFailure = 2;
}

/// The rendering format for `radar_ci report`.
enum ReportFormat {
  /// Plain markdown.
  md,

  /// GitHub-flavored markdown (admonitions) for step summaries / PR comments.
  github,

  /// A single JSON envelope: run document + assessments + comparison + gate.
  json,
}

/// The schema version of the JSON report envelope.
const int kReportEnvelopeSchemaVersion = 1;

/// Builds the argument parser for the `report` verb.
ArgParser buildReportArgParser() => ArgParser()
  ..addOption(
    'format',
    allowed: ['md', 'github', 'json'],
    defaultsTo: 'md',
    help: 'Output format.',
  )
  ..addOption(
    'baseline',
    help: 'Annotate clusters with NEW/grown badges against this baseline.',
  )
  ..addOption(
    'out',
    abbr: 'o',
    help: 'Write the report here instead of stdout.',
  )
  ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage.');

/// Runs the `report` verb and returns its process exit code.
///
/// Merges the radar_trace series assessments with the leak_graph markdown
/// report for the last checkpoint's analysis, following the 30-second contract:
/// line 1 is the overall verdict (worst of series + gate), then the featured
/// clusters (reusing [renderMarkdownReport] — the single cluster-rendering
/// path), then the series table, then the folded details. All I/O is injectable.
///
/// The report's cluster verdict always uses the default `heuristic`
/// min-confidence, so it can read FAIL where `gate --min-confidence confirmed`
/// passes — the report never suppresses a lower-confidence leak from view.
Future<int> runReport(
  List<String> argv, {
  required StringSink out,
  required StringSink err,
  TextReader readText = _readTextFromFile,
  TextWriter writeText = _writeTextToFile,
  SeriesAssessment Function(MetricSeries) assess = _assessDefault,
}) async {
  final parser = buildReportArgParser();
  final ArgResults args;
  try {
    args = parser.parse(argv);
  } on FormatException catch (e) {
    err.writeln('${e.message}\n\n${parser.usage}');
    return ReportExit.usage;
  }

  if (args['help'] as bool) {
    out.writeln(
      'radar_ci report — unified memory + leak report from a run.json.\n\n'
      'Usage: radar_ci report <run.json> [--format md|github|json] '
      '[--baseline <file>] [-o <file>]\n\n${parser.usage}',
    );
    return ReportExit.ok;
  }

  final rest = args.rest;
  if (rest.length != 1) {
    err.writeln('Expected exactly one run.json path.\n\n${parser.usage}');
    return ReportExit.usage;
  }
  final format = ReportFormat.values.byName(args['format'] as String);

  final RadarRunDocument run;
  try {
    run = RadarRunDocument.fromJson(
      (jsonDecode(await readText(rest.first)) as Map).cast<String, Object?>(),
    );
  } catch (e) {
    err.writeln('Error reading run.json "${rest.first}": $e');
    return ReportExit.toolFailure;
  }

  final series = assessGatedSeries(run, assess);

  final loaded = await _loadAnalysis(run, readText, err);
  final comparison = await _loadComparison(
    args['baseline'] as String?,
    loaded.analysis,
    readText,
    err,
  );

  final gate = evaluateVerdictGate(
    series: series,
    comparison: comparison.comparison,
    analysis: loaded.analysis,
  );

  final rendered = switch (format) {
    ReportFormat.json => _jsonEnvelope(
      run,
      series,
      comparison.comparison,
      gate,
      loaded.analysis,
    ),
    ReportFormat.md || ReportFormat.github => _composeMarkdown(
      github: format == ReportFormat.github,
      run: run,
      series: series,
      gate: gate,
      analysis: loaded.analysis,
      comparison: comparison.comparison,
      analysisNote: loaded.note,
      baselineNote: comparison.note,
    ),
  };

  final outPath = args['out'] as String?;
  if (outPath != null) {
    try {
      await writeText(outPath, '$rendered\n');
    } on FileSystemException catch (e) {
      err.writeln('Error writing report: ${e.message} — ${e.path}');
      return ReportExit.toolFailure;
    }
    err.writeln('Wrote report to $outPath');
  } else {
    out.writeln(rendered);
  }
  return ReportExit.ok;
}

/// Best-effort load of the freshest checkpoint's analysis. A missing or
/// unreadable analysis degrades to a null result with a human [note] — the
/// report still renders the series dimension rather than failing. When the
/// loaded analysis is not the run's final capture, [note] carries the same
/// staleness caveat the gate emits, so the cluster view never reads as a
/// verdict on the run's tail.
Future<({GraphAnalysisResult? analysis, String? note})> _loadAnalysis(
  RadarRunDocument run,
  TextReader readText,
  StringSink err,
) async {
  final selection = selectAnalysisCheckpoint(run);
  final checkpoint = selection.checkpoint;
  if (checkpoint == null) {
    return (analysis: null, note: 'no heap analysis was captured in this run');
  }
  try {
    final analysis = GraphAnalysisResult.fromJson(
      (jsonDecode(await readText(checkpoint.analysisPath!)) as Map)
          .cast<String, Object?>(),
    );
    return (analysis: analysis, note: selection.staleNote);
  } catch (e) {
    final note =
        'heap analysis at ${checkpoint.analysisPath} '
        'could not be read ($e)';
    err.writeln(note);
    return (analysis: null, note: note);
  }
}

/// Best-effort baseline comparison for cluster badges. A missing analysis,
/// unreadable baseline, or incomparable schema degrades to a null comparison
/// with a [note] — never all-NEW.
Future<({BaselineComparison? comparison, String? note})> _loadComparison(
  String? baselinePath,
  GraphAnalysisResult? analysis,
  TextReader readText,
  StringSink err,
) async {
  if (baselinePath == null) return (comparison: null, note: null);
  if (analysis == null) {
    return (
      comparison: null,
      note: 'baseline provided but no analysis to compare against',
    );
  }
  final LeakBaseline baseline;
  try {
    baseline = LeakBaseline.fromJson(
      (jsonDecode(await readText(baselinePath)) as Map).cast<String, Object?>(),
    );
  } catch (e) {
    final note =
        'baseline "$baselinePath" could not be read ($e) — '
        'not compared';
    err.writeln(note);
    return (comparison: null, note: note);
  }
  if (!isBaselineComparable(baseline.schemaVersion)) {
    return (
      comparison: null,
      note:
          'baseline schemaVersion ${baseline.schemaVersion} '
          'is not comparable — not compared',
    );
  }
  return (comparison: compareToBaseline(analysis, baseline), note: null);
}

String _composeMarkdown({
  required bool github,
  required RadarRunDocument run,
  required List<SeriesGateOutcome> series,
  required VerdictGateResult gate,
  GraphAnalysisResult? analysis,
  BaselineComparison? comparison,
  String? analysisNote,
  String? baselineNote,
}) {
  final buf = StringBuffer()
    ..writeln(_overallVerdictLine(gate))
    ..writeln();
  if (!run.metadata.completed) {
    final reason = run.metadata.abortReason;
    buf
      ..writeln(
        '> Note: this run is partial (completed:false'
        '${reason == null ? '' : ', $reason'}) — the verdict covers only what '
        'was captured.',
      )
      ..writeln();
  }

  if (analysisNote != null) buf.writeln('_$analysisNote._\n');

  final seriesSection = _seriesSection(series);
  if (analysis != null) {
    // Drop the renderer's own line-1 verdict: the composed overall line above
    // is the single verdict authority, so its `⚠ N clusters (no gate)` /
    // `✅ no leak clusters` sub-headline must never sit under a real ❌ FAIL.
    final leakReport = _stripLeadingVerdict(
      renderMarkdownReport(analysis, comparison: comparison, github: github),
    );
    buf.writeln(_insertBeforeDetails(leakReport, seriesSection));
  } else {
    buf.writeln(seriesSection);
  }
  if (baselineNote != null) buf.writeln('\n_$baselineNote._');
  return buf.toString().trimRight();
}

/// Strips [renderMarkdownReport]'s own line-1 verdict and the blank line that
/// follows it, so the composed overall verdict is the report's single headline.
String _stripLeadingVerdict(String leakReport) {
  final lines = leakReport.split('\n');
  var start = lines.isEmpty ? 0 : 1;
  if (start < lines.length && lines[start].trim().isEmpty) start++;
  return lines.sublist(start).join('\n');
}

/// Splits [leakReport] at its first folded `<details>` block and threads
/// [seriesSection] in above it, so the 30-second view reads verdict → clusters
/// → series table → details. Falls back to appending if the renderer emits no
/// details block.
String _insertBeforeDetails(String leakReport, String seriesSection) {
  final lines = leakReport.split('\n');
  final index = lines.indexWhere((line) => line.trim() == '<details>');
  if (index < 0) return '$leakReport\n\n$seriesSection';
  final before = lines.sublist(0, index).join('\n').trimRight();
  final after = lines.sublist(index).join('\n');
  return '$before\n\n$seriesSection\n\n$after';
}

String _overallVerdictLine(VerdictGateResult gate) {
  if (gate.passed) {
    return '✅ overall: PASS — no monotonic memory growth or new '
        'project-anchor leaks';
  }
  final reasons = <String>[];
  final growth = gate.growthSignals.toList();
  if (growth.isNotEmpty) {
    reasons.add('monotonic growth in ${growth.join(', ')}');
  }
  if (gate.newProjectClusters.isNotEmpty) {
    reasons.add(
      '${gate.newProjectClusters.length} new project-anchor cluster(s)',
    );
  }
  reasons.addAll(gate.byteViolations);
  return '❌ overall: FAIL — ${reasons.join('; ')}';
}

String _seriesSection(List<SeriesGateOutcome> series) {
  final buf = StringBuffer()
    ..writeln('### Memory series')
    ..writeln()
    ..writeln('| Metric | Verdict | Slope/h | Batch Δ/h | Samples | Detail |')
    ..writeln('|---|---|---|---|---|---|');
  for (final signal in series) {
    final assessment = signal.assessment;
    if (assessment == null) {
      buf.writeln(
        '| ${signal.name} | absent | — | — | — | not captured in this run |',
      );
      continue;
    }
    buf.writeln(
      '| ${signal.name} | ${assessment.verdict.name} | '
      '${formatBytesPerHour(assessment.slopePerHour)} | '
      '${formatBytesPerHour(assessment.batchDeltaPerHour)} | '
      '${assessment.samplesAssessed}/${assessment.samplesTotal} | '
      '${_escapeCell(assessment.detail)} |',
    );
  }
  return buf.toString().trimRight();
}

String _escapeCell(String text) => text.replaceAll('|', r'\|');

String _jsonEnvelope(
  RadarRunDocument run,
  List<SeriesGateOutcome> series,
  BaselineComparison? comparison,
  VerdictGateResult gate,
  GraphAnalysisResult? analysis,
) {
  final envelope = <String, Object?>{
    'schemaVersion': kReportEnvelopeSchemaVersion,
    'run': run.toJson(),
    'assessments': {
      for (final signal in series)
        if (signal.assessment != null) signal.name: signal.assessment!.toJson(),
    },
    if (comparison != null)
      'comparison': _encodeComparison(comparison, analysis),
    'gate': {
      'passed': gate.passed,
      'growthSignals': gate.growthSignals.toList(),
      'newProjectAnchorClusterCount': gate.newProjectClusters.length,
      'baselineCompared': gate.baselineCompared,
      'byteViolations': gate.byteViolations,
    },
  };
  return const JsonEncoder.withIndent('  ').convert(envelope);
}

Map<String, Object?> _encodeComparison(
  BaselineComparison comparison,
  GraphAnalysisResult? analysis,
) => {
  'baselineComparable': comparison.baselineComparable,
  'currentTotalShallowBytes': comparison.currentTotalShallowBytes,
  'baselineTotalShallowBytes': comparison.baselineTotalShallowBytes,
  'heapGrowthBytes': comparison.heapGrowthBytes,
  'deltas': [
    for (final delta in comparison.deltas)
      {
        'signature': delta.cluster.signature,
        'className': delta.cluster.className,
        'novelty': delta.novelty.name,
        'instanceDelta': delta.instanceDelta,
        'bytesDelta': delta.bytesDelta,
        'confidence': delta.cluster.confidence.name,
        'projectAnchor':
            analysis != null &&
            clusterOrigin(delta.cluster, analysis) == ClassOrigin.project,
        if (delta.nearestKnownSignature != null)
          'nearestKnownSignature': delta.nearestKnownSignature,
      },
  ],
  'gone': [
    for (final gone in comparison.gone)
      {
        'signature': gone.signature,
        'className': gone.className,
        'instanceCount': gone.instanceCount,
        'retainedShallowBytes': gone.retainedShallowBytes,
      },
  ],
};

SeriesAssessment _assessDefault(MetricSeries series) => assessSeries(series);

Future<String> _readTextFromFile(String path) => File(path).readAsString();

Future<void> _writeTextToFile(String path, String contents) =>
    File(path).writeAsString(contents);
