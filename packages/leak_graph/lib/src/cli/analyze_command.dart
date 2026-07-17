import 'dart:convert';
import 'dart:io';

import '../analysis/graph_leak_analyzer.dart';
import '../graph/heap_graph_view.dart';
import '../graph/snapshot_loader.dart';
import '../model/graph_analysis_result.dart';
import 'baseline.dart';
import 'cli_args.dart';
import 'markdown_renderer.dart';
import 'report_renderer.dart';

/// Loads a heap graph from a snapshot file path.
typedef HeapGraphLoader = Future<HeapGraphView> Function(String path);

/// Reads the whole contents of a text file at [path].
typedef TextReader = Future<String> Function(String path);

/// Writes [contents] to a text file at [path].
typedef TextWriter = Future<void> Function(String path, String contents);

/// Exit codes for the analyze command, per the CI gate contract.
///
/// 0 ok / 1 usage error / 2 tool failure / 3 gate failed.
abstract final class AnalyzeExit {
  static const int ok = 0;
  static const int usage = 1;
  static const int toolFailure = 2;
  static const int gateFailed = 3;
}

/// Runs the analyze command and returns its process exit code.
///
/// All I/O is injectable so the command can be unit-tested with in-memory
/// graphs and files — no process spawning. [out] receives the byte-stable
/// leak report (stdout); [err] receives every diagnostic (baseline notes, gate
/// verdicts) so the report on [out] is unaffected by the new flags.
///
/// Exit codes follow [AnalyzeExit]:
/// - bad flags → [AnalyzeExit.usage] (1);
/// - unreadable snapshot, unreadable/incomparable baseline that a gate needs,
///   or a failed file write → [AnalyzeExit.toolFailure] (2);
/// - a gate threshold exceeded → [AnalyzeExit.gateFailed] (3);
/// - otherwise [AnalyzeExit.ok] (0).
Future<int> runAnalyze(
  List<String> argv, {
  required StringSink out,
  required StringSink err,
  HeapGraphLoader loadGraph = _loadGraphFromFile,
  TextReader readText = _readTextFromFile,
  TextWriter writeText = _writeTextToFile,
  DateTime Function() now = _nowUtc,
}) async {
  final CliConfig config;
  try {
    config = parseCliArgs(argv);
  } on FormatException catch (e) {
    err.writeln(e.message);
    return AnalyzeExit.usage;
  }

  final HeapGraphView graph;
  try {
    graph = await loadGraph(config.dumpPath);
  } on FileSystemException catch (e) {
    err.writeln('Error reading heap snapshot: ${e.message} — ${e.path}');
    return AnalyzeExit.toolFailure;
  }

  final result = const GraphLeakAnalyzer().analyze(
    graph,
    GraphAnalysisOptions(
      appPackages: config.appPackages,
      disableAppFilter: config.all,
      minClusterSize: config.minCluster,
      confirmWithReachability: config.confirm,
    ),
  );

  // A baseline comparison is only ever read when the exit-code gate needs
  // one, OR a rich (md/github) report was asked to show baseline-derived
  // novelty. This keeps the plain-text/json default path exactly as it was
  // before `--format` existed: nothing new is read or computed for it, so
  // its stdout bytes cannot change.
  final wantsRichReport =
      config.format == CliOutputFormat.markdown ||
      config.format == CliOutputFormat.github;
  final needsComparison =
      config.gatingRequested ||
      (wantsRichReport && config.baselinePath != null);

  // A failure building the comparison (missing/unreadable/incomparable
  // baseline) is recorded but NOT returned yet — the primary report must
  // still reach stdout below before the command exits. Returning early here
  // silently drops the whole report for every format, which is worse than
  // the gate/baseline failure it was trying to report.
  BaselineComparison? comparison;
  int? comparisonFailureExit;
  String? comparisonFailureReason;
  if (needsComparison) {
    final built = await _buildComparison(
      config: config,
      result: result,
      readText: readText,
      err: err,
    );
    comparison = built.comparison;
    if (comparison == null) {
      comparisonFailureExit = built.exitCode;
      comparisonFailureReason = built.failureReason;
    }
  }
  final gate = (config.gatingRequested && comparison != null)
      ? evaluateGate(comparison, config.gate)
      : null;

  // A gate was actually REQUESTED (--fail-on-new-clusters / --max-*) but
  // could not be evaluated — distinct from "no gate requested" (which
  // renders `⚠ N clusters (no gate)`). Without this, a stdout-only CI reader
  // sees a line indistinguishable from never having asked for a gate at
  // all, even though the run is about to exit with a failure code.
  final gateUnavailableReason =
      config.gatingRequested && comparisonFailureExit != null
      ? (comparisonFailureReason ?? 'baseline could not be evaluated')
      : null;

  // The primary report always reaches stdout — even when the baseline/gate
  // path above already failed — because a caller that only reads stdout
  // (many CI wrappers do) must still see the report it can act on. Gate/
  // baseline diagnostics never go to stdout: text stays byte-stable (it
  // never discussed gate status, so this scenario cannot mislead it), the
  // others render richer detail from whatever comparison/gate is available
  // (possibly none, when the baseline path failed) plus the distinct
  // gate-unavailable verdict when applicable.
  out.writeln(switch (config.format) {
    CliOutputFormat.text => renderReport(result, top: config.top),
    CliOutputFormat.json =>
      gateUnavailableReason == null
          ? renderJson(result)
          : _renderJsonWithGateUnavailable(result, gateUnavailableReason),
    CliOutputFormat.markdown => renderMarkdownReport(
      result,
      comparison: comparison,
      gate: gate,
      gateUnavailableReason: gateUnavailableReason,
      github: false,
    ),
    CliOutputFormat.github => renderMarkdownReport(
      result,
      comparison: comparison,
      gate: gate,
      gateUnavailableReason: gateUnavailableReason,
      github: true,
    ),
  });

  final jsonOut = config.jsonOut;
  if (jsonOut != null) {
    try {
      await writeText(jsonOut, renderJson(result));
    } on FileSystemException catch (e) {
      err.writeln('Error writing JSON output: ${e.message} — ${e.path}');
      return AnalyzeExit.toolFailure;
    }
  }

  final writeBaselinePath = config.writeBaselinePath;
  if (writeBaselinePath != null) {
    final baseline = LeakBaseline.fromResult(result, createdAt: now());
    try {
      await writeText(writeBaselinePath, jsonEncode(baseline.toJson()));
    } on FileSystemException catch (e) {
      err.writeln('Error writing baseline: ${e.message} — ${e.path}');
      return AnalyzeExit.toolFailure;
    }
    err.writeln(
      'Wrote baseline (${result.clusters.length} clusters) to '
      '$writeBaselinePath',
    );
  }

  // Now that the report has reached stdout and any file writes ran, resolve
  // the actual outcome — honoring a comparison-build failure recorded above.
  if (comparisonFailureExit != null) return comparisonFailureExit;

  if (!config.gatingRequested) return AnalyzeExit.ok;
  if (gate == null) {
    // Unreachable in practice: gatingRequested implies needsComparison was
    // true above, so either a gate was computed here or comparisonFailureExit
    // was already returned above. Kept defensive rather than asserting
    // non-null.
    return AnalyzeExit.toolFailure;
  }

  if (gate.passed) {
    err.writeln('Gate passed.');
    return AnalyzeExit.ok;
  }
  err.writeln('Gate FAILED:');
  for (final violation in gate.violations) {
    err.writeln('  - $violation');
  }
  return AnalyzeExit.gateFailed;
}

/// Resolves the [BaselineComparison] for gate evaluation, honouring the
/// "never all-NEW / never false-green" honesty contract.
///
/// Returns a null comparison with a non-zero [exitCode] when the gate cannot be
/// evaluated honestly: a baseline-dependent gate without a baseline is a usage
/// error (1); an unreadable or incomparable baseline that a gate needs is a
/// tool failure (2). [failureReason] is a short, human-readable summary of
/// why (populated exactly when [comparison] is null) — callers thread it
/// into the rendered report's verdict line so a requested-but-unevaluated
/// gate never reads like no gate was requested at all.
Future<({BaselineComparison? comparison, int exitCode, String? failureReason})>
_buildComparison({
  required CliConfig config,
  required GraphAnalysisResult result,
  required TextReader readText,
  required StringSink err,
}) async {
  final baselinePath = config.baselinePath;

  if (baselinePath == null) {
    if (config.gate.requiresBaseline) {
      err.writeln(
        'A baseline-dependent gate was requested but no --baseline was '
        'provided. Pass --baseline <file> or drop the gate.',
      );
      return (
        comparison: null,
        exitCode: AnalyzeExit.usage,
        failureReason: 'no --baseline was provided',
      );
    }
    return (
      comparison: BaselineComparison.withoutBaseline(result),
      exitCode: AnalyzeExit.ok,
      failureReason: null,
    );
  }

  final String raw;
  try {
    raw = await readText(baselinePath);
  } on FileSystemException catch (e) {
    err.writeln('Error reading baseline: ${e.message} — ${e.path}');
    return (
      comparison: null,
      exitCode: AnalyzeExit.toolFailure,
      failureReason:
          'could not read baseline "$baselinePath" '
          '(${e.message})',
    );
  }

  final LeakBaseline baseline;
  try {
    baseline = LeakBaseline.fromJson(
      (jsonDecode(raw) as Map).cast<String, Object?>(),
    );
  } on Object catch (e) {
    err.writeln('Error parsing baseline "$baselinePath": $e');
    return (
      comparison: null,
      exitCode: AnalyzeExit.toolFailure,
      failureReason: 'could not parse baseline "$baselinePath"',
    );
  }

  if (isBaselineComparable(baseline.schemaVersion)) {
    return (
      comparison: compareToBaseline(result, baseline),
      exitCode: AnalyzeExit.ok,
      failureReason: null,
    );
  }

  // Incomparable baseline: report it and treat it as ABSENT — never classify
  // every current cluster as new.
  err.writeln(
    'baseline not comparable (schemaVersion ${baseline.schemaVersion})',
  );
  if (config.gate.requiresBaseline) {
    err.writeln(
      'Cannot evaluate a baseline-dependent gate against an incomparable '
      'baseline; refusing rather than reporting every cluster as new.',
    );
    return (
      comparison: null,
      exitCode: AnalyzeExit.toolFailure,
      failureReason:
          'baseline not comparable '
          '(schemaVersion ${baseline.schemaVersion})',
    );
  }
  return (
    comparison: BaselineComparison.withoutBaseline(result),
    exitCode: AnalyzeExit.ok,
    failureReason: null,
  );
}

/// Encodes [result] as JSON with an extra `gateUnavailable` key naming
/// [reason] — used only for the `--format json` stdout envelope when a
/// requested gate could not be evaluated. The `--json <file>` side-write and
/// the success path both keep calling [renderJson] directly and are
/// untouched by this.
String _renderJsonWithGateUnavailable(
  GraphAnalysisResult result,
  String reason,
) => jsonEncode({...result.toJson(), 'gateUnavailable': reason});

Future<HeapGraphView> _loadGraphFromFile(String path) =>
    loadHeapGraph(File(path));

Future<String> _readTextFromFile(String path) => File(path).readAsString();

Future<void> _writeTextToFile(String path, String contents) =>
    File(path).writeAsString(contents);

DateTime _nowUtc() => DateTime.now().toUtc();
