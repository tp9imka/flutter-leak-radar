import 'dart:convert';
import 'dart:io';

import '../analysis/graph_leak_analyzer.dart';
import '../graph/heap_graph_view.dart';
import '../graph/snapshot_loader.dart';
import '../model/graph_analysis_result.dart';
import 'baseline.dart';
import 'cli_args.dart';
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

  // Byte-stable report goes to stdout unchanged; nothing else does.
  out.writeln(renderReport(result, top: config.top));

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

  if (!config.gatingRequested) return AnalyzeExit.ok;

  final (:comparison, :exitCode) = await _buildComparison(
    config: config,
    result: result,
    readText: readText,
    err: err,
  );
  if (comparison == null) return exitCode;

  final gate = evaluateGate(comparison, config.gate);
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
/// tool failure (2).
Future<({BaselineComparison? comparison, int exitCode})> _buildComparison({
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
      return (comparison: null, exitCode: AnalyzeExit.usage);
    }
    return (
      comparison: BaselineComparison.withoutBaseline(result),
      exitCode: AnalyzeExit.ok,
    );
  }

  final String raw;
  try {
    raw = await readText(baselinePath);
  } on FileSystemException catch (e) {
    err.writeln('Error reading baseline: ${e.message} — ${e.path}');
    return (comparison: null, exitCode: AnalyzeExit.toolFailure);
  }

  final LeakBaseline baseline;
  try {
    baseline = LeakBaseline.fromJson(
      (jsonDecode(raw) as Map).cast<String, Object?>(),
    );
  } on Object catch (e) {
    err.writeln('Error parsing baseline "$baselinePath": $e');
    return (comparison: null, exitCode: AnalyzeExit.toolFailure);
  }

  if (isBaselineComparable(baseline.schemaVersion)) {
    return (
      comparison: compareToBaseline(result, baseline),
      exitCode: AnalyzeExit.ok,
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
    return (comparison: null, exitCode: AnalyzeExit.toolFailure);
  }
  return (
    comparison: BaselineComparison.withoutBaseline(result),
    exitCode: AnalyzeExit.ok,
  );
}

Future<HeapGraphView> _loadGraphFromFile(String path) =>
    loadHeapGraph(File(path));

Future<String> _readTextFromFile(String path) => File(path).readAsString();

Future<void> _writeTextToFile(String path, String contents) =>
    File(path).writeAsString(contents);

DateTime _nowUtc() => DateTime.now().toUtc();
