import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:radar_desktop/src/seams/file_snapshot_store.dart';
import 'package:radar_workbench/radar_workbench.dart';

void main() {
  late Directory dir;
  const fileName = 'session.json';

  setUp(() => dir = Directory.systemTemp.createTempSync('radar_fss_test'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  FileSnapshotStore store() =>
      FileSnapshotStore(fileName: fileName, directory: () async => dir);

  File sessionFile() => File(p.join(dir.path, fileName));

  test('round-trips the triage store through persist/restore', () async {
    final s = store();
    final triage = TriageStore.empty.acknowledge(
      'sigA',
      note: 'BUG-9',
      className: 'LeakyThing',
      now: DateTime(2026, 7, 1),
    );
    await s.persist(
      PersistedSession(
        bundles: const [],
        selectedIds: const [],
        view: RadarView.leakClusters,
        triage: triage,
      ),
    );
    final restored = await s.restore();
    expect(restored, isNotNull);
    expect(restored!.triage, triage);
    expect(s.restoreRefusal, isNull);
  });

  group('newer-schema file is refused, not overwritten', () {
    setUp(() {
      // Write a file one schema version ahead of this build.
      sessionFile().writeAsStringSync(
        jsonEncode({
          'version': kSessionSchemaVersion + 1,
          'bundles': const <Object?>[],
          'selectedIds': const <Object?>[],
          'view': 'leakClusters',
          'triage': const {'entries': <Object?>[]},
        }),
      );
    });

    test('restore refuses it and records a clear message', () async {
      final s = store();
      expect(await s.restore(), isNull);
      expect(s.restoreRefusal, isNotNull);
      expect(s.restoreRefusal, contains('newer'));
    });

    test('persist does NOT overwrite the newer file while refused', () async {
      final s = store();
      final before = sessionFile().readAsStringSync();
      await s.restore(); // sets the refusal
      await s.persist(
        const PersistedSession(
          bundles: [],
          selectedIds: [],
          view: RadarView.snapshotDiff,
        ),
      );
      // The newer file is untouched — the suppression held.
      expect(sessionFile().readAsStringSync(), before);
    });

    test('clear resets the refusal so persistence resumes', () async {
      final s = store();
      await s.restore();
      await s.clear();
      expect(s.restoreRefusal, isNull);
      await s.persist(
        const PersistedSession(
          bundles: [],
          selectedIds: [],
          view: RadarView.snapshotDiff,
        ),
      );
      // A fresh session now writes at the current schema version.
      final written =
          jsonDecode(sessionFile().readAsStringSync()) as Map<String, Object?>;
      expect(written['version'], kSessionSchemaVersion);
    });
  });
}
