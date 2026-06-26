import 'package:flutter_perf_radar/flutter_perf_radar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StabilityRecorder', () {
    late StabilityRecorder recorder;

    setUp(() {
      recorder = StabilityRecorder(
        maxErrorsRetained: 3,
        maxStallsRetained: 3,
        stallThresholdMicros: 100000,
      );
    });

    test('starts with zero counts', () {
      expect(recorder.errorCount, equals(0));
      expect(recorder.stallCount, equals(0));
    });

    test('recordError increments errorCount', () {
      recorder.recordError(
        Exception('test'),
        StackTrace.current,
        context: 'test_context',
      );
      expect(recorder.errorCount, equals(1));
    });

    test('errors list is bounded by maxErrorsRetained', () {
      for (var i = 0; i < 5; i++) {
        recorder.recordError(Exception('error $i'), null);
      }
      final snap = recorder.snapshot();
      expect(snap.recentErrors.length, equals(3));
    });

    test('oldest error is evicted when at capacity', () {
      recorder.recordError(Exception('first'), null);
      recorder.recordError(Exception('second'), null);
      recorder.recordError(Exception('third'), null);
      recorder.recordError(Exception('fourth'), null);
      final snap = recorder.snapshot();
      expect(
        snap.recentErrors.any((e) => e.message.contains('first')),
        isFalse,
      );
    });

    test('recordStall increments stallCount', () {
      recorder.recordStall(200000);
      expect(recorder.stallCount, equals(1));
    });

    test('stalls list is bounded by maxStallsRetained', () {
      for (var i = 0; i < 5; i++) {
        recorder.recordStall(200000);
      }
      final snap = recorder.snapshot();
      expect(snap.recentStalls.length, equals(3));
    });

    test('stall below threshold is not recorded', () {
      recorder.recordStall(50000);
      expect(recorder.stallCount, equals(0));
    });

    test('reset clears counts and lists', () {
      recorder.recordError(Exception('e'), null);
      recorder.recordStall(200000);
      recorder.reset();
      expect(recorder.errorCount, equals(0));
      expect(recorder.stallCount, equals(0));
      expect(recorder.snapshot().recentErrors, isEmpty);
      expect(recorder.snapshot().recentStalls, isEmpty);
    });
  });
}
