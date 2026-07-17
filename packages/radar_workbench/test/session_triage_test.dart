import 'package:flutter_test/flutter_test.dart';
import 'package:leak_graph/leak_graph.dart';
import 'package:radar_workbench/radar_workbench.dart';

import 'fakes.dart';

GraphLeakCluster _cluster(String signature) => GraphLeakCluster(
  className: 'Leaky',
  libraryUri: Uri.parse('package:my_app/x.dart'),
  instanceCount: 2,
  retainedShallowBytes: 100,
  representativePath: const GraphRetainingPath(
    hops: [GraphHop(className: 'Leaky')],
    rootKind: RootKind.stream,
  ),
  rootKind: RootKind.stream,
  confidence: LeakConfidence.heuristic,
  signature: signature,
);

SnapshotBundle _snap(List<String> signatures) => SnapshotBundle(
  id: 1,
  capturedAt: DateTime(2026),
  label: 's',
  histogram: const [],
  analysisResult: GraphAnalysisResult(
    clusters: [for (final s in signatures) _cluster(s)],
    stats: const GraphAnalysisStats(
      totalObjects: 0,
      reachableObjects: 0,
      leakCandidates: 0,
      clusters: 0,
      suppressedByAppFilter: 0,
      warnings: [],
    ),
    resolvedAppPackages: const ['my_app'],
  ),
);

void main() {
  final now = DateTime(2026, 7, 10, 12);

  group('PersistedSession triage round-trip', () {
    test('carries the triage store through toJson/fromJson', () {
      final triage = TriageStore.empty.acknowledge(
        'sigA',
        note: 'BUG-1',
        now: now,
      );
      final session = PersistedSession(
        bundles: const [],
        selectedIds: const [],
        view: RadarView.leakClusters,
        triage: triage,
      );
      final restored = PersistedSession.fromJson(session.toJson());
      expect(restored.triage, triage);
      expect(restored.triage.entryFor('sigA')!.note, 'BUG-1');
    });

    test('writes the current schema version', () {
      final json = const PersistedSession(
        bundles: [],
        selectedIds: [],
        view: RadarView.snapshotDiff,
      ).toJson();
      expect(json['version'], kSessionSchemaVersion);
    });
  });

  group('PersistedSession version gate', () {
    test('refuses a session newer than this build supports', () {
      final json = <String, Object?>{
        'version': kSessionSchemaVersion + 1,
        'bundles': const <Object?>[],
        'selectedIds': const <Object?>[],
        'view': 'leakClusters',
      };
      expect(
        () => PersistedSession.fromJson(json),
        throwsA(isA<UnsupportedSessionVersionException>()),
      );
    });

    test('migrates a v1 (pre-triage) session to an empty store', () {
      final json = <String, Object?>{
        'version': 1,
        'bundles': const <Object?>[],
        'selectedIds': const <Object?>[],
        'view': 'snapshotDiff',
        // No 'triage' key — the pre-A11 shape.
      };
      final restored = PersistedSession.fromJson(json);
      expect(restored.triage, TriageStore.empty);
    });
  });

  group('SessionPersistence folds current signatures as KNOWN on save', () {
    test(
      'promotes the focused snapshot signatures with firstSeen=clock',
      () async {
        final store = InMemorySnapshotStore();
        final memory = MemoryController(
          snapshotSource: FakeSnapshotSource(),
          connection: FakeRadarConnection(),
        )..debugAdd(_snap(['sigA', 'sigB']));
        var baseline = TriageStore.empty;
        final persistence = SessionPersistence(
          store: store,
          memory: memory,
          readView: () => RadarView.leakClusters,
          readTriage: () => baseline,
          clock: () => now,
        );

        await persistence.flush();

        final persisted = store.last!.triage;
        expect(persisted.entryFor('sigA')!.status, TriageStatus.known);
        expect(persisted.entryFor('sigA')!.firstSeen, now);
        expect(persisted.entryFor('sigB'), isNotNull);
        // The in-session baseline the views read is left un-promoted.
        expect(baseline, TriageStore.empty);
      },
    );

    test('carries a prior ACK through the save unchanged', () async {
      final store = InMemorySnapshotStore();
      final memory = MemoryController(
        snapshotSource: FakeSnapshotSource(),
        connection: FakeRadarConnection(),
      )..debugAdd(_snap(['sigA']));
      final baseline = TriageStore.empty.acknowledge('sigA', now: now);
      final persistence = SessionPersistence(
        store: store,
        memory: memory,
        readView: () => RadarView.leakClusters,
        readTriage: () => baseline,
        clock: () => now,
      );

      await persistence.flush();

      expect(
        store.last!.triage.entryFor('sigA')!.status,
        TriageStatus.acknowledged,
      );
    });
  });

  group('RadarSession triage lifecycle', () {
    tearDown(RadarSession.debugReset);

    test(
      'seeds the in-session triage baseline from the restored store',
      () async {
        final store = InMemorySnapshotStore();
        await store.persist(
          PersistedSession(
            bundles: const [],
            selectedIds: const [],
            view: RadarView.leakClusters,
            triage: TriageStore.empty.upsert(
              TriageEntry(
                signature: 'sigA',
                firstSeen: now,
                status: TriageStatus.known,
              ),
            ),
          ),
        );
        final connection = FakeRadarConnection();
        final session = RadarSession(
          connection: connection,
          memory: MemoryController(
            snapshotSource: FakeSnapshotSource(),
            connection: connection,
          ),
          perf: PerfDataController(),
          exporter: RecordingExporter(),
        );

        await session.attachStore(store);

        expect(session.triage.entryFor('sigA')!.status, TriageStatus.known);
      },
    );
  });
}
