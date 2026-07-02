import 'package:meta/meta.dart';

import 'native_callsite.dart';

/// Metadata about the capture that produced a [NativeHeapProfile].
///
/// All fields are optional — a checkpoint pulled from an older exporter or
/// a manually-assembled trace may not know its own pid/package/sampling
/// interval.
@immutable
final class NativeProfileMeta {
  const NativeProfileMeta({this.pid, this.package, this.samplingIntervalBytes});

  /// Process id of the captured app, if known.
  final int? pid;

  /// Application/package id of the captured app, if known.
  final String? package;

  /// heapprofd sampling interval in bytes, if known.
  final int? samplingIntervalBytes;

  Map<String, Object?> toJson() => {
    if (pid != null) 'pid': pid,
    if (package != null) 'package': package,
    if (samplingIntervalBytes != null)
      'samplingIntervalBytes': samplingIntervalBytes,
  };

  factory NativeProfileMeta.fromJson(Map<String, Object?> json) =>
      NativeProfileMeta(
        pid: (json['pid'] as num?)?.toInt(),
        package: json['package'] as String?,
        samplingIntervalBytes: (json['samplingIntervalBytes'] as num?)?.toInt(),
      );
}

/// One heapprofd checkpoint: a labeled, timestamped capture of native-heap
/// callsites (Lane B), plus capture [meta]data.
///
/// This is the unit that [NativeHeapProfile]s get diffed pairwise against —
/// two checkpoints for the same process, "before" and "after" a suspected
/// leak trigger.
@immutable
final class NativeHeapProfile {
  const NativeHeapProfile({
    required this.capturedAt,
    required this.label,
    required this.callsites,
    required this.meta,
  });

  /// When this checkpoint was captured.
  final DateTime capturedAt;

  /// Human-readable label for this checkpoint (e.g. `"before"`, `"after"`).
  final String label;

  /// Every callsite observed at this checkpoint.
  final List<NativeCallsite> callsites;

  final NativeProfileMeta meta;

  /// Total still-live bytes across all callsites — the leak signal for
  /// this checkpoint.
  int get totalStillLiveBytes =>
      callsites.fold(0, (sum, c) => sum + c.stillLiveBytes);

  Map<String, Object?> toJson() => {
    'version': 1,
    'capturedAt': capturedAt.toIso8601String(),
    'label': label,
    'meta': meta.toJson(),
    'callsites': [for (final c in callsites) c.toJson()],
  };

  /// Tolerant of a missing or older `version`: `meta` and `callsites`
  /// default to empty when absent rather than throwing.
  factory NativeHeapProfile.fromJson(Map<String, Object?> json) =>
      NativeHeapProfile(
        capturedAt: DateTime.parse(json['capturedAt'] as String),
        label: json['label'] as String,
        callsites: [
          for (final e in (json['callsites'] as List? ?? const []))
            NativeCallsite.fromJson((e as Map).cast<String, Object?>()),
        ],
        meta: switch (json['meta']) {
          final Map<Object?, Object?> m => NativeProfileMeta.fromJson(
            m.cast<String, Object?>(),
          ),
          _ => const NativeProfileMeta(),
        },
      );
}
