import 'package:radar_native/radar_native.dart';
import 'package:radar_native_host/radar_native_host.dart';

/// Reads the Lane A native columns once, for the co-drive tick at [tMicros].
///
/// The pure seam the run loop drives: an implementation shells out to `adb`
/// (see the `radar_ci_io` layer), a test supplies canned readings. Honesty
/// contract, identical to the overnight `sample` loop: a device/pid miss or a
/// per-command failure NEVER throws and NEVER reads 0 — it returns every column
/// as an unmeasured [SampleValue], which becomes a [SeriesGap] downstream.
abstract interface class NativeCoSampler {
  /// Reads all sampled columns for the instant [tMicros], one [SampleValue]
  /// per column. Never throws.
  Future<Map<TriageColumn, SampleValue>> sampleAt(int tMicros);
}

/// Drives a [NativeCoSampler] alongside the Dart lane during one `radar_ci
/// run`, accumulating a [TriageTimeline] on the run's host wall-clock.
///
/// The co-drive is deliberately a *simpler* sampler than the overnight
/// `radar_sample` loop: it ticks every [intervalMicros] across the run window
/// and drops a mark at each Dart checkpoint, sharing the run's clock so the two
/// lanes line up on one timeline. Robustness (device outages, pid re-resolve,
/// periodic flush) is the overnight loop's job; here the run's own
/// partial-flush + signal machinery already covers an abort — [build] reflects
/// exactly the ticks gathered so far, so an interrupted run keeps its native
/// lane the same way it keeps its Dart samples.
final class NativeCoDrive {
  /// Creates a co-drive that ticks [sampler] every [intervalMicros].
  ///
  /// [builder] must be constructed with the run's clock (`nowMicros:
  /// clock.nowMicros`) so a [mark] recorded at a checkpoint is stamped at the
  /// checkpoint's own instant, in real and virtual time alike.
  NativeCoDrive({
    required this.intervalMicros,
    required this.sampler,
    required TimelineBuilder builder,
  }) : _builder = builder;

  /// Interval between native ticks, in microseconds. Must be positive.
  final int intervalMicros;

  /// The seam that reads the device each tick.
  final NativeCoSampler sampler;

  final TimelineBuilder _builder;

  /// Samples once and appends the sweep at [tMicros].
  Future<void> tick(int tMicros) async {
    final values = await sampler.sampleAt(tMicros);
    _builder.add(NativeSampleSnapshot(tMicros: tMicros, values: values));
  }

  /// Records a labeled checkpoint at the builder's current (run-clock) instant.
  void mark(String label) => _builder.addMark(label);

  /// Builds the timeline gathered so far — safe to call mid-run for a partial
  /// flush.
  TriageTimeline build() => _builder.build();
}

/// Native tick offsets from run start: `0, interval, 2·interval, …` up to and
/// including [durationMicros] when it lands on a multiple.
///
/// Mirrors the Dart lane's `sampleOffsetsMicros` so both lanes anchor a reading
/// at the run's start; a non-positive interval degrades to a single start tick.
List<int> nativeTickOffsetsMicros({
  required int durationMicros,
  required int intervalMicros,
}) {
  if (intervalMicros <= 0) return const [0];
  return [for (var t = 0; t <= durationMicros; t += intervalMicros) t];
}
