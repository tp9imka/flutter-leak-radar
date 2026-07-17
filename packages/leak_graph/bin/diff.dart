import 'dart:io';

import 'package:leak_graph/src/cli/diff_command.dart';

/// Diffs two heap snapshots into a per-class growth histogram.
///
/// Exit codes: 0 ok, 1 usage error, 2 tool failure.
Future<void> main(List<String> argv) async {
  final code = await runDiff(argv, out: stdout, err: stderr);
  exit(code);
}
