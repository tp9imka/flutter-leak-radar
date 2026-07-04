import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:radar_native_host/radar_native_host.dart';

import 'tool_config.dart';

export 'tool_config.dart';

/// Persists [ToolConfig] to disk. Kept behind an interface so
/// [ToolsController] is testable with an in-memory fake — no real
/// filesystem or `path_provider` platform channel in unit tests.
abstract interface class ToolConfigStore {
  Future<ToolConfig> read();
  Future<void> write(ToolConfig config);
}

/// Persists [ToolConfig] as JSON (`tools.json`) under the app-support
/// directory. Mirrors `FileSnapshotStore`'s persistence pattern: best
/// effort, never throws into the UI — a missing or unreadable file
/// yields an empty config rather than an error, since "no config yet"
/// is the expected first run.
class FileToolConfigStore implements ToolConfigStore {
  FileToolConfigStore({this.fileName = 'tools.json'});

  final String fileName;

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, fileName));
  }

  @override
  Future<ToolConfig> read() async {
    try {
      final file = await _file();
      if (!file.existsSync()) return const ToolConfig({});
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map<String, Object?>) return const ToolConfig({});
      return ToolConfig.fromJson(raw);
    } catch (_) {
      return const ToolConfig({});
    }
  }

  @override
  Future<void> write(ToolConfig config) async {
    try {
      final file = await _file();
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(config.toJson()));
    } catch (_) {
      // Best-effort persistence; ignore I/O failures.
    }
  }
}

/// Owns tool discovery and the user's persisted path overrides: probes
/// every [ExternalTool] on [load], lets the user pin one via [locate] or
/// fetch `trace_processor` via [installTraceProcessor], and re-probes on
/// [recheck]. Screens read [statuses]/[statusOf]/[resolvedPath] and
/// listen for updates like any other `ChangeNotifier`.
class ToolsController extends ChangeNotifier {
  ToolsController({
    ToolProbe probe = const ToolProbe(),
    TraceProcessorInstaller installer = const TraceProcessorInstaller(),
    ToolConfigStore? store,
    Map<String, String>? env,
    String? installDir,
  }) : _probe = probe,
       _installer = installer,
       _store = store ?? FileToolConfigStore(),
       _env = env ?? Platform.environment,
       _installDir = installDir;

  final ToolProbe _probe;
  final TraceProcessorInstaller _installer;
  final ToolConfigStore _store;
  final Map<String, String> _env;
  final String? _installDir;

  ToolConfig _config = const ToolConfig({});
  final Map<ExternalTool, ToolStatus> _statuses = {
    for (final tool in ExternalTool.values)
      tool: ToolStatus(tool: tool, found: false, source: ToolSource.none),
  };

  /// Guards [_notify] against firing after [dispose] — a probe/locate/
  /// install call started before disposal can still complete afterward
  /// (e.g. a widget torn down mid-request), and `ChangeNotifier` asserts
  /// if `notifyListeners` runs post-dispose.
  bool _disposed = false;

  /// Set when [installTraceProcessor] fails; cleared at the start of the
  /// next attempt. Null when there's nothing to show.
  String? installError;

  /// The current status for every [ExternalTool], in declaration order.
  List<ToolStatus> get statuses => [
    for (final tool in ExternalTool.values) _statuses[tool]!,
  ];

  /// The current status for [tool].
  ToolStatus statusOf(ExternalTool tool) => _statuses[tool]!;

  /// The resolved on-disk path for [tool], or null if it isn't found —
  /// a convenience for feeding the profiling seams.
  String? resolvedPath(ExternalTool tool) => _statuses[tool]!.path;

  /// True once every tool the import flow needs is found — at minimum
  /// `trace_processor`. Screens that need a per-feature answer should
  /// read [statusOf] instead.
  bool get allRequiredPresent => ExternalTool.values
      .where((tool) => tool.isRequiredForImport)
      .every((tool) => _statuses[tool]!.found);

  /// True if any known tool is missing.
  bool get anyMissing => _statuses.values.any((status) => !status.found);

  /// Reads the persisted config (empty on first run — a missing file is
  /// not an error) and probes every tool with its configured path.
  Future<void> load() async {
    _config = await _store.read();
    await _probeAll();
  }

  /// Re-probes every tool with its currently configured path, without
  /// re-reading the persisted config — for a manual "Re-check all".
  Future<void> recheck() => _probeAll();

  Future<void> _probeAll() async {
    for (final tool in ExternalTool.values) {
      _statuses[tool] = await _probe.probe(
        tool,
        configuredPath: _config.pathByToolId[tool.id],
        env: _env,
      );
    }
    _notify();
  }

  /// Saves [path] as the user-set location for [tool], persists it, and
  /// re-probes just that tool so [resolvedPath]/[statusOf] reflect it.
  Future<void> locate(ExternalTool tool, String path) async {
    _config = _config.withPath(tool.id, path);
    await _store.write(_config);
    _statuses[tool] = await _probe.probe(tool, configuredPath: path, env: _env);
    _notify();
  }

  /// Downloads `trace_processor` to `<installDir>/trace_processor`
  /// (`installDir` defaults to `<app-support>/bin`) and, on success,
  /// [locate]s it. Never throws — a failure is surfaced honestly via
  /// [installError] instead, so a failed install doesn't crash the app.
  Future<void> installTraceProcessor() async {
    installError = null;
    try {
      final dir = _installDir ?? await _defaultInstallDir();
      final path = await _installer.install(
        destPath: p.join(dir, 'trace_processor'),
      );
      await locate(ExternalTool.traceProcessor, path);
    } catch (e) {
      installError = e.toString();
      _notify();
    }
  }

  Future<String> _defaultInstallDir() async {
    final dir = await getApplicationSupportDirectory();
    return p.join(dir.path, 'bin');
  }

  /// Marks this controller disposed so a probe/locate/install call still
  /// in flight cannot [notifyListeners] afterward.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }
}
