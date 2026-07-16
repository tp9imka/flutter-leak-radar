import 'dart:math' as math;

import 'package:meta/meta.dart';

import 'metric_series.dart';

/// Growth verdict for one assessed [MetricSeries].
enum SeriesVerdict {
  /// The second batch is still climbing at series end and sits above the
  /// first batch — the leak signature.
  monotonicGrowth,

  /// Reached a bounded steady state: warmed up then held, stayed flat, or
  /// declined. The bounded-cache / warm-up signature — not a leak.
  plateau,

  /// Variation dominates any trend; neither growth nor flatness can be
  /// separated honestly.
  noisy,

  /// Not enough trustworthy data for any verdict.
  insufficientData,
}

/// Tuning knobs for [assessSeries].
final class AssessOptions {
  /// Samples inside this window from the series start are trimmed —
  /// first samples are warm-up.
  final Duration settle;

  /// Fewer assessed samples than this reads
  /// [SeriesVerdict.insufficientData].
  final int minSamples;

  /// A shorter assessed span than this reads
  /// [SeriesVerdict.insufficientData].
  final Duration minSpan;

  /// A trend must exceed this multiple of the series' noise level to
  /// count as movement.
  final double noiseFactor;

  /// Creates options; defaults follow the field-proven methodology.
  const AssessOptions({
    this.settle = const Duration(seconds: 30),
    this.minSamples = 8,
    this.minSpan = const Duration(minutes: 2),
    this.noiseFactor = 2.0,
  });
}

/// The outcome of assessing one [MetricSeries].
@immutable
final class SeriesAssessment {
  /// The verdict; see [SeriesVerdict].
  final SeriesVerdict verdict;

  /// Robust slope over the last batch in unit/hour, or null when it
  /// cannot be truthfully computed.
  final double? slopePerHour;

  /// (batch2 center − batch1 center) normalized per hour — the init-free
  /// growth signal. Null when not computable.
  final double? batchDeltaPerHour;

  /// Samples actually assessed after settle-trim and gap handling.
  final int samplesAssessed;

  /// Samples present in the input series.
  final int samplesTotal;

  /// One honest human-readable sentence.
  final String detail;

  /// Creates an assessment.
  const SeriesAssessment({
    required this.verdict,
    required this.slopePerHour,
    required this.batchDeltaPerHour,
    required this.samplesAssessed,
    required this.samplesTotal,
    required this.detail,
  });

  /// Restores an assessment from [toJson] output.
  ///
  /// Throws [FormatException] on an unknown verdict name.
  factory SeriesAssessment.fromJson(Map<String, Object?> json) {
    final name = json['verdict'] as String;
    final verdict = SeriesVerdict.values.asNameMap()[name];
    if (verdict == null) {
      throw FormatException('unknown SeriesVerdict name: $name');
    }
    return SeriesAssessment(
      verdict: verdict,
      slopePerHour: (json['slopePerHour'] as num?)?.toDouble(),
      batchDeltaPerHour: (json['batchDeltaPerHour'] as num?)?.toDouble(),
      samplesAssessed: (json['samplesAssessed'] as num).toInt(),
      samplesTotal: (json['samplesTotal'] as num).toInt(),
      detail: json['detail'] as String,
    );
  }

  /// Serialises this assessment to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'verdict': verdict.name,
    'slopePerHour': slopePerHour,
    'batchDeltaPerHour': batchDeltaPerHour,
    'samplesAssessed': samplesAssessed,
    'samplesTotal': samplesTotal,
    'detail': detail,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SeriesAssessment &&
          verdict == other.verdict &&
          slopePerHour == other.slopePerHour &&
          batchDeltaPerHour == other.batchDeltaPerHour &&
          samplesAssessed == other.samplesAssessed &&
          samplesTotal == other.samplesTotal &&
          detail == other.detail;

  @override
  int get hashCode => Object.hash(
    verdict,
    slopePerHour,
    batchDeltaPerHour,
    samplesAssessed,
    samplesTotal,
    detail,
  );

  @override
  String toString() => 'SeriesAssessment(${verdict.name}: $detail)';
}

/// Assesses [series] for growth using settle-trimmed, gap-aware,
/// init-free batch comparison.
///
/// Honesty contract: a signal that cannot be truthfully computed reads
/// [SeriesVerdict.insufficientData] with null slopes — never a plausible
/// number. Gaps are never bridged. Never throws on any input.
SeriesAssessment assessSeries(
  MetricSeries series, [
  AssessOptions options = const AssessOptions(),
]) {
  // Mirrors the package-wide "never throw into the host" contract; a
  // failed assessment degrades to an honest non-verdict.
  try {
    return _assess(series, options);
  } catch (error) {
    return SeriesAssessment(
      verdict: SeriesVerdict.insufficientData,
      slopePerHour: null,
      batchDeltaPerHour: null,
      samplesAssessed: 0,
      samplesTotal: series.samples.length,
      detail: 'assessment failed internally ($error) — no verdict',
    );
  }
}

const double _microsPerHour = 3600 * 1e6;

// Consistency factor turning the median absolute deviation into a
// Gaussian-comparable sigma estimate.
const double _madToSigma = 1.4826;

// Flat-vs-noisy needs a scale; without caller input the only honest scale
// is the metric's own level. Above this per-sample noise fraction the
// measurements cannot vouch for a bounded level, so flatness is not
// separable from noise.
const double _noisyRelativeNoise = 0.2;

// Theil-Sen is O(n^2) in pair count; slope quality saturates long before
// this many points, so thin (preserving time coverage) past it.
const int _maxSlopeSamples = 400;

SeriesAssessment _assess(MetricSeries series, AssessOptions options) {
  final total = series.samples.length;

  SeriesAssessment fail(int assessed, String detail) => SeriesAssessment(
    verdict: SeriesVerdict.insufficientData,
    slopePerHour: null,
    batchDeltaPerHour: null,
    samplesAssessed: assessed,
    samplesTotal: total,
    detail: detail,
  );

  // Non-finite values are broken measurements, not data. Sorting a copy
  // upholds the documented "unordered input is never misread" contract.
  final ordered = [
    for (final sample in series.samples)
      if (sample.value.isFinite) sample,
  ]..sort((a, b) => a.tMicros.compareTo(b.tMicros));
  if (ordered.isEmpty) return fail(0, 'no finite samples to assess');

  final settleEnd = ordered.first.tMicros + options.settle.inMicroseconds;
  final settled = [
    for (final sample in ordered)
      if (sample.tMicros >= settleEnd) sample,
  ];
  if (settled.length < options.minSamples) {
    return fail(
      settled.length,
      'only ${settled.length} of $total samples remain after the '
      '${_fmtDuration(options.settle.inMicroseconds)} settle trim — '
      'need >= ${options.minSamples}',
    );
  }

  final regions = _splitByGaps(settled, series.gaps);
  if (regions.isEmpty) {
    return fail(0, 'every post-settle sample falls inside a declared gap');
  }

  bool qualifies(List<MetricSample> region) =>
      region.length >= options.minSamples &&
      _spanMicros(region) >= options.minSpan.inMicroseconds;

  // Prefer the region after the last gap (freshest steady state); fall
  // back to the longest contiguous region.
  var region = regions.last;
  if (!qualifies(region)) {
    region = regions.reduce((a, b) {
      final spanA = _spanMicros(a);
      final spanB = _spanMicros(b);
      if (spanB > spanA) return b;
      if (spanB == spanA && b.length > a.length) return b;
      return a;
    });
  }
  if (!qualifies(region)) {
    if (regions.length > 1) {
      final percent = _gapCoveragePercent(settled, series.gaps);
      return fail(
        region.length,
        'gaps cover ~$percent% of the post-settle window — no contiguous '
        'region has >= ${options.minSamples} samples over '
        '${_fmtDuration(options.minSpan.inMicroseconds)}',
      );
    }
    if (region.length < options.minSamples) {
      return fail(
        region.length,
        'only ${region.length} contiguous samples — '
        'need >= ${options.minSamples}',
      );
    }
    return fail(
      region.length,
      'assessed span ${_fmtDuration(_spanMicros(region))} — '
      'need >= ${_fmtDuration(options.minSpan.inMicroseconds)}',
    );
  }

  final assessed = region.length;
  final startMicros = region.first.tMicros;
  final endMicros = region.last.tMicros;
  final regionSpan = endMicros - startMicros;

  // Two equal-duration batches: batch1 carries warm-up, batch2 carries
  // the init-free signal.
  final midMicros = startMicros + regionSpan ~/ 2;
  final batch1 = [
    for (final sample in region)
      if (sample.tMicros < midMicros) sample,
  ];
  final batch2 = [
    for (final sample in region)
      if (sample.tMicros >= midMicros) sample,
  ];
  if (batch1.length < 2 || batch2.length < 3) {
    return fail(
      assessed,
      'samples cluster in one half of the window '
      '(${batch1.length} vs ${batch2.length}) — cannot compare batches',
    );
  }

  // Medians as central tendency: one spike cannot move them.
  final center1 = _median([for (final sample in batch1) sample.value]);
  final center2 = _median([for (final sample in batch2) sample.value]);
  final halfSpanMicros = regionSpan / 2;
  final batchDeltaPerHour =
      (center2 - center1) / halfSpanMicros * _microsPerHour;

  // Theil-Sen slope over batch2: the median of pairwise slopes has a
  // ~29% breakdown point, so a single spike or dip cannot flip its sign
  // the way it can with least squares.
  final slopeSamples = _thinned(batch2, _maxSlopeSamples);
  final pairSlopes = <double>[];
  for (var i = 0; i < slopeSamples.length; i++) {
    for (var j = i + 1; j < slopeSamples.length; j++) {
      final dtMicros = slopeSamples[j].tMicros - slopeSamples[i].tMicros;
      if (dtMicros <= 0) continue;
      pairSlopes.add(
        (slopeSamples[j].value - slopeSamples[i].value) / dtMicros,
      );
    }
  }
  if (pairSlopes.isEmpty) {
    return fail(
      assessed,
      'second half of the window has no time spread — '
      'slope not computable',
    );
  }
  final slopePerMicro = _median(pairSlopes);
  final slopePerHour = slopePerMicro * _microsPerHour;

  // Noise = robust residual scale of batch2 about its own trend line
  // (batch1 warm-up curvature must not inflate it). Times are taken
  // relative to the region start to preserve double precision.
  final intercept = _median([
    for (final sample in batch2)
      sample.value - slopePerMicro * (sample.tMicros - startMicros),
  ]);
  final noise =
      _madToSigma *
      _median([
        for (final sample in batch2)
          (sample.value -
                  (intercept + slopePerMicro * (sample.tMicros - startMicros)))
              .abs(),
      ]);

  final unit = series.unit;
  final batch2SpanMicros = endMicros - batch2.first.tMicros;
  final slopeDrift = slopePerMicro * batch2SpanMicros;
  final deltaMove = center2 - center1;
  // Tiny value-scaled epsilon so a zero-noise series still needs real
  // movement (not float dust) to register a trend.
  final epsilon = 1e-9 * math.max(center2.abs(), 1.0);
  final threshold = options.noiseFactor * noise + epsilon;

  SeriesAssessment verdictOf(SeriesVerdict verdict, String detail) =>
      SeriesAssessment(
        verdict: verdict,
        slopePerHour: slopePerHour,
        batchDeltaPerHour: batchDeltaPerHour,
        samplesAssessed: assessed,
        samplesTotal: total,
        detail: detail,
      );

  // Batch medians and Theil-Sen both discount movement confined to the
  // final stretch — the same property that makes them spike-robust. The
  // end shift restores honesty at the series end: a sustained tail drop
  // vetoes "still climbing", a sustained tail rise vetoes "bounded".
  final endShift = _endShift(batch2);

  if (slopeDrift > threshold && deltaMove > 0) {
    if (endShift != null && endShift < -threshold) {
      // Monotonic-then-crash: "still climbing at series end" would be a
      // lie, and "bounded" was never demonstrated either.
      return verdictOf(
        SeriesVerdict.noisy,
        'grew ${_fmt(slopePerHour)} $unit/h, then dropped in the final '
        'stretch — growth not sustained through series end',
      );
    }
    return verdictOf(
      SeriesVerdict.monotonicGrowth,
      'grew ${_fmt(slopePerHour)} $unit/h in the second half — '
      'still climbing at series end',
    );
  }

  final level = _median([for (final sample in region) sample.value]);
  final relativeNoise = level.abs() > 0
      ? noise / level.abs()
      : (noise > 0 ? double.infinity : 0.0);
  if (relativeNoise > _noisyRelativeNoise) {
    return verdictOf(
      SeriesVerdict.noisy,
      'per-sample noise ~${_fmt(noise)} $unit dominates any trend at the '
      '~${_fmt(level)} $unit level',
    );
  }
  if (endShift != null && endShift > threshold) {
    return verdictOf(
      SeriesVerdict.noisy,
      'level rose ${_fmt(endShift)} $unit in the final stretch — too late '
      'in the window to demonstrate either growth or a bounded plateau',
    );
  }
  if (deltaMove > threshold) {
    return verdictOf(
      SeriesVerdict.plateau,
      'warmed up ${_fmt(deltaMove)} $unit between halves, then flat over '
      '${_fmtDuration(batch2SpanMicros)} — bounded, not a leak',
    );
  }
  if (deltaMove < -threshold || slopeDrift < -threshold) {
    return verdictOf(
      SeriesVerdict.plateau,
      'declining over the window — not growing',
    );
  }
  return verdictOf(
    SeriesVerdict.plateau,
    'flat within noise over ${_fmtDuration(regionSpan)} — '
    'bounded, not a leak',
  );
}

/// (final-quarter median − rest-of-batch2 median), or null when either
/// side is too thin to judge. A 1-2 sample blip must not steer any
/// verdict (symmetric with Theil-Sen's spike robustness), hence the
/// minimum head/tail sizes.
double? _endShift(List<MetricSample> batch2) {
  final startMicros = batch2.first.tMicros;
  final endMicros = batch2.last.tMicros;
  final tailStart = endMicros - (endMicros - startMicros) ~/ 4;
  final tail = [
    for (final sample in batch2)
      if (sample.tMicros >= tailStart) sample,
  ];
  final head = [
    for (final sample in batch2)
      if (sample.tMicros < tailStart) sample,
  ];
  if (tail.length < 3 || head.length < 3) return null;
  return _median([for (final sample in tail) sample.value]) -
      _median([for (final sample in head) sample.value]);
}

/// Splits [samples] into contiguous regions separated by [gaps].
/// Samples strictly inside a gap are dropped; boundary samples belong to
/// the adjacent region.
List<List<MetricSample>> _splitByGaps(
  List<MetricSample> samples,
  List<SeriesGap> gaps,
) {
  if (samples.isEmpty) return const [];
  final merged = _mergedIntervals(gaps);
  if (merged.isEmpty) return [samples];

  final regions = <List<MetricSample>>[];
  List<MetricSample>? current;
  var currentKey = -1;
  for (final sample in samples) {
    var key = 0;
    var insideGap = false;
    for (final gap in merged) {
      if (gap.end <= sample.tMicros) {
        key++;
        continue;
      }
      insideGap = gap.start < sample.tMicros && sample.tMicros < gap.end;
      break;
    }
    if (insideGap) continue;
    if (key != currentKey || current == null) {
      current = [];
      regions.add(current);
      currentKey = key;
    }
    current.add(sample);
  }
  return regions;
}

/// Sorted, disjoint gap intervals; malformed gaps (end <= start) are
/// ignored.
List<({int start, int end})> _mergedIntervals(List<SeriesGap> gaps) {
  final valid = [
    for (final gap in gaps)
      if (gap.endMicros > gap.startMicros)
        (start: gap.startMicros, end: gap.endMicros),
  ]..sort((a, b) => a.start.compareTo(b.start));
  final merged = <({int start, int end})>[];
  for (final interval in valid) {
    if (merged.isEmpty || interval.start > merged.last.end) {
      merged.add(interval);
    } else if (interval.end > merged.last.end) {
      merged.last = (start: merged.last.start, end: interval.end);
    }
  }
  return merged;
}

int _gapCoveragePercent(List<MetricSample> settled, List<SeriesGap> gaps) {
  final start = settled.first.tMicros;
  final end = settled.last.tMicros;
  if (end <= start) return 0;
  var covered = 0;
  for (final gap in _mergedIntervals(gaps)) {
    covered += math.max(0, math.min(end, gap.end) - math.max(start, gap.start));
  }
  return (covered * 100 / (end - start)).round().clamp(0, 100);
}

int _spanMicros(List<MetricSample> samples) =>
    samples.isEmpty ? 0 : samples.last.tMicros - samples.first.tMicros;

/// Median of a non-empty list.
double _median(List<double> values) {
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid]
      : (sorted[mid - 1] + sorted[mid]) / 2;
}

/// Evenly strided subset of at most [maxCount] samples, always keeping
/// the first and last.
List<MetricSample> _thinned(List<MetricSample> samples, int maxCount) {
  if (samples.length <= maxCount) return samples;
  return [
    for (var i = 0; i < maxCount; i++)
      samples[i * (samples.length - 1) ~/ (maxCount - 1)],
  ];
}

String _fmt(double value) {
  final magnitude = value.abs();
  if (magnitude >= 100) return value.toStringAsFixed(0);
  if (magnitude >= 10) return value.toStringAsFixed(1);
  return value.toStringAsFixed(2);
}

String _fmtDuration(int micros) {
  final seconds = micros / 1e6;
  if (seconds < 90) return '${_fmt(seconds)}s';
  return '${_fmt(seconds / 60)}m';
}
