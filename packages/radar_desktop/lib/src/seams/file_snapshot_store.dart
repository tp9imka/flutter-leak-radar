import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:radar_workbench/radar_workbench.dart';

/// Auto-restore session store backed by a JSON file under the app support
/// directory (`~/Library/Application Support/<bundle-id>/`). Degrades
/// gracefully — never throws into the UI; a read/parse failure yields null.
class FileSnapshotStore implements SnapshotStore {
  FileSnapshotStore({
    this.fileName = 'radar_desktop_session.json',
    Future<Directory> Function()? directory,
  }) : _directory = directory ?? getApplicationSupportDirectory;

  final String fileName;

  /// Resolves the directory the session file lives in. Injectable so tests can
  /// point at a temp dir without a `path_provider` platform mock.
  final Future<Directory> Function() _directory;

  String? _refusal;

  @override
  String? get restoreRefusal => _refusal;

  Future<File> _file() async {
    final dir = await _directory();
    return File(p.join(dir.path, fileName));
  }

  @override
  Future<void> persist(PersistedSession session) async {
    // Never overwrite a session written by a newer build while refusing it.
    if (_refusal != null) return;
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode(session.toJson()));
    } catch (_) {
      // Best-effort persistence; ignore I/O failures.
    }
  }

  @override
  Future<PersistedSession?> restore() async {
    try {
      final file = await _file();
      if (!file.existsSync()) return null;
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map<String, Object?>) return null;
      return PersistedSession.fromJson(raw);
    } on UnsupportedSessionVersionException catch (e) {
      // A newer build wrote this file — refuse it and record why, rather than
      // starting empty and clobbering it on the next persist.
      _refusal = e.toString();
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> clear() async {
    _refusal = null;
    try {
      final file = await _file();
      if (file.existsSync()) await file.delete();
    } catch (_) {}
  }

  /// Persists [session] to an absolute, user-chosen path (e.g. a
  /// `.radarworkspace` file picked via `saveWorkspace`).
  Future<void> persistAtPath(PersistedSession session, String path) async {
    try {
      await File(path).writeAsString(jsonEncode(session.toJson()));
    } catch (_) {}
  }

  /// Restores a session from an absolute, user-chosen path. Mirrors
  /// [restore] but never touches the app-support directory.
  Future<PersistedSession?> restoreFromPath(String path) async {
    try {
      final file = File(path);
      if (!file.existsSync()) return null;
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map<String, Object?>) return null;
      return PersistedSession.fromJson(raw);
    } catch (_) {
      return null;
    }
  }
}
