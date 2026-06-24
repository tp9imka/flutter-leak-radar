// test/analysis/severity_test.dart
import 'package:flutter_leak_radar/src/analysis/severity.dart';
import 'package:flutter_leak_radar/src/config/leak_rule.dart';
import 'package:flutter_leak_radar/src/model/leak_kind.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('computeSeverity — maxLive mode', () {
    test('liveCount > 2*maxLive → critical', () {
      // Arrange
      const mode = LeakDetectionMode.maxLive;
      const maxLive = 10;
      const liveCount = 21; // 21 > 2*10

      // Act
      final result = computeSeverity(
        mode: mode,
        growth: 0,
        liveCount: liveCount,
        maxLive: maxLive,
        monotonic: false,
      );

      // Assert
      expect(result, LeakSeverity.critical);
    });

    test('maxLive < liveCount <= 2*maxLive → warning', () {
      // Arrange
      const mode = LeakDetectionMode.maxLive;
      const maxLive = 10;
      const liveCount = 15; // 10 < 15 <= 20

      // Act
      final result = computeSeverity(
        mode: mode,
        growth: 0,
        liveCount: liveCount,
        maxLive: maxLive,
        monotonic: false,
      );

      // Assert
      expect(result, LeakSeverity.warning);
    });

    test('liveCount <= maxLive → info', () {
      // Arrange
      const mode = LeakDetectionMode.maxLive;
      const maxLive = 10;
      const liveCount = 10; // 10 <= 10

      // Act
      final result = computeSeverity(
        mode: mode,
        growth: 0,
        liveCount: liveCount,
        maxLive: maxLive,
        monotonic: false,
      );

      // Assert
      expect(result, LeakSeverity.info);
    });
  });

  group('computeSeverity — growth mode', () {
    test('monotonic == true && growth >= 2 → critical', () {
      // Arrange
      const mode = LeakDetectionMode.growth;
      const growth = 2;
      const monotonic = true;

      // Act
      final result = computeSeverity(
        mode: mode,
        growth: growth,
        liveCount: 0,
        monotonic: monotonic,
      );

      // Assert
      expect(result, LeakSeverity.critical);
    });

    test('growth >= 1 but monotonic == false → warning', () {
      // Arrange
      const mode = LeakDetectionMode.growth;
      const growth = 1;
      const monotonic = false;

      // Act
      final result = computeSeverity(
        mode: mode,
        growth: growth,
        liveCount: 0,
        monotonic: monotonic,
      );

      // Assert
      expect(result, LeakSeverity.warning);
    });

    test('growth == 0 → info', () {
      // Arrange
      const mode = LeakDetectionMode.growth;
      const growth = 0;
      const monotonic = false;

      // Act
      final result = computeSeverity(
        mode: mode,
        growth: growth,
        liveCount: 0,
        monotonic: monotonic,
      );

      // Assert
      expect(result, LeakSeverity.info);
    });
  });

  group('computeSeverity — hint behaviour', () {
    test('hint raises: info input with hint critical → critical', () {
      // Arrange — growth == 0 would normally be info
      const mode = LeakDetectionMode.growth;
      const growth = 0;

      // Act
      final result = computeSeverity(
        mode: mode,
        growth: growth,
        liveCount: 0,
        monotonic: false,
        hint: LeakSeverity.critical,
      );

      // Assert
      expect(result, LeakSeverity.critical);
    });

    test(
      'hint does NOT lower: critical input with hint info → stays critical',
      () {
        // Arrange — monotonic growth >= 2 is critical; hint should not reduce it
        const mode = LeakDetectionMode.growth;
        const growth = 3;
        const monotonic = true;

        // Act
        final result = computeSeverity(
          mode: mode,
          growth: growth,
          liveCount: 0,
          monotonic: monotonic,
          hint: LeakSeverity.info,
        );

        // Assert
        expect(result, LeakSeverity.critical);
      },
    );
  });
}
