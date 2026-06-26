import 'package:flutter_perf_radar/flutter_perf_radar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StallWatchdog', () {
    test('does not report stall when ticks arrive on time', () async {
      final stalls = <int>[];
      int fakeTimeMicros = 0;
      final intervalMicros = 100000;

      final watchdog = StallWatchdog(
        interval: const Duration(milliseconds: 100),
        threshold: const Duration(milliseconds: 200),
        onStall: stalls.add,
        clockMicros: () => fakeTimeMicros,
      );

      fakeTimeMicros += intervalMicros;
      await Future<void>.delayed(const Duration(milliseconds: 110));
      fakeTimeMicros += intervalMicros;
      await Future<void>.delayed(const Duration(milliseconds: 110));

      watchdog.dispose();
      expect(stalls, isEmpty);
    });

    test('dispose stops further callbacks', () async {
      final stalls = <int>[];
      final watchdog = StallWatchdog(
        interval: const Duration(milliseconds: 50),
        threshold: const Duration(milliseconds: 10),
        onStall: stalls.add,
      );
      watchdog.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final countAfterDispose = stalls.length;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(stalls.length, equals(countAfterDispose));
    });
  });
}
