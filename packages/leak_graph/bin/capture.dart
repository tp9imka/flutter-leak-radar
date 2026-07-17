import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:leak_graph/leak_graph.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

/// Dumps the raw heap snapshot of a running Dart/Flutter app to a file over its
/// VM Service — the command-line equivalent of a DevTools heap snapshot, with
/// no GUI. The written file is the faithful VM `dartheap` format (identical to
/// `NativeRuntime.writeHeapSnapshotToFile`), so it re-loads via
/// `loadHeapGraph` / `HeapSnapshotGraph.fromChunks` for any deeper analysis.
///
/// Point it at the VM Service URI from `flutter run`/`flutter attach`, or found
/// on a device via:
///   adb logcat | grep -i "VM service"     # -> http://127.0.0.1:DEVPORT/TOKEN=/
///   adb forward tcp:8181 tcp:DEVPORT
///   dart run leak_graph:capture --uri http://127.0.0.1:8181/TOKEN=/ -o heap.data
///
/// Exit codes follow the initiative-wide contract: 0 ok, 1 usage error (bad
/// flags or a missing `--uri`), 2 tool failure (could not connect, or the
/// target VM had no isolates).
Future<void> main(List<String> argv) async {
  final parser = _buildParser();

  ArgResults args;
  try {
    args = parser.parse(argv);
  } on FormatException catch (e) {
    stderr.writeln('${e.message}\n\n${parser.usage}');
    exit(1);
  }

  final uri = args['uri'] as String?;
  if (args['help'] as bool || uri == null) {
    stdout.writeln(
      'Dump a live heap snapshot to a file over the VM Service.\n\n'
      'Usage: dart run leak_graph:capture --uri <vm-service-uri> [-o out.data]\n\n'
      '${parser.usage}',
    );
    exit(uri == null && !(args['help'] as bool) ? 1 : 0);
  }

  final wsUri = _toWebSocketUri(uri);
  final outPath = (args['out'] as String?) ?? _defaultOutPath();

  final VmService service;
  try {
    service = await vmServiceConnectUri(wsUri.toString());
  } catch (e) {
    stderr.writeln(
      'Could not connect to $wsUri\n$e\n\n'
      'Is the app running in debug/profile and the port forwarded?\n'
      '  adb forward tcp:8181 tcp:<devicePort>',
    );
    exit(2);
  }

  try {
    final vm = await service.getVM();
    final isolates = vm.isolates ?? const <IsolateRef>[];
    if (isolates.isEmpty) {
      stderr.writeln('No isolates found on the target VM.');
      exit(2);
    }
    final isolate = _selectIsolate(isolates, args['isolate'] as String?);
    stderr.writeln('Target isolate: ${isolate.name} (${isolate.id})');

    if (args['gc'] as bool) {
      try {
        // reset:true doubles as a GC trigger (the same approach the DevTools
        // capture path uses), so the dump excludes just-freed garbage.
        await service.getAllocationProfile(isolate.id!, reset: true);
      } catch (_) {
        // Best-effort — proceed without GC if the target rejects it.
      }
    }

    stderr.writeln('Dumping heap snapshot…');
    final bytes = await _dumpRawSnapshot(service, isolate, outPath);
    stderr.writeln('Wrote ${_mib(bytes)} ($bytes bytes) to:');
    stdout.writeln(outPath);

    if (args['analyze'] as bool) {
      stderr.writeln('Analyzing…');
      final graph = await loadHeapGraph(File(outPath));
      final result = GraphLeakAnalyzer().analyze(
        graph,
        GraphAnalysisOptions(
          appPackages: args['app-package'] as List<String>,
          disableAppFilter: args['all'] as bool,
          minClusterSize: int.tryParse(args['min-cluster'] as String) ?? 2,
          confirmWithReachability: args['confirm'] as bool,
        ),
      );
      stderr.writeln(
        renderReport(result, top: int.tryParse(args['top'] as String) ?? 20),
      );
    }
  } finally {
    await service.dispose();
  }
}

/// Streams the raw heap snapshot for [isolate] and writes the concatenated
/// chunks to [outPath]. The chunks already carry the `dartheap` magic header,
/// so the file is a complete, self-describing VM heap snapshot.
Future<int> _dumpRawSnapshot(
  VmService service,
  IsolateRef isolate,
  String outPath,
) async {
  await service.streamListen(EventStreams.kHeapSnapshot);
  final sink = File(outPath).openWrite();
  final done = Completer<void>();
  var total = 0;

  late final StreamSubscription<Event> sub;
  sub = service.onHeapSnapshotEvent.listen(
    (event) {
      final data = event.data;
      if (data != null) {
        final view = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        sink.add(view);
        total += view.length;
      }
      if (event.last == true && !done.isCompleted) done.complete();
    },
    onError: (Object err) {
      if (!done.isCompleted) done.completeError(err);
    },
  );

  await service.requestHeapSnapshot(isolate.id!);
  await done.future;
  await sub.cancel();
  await service.streamCancel(EventStreams.kHeapSnapshot);
  await sink.flush();
  await sink.close();
  return total;
}

ArgParser _buildParser() => ArgParser()
  ..addOption(
    'uri',
    abbr: 'u',
    help:
        'VM Service URI (http(s):// or ws(s)://), '
        'e.g. http://127.0.0.1:8181/TOKEN=/',
  )
  ..addOption(
    'out',
    abbr: 'o',
    help:
        'Output file for the raw heap snapshot '
        '(default: heap_<timestamp>.data).',
  )
  ..addOption(
    'isolate',
    help: 'Isolate name or id to snapshot (default: the main isolate).',
  )
  ..addFlag(
    'gc',
    defaultsTo: true,
    help: 'Trigger a GC before the snapshot to drop floating garbage.',
  )
  ..addFlag(
    'analyze',
    abbr: 'a',
    negatable: false,
    help: 'Also print a leak report after dumping (off by default).',
  )
  ..addMultiOption(
    'app-package',
    abbr: 'p',
    help:
        'With --analyze: app-owned package prefix(es), '
        'e.g. package:katim_connect/.',
  )
  ..addFlag(
    'all',
    negatable: false,
    help: 'With --analyze: report every class.',
  )
  ..addOption(
    'min-cluster',
    defaultsTo: '2',
    help: 'With --analyze: min cluster size.',
  )
  ..addOption(
    'top',
    abbr: 't',
    defaultsTo: '20',
    help: 'With --analyze: top N clusters.',
  )
  ..addFlag(
    'confirm',
    negatable: false,
    help: 'With --analyze: reachability pass.',
  )
  ..addFlag('help', abbr: 'h', negatable: false);

String _defaultOutPath() {
  final stamp = DateTime.now()
      .toIso8601String()
      .replaceAll(':', '-')
      .replaceAll('.', '-');
  return 'heap_$stamp.data';
}

String _mib(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';

/// Normalises a VM Service URI to the WebSocket form `vmServiceConnectUri`
/// expects: `http`→`ws`, `https`→`wss`, and a `/ws` path suffix.
Uri _toWebSocketUri(String raw) {
  var u = Uri.parse(raw.trim());
  if (u.scheme == 'http') u = u.replace(scheme: 'ws');
  if (u.scheme == 'https') u = u.replace(scheme: 'wss');
  var path = u.path;
  if (!path.endsWith('/ws')) {
    if (!path.endsWith('/')) path = '$path/';
    path = '${path}ws';
  }
  return u.replace(path: path);
}

/// Picks the isolate to snapshot: an explicit `--isolate` match, else the one
/// named `main`, else the first.
IsolateRef _selectIsolate(List<IsolateRef> isolates, String? selector) {
  if (selector != null) {
    for (final iso in isolates) {
      if (iso.id == selector || iso.name == selector) return iso;
    }
    stderr.writeln('Isolate "$selector" not found; using the first isolate.');
  }
  for (final iso in isolates) {
    if (iso.name == 'main') return iso;
  }
  return isolates.first;
}
