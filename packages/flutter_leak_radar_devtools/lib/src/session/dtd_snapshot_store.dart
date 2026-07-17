import 'dart:async';
import 'dart:convert';

import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:dtd/dtd.dart';
import 'package:radar_workbench/radar_workbench.dart';

import 'dtd_session_manifest.dart';

/// [SnapshotStore] backed by the Dart Tooling Daemon (DTD) file system service.
///
/// DevTools disposes this extension's iframe when another DevTools tab is
/// active, destroying all in-memory state. The only durable store an extension
/// can reach is the developer's file system via DTD, sandboxed to the IDE
/// workspace roots. We write one file per snapshot bundle plus a small manifest
/// under `<projectRoot>/.dart_tool/`, and rebuild the session from them on the
/// next launch.
///
/// Degrades to a no-op when no DTD connection is available (e.g. DevTools
/// attached to a bare VM service without a Tooling Daemon).
final class DtdSnapshotStore implements SnapshotStore {
  static const _manifestName = 'flutter_leak_radar_session.json';
  static const _filePrefix = 'flutter_leak_radar_snapshot_';
  static const _connectTimeout = Duration(seconds: 5);

  /// Bundle ids already written this session, so a re-persist after mutations
  /// only rewrites the small manifest, not every (multi-MB) bundle file.
  final Set<int> _writtenIds = {};

  String? _refusal;

  @override
  String? get restoreRefusal => _refusal;

  Future<DartToolingDaemon?> _connection() async {
    final conn = dtdManager.connection;
    if (conn.value != null) return conn.value;
    final completer = Completer<DartToolingDaemon?>();
    void listener() {
      if (conn.value != null && !completer.isCompleted) {
        completer.complete(conn.value);
      }
    }

    conn.addListener(listener);
    final result = await completer.future.timeout(
      _connectTimeout,
      onTimeout: () => conn.value,
    );
    conn.removeListener(listener);
    return result;
  }

  /// `<workspaceRoot>/.dart_tool/` — a directory present in any built project
  /// and conventionally gitignored. `writeFileAsString` creates files but not
  /// parent dirs, so we target one known to exist. Null when unavailable.
  Future<Uri?> _baseDir() async {
    if (!dtdManager.hasConnection) return null;
    final roots =
        (await dtdManager.projectRoots())?.uris ??
        (await dtdManager.workspaceRoots())?.ideWorkspaceRoots ??
        const <Uri>[];
    if (roots.isEmpty) return null;
    var root = roots.first;
    if (!root.path.endsWith('/')) {
      root = root.replace(path: '${root.path}/');
    }
    return root.resolve('.dart_tool/');
  }

  @override
  Future<void> persist(PersistedSession session) async {
    // Suppress writes while refusing a newer-schema session, so it is not
    // overwritten before the user chooses to start fresh.
    if (_refusal != null) return;
    final dtd = await _connection();
    if (dtd == null) return;
    final base = await _baseDir();
    if (base == null) return;
    try {
      for (final b in session.bundles) {
        if (_writtenIds.contains(b.id)) continue;
        await dtd.writeFileAsString(
          base.resolve('$_filePrefix${b.id}.json'),
          jsonEncode(b.toJson()),
        );
        _writtenIds.add(b.id);
      }
      await dtd.writeFileAsString(
        base.resolve(_manifestName),
        jsonEncode(buildSessionManifest(session)),
      );
    } on Exception {
      // Sandbox/permission denied or missing dir — degrade to in-memory only.
    }
  }

  @override
  Future<PersistedSession?> restore() async {
    final dtd = await _connection();
    if (dtd == null) return null;
    final base = await _baseDir();
    if (base == null) return null;
    try {
      final manifestStr = (await dtd.readFileAsString(
        base.resolve(_manifestName),
      )).content;
      if (manifestStr == null || manifestStr.isEmpty) return null;
      final manifest = parseSessionManifest(
        jsonDecode(manifestStr) as Map<String, Object?>,
      );

      final bundles = <SnapshotBundle>[];
      for (final id in manifest.bundleIds) {
        final content = (await dtd.readFileAsString(
          base.resolve('$_filePrefix$id.json'),
        )).content;
        if (content != null && content.isNotEmpty) {
          bundles.add(
            SnapshotBundle.fromJson(
              (jsonDecode(content) as Map).cast<String, Object?>(),
            ),
          );
          _writtenIds.add(id);
        }
      }

      // A triage-only session (fixes recorded, all bundles pruned) is still
      // worth restoring — do not drop it just because there are no bundles.
      if (bundles.isEmpty && manifest.triage.entries.isEmpty) return null;

      return PersistedSession(
        bundles: bundles,
        selectedIds: manifest.selectedIds,
        view: manifest.view,
        triage: manifest.triage,
      );
    } on UnsupportedSessionVersionException catch (e) {
      // A newer build wrote this session — refuse it (and suppress writes so
      // it is not overwritten) rather than truncating.
      _refusal = e.toString();
      return null;
    } on Exception {
      // Manifest missing (first run), permission denied, or corrupt JSON —
      // start fresh rather than surfacing an error.
      return null;
    }
  }

  @override
  Future<void> clear() async {
    _refusal = null;
    final dtd = await _connection();
    if (dtd == null) return;
    final base = await _baseDir();
    if (base == null) return;
    _writtenIds.clear();
    try {
      // DTD exposes no delete RPC; the manifest is the source of truth, so an
      // empty manifest orphans (ignores) any leftover bundle files.
      await dtd.writeFileAsString(
        base.resolve(_manifestName),
        jsonEncode(
          buildSessionManifest(
            const PersistedSession(
              bundles: [],
              selectedIds: [],
              view: RadarView.snapshotDiff,
            ),
          ),
        ),
      );
    } on Exception {
      // ignore — best-effort clear.
    }
  }
}
