// test/config/auto_scan_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_leak_radar/src/config/leak_radar_config.dart';

void main() {
  group('AutoScan', () {
    test('default values', () {
      const s = AutoScan();
      expect(s.onNavigation, isFalse);
      expect(s.period, isNull);
      expect(s.hasPeriodic, isFalse);
      expect(s.navigationDebounce, const Duration(milliseconds: 500));
    });

    test('hasPeriodic is true when period is set', () {
      const s = AutoScan(period: Duration(seconds: 30));
      expect(s.hasPeriodic, isTrue);
    });

    test('copyWith preserves unchanged fields', () {
      const original = AutoScan(onNavigation: true);
      final copy = original.copyWith(period: const Duration(seconds: 60));
      expect(copy.onNavigation, isTrue);
      expect(copy.period, const Duration(seconds: 60));
    });

    test('equality and hashCode', () {
      const a = AutoScan(onNavigation: true, period: Duration(seconds: 30));
      const b = AutoScan(onNavigation: true, period: Duration(seconds: 30));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('LeakRadarConfig with AutoScan', () {
    test('default config has AutoScan with no triggers', () {
      const config = LeakRadarConfig();
      expect(config.autoScan.hasPeriodic, isFalse);
      expect(config.autoScan.onNavigation, isFalse);
    });

    test('copyWith updates autoScan', () {
      const original = LeakRadarConfig();
      final updated = original.copyWith(
        autoScan: const AutoScan(onNavigation: true),
      );
      expect(updated.autoScan.onNavigation, isTrue);
    });

    test('maxRetainingPathRequests defaults to 5', () {
      const config = LeakRadarConfig();
      expect(config.maxRetainingPathRequests, 5);
    });
  });
}
