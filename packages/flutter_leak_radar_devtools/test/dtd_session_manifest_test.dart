import 'dart:convert';

import 'package:flutter_leak_radar_devtools/src/session/dtd_session_manifest.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_workbench/radar_workbench.dart';

TriageStore _triage() => TriageStore.empty.acknowledge(
  'sigA',
  note: 'BUG-1',
  className: 'LeakyThing',
  now: DateTime(2026, 7, 1),
);

void main() {
  group('DevTools session manifest', () {
    test('round-trips the triage store through build/parse', () {
      final session = PersistedSession(
        bundles: const [],
        selectedIds: const [3, 7],
        view: RadarView.leakClusters,
        triage: _triage(),
      );

      // Encode + decode to mimic the on-disk JSON string.
      final json =
          jsonDecode(jsonEncode(buildSessionManifest(session)))
              as Map<String, Object?>;
      final parsed = parseSessionManifest(json);

      expect(parsed.triage, _triage());
      expect(parsed.triage.entryFor('sigA')!.note, 'BUG-1');
      expect(parsed.selectedIds, [3, 7]);
      expect(parsed.view, RadarView.leakClusters);
    });

    test('parses a triage-only manifest (no bundles) with triage intact', () {
      final session = PersistedSession(
        bundles: const [],
        selectedIds: const [],
        view: RadarView.snapshotDiff,
        triage: _triage(),
      );
      final parsed = parseSessionManifest(buildSessionManifest(session));
      expect(parsed.bundleIds, isEmpty);
      expect(parsed.triage.entries, isNotEmpty);
    });

    test('refuses a manifest written by a newer build', () {
      final json = <String, Object?>{
        'version': kSessionSchemaVersion + 1,
        'bundleIds': const <Object?>[],
        'selectedIds': const <Object?>[],
        'view': 'leakClusters',
        'triage': const {'entries': <Object?>[]},
      };
      expect(
        () => parseSessionManifest(json),
        throwsA(isA<UnsupportedSessionVersionException>()),
      );
    });

    test('an absent triage key migrates to an empty store', () {
      final json = <String, Object?>{
        'version': kSessionSchemaVersion,
        'bundleIds': const <Object?>[1],
        'selectedIds': const <Object?>[1],
        'view': 'snapshotDiff',
      };
      expect(parseSessionManifest(json).triage, TriageStore.empty);
    });
  });
}
