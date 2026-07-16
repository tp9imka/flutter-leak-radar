import 'dart:convert';
import 'dart:math' as math;

import 'package:radar_trace/radar_trace.dart';
import 'package:test/test.dart';

/// Builds a series sampled every [interval] starting at [startMicros].
MetricSeries seriesOf(
  List<double> values, {
  Duration interval = const Duration(seconds: 5),
  int startMicros = 0,
  List<SeriesGap> gaps = const [],
  String unit = 'mb',
}) {
  final step = interval.inMicroseconds;
  return MetricSeries(
    name: 'test.native_pss',
    unit: unit,
    gaps: gaps,
    samples: [
      for (var i = 0; i < values.length; i++)
        MetricSample(tMicros: startMicros + i * step, value: values[i]),
    ],
  );
}

/// [count] values of f(t seconds) at a fixed [stepSeconds] cadence.
List<double> valuesOf(
  int count,
  double Function(double tSeconds) f, {
  double stepSeconds = 5,
}) => [for (var i = 0; i < count; i++) f(i * stepSeconds)];

/// Triangle wave in [0, 1] with the given period.
double tri(double tSeconds, double period) {
  final phase = (tSeconds % period) / period;
  return phase < 0.5 ? phase * 2 : 2 - phase * 2;
}

// Standard window: 96 samples @ 5s = t 0..475s. The default 30s settle
// trims t < 30s (6 samples), leaving 90 samples over 445s.
const standardCount = 96;

void main() {
  group('AssessOptions', () {
    test('documented defaults', () {
      const options = AssessOptions();
      expect(options.settle, const Duration(seconds: 30));
      expect(options.minSamples, 8);
      expect(options.minSpan, const Duration(minutes: 2));
      expect(options.noiseFactor, 2.0);
    });
  });

  group('SeriesAssessment JSON', () {
    test('round-trip with numeric fields', () {
      const assessment = SeriesAssessment(
        verdict: SeriesVerdict.monotonicGrowth,
        slopePerHour: 4.2,
        batchDeltaPerHour: 3.9,
        samplesAssessed: 90,
        samplesTotal: 96,
        detail: 'grew 4.2 mb/h in the second half',
      );
      final decoded = jsonDecode(jsonEncode(assessment.toJson()));
      final restored = SeriesAssessment.fromJson(
        decoded as Map<String, Object?>,
      );
      expect(restored, equals(assessment));
      expect(restored.hashCode, equals(assessment.hashCode));
    });

    test('round-trip with null slopes', () {
      const assessment = SeriesAssessment(
        verdict: SeriesVerdict.insufficientData,
        slopePerHour: null,
        batchDeltaPerHour: null,
        samplesAssessed: 0,
        samplesTotal: 3,
        detail: 'only 0 of 3 samples remain after the settle trim',
      );
      final decoded = jsonDecode(jsonEncode(assessment.toJson()));
      expect(
        SeriesAssessment.fromJson(decoded as Map<String, Object?>),
        equals(assessment),
      );
    });

    test('unknown verdict name throws FormatException', () {
      expect(
        () => SeriesAssessment.fromJson(const {
          'verdict': 'exploded',
          'slopePerHour': null,
          'batchDeltaPerHour': null,
          'samplesAssessed': 0,
          'samplesTotal': 0,
          'detail': '',
        }),
        throwsFormatException,
      );
    });
  });

  group('verdicts', () {
    test('pure linear ramp -> monotonicGrowth, slope ~ constructed', () {
      // 60 mb/h ramp: value = 100 + tSeconds / 60.
      final series = seriesOf(valuesOf(standardCount, (t) => 100 + t / 60));
      final a = assessSeries(series);
      expect(a.verdict, SeriesVerdict.monotonicGrowth);
      expect(a.slopePerHour, isNotNull);
      expect(a.slopePerHour, closeTo(60, 1));
      expect(a.batchDeltaPerHour, isNotNull);
      expect(a.batchDeltaPerHour, closeTo(60, 6));
      expect(a.samplesTotal, standardCount);
      expect(a.samplesAssessed, standardCount - 6);
    });

    test('ramp through batch1 then flat through batch2 -> plateau', () {
      final series = seriesOf(
        valuesOf(standardCount, (t) => t < 250 ? 100 * t / 250 : 100),
      );
      final a = assessSeries(series);
      expect(a.verdict, SeriesVerdict.plateau);
      expect(a.batchDeltaPerHour, greaterThan(0));
    });

    test('flat with small noise -> plateau', () {
      // Documented choice: small noise around a stable level is plateau,
      // not noisy — the measurements confidently track a bounded level,
      // and bounded is exactly what plateau asserts. It must never read
      // as monotonicGrowth.
      final random = math.Random(7);
      final series = seriesOf(
        valuesOf(standardCount, (_) => 100 + (random.nextDouble() - 0.5)),
      );
      final a = assessSeries(series);
      expect(a.verdict, SeriesVerdict.plateau);
    });

    test('large random noise, no trend -> noisy', () {
      final random = math.Random(11);
      final series = seriesOf(
        valuesOf(standardCount, (_) => 100 + (random.nextDouble() - 0.5) * 100),
      );
      final a = assessSeries(series);
      expect(a.verdict, SeriesVerdict.noisy);
    });
  });

  group('insufficientData', () {
    test('3 samples', () {
      final a = assessSeries(seriesOf([1, 2, 3]));
      expect(a.verdict, SeriesVerdict.insufficientData);
      expect(a.slopePerHour, isNull);
      expect(a.batchDeltaPerHour, isNull);
      expect(a.samplesTotal, 3);
    });

    test('30s span', () {
      // 11 samples at 3s cadence span exactly 30s < the 2min minSpan.
      final a = assessSeries(
        seriesOf(
          valuesOf(11, (_) => 100, stepSeconds: 3),
          interval: const Duration(seconds: 3),
        ),
        const AssessOptions(settle: Duration.zero),
      );
      expect(a.verdict, SeriesVerdict.insufficientData);
      expect(a.detail, contains('span'));
    });
  });

  group('settle trim', () {
    test('ramp entirely inside the settle window is not growth', () {
      final series = seriesOf(
        valuesOf(standardCount, (t) => t < 30 ? 100 * t / 30 : 100),
      );
      final a = assessSeries(series);
      expect(a.verdict, isNot(SeriesVerdict.monotonicGrowth));
      expect(a.verdict, SeriesVerdict.plateau);
    });
  });

  group('gaps', () {
    test('healthy region after a gap is assessed alone (never bridged)', () {
      // Pre-gap plateau at 5000, then a 200s gap, then a gentle 120 mb/h
      // ramp from 100. If the gap were bridged the 4900 cliff would poison
      // both slope and delta; the pinned slope proves only the post-gap
      // region was read.
      const micros = 1000000;
      final samples = [
        for (var t = 0; t <= 200; t += 5)
          MetricSample(tMicros: t * micros, value: 5000),
        for (var t = 400; t <= 800; t += 5)
          MetricSample(tMicros: t * micros, value: 100 + (t - 400) / 30),
      ];
      final series = MetricSeries(
        name: 'test.native_pss',
        unit: 'mb',
        samples: samples,
        gaps: const [
          SeriesGap(
            startMicros: 200 * micros,
            endMicros: 400 * micros,
            reason: 'adb reconnect',
          ),
        ],
      );
      final a = assessSeries(series);
      expect(a.verdict, SeriesVerdict.monotonicGrowth);
      expect(a.samplesAssessed, 81);
      expect(a.slopePerHour, closeTo(120, 2));
    });

    test('gap swallowing most of the window -> insufficientData', () {
      const micros = 1000000;
      final samples = [
        for (var t = 0; t <= 60; t += 5)
          MetricSample(tMicros: t * micros, value: 100),
        for (var t = 3600; t <= 3630; t += 5)
          MetricSample(tMicros: t * micros, value: 100),
      ];
      final series = MetricSeries(
        name: 'test.native_pss',
        unit: 'mb',
        samples: samples,
        gaps: const [
          SeriesGap(
            startMicros: 60 * micros,
            endMicros: 3600 * micros,
            reason: 'sampler error',
          ),
        ],
      );
      final a = assessSeries(series);
      expect(a.verdict, SeriesVerdict.insufficientData);
      expect(a.detail, contains('gap'));
    });
  });

  group('robustness', () {
    test('single spike in an otherwise flat series is not growth', () {
      final values = valuesOf(standardCount, (_) => 100.0);
      values[70] = 500; // one spike inside batch2
      final a = assessSeries(seriesOf(values));
      expect(a.verdict, isNot(SeriesVerdict.monotonicGrowth));
      expect(a.verdict, SeriesVerdict.plateau);
    });
  });

  group('never throws', () {
    test('empty series', () {
      final a = assessSeries(
        const MetricSeries(name: 'm', unit: 'mb', samples: []),
      );
      expect(a.verdict, SeriesVerdict.insufficientData);
      expect(a.samplesTotal, 0);
      expect(a.samplesAssessed, 0);
    });

    test('single sample', () {
      final a = assessSeries(seriesOf([100]));
      expect(a.verdict, SeriesVerdict.insufficientData);
    });

    test('unordered samples assess the same as ordered', () {
      final values = valuesOf(standardCount, (t) => 100 + t / 60);
      final ordered = seriesOf(values);
      final unordered = MetricSeries(
        name: ordered.name,
        unit: ordered.unit,
        samples: ordered.samples.reversed.toList(),
      );
      final a = assessSeries(unordered);
      expect(a.verdict, SeriesVerdict.monotonicGrowth);
      expect(a.slopePerHour, closeTo(60, 1));
    });

    test('non-finite values are dropped, not assessed', () {
      final values = valuesOf(standardCount, (_) => 100.0);
      values[40] = double.nan;
      values[41] = double.infinity;
      final a = assessSeries(seriesOf(values));
      expect(a.verdict, SeriesVerdict.plateau);
      expect(a.samplesAssessed, standardCount - 6 - 2);
    });

    test('all samples at one timestamp', () {
      final series = MetricSeries(
        name: 'm',
        unit: 'mb',
        samples: [
          for (var i = 0; i < 10; i++)
            MetricSample(tMicros: 0, value: 100.0 + i),
        ],
      );
      final a = assessSeries(
        series,
        const AssessOptions(settle: Duration.zero, minSpan: Duration.zero),
      );
      expect(a.verdict, SeriesVerdict.insufficientData);
    });
  });

  group('misleading-shape audit', () {
    test('bounded GC sawtooth -> plateau, never growth', () {
      final series = seriesOf(
        valuesOf(standardCount, (t) => 100 + 10 * tri(t, 60)),
      );
      final a = assessSeries(series);
      expect(a.verdict, isNot(SeriesVerdict.monotonicGrowth));
      expect(a.verdict, SeriesVerdict.plateau);
    });

    test('ratcheting sawtooth (rising baseline) -> monotonicGrowth', () {
      // Baseline climbs 120 mb/h under a +-3 mb GC sawtooth: this IS the
      // leak signature and must not hide behind the oscillation.
      final series = seriesOf(
        valuesOf(standardCount, (t) => 100 + t / 30 + 3 * tri(t, 40)),
      );
      final a = assessSeries(series);
      expect(a.verdict, SeriesVerdict.monotonicGrowth);
      expect(a.slopePerHour, closeTo(120, 15));
    });

    test('step function -> plateau (one-time jump is not monotonic)', () {
      final series = seriesOf(
        valuesOf(standardCount, (t) => t < 252.5 ? 100.0 : 200.0),
      );
      final a = assessSeries(series);
      expect(a.verdict, SeriesVerdict.plateau);
      expect(a.batchDeltaPerHour, greaterThan(0));
    });

    test('monotonic ramp then sustained end crash is not growth', () {
      // Ramp at 600 mb/h until t=420s, then back at baseline for the final
      // ~55s. "Still climbing at series end" would be a lie.
      final series = seriesOf(
        valuesOf(standardCount, (t) => t < 420 ? 100 + t / 6 : 100),
      );
      final a = assessSeries(series);
      expect(a.verdict, isNot(SeriesVerdict.monotonicGrowth));
    });

    test('late-onset ramp in the final stretch is not a bounded plateau', () {
      // Flat until t=430s, then climbing steeply through series end. Batch
      // medians and Theil-Sen both discount the short tail (that is what
      // makes them spike-robust), so without an end-shift check this would
      // read plateau — asserting "bounded, not a leak" while the level is
      // visibly rising at series end. Honest answer: cannot classify.
      final series = seriesOf(
        valuesOf(standardCount, (t) => t < 430 ? 100 : 100 + (t - 430) * 2),
      );
      final a = assessSeries(series);
      expect(a.verdict, SeriesVerdict.noisy);
    });

    test('step late in batch2 then a short hold is not a bounded plateau', () {
      // Step +100 at ~70% of the window, held only ~65s. Too little
      // post-step data to demonstrate bounded; must not claim plateau.
      final series = seriesOf(
        valuesOf(standardCount, (t) => t < 408 ? 100.0 : 200.0),
      );
      final a = assessSeries(series);
      expect(a.verdict, isNot(SeriesVerdict.monotonicGrowth));
      expect(a.verdict, isNot(SeriesVerdict.plateau));
    });

    test('declining series is not growth', () {
      final series = seriesOf(valuesOf(standardCount, (t) => 200 - t / 60));
      final a = assessSeries(series);
      expect(a.verdict, isNot(SeriesVerdict.monotonicGrowth));
      expect(a.verdict, SeriesVerdict.plateau);
    });
  });
}
