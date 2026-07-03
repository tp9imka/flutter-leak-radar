import 'package:radar_native_host/radar_native_host.dart';
import 'package:test/test.dart';

void main() {
  group('heapprofdConfig', () {
    test('emits the device-proven textproto shape with defaults', () {
      final config = heapprofdConfig(packageId: 'com.x', durationMs: 30000);

      expect(config, contains('process_cmdline: "com.x"'));
      expect(config, contains('duration_ms: 30000'));
      expect(config, contains('name: "android.heapprofd"'));
      expect(config, contains('dump_interval_ms: 3000'));
      expect(config, contains('block_client: true'));
    });

    test('interpolates a custom sampling interval and dump interval', () {
      final config = heapprofdConfig(
        packageId: 'com.x',
        durationMs: 30000,
        samplingIntervalBytes: 8192,
        dumpIntervalMs: 5000,
      );

      expect(config, contains('sampling_interval_bytes: 8192'));
      expect(config, contains('dump_interval_ms: 5000'));
      expect(config, isNot(contains('sampling_interval_bytes: 4096')));
    });
  });
}
