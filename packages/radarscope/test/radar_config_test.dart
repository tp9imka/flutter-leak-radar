// test/radar_config_test.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radarscope/radarscope.dart';

void main() {
  group('RadarConfig', () {
    test('standard() builds both configs', () {
      final config = RadarConfig.standard();
      expect(config.leak, isA<LeakRadarConfig>());
      expect(config.perf, isA<PerfRadarConfig>());
    });

    test('standard() sets enabled = kDebugMode || kProfileMode', () {
      final config = RadarConfig.standard();
      final expected = kDebugMode || kProfileMode;
      expect(config.leak.enabled, expected);
      expect(config.perf.enabled, expected);
    });

    test('copyWith replaces leak config', () {
      final base = RadarConfig.standard();
      final updated = base.copyWith(
        leak: const LeakRadarConfig(enabled: false),
      );
      expect(updated.leak.enabled, isFalse);
      expect(updated.perf, base.perf);
    });

    test('copyWith replaces perf config', () {
      final base = RadarConfig.standard();
      final updated = base.copyWith(
        perf: const PerfRadarConfig(enabled: false, stallThresholdMicros: 1000),
      );
      expect(updated.perf.enabled, isFalse);
      expect(updated.leak, base.leak);
    });

    test('equality is value-based', () {
      final a = RadarConfig.standard();
      final b = RadarConfig.standard();
      expect(a, equals(b));
    });
  });
}
