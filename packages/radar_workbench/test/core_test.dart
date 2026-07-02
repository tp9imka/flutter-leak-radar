import 'package:flutter_test/flutter_test.dart';
import 'package:radar_workbench/radar_workbench.dart';

import 'fakes.dart';

void main() {
  test('FakeRadarConnection notifies and exposes state', () {
    final conn = FakeRadarConnection();
    var notified = 0;
    conn.addListener(() => notified++);
    expect(conn.state.phase, ConnectionPhase.disconnected);
    conn.set(state: const ConnectionState(phase: ConnectionPhase.connected));
    expect(notified, 1);
    expect(conn.state.phase, ConnectionPhase.connected);
  });

  test('RecordingExporter records exports', () async {
    final exporter = RecordingExporter();
    final bundle = SnapshotBundle.failed(label: 'x', message: 'm');
    await exporter.export(bundle);
    expect(exporter.exported.single.label, 'x');
  });
}
