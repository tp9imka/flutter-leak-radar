import 'package:meta/meta.dart';
import 'package:vm_service/vm_service.dart';

/// Minimum post-settle sample count for radar_trace's growth verdicts.
///
/// `assessSeries` splits the assessed region into two equal halves and its
/// Mann–Kendall certification refuses a batch2 smaller than 6 samples, so a
/// growth verdict needs at least 12 assessed post-settle samples. Cadence
/// defaults are chosen to clear this floor; [isAssessableCadence] warns when
/// a caller's overrides do not.
const int kMannKendallSampleFloor = 12;

/// One planned checkpoint: when to fire it, its label, and whether a full
/// heap snapshot is taken there.
@immutable
final class ScheduledCheckpoint {
  /// Offset from run start, in microseconds.
  final int offsetMicros;

  /// `'start'`, `'cp1'`…`'cpN'`, or `'end'`.
  final String label;

  /// Whether a full heap snapshot is captured at this checkpoint.
  final bool takeSnapshot;

  /// Creates a scheduled checkpoint.
  const ScheduledCheckpoint({
    required this.offsetMicros,
    required this.label,
    required this.takeSnapshot,
  });
}

/// Plans [interiorCount] evenly spaced checkpoints strictly between the run
/// start and end, plus the `start` (offset 0) and `end` (offset
/// [durationMicros]) bookends.
///
/// A snapshot is taken at every [snapshotEvery]-th checkpoint by index
/// (start = index 0); [snapshotEvery] of 0 disables snapshots entirely.
List<ScheduledCheckpoint> planCheckpoints({
  required int durationMicros,
  required int interiorCount,
  required int snapshotEvery,
}) {
  final interior = interiorCount < 0 ? 0 : interiorCount;
  final offsets = <int>[0];
  for (var i = 1; i <= interior; i++) {
    offsets.add(durationMicros * i ~/ (interior + 1));
  }
  offsets.add(durationMicros);

  bool snapshotAt(int index) => snapshotEvery > 0 && index % snapshotEvery == 0;

  return [
    for (var index = 0; index < offsets.length; index++)
      ScheduledCheckpoint(
        offsetMicros: offsets[index],
        label: _labelFor(index, offsets.length),
        takeSnapshot: snapshotAt(index),
      ),
  ];
}

String _labelFor(int index, int total) {
  if (index == 0) return 'start';
  if (index == total - 1) return 'end';
  return 'cp$index';
}

/// Sample offsets from run start: `0, interval, 2·interval, …` up to and
/// including [durationMicros] when it lands on a multiple.
List<int> sampleOffsetsMicros({
  required int durationMicros,
  required int sampleIntervalMicros,
}) {
  if (sampleIntervalMicros <= 0) return const [0];
  return [for (var t = 0; t <= durationMicros; t += sampleIntervalMicros) t];
}

/// Number of sample offsets that fall at or after the [settleMicros] window —
/// an upper bound on what `assessSeries` can assess (gaps only reduce it).
int projectedPostSettleSampleCount({
  required int durationMicros,
  required int sampleIntervalMicros,
  required int settleMicros,
}) {
  final offsets = sampleOffsetsMicros(
    durationMicros: durationMicros,
    sampleIntervalMicros: sampleIntervalMicros,
  );
  return offsets.where((t) => t >= settleMicros).length;
}

/// Whether the projected post-settle sample count clears
/// [kMannKendallSampleFloor], i.e. a growth verdict is even reachable.
bool isAssessableCadence({
  required int durationMicros,
  required int sampleIntervalMicros,
  required int settleMicros,
}) =>
    projectedPostSettleSampleCount(
      durationMicros: durationMicros,
      sampleIntervalMicros: sampleIntervalMicros,
      settleMicros: settleMicros,
    ) >=
    kMannKendallSampleFloor;

/// Captures the top [topN] classes by total retained bytes across every
/// isolate, mapping each to its summed live instance count.
///
/// Classes with no name are skipped (synthetic/anonymous entries).
Future<Map<String, int>> captureAllocationTopN(
  VmService service, {
  required int topN,
}) async {
  final vm = await service.getVM();
  final isolates = vm.isolates ?? const <IsolateRef>[];

  final bytes = <String, int>{};
  final instances = <String, int>{};
  for (final isolate in isolates) {
    final id = isolate.id;
    if (id == null) continue;
    final profile = await service.getAllocationProfile(id);
    for (final member in profile.members ?? const <ClassHeapStats>[]) {
      final name = member.classRef?.name;
      if (name == null || name.isEmpty) continue;
      bytes[name] = (bytes[name] ?? 0) + (member.bytesCurrent ?? 0);
      instances[name] = (instances[name] ?? 0) + (member.instancesCurrent ?? 0);
    }
  }

  final ranked = bytes.keys.toList()
    ..sort((a, b) => bytes[b]!.compareTo(bytes[a]!));

  return {for (final name in ranked.take(topN)) name: instances[name] ?? 0};
}
