import 'package:flutter/foundation.dart';
import 'package:flutter_perf_radar/flutter_perf_radar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PerfRadarConfig', () {
    test('equality and hashCode work by value', () {
      const a = PerfRadarConfig(
        enabled: true,
        jankThresholdMicros: 16667,
        stallThresholdMicros: 250000,
        maxStallsRetained: 50,
        maxErrorsRetained: 100,
      );
      const b = PerfRadarConfig(
        enabled: true,
        jankThresholdMicros: 16667,
        stallThresholdMicros: 250000,
        maxStallsRetained: 50,
        maxErrorsRetained: 100,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('copyWith creates new instance with changed field', () {
      const original = PerfRadarConfig(
        enabled: true,
        jankThresholdMicros: 16667,
        stallThresholdMicros: 250000,
        maxStallsRetained: 50,
        maxErrorsRetained: 100,
      );
      final copy = original.copyWith(enabled: false);
      expect(copy.enabled, isFalse);
      expect(copy.jankThresholdMicros, equals(16667));
    });

    test('standard() sets enabled based on kDebugMode || kProfileMode', () {
      final config = PerfRadarConfig.standard();
      expect(config.enabled, equals(kDebugMode || kProfileMode));
    });

    test('jankThreshold defaults to 16667 microseconds', () {
      const config = PerfRadarConfig(
        enabled: true,
        stallThresholdMicros: 250000,
        maxStallsRetained: 50,
        maxErrorsRetained: 100,
      );
      expect(config.jankThresholdMicros, equals(16667));
    });

    test('maxStallsRetained defaults to 50', () {
      const config = PerfRadarConfig(
        enabled: true,
        stallThresholdMicros: 250000,
        maxErrorsRetained: 100,
      );
      expect(config.maxStallsRetained, equals(50));
    });

    test('maxErrorsRetained defaults to 100', () {
      const config = PerfRadarConfig(
        enabled: true,
        stallThresholdMicros: 250000,
        maxStallsRetained: 50,
      );
      expect(config.maxErrorsRetained, equals(100));
    });
  });
}
