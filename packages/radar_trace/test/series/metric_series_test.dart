import 'dart:convert';

import 'package:radar_trace/radar_trace.dart';
import 'package:test/test.dart';

void main() {
  group('MetricSample', () {
    test('value equality and hashCode', () {
      const a = MetricSample(tMicros: 1000, value: 2.5);
      const b = MetricSample(tMicros: 1000, value: 2.5);
      const c = MetricSample(tMicros: 1001, value: 2.5);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('JSON round-trip', () {
      const sample = MetricSample(tMicros: 1700000000000000, value: 123.75);
      final decoded = jsonDecode(jsonEncode(sample.toJson()));
      final restored = MetricSample.fromJson(decoded as Map<String, Object?>);
      expect(restored, equals(sample));
    });

    test('fromJson tolerates an integer value field', () {
      final restored = MetricSample.fromJson(const {
        'tMicros': 10,
        'value': 42,
      });
      expect(restored.value, 42.0);
    });
  });

  group('SeriesGap', () {
    test('value equality and hashCode', () {
      const a = SeriesGap(
        startMicros: 1,
        endMicros: 2,
        reason: 'adb reconnect',
      );
      const b = SeriesGap(
        startMicros: 1,
        endMicros: 2,
        reason: 'adb reconnect',
      );
      const c = SeriesGap(
        startMicros: 1,
        endMicros: 3,
        reason: 'adb reconnect',
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('JSON round-trip', () {
      const gap = SeriesGap(
        startMicros: 100,
        endMicros: 200,
        reason: 'sampler error',
      );
      final decoded = jsonDecode(jsonEncode(gap.toJson()));
      expect(SeriesGap.fromJson(decoded as Map<String, Object?>), equals(gap));
    });
  });

  group('MetricSeries', () {
    const samples = [
      MetricSample(tMicros: 0, value: 1),
      MetricSample(tMicros: 1000000, value: 2),
    ];
    const gaps = [
      SeriesGap(startMicros: 500000, endMicros: 600000, reason: 'reconnect'),
    ];

    test('JSON round-trip with samples and gaps', () {
      const series = MetricSeries(
        name: 'meminfo.native_pss',
        unit: 'kb',
        samples: samples,
        gaps: gaps,
      );
      final json = series.toJson();
      expect(json['schemaVersion'], 1);
      final decoded = jsonDecode(jsonEncode(json));
      final restored = MetricSeries.fromJson(decoded as Map<String, Object?>);
      expect(restored.name, series.name);
      expect(restored.unit, series.unit);
      expect(restored.samples, equals(series.samples));
      expect(restored.gaps, equals(series.gaps));
    });

    test('fromJson with absent gaps yields an empty gap list', () {
      final restored = MetricSeries.fromJson({
        'schemaVersion': 1,
        'name': 'm',
        'unit': 'bytes',
        'samples': [for (final s in samples) s.toJson()],
      });
      expect(restored.gaps, isEmpty);
    });

    test('fromJson rejects schemaVersion 2 with FormatException', () {
      expect(
        () => MetricSeries.fromJson(const {
          'schemaVersion': 2,
          'name': 'm',
          'unit': 'bytes',
          'samples': <Object?>[],
        }),
        throwsFormatException,
      );
    });

    test('fromJson rejects a non-numeric schemaVersion', () {
      // A string "2" must not silently read as v1.
      expect(
        () => MetricSeries.fromJson(const {
          'schemaVersion': '2',
          'name': 'm',
          'unit': 'bytes',
          'samples': <Object?>[],
        }),
        throwsFormatException,
      );
    });

    test('fromJson accepts an absent schemaVersion (treated as 1)', () {
      final restored = MetricSeries.fromJson(const {
        'name': 'm',
        'unit': 'bytes',
        'samples': <Object?>[],
      });
      expect(restored.samples, isEmpty);
    });

    test('constructor preserves the given sample order (documented)', () {
      // The const ctor cannot sort or assert; the documented contract is
      // that producers emit time-ordered samples and consumers such as
      // assessSeries sort a defensive copy.
      const unordered = MetricSeries(
        name: 'm',
        unit: 'kb',
        samples: [
          MetricSample(tMicros: 1000000, value: 2),
          MetricSample(tMicros: 0, value: 1),
        ],
      );
      expect(unordered.samples.first.tMicros, 1000000);
    });
  });
}
