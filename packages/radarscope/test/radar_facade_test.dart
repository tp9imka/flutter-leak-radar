// test/radar_facade_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:radarscope/radarscope.dart';

void main() {
  group('Radar facade', () {
    tearDown(() async => Radar.dispose());

    test('init + dispose does not throw in test environment', () async {
      await expectLater(Radar.init(RadarConfig.standard()), completes);
      await expectLater(Radar.dispose(), completes);
    });

    test('dispose without init does not throw', () async {
      await expectLater(Radar.dispose(), completes);
    });

    test('track is a no-op when not initialised and does not throw', () {
      expect(() => Radar.track(Object(), tag: 'Test'), returnsNormally);
    });

    test('markDisposed is a no-op when not initialised and does not throw', () {
      expect(() => Radar.markDisposed(Object()), returnsNormally);
    });

    test('trace returns body result when not initialised', () {
      final result = Radar.trace('test', () => 42);
      expect(result, 42);
    });

    test('traceAsync returns body result when not initialised', () async {
      final result = await Radar.traceAsync('test', () async => 'hello');
      expect(result, 'hello');
    });

    test('trace / traceAsync / start accept a dedupKey and stay a no-op safe '
        'passthrough', () async {
      // The umbrella facade must forward dedupKey to PerfRadar (the actual
      // duplicate counting is covered by radar_trace's Tracer tests; the perf
      // engine does not record in the flutter_test VM). Here we guard that the
      // delegation exists and preserves the zero-throw / body-result contract.
      expect(Radar.trace('t', () => 42, dedupKey: const ['a']), 42);
      expect(
        await Radar.traceAsync('t', () async => 'hello', dedupKey: const ['a']),
        'hello',
      );
      expect(
        () => Radar.start('t', dedupKey: const ['a']).stop(),
        returnsNormally,
      );
    });

    test('navigatorObserver is non-null at all times', () {
      expect(Radar.navigatorObserver, isNotNull);
    });
  });

  group('Radar release no-op', () {
    test('init is a no-op in test mode (kReleaseMode is false)', () async {
      // In flutter_test, kReleaseMode is always false, kDebugMode is true.
      // We verify init does not throw and does not crash.
      await expectLater(
        Radar.init(
          const RadarConfig(
            leak: LeakRadarConfig(enabled: false),
            perf: PerfRadarConfig(enabled: false, stallThresholdMicros: 250000),
          ),
        ),
        completes,
      );
    });
  });
}
