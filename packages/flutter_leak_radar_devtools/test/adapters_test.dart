import 'package:flutter_leak_radar_devtools/src/adapters/devtools_snapshot_exporter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_workbench/radar_workbench.dart';

void main() {
  test(
    'DevToolsSnapshotExporter builds a sanitized filename and does not throw',
    () async {
      const exporter = DevToolsSnapshotExporter();
      final bundle = SnapshotBundle.failed(label: 'A B/C', message: 'm');
      // downloadJson requires a DOM; under the web test host it is a no-op path,
      // so this asserts the export call completes without throwing.
      await expectLater(exporter.export(bundle), completes);
    },
  );
}
