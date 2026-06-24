// test/triggers/scan_scheduler_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_leak_radar/src/triggers/scan_scheduler.dart';

void main() {
  group('ScanScheduler', () {
    test('does not fire when period is null', () async {
      var fired = 0;
      final scheduler = ScanScheduler(
        period: null,
        onTick: () async {
          fired++;
        },
      );
      scheduler.start();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      scheduler.stop();
      expect(fired, 0);
    });

    test('fires at the configured period', () async {
      var fired = 0;
      final scheduler = ScanScheduler(
        period: const Duration(milliseconds: 20),
        onTick: () async {
          fired++;
        },
      );
      scheduler.start();
      await Future<void>.delayed(const Duration(milliseconds: 70));
      scheduler.stop();
      // Should have fired approximately 3 times (20ms intervals over 70ms).
      expect(fired, greaterThanOrEqualTo(2));
    });

    test('stop cancels the timer — no more ticks', () async {
      var fired = 0;
      final scheduler = ScanScheduler(
        period: const Duration(milliseconds: 20),
        onTick: () async {
          fired++;
        },
      );
      scheduler.start();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      scheduler.stop();
      final countAtStop = fired;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(fired, countAtStop); // no more ticks after stop
    });

    test('start is idempotent — calling twice does not double-fire', () async {
      var fired = 0;
      final scheduler = ScanScheduler(
        period: const Duration(milliseconds: 20),
        onTick: () async {
          fired++;
        },
      );
      scheduler.start();
      scheduler.start(); // second call should be a no-op
      await Future<void>.delayed(const Duration(milliseconds: 60));
      scheduler.stop();
      // Should not have fired at 2x rate.
      expect(fired, lessThanOrEqualTo(5));
    });
  });
}
