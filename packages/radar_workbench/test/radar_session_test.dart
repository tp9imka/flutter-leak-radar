import 'package:flutter_test/flutter_test.dart';
import 'package:leak_graph/leak_graph.dart';
import 'package:radar_workbench/radar_workbench.dart';

import 'fakes.dart';

RadarSession _build() {
  final connection = FakeRadarConnection();
  return RadarSession(
    connection: connection,
    memory: MemoryController(
      snapshotSource: FakeSnapshotSource(),
      connection: connection,
    ),
    perf: PerfDataController(),
    exporter: RecordingExporter(),
  );
}

void main() {
  tearDown(RadarSession.debugReset);

  test('instance throws before install', () {
    expect(() => RadarSession.instance, throwsStateError);
  });

  test('install exposes the session', () {
    final s = _build();
    RadarSession.install(s);
    expect(identical(RadarSession.instance, s), isTrue);
  });

  test('ensureInitialized runs onInit exactly once', () {
    var calls = 0;
    final connection = FakeRadarConnection();
    final s = RadarSession(
      connection: connection,
      memory: MemoryController(
        snapshotSource: FakeSnapshotSource(),
        connection: connection,
      ),
      perf: PerfDataController(),
      exporter: RecordingExporter(),
      onInit: () => calls++,
    );
    s.ensureInitialized();
    s.ensureInitialized();
    expect(calls, 1);
  });

  test('attachStore restores a persisted session', () async {
    final s = _build();
    final store = InMemorySnapshotStore();
    await store.persist(
      PersistedSession(
        bundles: [
          SnapshotBundle(
            id: 1,
            capturedAt: DateTime(2026),
            label: 'restored',
            histogram: const [],
            analysisResult: const GraphAnalysisResult(
              clusters: [],
              stats: GraphAnalysisStats(
                totalObjects: 0,
                reachableObjects: 0,
                leakCandidates: 0,
                clusters: 0,
                suppressedByAppFilter: 0,
                warnings: [],
              ),
            ),
          ),
        ],
        selectedIds: const [1],
        view: RadarView.classHistogram,
      ),
    );
    await s.attachStore(store);
    expect(s.memory.snapshots.single.label, 'restored');
    expect(s.currentView, RadarView.classHistogram);
  });
}
