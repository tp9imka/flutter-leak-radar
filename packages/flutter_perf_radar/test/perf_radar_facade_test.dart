import 'package:flutter_perf_radar/flutter_perf_radar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() async {
    await PerfRadar.dispose();
  });

  group('PerfRadar facade', () {
    test('init with enabled:false is a no-op (no engine)', () async {
      await PerfRadar.init(
        const PerfRadarConfig(
          enabled: false,
          stallThresholdMicros: 250000,
          maxStallsRetained: 50,
          maxErrorsRetained: 100,
        ),
      );
      expect(PerfRadar.configListenable.value.enabled, isFalse);
    });

    test('trace returns body result', () async {
      await PerfRadar.init(
        const PerfRadarConfig(
          enabled: false,
          stallThresholdMicros: 250000,
          maxStallsRetained: 50,
          maxErrorsRetained: 100,
        ),
      );
      final result = PerfRadar.trace('test', () => 42);
      expect(result, equals(42));
    });

    test('traceAsync returns body result', () async {
      await PerfRadar.init(
        const PerfRadarConfig(
          enabled: false,
          stallThresholdMicros: 250000,
          maxStallsRetained: 50,
          maxErrorsRetained: 100,
        ),
      );
      final result = await PerfRadar.traceAsync('test', () async => 'hello');
      expect(result, equals('hello'));
    });

    test('start returns a SpanHandle with stop method', () async {
      await PerfRadar.init(
        const PerfRadarConfig(
          enabled: false,
          stallThresholdMicros: 250000,
          maxStallsRetained: 50,
          maxErrorsRetained: 100,
        ),
      );
      final handle = PerfRadar.start('test_span');
      handle.stop();
    });

    test('snapshot returns a TraceSnapshot', () async {
      await PerfRadar.init(
        const PerfRadarConfig(
          enabled: false,
          stallThresholdMicros: 250000,
          maxStallsRetained: 50,
          maxErrorsRetained: 100,
        ),
      );
      final snap = PerfRadar.snapshot();
      expect(snap, isNotNull);
    });

    test('configListenable starts with enabled:false before init', () {
      expect(PerfRadar.configListenable, isNotNull);
    });

    test('dispose resets the facade', () async {
      await PerfRadar.init(
        const PerfRadarConfig(
          enabled: false,
          stallThresholdMicros: 250000,
          maxStallsRetained: 50,
          maxErrorsRetained: 100,
        ),
      );
      await PerfRadar.dispose();
      await PerfRadar.init(
        const PerfRadarConfig(
          enabled: false,
          stallThresholdMicros: 250000,
          maxStallsRetained: 50,
          maxErrorsRetained: 100,
        ),
      );
    });

    test(
      'resetFrameStats is a safe no-op when the engine is not running',
      () async {
        await PerfRadar.init(
          const PerfRadarConfig(
            enabled: false,
            stallThresholdMicros: 250000,
            maxStallsRetained: 50,
            maxErrorsRetained: 100,
          ),
        );
        expect(PerfRadar.resetFrameStats, returnsNormally);
      },
    );

    test('trace propagates exception from body', () async {
      await PerfRadar.init(
        const PerfRadarConfig(
          enabled: false,
          stallThresholdMicros: 250000,
          maxStallsRetained: 50,
          maxErrorsRetained: 100,
        ),
      );
      expect(
        () => PerfRadar.trace('test', () => throw Exception('boom')),
        throwsException,
      );
    });
  });
}
