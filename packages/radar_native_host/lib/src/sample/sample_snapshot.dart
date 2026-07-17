import 'package:meta/meta.dart';
import 'package:radar_native/radar_native.dart';
import 'package:radar_trace/radar_trace.dart';

/// One sampler reading of one [TriageColumn].
///
/// The parsed-or-unmeasured contract lives here: a parse miss (OEM format
/// variance, permission denial, dead pid) is **never** encoded as `value: 0`.
/// It is [SampleValue.unmeasured] — `measured == false`, `value == null`, and a
/// human [error] naming the miss. A measured `0` (e.g. a process that genuinely
/// has zero dmabuf fds) is a distinct, honest fact: `measured == true,
/// value == 0`. Downstream, an unmeasured reading becomes a [SeriesGap] /
/// not-measured column, never a flat zero that could out-rank a real trend.
@immutable
final class SampleValue {
  /// The parsed value in the column's canonical unit (KiB for byte columns,
  /// a raw count otherwise), or `null` when [measured] is false.
  final int? value;

  /// Whether this reading was successfully parsed from device output.
  final bool measured;

  /// Why the reading is unmeasured; `null` when [measured] is true.
  final String? error;

  /// A successful reading of [value].
  const SampleValue.measured(int this.value) : measured = true, error = null;

  /// A failed reading: not measured, carrying [error] as the honest reason.
  const SampleValue.unmeasured(String this.error)
    : value = null,
      measured = false;

  /// Restores from [toJson] output.
  factory SampleValue.fromJson(Map<String, Object?> json) {
    final measured = json['measured'] as bool;
    if (measured) {
      return SampleValue.measured((json['value'] as num).toInt());
    }
    return SampleValue.unmeasured(json['error'] as String? ?? 'not measured');
  }

  /// Serialises to a JSON-encodable map. `value`/`error` are elided when null
  /// so a measured reading and an unmeasured one never collide on shape.
  Map<String, Object?> toJson() => {
    'measured': measured,
    if (value != null) 'value': value,
    if (error != null) 'error': error,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SampleValue &&
          value == other.value &&
          measured == other.measured &&
          error == other.error;

  @override
  int get hashCode => Object.hash(value, measured, error);

  @override
  String toString() => measured
      ? 'SampleValue.measured($value)'
      : 'SampleValue.unmeasured($error)';
}

/// One host-timestamped sweep of Lane A columns.
///
/// A column absent from [values] was never attempted by any sampler in the
/// sweep; a column present with an unmeasured [SampleValue] *was* attempted and
/// failed. [TimelineBuilder] distinguishes the two: absent → omitted from the
/// timeline (honest by omission); present-but-unmeasured → a [SeriesGap].
@immutable
final class NativeSampleSnapshot {
  /// Host wall-clock microseconds since epoch for this sweep.
  final int tMicros;

  /// Per-column readings gathered in the sweep.
  final Map<TriageColumn, SampleValue> values;

  /// Creates a snapshot at [tMicros] over [values].
  const NativeSampleSnapshot({required this.tMicros, required this.values});

  /// Restores from [toJson] output. Throws [FormatException] on an unknown
  /// [TriageColumn] name — a corrupt column key must not silently vanish.
  factory NativeSampleSnapshot.fromJson(Map<String, Object?> json) {
    final byName = TriageColumn.values.asNameMap();
    final values = <TriageColumn, SampleValue>{};
    for (final entry in (json['values'] as Map? ?? const {}).entries) {
      final name = entry.key as String;
      final column = byName[name];
      if (column == null) {
        throw FormatException('unknown TriageColumn name: $name');
      }
      values[column] = SampleValue.fromJson(
        (entry.value as Map).cast<String, Object?>(),
      );
    }
    return NativeSampleSnapshot(
      tMicros: (json['tMicros'] as num).toInt(),
      values: values,
    );
  }

  /// Serialises to a JSON-encodable map, keying values by [TriageColumn.name].
  Map<String, Object?> toJson() => {
    'tMicros': tMicros,
    'values': {
      for (final entry in values.entries) entry.key.name: entry.value.toJson(),
    },
  };

  @override
  String toString() =>
      'NativeSampleSnapshot(t: $tMicros, ${values.length} columns)';
}

/// A side-effect-free reader of one or more [TriageColumn]s off a device.
///
/// Implementations shell out to read-only `adb` commands (`dumpsys`, `cat
/// /proc/...`, `ls -l`) — they never trigger an in-process device allocation
/// (no `am dumpheap`), so sampling cannot itself perturb the very memory it
/// measures.
abstract interface class NativeSampler {
  /// The columns this sampler can produce. A returned map from [sample] always
  /// has exactly these keys (each measured or unmeasured).
  Set<TriageColumn> get columns;

  /// Reads [columns] for [package] / [pid], one [SampleValue] per column.
  Future<Map<TriageColumn, SampleValue>> sample(String package, int pid);
}

/// Every column in [columns] as an unmeasured reading carrying [error].
///
/// The canonical pid-gone / command-failed shape: a whole sampler's columns
/// read not-measured at once, never a fabricated set of zeros.
Map<TriageColumn, SampleValue> allUnmeasured(
  Set<TriageColumn> columns,
  String error,
) => {for (final column in columns) column: SampleValue.unmeasured(error)};

/// Builds a per-column reading map: each column in [columns] is measured from
/// [found] when present, else unmeasured via [missReason].
///
/// A `0` in [found] is a genuine measured zero and stays measured — only an
/// absent key becomes unmeasured, keeping the measured-zero / not-measured
/// distinction intact.
Map<TriageColumn, SampleValue> readingsFrom(
  Set<TriageColumn> columns,
  Map<TriageColumn, int> found,
  String Function(TriageColumn column) missReason,
) {
  final readings = <TriageColumn, SampleValue>{};
  for (final column in columns) {
    final value = found[column];
    readings[column] = value == null
        ? SampleValue.unmeasured(missReason(column))
        : SampleValue.measured(value);
  }
  return readings;
}

/// Runs several [NativeSampler]s and merges their readings into one map.
///
/// Merge rule (deterministic, honesty-preserving): first *measured* reading of
/// a column wins; an unmeasured reading only fills a column no earlier sampler
/// measured. So when two samplers both produce a column (e.g. `threads` from
/// both `/proc/status` and `task/*/comm`), the earlier sampler in [samplers] is
/// authoritative, and a failing sampler never overwrites a good reading.
///
/// Throw isolation: a sampler that throws mid-sweep (a bad parse, a
/// `ProcessException` when `adb` can't launch) has its columns degraded to
/// not-measured for that tick; every other sampler's readings survive.
final class CompositeSampler implements NativeSampler {
  /// Creates a composite over [samplers], applied in order.
  const CompositeSampler(this.samplers);

  /// The delegated samplers, in merge-precedence order.
  final List<NativeSampler> samplers;

  @override
  Set<TriageColumn> get columns => {
    for (final sampler in samplers) ...sampler.columns,
  };

  @override
  Future<Map<TriageColumn, SampleValue>> sample(String package, int pid) async {
    final merged = <TriageColumn, SampleValue>{};
    for (final sampler in samplers) {
      // A single sampler throwing (a bad parse, a ProcessException when adb
      // can't launch) must not lose the whole tick's already-gathered
      // readings: its columns degrade to not-measured and the sweep continues.
      Map<TriageColumn, SampleValue> readings;
      try {
        readings = await sampler.sample(package, pid);
      } catch (error) {
        readings = allUnmeasured(sampler.columns, 'sampler threw: $error');
      }
      for (final entry in readings.entries) {
        final existing = merged[entry.key];
        final upgradesUnmeasured =
            existing != null && !existing.measured && entry.value.measured;
        if (existing == null || upgradesUnmeasured) {
          merged[entry.key] = entry.value;
        }
      }
    }
    return merged;
  }
}

int _realNowMicros() => DateTime.now().microsecondsSinceEpoch;

/// Accumulates [NativeSampleSnapshot]s into a [TriageTimeline], one
/// [MetricSeries] per column, with [SeriesGap]s spanning unmeasured stretches.
///
/// Every emitted series carries `unit == expectedUnit(column)` so the triage
/// router never degrades a correctly-sampled column on a unit mismatch. A
/// maximal run of consecutive unmeasured readings for a column becomes one gap
/// whose `reason` is the first sampler error in that run.
final class TimelineBuilder {
  /// Creates a builder. [nowMicros] stamps [addMark]s; injectable so tests are
  /// deterministic.
  TimelineBuilder({int Function()? nowMicros})
    : _nowMicros = nowMicros ?? _realNowMicros;

  final int Function() _nowMicros;
  final List<NativeSampleSnapshot> _snapshots = [];
  final List<TriageMark> _marks = [];

  /// Appends a sampled sweep.
  void add(NativeSampleSnapshot snapshot) => _snapshots.add(snapshot);

  /// Records a labeled checkpoint at the builder's current wall-clock.
  void addMark(String label) =>
      _marks.add(TriageMark(tMicros: _nowMicros(), label: label));

  /// Builds the timeline. Columns are emitted in [TriageColumn] declaration
  /// order; a column attempted in no snapshot is omitted entirely (never a
  /// fabricated empty series).
  TriageTimeline build() {
    final sorted = [..._snapshots]
      ..sort((a, b) => a.tMicros.compareTo(b.tMicros));
    final columns = <TriageColumn, MetricSeries>{};
    for (final column in TriageColumn.values) {
      final attempted = sorted.any((s) => s.values.containsKey(column));
      if (!attempted) continue;
      columns[column] = _seriesFor(column, sorted);
    }
    return TriageTimeline(columns: columns, marks: [..._marks]);
  }

  MetricSeries _seriesFor(
    TriageColumn column,
    List<NativeSampleSnapshot> sorted,
  ) {
    final samples = <MetricSample>[];
    final gaps = <SeriesGap>[];

    int? lastGoodMicros;
    int? firstNullMicros;
    int? lastNullMicros;
    String? gapReason;

    // A gap spans from the last measured sample to the next one — the same
    // nonzero-width encoding radar_ci's sampler.dart uses. Even a lone
    // not-measured tick between two readings becomes a nonzero-width gap.
    // series_assessment's `_mergedIntervals` discards zero-width gaps as
    // malformed, so the earlier "lone tick" encoding let the native lane
    // silently bridge an outage the Dart lane would split on (and so certify
    // monotonicGrowth across unmeasured stretches); this one never does.
    void flushGap(int? endMicros) {
      final firstNull = firstNullMicros;
      if (firstNull == null) return;
      gaps.add(
        SeriesGap(
          startMicros: lastGoodMicros ?? firstNull,
          endMicros: endMicros ?? lastNullMicros ?? firstNull,
          reason: gapReason ?? 'not measured',
        ),
      );
      firstNullMicros = null;
      lastNullMicros = null;
      gapReason = null;
    }

    for (final snapshot in sorted) {
      final reading = snapshot.values[column];
      if (reading == null) continue;
      final value = reading.value;
      if (reading.measured && value != null) {
        flushGap(snapshot.tMicros);
        samples.add(
          MetricSample(tMicros: snapshot.tMicros, value: value.toDouble()),
        );
        lastGoodMicros = snapshot.tMicros;
      } else {
        firstNullMicros ??= snapshot.tMicros;
        gapReason ??= reading.error;
        lastNullMicros = snapshot.tMicros;
      }
    }
    flushGap(null);

    return MetricSeries(
      name: column.name,
      unit: expectedUnit(column),
      samples: samples,
      gaps: gaps,
    );
  }
}
