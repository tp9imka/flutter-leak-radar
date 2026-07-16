import 'dart:io';

import 'package:leak_graph/src/cli/analyze_command.dart';

/// Analyzes a heap snapshot for leak clusters, optionally comparing against a
/// baseline and enforcing CI gate thresholds.
///
/// Exit codes: 0 ok, 1 usage error, 2 tool failure, 3 gate failed.
Future<void> main(List<String> argv) async {
  final code = await runAnalyze(argv, out: stdout, err: stderr);
  exit(code);
}
