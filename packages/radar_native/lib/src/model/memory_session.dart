import 'package:meta/meta.dart';

import 'native_heap_profile.dart';

/// An opaque pointer to a `.dartheap` analysis held elsewhere — the
/// desktop's `SnapshotBundle`.
///
/// `radar_native` does not depend on `leak_graph`, so Dart-heap data is
/// never modeled here directly; this is a reference by id/label/time only.
/// Joining it back to the real analysis is the desktop's job.
@immutable
final class DartAnalysisRef {
  const DartAnalysisRef({
    required this.bundleId,
    required this.label,
    required this.capturedAt,
  });

  /// Identifier of the `SnapshotBundle` this ref points to, in whatever
  /// numbering scheme the owning client uses.
  final int bundleId;

  /// Human-readable label for this analysis (e.g. `"before"`, `"after"`).
  final String label;

  /// When the underlying Dart-heap snapshot was captured.
  final DateTime capturedAt;

  Map<String, Object?> toJson() => {
    'bundleId': bundleId,
    'label': label,
    'capturedAt': capturedAt.toIso8601String(),
  };

  factory DartAnalysisRef.fromJson(Map<String, Object?> json) =>
      DartAnalysisRef(
        bundleId: (json['bundleId'] as num).toInt(),
        label: json['label'] as String,
        capturedAt: DateTime.parse(json['capturedAt'] as String),
      );
}

/// A multi-modal capture session: native-heap profiles ([nativeProfiles],
/// Lane B) alongside references to Dart-heap analyses held elsewhere
/// ([dartRefs], Lane A — the desktop's `SnapshotBundle`s).
///
/// v1 holds no `leak_graph` dependency: Dart-heap data is referenced only
/// via [DartAnalysisRef], and cross-lane correlation is left to the
/// desktop. This container's own contribution is [timeline] — putting
/// both lanes on one shared time axis.
@immutable
final class MemorySession {
  const MemorySession({
    required this.label,
    required this.nativeProfiles,
    required this.dartRefs,
  });

  /// Human-readable label for this session.
  final String label;

  /// Native-heap checkpoints captured in this session (Lane B).
  final List<NativeHeapProfile> nativeProfiles;

  /// References to Dart-heap analyses captured in this session (Lane A),
  /// held elsewhere as the desktop's `SnapshotBundle`s.
  final List<DartAnalysisRef> dartRefs;

  /// Both lanes unified on one shared time axis, sorted by `capturedAt`
  /// ascending.
  ///
  /// v1 orders purely by the `capturedAt` each source model already
  /// stores; it does not itself reconcile clock domains. If native
  /// profiles and Dart-heap refs come from different clocks (e.g. device
  /// monotonic time vs. desktop wall-clock time), the parser layer that
  /// populates [nativeProfiles]/[dartRefs] is responsible for normalizing
  /// both into one clock before this ordering can be trusted for
  /// cross-lane comparisons.
  List<({DateTime at, String kind, String label})> get timeline {
    final List<({DateTime at, String kind, String label})> entries = [
      for (final profile in nativeProfiles)
        (at: profile.capturedAt, kind: 'native', label: profile.label),
      for (final ref in dartRefs)
        (at: ref.capturedAt, kind: 'dart', label: ref.label),
    ];
    entries.sort((a, b) => a.at.compareTo(b.at));
    return entries;
  }

  Map<String, Object?> toJson() => {
    'version': 1,
    'label': label,
    'nativeProfiles': [for (final p in nativeProfiles) p.toJson()],
    'dartRefs': [for (final r in dartRefs) r.toJson()],
  };

  /// Tolerant of a missing or older `version`: `nativeProfiles` and
  /// `dartRefs` default to empty when absent rather than throwing.
  factory MemorySession.fromJson(Map<String, Object?> json) => MemorySession(
    label: json['label'] as String,
    nativeProfiles: [
      for (final e in (json['nativeProfiles'] as List? ?? const []))
        NativeHeapProfile.fromJson((e as Map).cast<String, Object?>()),
    ],
    dartRefs: [
      for (final e in (json['dartRefs'] as List? ?? const []))
        DartAnalysisRef.fromJson((e as Map).cast<String, Object?>()),
    ],
  );
}
