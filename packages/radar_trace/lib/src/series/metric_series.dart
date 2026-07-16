import 'package:meta/meta.dart';

/// One measurement of a metric at a wall-clock instant.
@immutable
final class MetricSample {
  /// Host wall-clock microseconds since epoch.
  final int tMicros;

  /// Measured value, in the owning [MetricSeries.unit].
  final double value;

  /// Creates a sample at [tMicros] with [value].
  const MetricSample({required this.tMicros, required this.value});

  /// Restores a sample from [toJson] output.
  ///
  /// Integer `value` fields (common after JSON round-trips of whole
  /// numbers) are widened to double.
  factory MetricSample.fromJson(Map<String, Object?> json) => MetricSample(
    tMicros: (json['tMicros'] as num).toInt(),
    value: (json['value'] as num).toDouble(),
  );

  /// Serialises this sample to a JSON-encodable map.
  Map<String, Object?> toJson() => {'tMicros': tMicros, 'value': value};

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MetricSample && tMicros == other.tMicros && value == other.value;

  @override
  int get hashCode => Object.hash(tMicros, value);

  @override
  String toString() => 'MetricSample(t: $tMicros, value: $value)';
}

/// An explicit not-measured interval inside a [MetricSeries].
///
/// Gaps make missing data honest: assessment never bridges a gap as if
/// measurement had been continuous across it.
@immutable
final class SeriesGap {
  /// Gap start, host wall-clock microseconds since epoch.
  final int startMicros;

  /// Gap end, host wall-clock microseconds since epoch.
  final int endMicros;

  /// Why measurement stopped (e.g. `'adb reconnect'`, `'sampler error'`).
  final String reason;

  /// Creates a gap covering [startMicros]..[endMicros].
  const SeriesGap({
    required this.startMicros,
    required this.endMicros,
    required this.reason,
  });

  /// Restores a gap from [toJson] output.
  factory SeriesGap.fromJson(Map<String, Object?> json) => SeriesGap(
    startMicros: (json['startMicros'] as num).toInt(),
    endMicros: (json['endMicros'] as num).toInt(),
    reason: json['reason'] as String,
  );

  /// Serialises this gap to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'startMicros': startMicros,
    'endMicros': endMicros,
    'reason': reason,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SeriesGap &&
          startMicros == other.startMicros &&
          endMicros == other.endMicros &&
          reason == other.reason;

  @override
  int get hashCode => Object.hash(startMicros, endMicros, reason);

  @override
  String toString() => 'SeriesGap($startMicros..$endMicros, reason: $reason)';
}

/// A named, unit-tagged time series of [MetricSample]s with explicit
/// not-measured [gaps].
@immutable
final class MetricSeries {
  /// The JSON schema version written by [toJson].
  static const int schemaVersion = 1;

  /// Metric identifier (e.g. `'meminfo.native_pss'`).
  final String name;

  /// Value unit (e.g. `'bytes'`, `'count'`, `'kb'`).
  final String unit;

  /// The samples, expected in ascending [MetricSample.tMicros] order.
  ///
  /// Ordering contract: the const constructor cannot sort or verify, so
  /// producers must emit time-ordered samples. Consumers that depend on
  /// order (assessment) sort a defensive copy, so an unordered series is
  /// never misread — it is merely unconventional.
  final List<MetricSample> samples;

  /// Intervals where measurement was known to be off.
  final List<SeriesGap> gaps;

  /// Creates a series over [samples] with optional [gaps].
  const MetricSeries({
    required this.name,
    required this.unit,
    required this.samples,
    this.gaps = const [],
  });

  /// Restores a series from [toJson] output.
  ///
  /// Tolerates absent `gaps` (and `samples`) as empty lists and an absent
  /// `schemaVersion` (treated as 1). Throws [FormatException] when the
  /// payload declares a schema version newer than [schemaVersion].
  factory MetricSeries.fromJson(Map<String, Object?> json) {
    final version = json['schemaVersion'];
    if (version is num && version > schemaVersion) {
      throw FormatException(
        'unsupported MetricSeries schemaVersion $version — '
        'this reader supports <= $schemaVersion',
      );
    }
    return MetricSeries(
      name: json['name'] as String,
      unit: json['unit'] as String,
      samples: [
        for (final sample in json['samples'] as List<Object?>? ?? const [])
          MetricSample.fromJson(sample as Map<String, Object?>),
      ],
      gaps: [
        for (final gap in json['gaps'] as List<Object?>? ?? const [])
          SeriesGap.fromJson(gap as Map<String, Object?>),
      ],
    );
  }

  /// Serialises this series to a JSON-encodable map carrying
  /// `'schemaVersion': 1`.
  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'name': name,
    'unit': unit,
    'samples': [for (final sample in samples) sample.toJson()],
    'gaps': [for (final gap in gaps) gap.toJson()],
  };

  @override
  String toString() =>
      'MetricSeries($name, $unit, ${samples.length} samples, '
      '${gaps.length} gaps)';
}
