import 'dart:io';

import 'perfetto_row.dart';
import 'perfetto_sql.dart';

/// Runs the still-live-with-stack query against a captured heapprofd trace
/// and returns the parsed rows.
abstract interface class TraceProcessorRunner {
  Future<List<PerfettoRow>> query(String tracePath);
}

/// [TraceProcessorRunner] backed by an external `trace_processor_shell`
/// binary, invoked via [Process.run].
final class ProcessTraceProcessorRunner implements TraceProcessorRunner {
  const ProcessTraceProcessorRunner({required this.binaryPath});

  /// Path to the `trace_processor_shell` (or equivalent) executable.
  final String binaryPath;

  @override
  Future<List<PerfettoRow>> query(String tracePath) async {
    final tempDir = Directory.systemTemp.createTempSync('radar_native_host_');
    final sqlFile = File('${tempDir.path}/still_live_with_stack.sql');
    try {
      await sqlFile.writeAsString(kStillLiveWithStackSql);
      final result = await Process.run(binaryPath, [
        tracePath,
        '-q',
        sqlFile.path,
      ]);
      if (result.exitCode != 0) {
        throw TraceProcessorException(
          'trace_processor exited with code ${result.exitCode}',
          stderr: result.stderr as String,
        );
      }
      return parseTraceProcessorOutput(result.stdout as String);
    } finally {
      await tempDir.delete(recursive: true);
    }
  }
}

/// Thrown when the `trace_processor` process exits with a non-zero code.
final class TraceProcessorException implements Exception {
  const TraceProcessorException(this.message, {required this.stderr});

  final String message;
  final String stderr;

  @override
  String toString() => 'TraceProcessorException: $message\n$stderr';
}

/// Number of cells a well-formed still-live-with-stack row splits into.
const int _cellCount = 9;

/// Exposed for testing: parse trace_processor's stdout into rows.
///
/// `trace_processor_shell -q` CSV-quotes its single `row` column: each data
/// line is wrapped in `"..."`, with any literal `"` inside doubled. This
/// strips that quoting per line, then splits the unquoted content on
/// U+001F into the 9 [PerfettoRow] cells. The header line (`"row"`) and
/// blank lines are dropped; any other malformed line is skipped rather
/// than thrown on.
List<PerfettoRow> parseTraceProcessorOutput(String stdout) => [
  for (final line in stdout.split('\n'))
    if (_unquoteCells(line) case final cells?) PerfettoRow.fromCells(cells),
];

List<String>? _unquoteCells(String line) {
  if (line.trim().isEmpty || line == '"row"') return null;
  if (line.length < 2 || !line.startsWith('"') || !line.endsWith('"')) {
    return null;
  }
  final unquoted = line.substring(1, line.length - 1).replaceAll('""', '"');
  final cells = unquoted.split('\u001F');
  return cells.length == _cellCount ? cells : null;
}
