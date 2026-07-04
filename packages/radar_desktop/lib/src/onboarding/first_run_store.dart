import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Persists whether the user has completed or skipped the first-run
/// guide. Kept behind an interface so [FirstRunGuideController] is
/// testable with an in-memory fake — no real filesystem or
/// `path_provider` platform channel in unit tests.
abstract interface class FirstRunStore {
  Future<bool> hasSeen();
  Future<void> markSeen();
}

/// Persists the seen flag as JSON (`first_run.json`, `{"seen": true}`)
/// under the app-support directory. Mirrors `FileToolConfigStore`'s
/// persistence pattern: best effort, never throws into the UI — a
/// missing or unreadable file reads as "not seen yet", since that's the
/// expected state on first run.
final class FileFirstRunStore implements FirstRunStore {
  const FileFirstRunStore({this.fileName = 'first_run.json'});

  final String fileName;

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, fileName));
  }

  @override
  Future<bool> hasSeen() async {
    try {
      final file = await _file();
      if (!file.existsSync()) return false;
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map<String, Object?>) return false;
      return raw['seen'] == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> markSeen() async {
    try {
      final file = await _file();
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode({'seen': true}));
    } catch (_) {
      // Best-effort persistence; ignore I/O failures.
    }
  }
}
