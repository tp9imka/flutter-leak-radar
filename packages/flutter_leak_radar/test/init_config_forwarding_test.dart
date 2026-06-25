// test/init_config_forwarding_test.dart
//
// Regression: init() built the engine without passing `config:`, so the
// engine fell back to const LeakRadarConfig() — silently dropping graphScan
// (live graph scanning never ran), preciseTracking, and reportThreshold.
import 'package:flutter_leak_radar/flutter_leak_radar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => LeakRadar.dispose());

  test('init forwards graphScan to the engine config', () async {
    await LeakRadar.init(
      LeakRadarConfig.standard(
        graphScan: const GraphScan(everyNthNavigation: 3),
      ),
    );
    expect(LeakRadar.debugEngineConfig?.graphScan?.everyNthNavigation, 3);
  });

  test('init forwards reportThreshold to the engine config', () async {
    await LeakRadar.init(
      const LeakRadarConfig(reportThreshold: LeakSeverity.critical),
    );
    expect(LeakRadar.debugEngineConfig?.reportThreshold, LeakSeverity.critical);
  });
}
