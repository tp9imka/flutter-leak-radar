// test/radar_facade_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_radar/flutter_radar.dart';

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
