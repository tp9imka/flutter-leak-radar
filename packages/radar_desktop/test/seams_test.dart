import 'package:flutter_test/flutter_test.dart';
import 'package:radar_desktop/src/seams/disconnected_connection.dart';
import 'package:radar_desktop/src/seams/offline_snapshot_source.dart';
import 'package:radar_workbench/radar_workbench.dart';

void main() {
  test('DisconnectedRadarConnection is always disconnected', () {
    final c = DisconnectedRadarConnection();
    expect(c.state.phase, RadarConnectionPhase.disconnected);
    expect(c.vmService, isNull);
    expect(c.isolateRef, isNull);
  });

  test(
    'OfflineSnapshotSource.capture returns a failed bundle, never throws',
    () async {
      const source = OfflineSnapshotSource();
      final bundle = await source.capture(label: 'x');
      expect(bundle.label, 'x');
      expect(bundle.analysisResult.clusters, isEmpty);
    },
  );

  test('MemoryController wires cleanly with the offline seams', () {
    final controller = MemoryController(
      snapshotSource: const OfflineSnapshotSource(),
      connection: DisconnectedRadarConnection(),
    );
    expect(controller.canCapture, isFalse);
    expect(controller.snapshots, isEmpty);
  });
}
