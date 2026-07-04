import 'dart:convert';
import 'dart:io';

import 'package:radar_native/radar_native.dart';
import 'package:radar_native_host/radar_native_host.dart';

import '../../android/native_profiling_controller.dart';

/// Environment variable naming the `trace_processor_shell` (or equivalent)
/// binary, consulted when [PerfettoTraceImporter.traceProcessorPath] is not
/// set.
const String kTraceProcessorBinEnvVar = 'RADAR_TP_BIN';

/// Production [NativeTraceImporter]: parses heapprofd traces via an external
/// `trace_processor` binary and reads symbol-store/FFI-log JSON off disk.
final class PerfettoTraceImporter implements NativeTraceImporter {
  const PerfettoTraceImporter({this.traceProcessorPath});

  /// Resolves the current `trace_processor` binary path, called fresh at
  /// the start of every [importTrace] — e.g. `ToolsController.resolvedPath`,
  /// so a Locate/Install in the Tools screen takes effect on the very next
  /// import with no need to rebuild this importer. Falls back to
  /// [resolveTraceProcessorBinary] (the `RADAR_TP_BIN` env var) when this is
  /// null, or when calling it returns null.
  final String? Function()? traceProcessorPath;

  @override
  Future<NativeHeapProfile> importTrace(
    String path, {
    required String label,
  }) async {
    final binaryPath = resolveTraceProcessorBinary(
      explicit: traceProcessorPath?.call(),
    );
    final parser = PerfettoTraceProcessorParser(
      ProcessTraceProcessorRunner(binaryPath: binaryPath),
    );
    return parser.parseTrace(path, capturedAt: DateTime.now(), label: label);
  }

  @override
  Future<SymbolStore> importSymbolStore(String path) async {
    final raw = await File(path).readAsString();
    return SymbolStore.fromJson(jsonDecode(raw) as Map<String, Object?>);
  }

  @override
  Future<FfiAllocationLog> importFfiLog(String path) async {
    final raw = await File(path).readAsString();
    return const JsonFfiAllocationLogParser().parse(raw);
  }
}

/// Resolves the `trace_processor` binary path: [explicit] wins when
/// non-null and non-empty; otherwise the `RADAR_TP_BIN` entry of [env]
/// (defaulting to [Platform.environment]) when non-empty; otherwise throws a
/// [StateError] naming both options.
String resolveTraceProcessorBinary({
  String? explicit,
  Map<String, String>? env,
}) {
  if (explicit != null && explicit.isNotEmpty) return explicit;
  final fromEnv = (env ?? Platform.environment)[kTraceProcessorBinEnvVar];
  if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
  throw StateError(
    'No trace_processor binary configured: set the $kTraceProcessorBinEnvVar '
    'environment variable or pass a trace_processor path explicitly.',
  );
}
