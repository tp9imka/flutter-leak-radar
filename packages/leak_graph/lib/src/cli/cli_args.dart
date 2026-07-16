import 'package:args/args.dart';

import '../model/root_kind.dart';
import 'baseline.dart';

/// Output format for the primary report on stdout (`--format`).
enum CliOutputFormat {
  /// The original plain-text ranked report (default; byte-stable).
  text,

  /// The full analysis result as JSON — the same envelope `--json <file>`
  /// writes, printed to stdout instead.
  json,

  /// The 30-second markdown report, standard-markdown only.
  markdown,

  /// The 30-second markdown report with GitHub-flavored-markdown extras
  /// (step-summary/PR-comment tuning).
  github,
}

/// Parsed command-line configuration for the analyze CLI.
final class CliConfig {
  final String dumpPath;
  final List<String> appPackages;
  final bool all;
  final int minCluster;
  final int top;
  final String? jsonOut;
  final bool confirm;

  /// Output format for the primary report on stdout (`--format`).
  final CliOutputFormat format;

  /// Path to a baseline JSON to compare this run against (`--baseline`).
  final String? baselinePath;

  /// Path to write this run's clusters as a new baseline (`--write-baseline`).
  final String? writeBaselinePath;

  /// Gate thresholds assembled from the `--fail-on-*` / `--max-*` /
  /// `--min-confidence` flags.
  final GateOptions gate;

  const CliConfig({
    required this.dumpPath,
    required this.appPackages,
    required this.all,
    required this.minCluster,
    required this.top,
    required this.jsonOut,
    required this.confirm,
    this.format = CliOutputFormat.text,
    this.baselinePath,
    this.writeBaselinePath,
    this.gate = const GateOptions(),
  });

  /// Whether any gate threshold was requested on the command line.
  bool get gatingRequested =>
      gate.maxTotalClusters != null || gate.requiresBaseline;
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
  )
  ..addOption(
    'format',
    defaultsTo: 'text',
    help:
        'Primary report format on stdout: text|json|md|github '
        '(default: text).',
  )
  ..addOption(
    'baseline',
    help: 'Baseline JSON file to compare this run against.',
  )
  ..addOption(
    'write-baseline',
    help: "Write this run's clusters as a baseline JSON to this path.",
  )
  ..addFlag(
    'fail-on-new-clusters',
    negatable: false,
    help:
        'Fail (exit 3) if any cluster is absent from the baseline. '
        'Shorthand for --max-new-clusters 0. Requires --baseline.',
  )
  ..addOption(
    'max-new-clusters',
    help:
        'Fail if more than N clusters are new vs the baseline. '
        'Requires --baseline.',
  )
  ..addOption(
    'max-total-clusters',
    help: 'Fail if the run reports more than N clusters (no baseline needed).',
  )
  ..addOption(
    'max-class-growth-instances',
    help:
        'Fail if any known cluster grows by more than N instances vs the '
        'baseline. Requires --baseline.',
  )
  ..addOption(
    'max-heap-growth-bytes',
    help:
        'Fail if total retained shallow bytes grow by more than N vs the '
        'baseline. Requires --baseline.',
  )
  ..addOption(
    'min-confidence',
    help:
        'Only count clusters at or above this confidence in gate checks: '
        'heuristic|confirmed (default: heuristic).',
  );

/// Parses [argv] into a [CliConfig].
///
/// Throws [FormatException] with a usage message when the positional dump path
/// is missing or any option value is invalid. A [FormatException] maps to a
/// usage-error exit code (1) at the command boundary — it never indicates an
/// I/O or tool failure.
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
      'Missing required positional argument: <dump.data>\n\n'
      'Usage: analyze <dump.data> [options]\n${_parser.usage}',
    );
  }

  final minCluster = int.tryParse(results['min-cluster'] as String);
  if (minCluster == null) {
    throw const FormatException('--min-cluster must be an integer');
  }

  final top = int.tryParse(results['top'] as String);
  if (top == null) {
    throw const FormatException('--top must be an integer');
  }

  return CliConfig(
    dumpPath: rest.first,
    appPackages: List<String>.from(results['package'] as List),
    all: results['all'] as bool,
    minCluster: minCluster,
    top: top,
    jsonOut: results['json'] as String?,
    confirm: results['confirm'] as bool,
    format: _parseFormat(results['format'] as String),
    baselinePath: results['baseline'] as String?,
    writeBaselinePath: results['write-baseline'] as String?,
    gate: _parseGate(results),
  );
}

GateOptions _parseGate(ArgResults results) {
  final maxNew = _parseNullableInt(results, 'max-new-clusters');
  final failOnNew = results['fail-on-new-clusters'] as bool;
  return GateOptions(
    // An explicit --max-new-clusters wins; --fail-on-new-clusters means 0.
    maxNewClusters: maxNew ?? (failOnNew ? 0 : null),
    maxTotalClusters: _parseNullableInt(results, 'max-total-clusters'),
    maxClassGrowthInstances: _parseNullableInt(
      results,
      'max-class-growth-instances',
    ),
    maxHeapGrowthBytes: _parseNullableInt(results, 'max-heap-growth-bytes'),
    minConfidence: _parseConfidence(results['min-confidence'] as String?),
  );
}

int? _parseNullableInt(ArgResults results, String name) {
  final raw = results[name] as String?;
  if (raw == null) return null;
  final value = int.tryParse(raw);
  if (value == null || value < 0) {
    throw FormatException('--$name must be a non-negative integer');
  }
  return value;
}

/// Parses `--format`, accepting the short `md`/`github` spellings alongside
/// the [CliOutputFormat] enum names.
CliOutputFormat _parseFormat(String raw) => switch (raw) {
  'text' => CliOutputFormat.text,
  'json' => CliOutputFormat.json,
  'md' || 'markdown' => CliOutputFormat.markdown,
  'github' => CliOutputFormat.github,
  _ => throw FormatException(
    '--format must be one of: text|json|md|github (got "$raw")',
  ),
};

LeakConfidence _parseConfidence(String? raw) {
  if (raw == null) return LeakConfidence.heuristic;
  try {
    return LeakConfidence.values.byName(raw);
  } on ArgumentError {
    throw FormatException(
      '--min-confidence must be one of: '
      '${LeakConfidence.values.map((c) => c.name).join('|')}',
    );
  }
}
