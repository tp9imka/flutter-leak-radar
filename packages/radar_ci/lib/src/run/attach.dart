import 'dart:async';
import 'dart:convert';

import 'package:radar_native_host/radar_native_host.dart'
    show parseLogcatVmServiceUris;

/// Normalises a VM-service URI to the WebSocket form `vmServiceConnectUri`
/// expects: `http`→`ws`, `https`→`wss`, with exactly one trailing `/ws`.
String toWebSocketUri(String raw) {
  var uri = Uri.parse(raw.trim());
  if (uri.scheme == 'http') uri = uri.replace(scheme: 'ws');
  if (uri.scheme == 'https') uri = uri.replace(scheme: 'wss');
  var path = uri.path;
  if (!path.endsWith('/ws')) {
    if (!path.endsWith('/')) path = '$path/';
    path = '${path}ws';
  }
  return uri.replace(path: path).toString();
}

/// Extracts and normalises a VM-service `wsUri` from one `flutter run
/// --machine` daemon line (a JSON array of event objects), or null.
///
/// Reads the `wsUri` param of an `app.debugPort` event — the event Flutter
/// emits once the VM service is reachable.
String? vmServiceWsUriFromMachineLine(String line) {
  final trimmed = line.trim();
  if (!trimmed.startsWith('[')) return null;

  final Object? decoded;
  try {
    decoded = jsonDecode(trimmed);
  } on FormatException {
    return null;
  }
  if (decoded is! List) return null;

  for (final entry in decoded) {
    if (entry is! Map) continue;
    if (entry['event'] != 'app.debugPort') continue;
    final params = entry['params'];
    if (params is! Map) continue;
    final wsUri = params['wsUri'];
    if (wsUri is String && wsUri.isNotEmpty) return toWebSocketUri(wsUri);
  }
  return null;
}

/// Discovers a normalised VM-service WebSocket URI from a single output
/// [line], trying the `flutter --machine` JSON form first, then the plain
/// `The Dart VM service is listening on …` / `Observatory listening on …`
/// wording (reusing radar_native_host's [parseLogcatVmServiceUris], which
/// matches plain `dart --enable-vm-service` stdout identically to adb logcat).
///
/// Returns null when the line carries no VM-service URI.
String? discoverVmServiceWsUri(String line) {
  final machine = vmServiceWsUriFromMachineLine(line);
  if (machine != null) return machine;

  final parsed = parseLogcatVmServiceUris(line);
  if (parsed.isEmpty) return null;
  final uri = parsed.first;
  final path = uri.path.isEmpty ? '/' : uri.path;
  return toWebSocketUri('http://${uri.host}:${uri.port}$path');
}

/// Scans a line-oriented output [stream] and completes with the first
/// discovered VM-service WebSocket URI, or null if the stream ends or
/// [timeout] elapses first.
///
/// The stream is left running; the caller owns its lifecycle (a spawned
/// process keeps producing output after attach).
Future<String?> scanForVmServiceUri(
  Stream<String> stream, {
  required Duration timeout,
}) {
  final completer = Completer<String?>();
  Timer? timer;
  late final StreamSubscription<String> subscription;

  void finish(String? uri) {
    if (completer.isCompleted) return;
    timer?.cancel();
    completer.complete(uri);
  }

  timer = Timer(timeout, () => finish(null));
  subscription = stream.listen(
    (line) {
      final uri = discoverVmServiceWsUri(line);
      if (uri != null) finish(uri);
    },
    onError: (_) => finish(null),
    onDone: () => finish(null),
    cancelOnError: false,
  );

  return completer.future.whenComplete(subscription.cancel);
}
