import 'package:args/args.dart';
import 'package:vm_service/vm_service.dart';

import '../model/run_document.dart';
import 'checkpoint.dart';
import 'run_clock.dart';
import 'sampler.dart';

/// A snapshot/analysis pair produced at a checkpoint, either path nullable.
typedef CheckpointCapture = ({String? snapshotPath, String? analysisPath});

/// Thrown for a command-line usage error (maps to exit code 1).
final class UsageException implements Exception {
  /// The human-readable reason.
  final String message;

  /// Creates a usage exception.
  const UsageException(this.message);

  @override
  String toString() => 'UsageException: $message';
}

const int _second = 1000000;

/// The enforced minimum run duration unless `--allow-short` is passed.
const int kMinDurationMicros = 120 * _second;

/// Resolved configuration for one `radar_ci run`.
final class RunConfig {
  /// Total run duration, in microseconds.
  final int durationMicros;

  /// Interval between memory samples, in microseconds.
  final int sampleIntervalMicros;

  /// Warm-up window trimmed before assessment, in microseconds.
  final int settleMicros;

  /// Number of interior checkpoints (evenly spaced between start and end).
  final int checkpointCount;

  /// Take a heap snapshot every Nth checkpoint (0 disables).
  final int snapshotEvery;

  /// Number of top classes captured in each checkpoint's allocation profile.
  final int allocationTopN;

  /// Output path for `run.json`.
  final String outPath;

  /// App-owned package names scoping leak analysis.
  final List<String> projectPackages;

  /// How [projectPackages] was resolved (`flag`, `io-detect`, `none`).
  final String projectPackagesSource;

  /// An explicit VM-service URI to attach to, if given.
  final String? vmUri;

  /// A command to spawn the app, if given (mutually exclusive with [vmUri]).
  final String? cmd;

  /// A shell command fired between checkpoints, if given.
  final String? execCommand;

  /// A service extension fired between checkpoints, if given.
  final String? callExtension;

  /// App run mode recorded in metadata.
  final String? mode;

  /// Free-form operator note recorded in metadata.
  final String? notes;

  /// Creates a run configuration.
  const RunConfig({
    required this.durationMicros,
    required this.sampleIntervalMicros,
    required this.settleMicros,
    required this.checkpointCount,
    required this.snapshotEvery,
    required this.allocationTopN,
    required this.outPath,
    required this.projectPackages,
    required this.projectPackagesSource,
    this.vmUri,
    this.cmd,
    this.execCommand,
    this.callExtension,
    this.mode,
    this.notes,
  });

  /// Returns a copy with [projectPackages]/[projectPackagesSource] replaced,
  /// used after `dart:io` package auto-detection resolves them.
  RunConfig withProjectPackages(List<String> packages, String source) =>
      RunConfig(
        durationMicros: durationMicros,
        sampleIntervalMicros: sampleIntervalMicros,
        settleMicros: settleMicros,
        checkpointCount: checkpointCount,
        snapshotEvery: snapshotEvery,
        allocationTopN: allocationTopN,
        outPath: outPath,
        projectPackages: packages,
        projectPackagesSource: source,
        vmUri: vmUri,
        cmd: cmd,
        execCommand: execCommand,
        callExtension: callExtension,
        mode: mode,
        notes: notes,
      );
}

/// Parses a duration like `30s`, `3m`, `1h`, or a bare seconds count `45`.
///
/// Throws [FormatException] on anything else (including negatives).
int parseDurationMicros(String raw) {
  final match = RegExp(r'^(\d+)(ms|s|m|h)?$').firstMatch(raw.trim());
  if (match == null) {
    throw FormatException('not a duration (e.g. 30s, 3m, 1h): "$raw"');
  }
  final value = int.parse(match.group(1)!);
  return switch (match.group(2)) {
    'ms' => value * 1000,
    'h' => value * 3600 * _second,
    'm' => value * 60 * _second,
    _ => value * _second,
  };
}

/// Builds the argument parser for the `run` verb.
ArgParser buildRunArgParser() => ArgParser()
  ..addOption(
    'vm-uri',
    help: 'Attach to this VM-service URI (ws:// or http://).',
  )
  ..addOption('cmd', help: 'Spawn the app with this command and attach to it.')
  ..addOption('duration', abbr: 'd', defaultsTo: '3m', help: 'Total run time.')
  ..addOption(
    'sample-interval',
    defaultsTo: '5s',
    help: 'Time between samples.',
  )
  ..addOption('settle', defaultsTo: '30s', help: 'Warm-up window to trim.')
  ..addOption(
    'checkpoints',
    defaultsTo: '3',
    help: 'Interior checkpoint count.',
  )
  ..addOption(
    'snapshot-every',
    defaultsTo: '1',
    help: 'Full heap snapshot every Nth checkpoint (0 = none).',
  )
  ..addOption(
    'allocation-top',
    defaultsTo: '20',
    help: 'Top N classes per checkpoint allocation profile.',
  )
  ..addOption('exec', help: 'Shell command fired between checkpoints.')
  ..addOption(
    'call-extension',
    help: 'Service extension fired between checkpoints.',
  )
  ..addOption('out', abbr: 'o', defaultsTo: 'run.json', help: 'Output path.')
  ..addOption(
    'project-packages',
    help: 'Comma-separated app package names (else auto-detected from cwd).',
  )
  ..addOption('mode', defaultsTo: 'profile', help: 'App run mode label.')
  ..addOption('notes', help: 'Free-form note recorded in metadata.')
  ..addFlag(
    'allow-short',
    negatable: false,
    help: 'Permit a duration below the 2m minimum.',
  )
  ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage.');

/// Resolves an [ArgResults] into a validated [RunConfig].
///
/// Throws [UsageException] on invalid combinations (e.g. a sub-2m duration
/// without `--allow-short`, or a non-positive interval).
RunConfig parseRunConfig(ArgResults args) {
  int intOf(String name) {
    final raw = args[name] as String;
    final value = int.tryParse(raw);
    if (value == null) {
      throw UsageException('--$name must be an integer: "$raw"');
    }
    return value;
  }

  final int durationMicros;
  final int sampleIntervalMicros;
  final int settleMicros;
  try {
    durationMicros = parseDurationMicros(args['duration'] as String);
    sampleIntervalMicros = parseDurationMicros(
      args['sample-interval'] as String,
    );
    settleMicros = parseDurationMicros(args['settle'] as String);
  } on FormatException catch (e) {
    throw UsageException(e.message);
  }

  if (sampleIntervalMicros <= 0) {
    throw const UsageException('--sample-interval must be positive');
  }
  final allowShort = args['allow-short'] as bool;
  if (durationMicros < kMinDurationMicros && !allowShort) {
    throw UsageException(
      'duration ${args['duration']} is below the 2m minimum; pass '
      '--allow-short to override (short runs may be un-assessable)',
    );
  }

  final packagesFlag = args['project-packages'] as String?;
  final packages = packagesFlag == null
      ? const <String>[]
      : [
          for (final name in packagesFlag.split(','))
            if (name.trim().isNotEmpty) name.trim(),
        ];

  return RunConfig(
    durationMicros: durationMicros,
    sampleIntervalMicros: sampleIntervalMicros,
    settleMicros: settleMicros,
    checkpointCount: intOf('checkpoints'),
    snapshotEvery: intOf('snapshot-every'),
    allocationTopN: intOf('allocation-top'),
    outPath: args['out'] as String,
    projectPackages: packages,
    projectPackagesSource: packagesFlag == null ? 'none' : 'flag',
    vmUri: args['vm-uri'] as String?,
    cmd: args['cmd'] as String?,
    execCommand: args['exec'] as String?,
    callExtension: args['call-extension'] as String?,
    mode: args['mode'] as String?,
    notes: args['notes'] as String?,
  );
}

/// Drives the sampling loop against a connected [service], returning the
/// assembled [RadarRunDocument].
///
/// Time is driven through [clock] so tests run the whole cadence in virtual
/// time. Samples and checkpoints are interleaved by their offsets; a checkpoint
/// captures an allocation profile (via [onCheckpoint] for observation and/or
/// [captureSnapshot] for a heap dump), and the optional [driverHook] fires
/// once between each pair of checkpoints (never after the last). [warn] is
/// invoked once if the cadence cannot reach an assessable post-settle sample
/// count.
Future<RadarRunDocument> executeRun({
  required VmService service,
  required RunClock clock,
  required RunConfig config,
  required RunMetadata metadata,
  Future<CheckpointCapture?> Function(ScheduledCheckpoint cp, int tMicros)?
  captureSnapshot,
  Future<void> Function(ScheduledCheckpoint cp, int tMicros)? onCheckpoint,
  Future<void> Function()? driverHook,
  void Function(String message)? warn,
}) async {
  if (warn != null &&
      !isAssessableCadence(
        durationMicros: config.durationMicros,
        sampleIntervalMicros: config.sampleIntervalMicros,
        settleMicros: config.settleMicros,
      )) {
    final projected = projectedPostSettleSampleCount(
      durationMicros: config.durationMicros,
      sampleIntervalMicros: config.sampleIntervalMicros,
      settleMicros: config.settleMicros,
    );
    warn(
      'cadence yields only $projected post-settle samples '
      '(< $kMannKendallSampleFloor): growth verdicts will read '
      'insufficientData. Lengthen --duration, shorten --sample-interval, '
      'or reduce --settle to make this run assessable.',
    );
  }

  final sampler = MemorySampler(service);
  final sampleOffsets = sampleOffsetsMicros(
    durationMicros: config.durationMicros,
    sampleIntervalMicros: config.sampleIntervalMicros,
  ).toSet();
  final plan = planCheckpoints(
    durationMicros: config.durationMicros,
    interiorCount: config.checkpointCount,
    snapshotEvery: config.snapshotEvery,
  );
  final checkpointByOffset = {for (final cp in plan) cp.offsetMicros: cp};

  final offsets = {...sampleOffsets, ...checkpointByOffset.keys}.toList()
    ..sort();

  final readings = <MemoryReading>[];
  final checkpoints = <RunCheckpoint>[];
  final startMicros = clock.nowMicros();

  for (final offset in offsets) {
    final target = startMicros + offset;
    await clock.delay(Duration(microseconds: target - clock.nowMicros()));
    final now = clock.nowMicros();

    if (sampleOffsets.contains(offset)) {
      readings.add(await sampler.read(now));
    }

    final cp = checkpointByOffset[offset];
    if (cp == null) continue;

    final allocationTopN = await captureAllocationTopN(
      service,
      topN: config.allocationTopN,
    );
    final capture = cp.takeSnapshot && captureSnapshot != null
        ? await captureSnapshot(cp, now)
        : null;
    checkpoints.add(
      RunCheckpoint(
        tMicros: now,
        label: cp.label,
        allocationTopN: allocationTopN,
        snapshotPath: capture?.snapshotPath,
        analysisPath: capture?.analysisPath,
      ),
    );
    if (onCheckpoint != null) await onCheckpoint(cp, now);

    final isLast = identical(cp, plan.last);
    if (!isLast && driverHook != null) await driverHook();
  }

  return RadarRunDocument(
    metadata: metadata,
    series: readingsToSeries(readings),
    checkpoints: checkpoints,
  );
}
