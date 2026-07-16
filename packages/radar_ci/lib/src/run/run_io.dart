import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:leak_graph/io.dart';
import 'package:leak_graph/leak_graph.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import '../model/run_document.dart';
import 'attach.dart';
import 'run_clock.dart';
import 'run_command.dart';

/// Exit codes per the initiative-wide contract.
const int _exitOk = 0;
const int _exitUsage = 1;
const int _exitToolFailure = 2;

/// How long to wait for a spawned app to announce its VM-service URI.
const Duration _discoverTimeout = Duration(seconds: 90);

/// Runs the `run` verb end to end and returns a process exit code
/// (0 ok / 1 usage / 2 tool failure).
Future<int> runVerb(List<String> argv) async {
  final parser = buildRunArgParser();

  final ArgResults args;
  try {
    args = parser.parse(argv);
  } on FormatException catch (e) {
    stderr.writeln('${e.message}\n\n${parser.usage}');
    return _exitUsage;
  }

  if (args['help'] as bool) {
    stdout.writeln(
      'radar_ci run — attach to (or spawn) an app, sample memory into a '
      'run.json.\n\nUsage: radar_ci run (--vm-uri <uri> | --cmd "<command>") '
      '[options]\n\n${parser.usage}',
    );
    return _exitOk;
  }

  RunConfig config;
  try {
    config = parseRunConfig(args);
  } on UsageException catch (e) {
    stderr.writeln('${e.message}\n\n${parser.usage}');
    return _exitUsage;
  }

  if (config.vmUri == null && config.cmd == null) {
    stderr.writeln(
      'Provide --vm-uri <uri> or --cmd "<command>".\n\n'
      '${parser.usage}',
    );
    return _exitUsage;
  }
  if (config.vmUri != null && config.cmd != null) {
    stderr.writeln('--vm-uri and --cmd are mutually exclusive.');
    return _exitUsage;
  }

  config = await _resolveProjectPackages(config);

  Process? spawned;
  final String wsUri;
  try {
    if (config.vmUri != null) {
      wsUri = toWebSocketUri(config.vmUri!);
    } else {
      final launch = await _spawnAndDiscover(config.cmd!);
      spawned = launch.process;
      final discovered = launch.wsUri;
      if (discovered == null) {
        stderr.writeln(
          'Could not discover a VM-service URI from: ${config.cmd}\n'
          'Is the app running in debug/profile with the VM service enabled?',
        );
        spawned.kill();
        return _exitToolFailure;
      }
      wsUri = discovered;
    }
  } catch (error) {
    stderr.writeln('Spawn/attach failed: $error');
    spawned?.kill();
    return _exitToolFailure;
  }

  final VmService service;
  try {
    service = await vmServiceConnectUri(wsUri);
  } catch (error) {
    stderr.writeln('Could not connect to $wsUri: $error');
    spawned?.kill();
    return _exitToolFailure;
  }

  final mainIsolate = await _selectMainIsolate(service);
  final metadata = RunMetadata(
    startedAt: DateTime.now(),
    dartVersion: Platform.version.split(' ').first,
    mode: config.mode,
    cmdLine: config.cmd,
    notes: config.notes,
    projectPackages: config.projectPackages,
    projectPackagesSource: config.projectPackagesSource,
  );
  final stem = _outStem(config.outPath);
  final progress = RunProgress();

  // Reap the child and flush a partial run.json on Ctrl-C / SIGTERM, since the
  // finally below does not run once a signal handler calls exit().
  final signalSubs = _installInterruptReaper(
    progress: progress,
    metadata: metadata,
    outPath: config.outPath,
    killChild: () => spawned?.kill(),
  );

  RadarRunDocument? document;
  try {
    document = await executeRun(
      service: service,
      clock: const SystemRunClock(),
      config: config,
      metadata: metadata,
      progress: progress,
      warn: (message) => stderr.writeln('warning: $message'),
      captureSnapshot: mainIsolate == null
          ? null
          : (cp, tMicros) => _snapshotAndAnalyze(
              service,
              mainIsolate,
              config,
              stem,
              cp.label,
            ),
      driverHook: _buildDriverHook(service, mainIsolate, config),
    );
    return exitCodeForDocument(document);
  } catch (error, stack) {
    // executeRun degrades internally rather than throwing; reaching here is
    // truly unexpected, so still flush whatever was gathered.
    stderr.writeln('Run failed: $error\n$stack');
    document = progress.toDocument(metadata, abortReason: 'run failed: $error');
    return _exitToolFailure;
  } finally {
    for (final sub in signalSubs) {
      unawaited(sub.cancel());
    }
    if (document != null) {
      try {
        await _writeRunJson(config.outPath, document);
        stdout.writeln(config.outPath);
        _printSummary(document);
      } catch (error) {
        stderr.writeln('Failed to write ${config.outPath}: $error');
      }
    }
    await service.dispose();
    spawned?.kill();
  }
}

/// Installs SIGINT/SIGTERM handlers that reap the spawned child, flush the
/// in-flight [progress] as a partial `run.json`, and exit with the
/// tool-failure code. Idempotent; returns the subscriptions to cancel on a
/// clean finish. Signals unsupported on the host platform are skipped.
List<StreamSubscription<ProcessSignal>> _installInterruptReaper({
  required RunProgress progress,
  required RunMetadata metadata,
  required String outPath,
  required void Function() killChild,
}) {
  var handled = false;
  Future<void> onSignal(ProcessSignal signal) async {
    if (handled) return;
    handled = true;
    killChild();
    try {
      await flushPartialRun(
        progress: progress,
        metadata: metadata,
        outPath: outPath,
        abortReason: 'interrupted',
      );
      stderr.writeln(
        'radar_ci: interrupted ($signal) — wrote partial $outPath',
      );
    } catch (error) {
      stderr.writeln('radar_ci: interrupted; failed to flush partial: $error');
    }
    exit(_exitToolFailure);
  }

  final subs = <StreamSubscription<ProcessSignal>>[];
  for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
    try {
      subs.add(signal.watch().listen(onSignal));
    } catch (_) {
      // Signal unsupported on this platform (e.g. SIGTERM on Windows).
    }
  }
  return subs;
}

/// Flushes the in-flight [progress] as a partial run artifact
/// (`completed: false`, [abortReason]) to [outPath], returning the document.
///
/// Extracted so the interrupt-cleanup path is unit-testable without raising a
/// real OS signal.
Future<RadarRunDocument> flushPartialRun({
  required RunProgress progress,
  required RunMetadata metadata,
  required String outPath,
  required String abortReason,
}) async {
  final document = progress.toDocument(metadata, abortReason: abortReason);
  await _writeRunJson(outPath, document);
  return document;
}

Future<void> _writeRunJson(String outPath, RadarRunDocument document) async {
  final outFile = File(outPath);
  if (!await outFile.parent.exists()) {
    await outFile.parent.create(recursive: true);
  }
  await outFile.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(document.toJson())}\n',
  );
}

Future<RunConfig> _resolveProjectPackages(RunConfig config) async {
  if (config.projectPackagesSource == 'flag') return config;
  final detected = await projectPackagesFromDir(Directory.current.path);
  if (detected.isEmpty) return config;
  return config.withProjectPackages(detected.toList()..sort(), 'io-detect');
}

/// Spawns [command] (whitespace-split), merges its stdout+stderr, and scans
/// for the app's VM-service URI. The process keeps running on return.
Future<({Process process, String? wsUri})> _spawnAndDiscover(
  String command,
) async {
  final parts = command
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) {
    throw const FormatException('--cmd is empty');
  }
  final process = await Process.start(
    parts.first,
    parts.sublist(1),
    mode: ProcessStartMode.normal,
  );

  final lines = StreamController<String>();
  final subs = <StreamSubscription<String>>[
    for (final stream in [process.stdout, process.stderr])
      stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(lines.add, onError: (_) {}),
  ];

  final wsUri = await scanForVmServiceUri(
    lines.stream,
    timeout: _discoverTimeout,
  );
  for (final sub in subs) {
    unawaited(sub.cancel());
  }
  unawaited(lines.close());
  return (process: process, wsUri: wsUri);
}

Future<IsolateRef?> _selectMainIsolate(VmService service) async {
  final vm = await service.getVM();
  final isolates = vm.isolates ?? const <IsolateRef>[];
  if (isolates.isEmpty) return null;
  for (final isolate in isolates) {
    if (isolate.name == 'main') return isolate;
  }
  return isolates.first;
}

/// Dumps a heap snapshot for the main isolate and analyses it in-process,
/// writing both files next to `run.json`. Degrades honestly: on snapshot
/// failure returns null; on analysis failure keeps the snapshot path.
Future<CheckpointCapture?> _snapshotAndAnalyze(
  VmService service,
  IsolateRef isolate,
  RunConfig config,
  String stem,
  String label,
) async {
  final snapshotPath = '$stem.$label.data';
  try {
    await _dumpHeapSnapshot(service, isolate, snapshotPath);
  } catch (error) {
    return (
      snapshotPath: null,
      analysisPath: null,
      error: 'heap snapshot failed: $error',
    );
  }

  try {
    final graph = await loadHeapGraph(File(snapshotPath));
    final result = const GraphLeakAnalyzer().analyze(
      graph,
      GraphAnalysisOptions(appPackages: config.projectPackages),
    );
    final analysisPath = '$stem.$label.analysis.json';
    await File(analysisPath).writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(result.toJson())}\n',
    );
    return (
      snapshotPath: snapshotPath,
      analysisPath: analysisPath,
      error: null,
    );
  } catch (error) {
    return (
      snapshotPath: snapshotPath,
      analysisPath: null,
      error: 'analysis failed: $error',
    );
  }
}

/// Streams the raw `dartheap` snapshot for [isolate] to [outPath].
Future<void> _dumpHeapSnapshot(
  VmService service,
  IsolateRef isolate,
  String outPath,
) async {
  await service.streamListen(EventStreams.kHeapSnapshot);
  final sink = File(outPath).openWrite();
  final done = Completer<void>();

  late final StreamSubscription<Event> sub;
  sub = service.onHeapSnapshotEvent.listen(
    (event) {
      final data = event.data;
      if (data != null) {
        sink.add(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
      }
      if (event.last == true && !done.isCompleted) done.complete();
    },
    onError: (Object error) {
      if (!done.isCompleted) done.completeError(error);
    },
  );

  try {
    await service.requestHeapSnapshot(isolate.id!);
    await done.future;
  } finally {
    await sub.cancel();
    await service.streamCancel(EventStreams.kHeapSnapshot);
    await sink.flush();
    await sink.close();
  }
}

/// Builds the between-checkpoints driver hook, or null when neither `--exec`
/// nor `--call-extension` was given. Hook failures are logged, never fatal.
Future<void> Function()? _buildDriverHook(
  VmService service,
  IsolateRef? isolate,
  RunConfig config,
) {
  final exec = config.execCommand;
  final extension = config.callExtension;
  if (exec != null) {
    return () async {
      try {
        final result = await Process.run('/bin/sh', ['-c', exec]);
        if (result.exitCode != 0) {
          stderr.writeln('warning: --exec exited ${result.exitCode}');
        }
      } catch (error) {
        stderr.writeln('warning: --exec failed: $error');
      }
    };
  }
  if (extension != null && isolate != null) {
    return () async {
      try {
        await service.callServiceExtension(extension, isolateId: isolate.id);
      } catch (error) {
        stderr.writeln('warning: --call-extension "$extension" failed: $error');
      }
    };
  }
  return null;
}

String _outStem(String outPath) => outPath.endsWith('.json')
    ? outPath.substring(0, outPath.length - '.json'.length)
    : outPath;

void _printSummary(RadarRunDocument document) {
  stderr.writeln('captured ${document.checkpoints.length} checkpoints');
  for (final series in document.series) {
    stderr.writeln(
      '  ${series.name}: ${series.samples.length} samples, '
      '${series.gaps.length} gaps',
    );
  }
}
