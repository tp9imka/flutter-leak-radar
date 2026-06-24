import 'package:args/args.dart';

/// Parsed command-line configuration for the analyze CLI.
final class CliConfig {
  final String dumpPath;
  final List<String> appPackages;
  final bool all;
  final int minCluster;
  final int top;
  final String? jsonOut;
  final bool confirm;

  const CliConfig({
    required this.dumpPath,
    required this.appPackages,
    required this.all,
    required this.minCluster,
    required this.top,
    required this.jsonOut,
    required this.confirm,
  });
}

final _parser = ArgParser()
  ..addMultiOption(
    'package',
    abbr: 'p',
    help: 'App package names to include in analysis (repeatable).',
  )
  ..addFlag(
    'all',
    negatable: false,
    help: 'Disable app-package filter — include all leaked objects.',
  )
  ..addOption(
    'min-cluster',
    defaultsTo: '2',
    help: 'Minimum number of instances to form a cluster.',
  )
  ..addOption(
    'top',
    defaultsTo: '50',
    help: 'Maximum number of clusters to display in the report.',
  )
  ..addOption('json', help: 'Write full JSON output to this file path.')
  ..addFlag(
    'confirm',
    negatable: false,
    help: 'Run reachability confirmation on each cluster.',
  );

/// Parses [argv] into a [CliConfig].
///
/// Throws [FormatException] with a usage message when the positional dump path
/// is missing or any option value is invalid.
CliConfig parseCliArgs(List<String> argv) {
  final ArgResults results;
  try {
    results = _parser.parse(argv);
  } on ArgParserException catch (e) {
    throw FormatException(
      '${e.message}\n\nUsage: analyze <dump.data> [options]\n${_parser.usage}',
    );
  }

  final rest = results.rest;
  if (rest.isEmpty) {
    throw FormatException(
      'Missing required positional argument: <dump.data>\n\nUsage: analyze <dump.data> [options]\n${_parser.usage}',
    );
  }

  final minCluster = int.tryParse(results['min-cluster'] as String);
  if (minCluster == null) {
    throw FormatException('--min-cluster must be an integer');
  }

  final top = int.tryParse(results['top'] as String);
  if (top == null) {
    throw FormatException('--top must be an integer');
  }

  return CliConfig(
    dumpPath: rest.first,
    appPackages: List<String>.from(results['package'] as List),
    all: results['all'] as bool,
    minCluster: minCluster,
    top: top,
    jsonOut: results['json'] as String?,
    confirm: results['confirm'] as bool,
  );
}
