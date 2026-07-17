import 'package:radar_trace/radar_trace.dart';

/// Microseconds per second.
const int _secMicros = 1000000;

/// A strictly-increasing series long enough (post-settle) to certify
/// [SeriesVerdict.monotonicGrowth]: 40 samples 30s apart, ramping [step]/sample
/// from [base].
MetricSeries growingSeries(
  String name,
  String unit, {
  num base = 100000,
  num step = 1000,
  int samples = 40,
  int intervalSec = 30,
}) => MetricSeries(
  name: name,
  unit: unit,
  samples: [
    for (var i = 0; i < samples; i++)
      MetricSample(
        tMicros: i * intervalSec * _secMicros,
        value: (base + step * i).toDouble(),
      ),
  ],
);

/// A constant series over the same window — reads [SeriesVerdict.plateau].
MetricSeries flatSeries(
  String name,
  String unit, {
  num value = 100000,
  int samples = 40,
  int intervalSec = 30,
}) => MetricSeries(
  name: name,
  unit: unit,
  samples: [
    for (var i = 0; i < samples; i++)
      MetricSample(
        tMicros: i * intervalSec * _secMicros,
        value: value.toDouble(),
      ),
  ],
);

/// Too few samples to assess — reads [SeriesVerdict.insufficientData].
MetricSeries shortSeries(String name, String unit) => MetricSeries(
  name: name,
  unit: unit,
  samples: [
    for (var i = 0; i < 3; i++)
      MetricSample(tMicros: i * 30 * _secMicros, value: 1000.0 + i),
  ],
);
