import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

import '../analysis/histogram_diff.dart';
import '../graph/heap_graph_view.dart';
import '../graph/snapshot_loader.dart';

/// Loads a heap graph from a snapshot file path (injectable for tests).
typedef HeapGraphLoader = Future<HeapGraphView> Function(String path);

/// Exit codes for the diff command: 0 ok / 1 usage error / 2 tool failure.
abstract final class DiffExit {
  static const int ok = 0;
  static const int usage = 1;
  static const int toolFailure = 2;
}

final _parser = ArgParser()
  ..addFlag(
    'json',
    negatable: false,
    help: 'Emit the diff as schema-stamped JSON instead of text.',
  )
  ..addFlag(
    'all',
    negatable: false,
    help: 'Include unchanged/shrinking classes in text output.',
  )
  ..addOption(
    'top',
    defaultsTo: '50',
    help: 'Maximum number of rows in text output.',
  );

/// Runs the histogram-diff command over two heap snapshots and returns its
/// exit code.
///
/// Consumes the same input `bin/analyze` does: raw VM heap snapshot files.
/// Each is loaded, reduced to a class histogram, and diffed with [computeDiff].
/// Output is text by default or schema-stamped JSON with `--json`.
Future<int> runDiff(
  List<String> argv, {
  required StringSink out,
  required StringSink err,
  HeapGraphLoader loadGraph = _loadGraphFromFile,
}) async {
  final ArgResults results;
  try {
    results = _parser.parse(argv);
  } on ArgParserException catch (e) {
    err.writeln(
      '${e.message}\n\n'
      'Usage: diff <before.data> <after.data> [options]\n${_parser.usage}',
    );
    return DiffExit.usage;
  }

  final rest = results.rest;
  if (rest.length != 2) {
    err.writeln(
      'Expected exactly two snapshot paths.\n\n'
      'Usage: diff <before.data> <after.data> [options]\n${_parser.usage}',
    );
    return DiffExit.usage;
  }

  final top = int.tryParse(results['top'] as String);
  if (top == null || top < 0) {
    err.writeln('--top must be a non-negative integer');
    return DiffExit.usage;
  }

  final List<ClassCount> before;
  final List<ClassCount> after;
  try {
    before = (await loadGraph(rest[0])).classHistogram();
    after = (await loadGraph(rest[1])).classHistogram();
  } on FileSystemException catch (e) {
    err.writeln('Error reading snapshot: ${e.message} — ${e.path}');
    return DiffExit.toolFailure;
  }

  final diffs = computeDiff(before, after);

  if (results['json'] as bool) {
    out.writeln(jsonEncode(encodeDiffReport(diffs)));
  } else {
    out.writeln(_renderDiffText(diffs, top: top, all: results['all'] as bool));
  }
  return DiffExit.ok;
}

String _renderDiffText(
  List<ClassCountDiff> diffs, {
  required int top,
  required bool all,
}) {
  final rows = all
      ? diffs
      : [
          for (final d in diffs)
            if (d.instanceDelta != 0) d,
        ];
  final shown = rows.length > top ? top : rows.length;
  final suppressed = rows.length - shown;

  final buf = StringBuffer()
    ..writeln(
      'Histogram diff: ${rows.length} class(es) changed'
      '${suppressed > 0 ? ', $suppressed suppressed by --top limit' : ''}',
    );
  for (var i = 0; i < shown; i++) {
    final d = rows[i];
    buf.writeln(
      '${_signed(d.instanceDelta)}  ${d.after.className}  '
      '(${_signed(d.bytesDelta)} B)',
    );
  }
  return buf.toString().trimRight();
}

String _signed(int value) => value >= 0 ? '+$value' : '$value';

Future<HeapGraphView> _loadGraphFromFile(String path) =>
    loadHeapGraph(File(path));
