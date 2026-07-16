import 'dart:io';

import 'package:leak_graph/src/cli/analyze_command.dart';

/// Analyzes a heap snapshot for leak clusters, optionally comparing against a
/// baseline and enforcing CI gate thresholds.
///
/// `--format` selects the primary report on stdout: `text` (default, plain
/// ranked report), `json` (the full analysis result), `md` (the 30-second
/// markdown report), or `github` (the same report with GitHub-flavored-
/// markdown admonitions for step summaries/PR comments).
///
/// Exit codes: 0 ok, 1 usage error, 2 tool failure, 3 gate failed.
Future<void> main(List<String> argv) async {
  final code = await runAnalyze(argv, out: stdout, err: stderr);
  exit(code);
}
