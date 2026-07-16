import 'dart:io';

import 'package:radar_ci/radar_ci_io.dart';

const String _usage = '''
radar_ci — headless memory tracking around a real app run.

Usage: radar_ci <verb> [options]

Verbs:
  run     Attach to (or spawn) an app, sample memory, emit run.json.
  help    Show this message.

Run `radar_ci run --help` for run options.
''';

/// Dispatches `radar_ci <verb>` and exits with the verb's status code.
///
/// Exit contract: 0 ok / 1 usage error / 2 tool failure / 3 gate failed.
Future<void> main(List<String> argv) async {
  if (argv.isEmpty) {
    stderr.writeln(_usage);
    exit(1);
  }

  final verb = argv.first;
  final rest = argv.sublist(1);

  final code = switch (verb) {
    'run' => await runVerb(rest),
    'help' || '-h' || '--help' => _printTopUsage(),
    _ => _unknownVerb(verb),
  };
  exit(code);
}

int _printTopUsage() {
  stdout.writeln(_usage);
  return 0;
}

int _unknownVerb(String verb) {
  stderr.writeln('Unknown verb "$verb".\n\n$_usage');
  return 1;
}
