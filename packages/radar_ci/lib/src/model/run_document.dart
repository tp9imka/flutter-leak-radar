import 'package:meta/meta.dart';
import 'package:radar_trace/radar_trace.dart';

/// The JSON schema version written by [RadarRunDocument.toJson].
const int kRadarRunDocumentSchemaVersion = 1;

/// Descriptive, tool-agnostic context for a single `radar_ci run`.
///
/// Every field except [startedAt] is optional: honest absence is preferred
/// over a fabricated value when the environment could not report it.
@immutable
final class RunMetadata {
  /// Wall-clock instant the run began.
  final DateTime startedAt;

  /// `flutter --version` short version, when known.
  final String? flutterVersion;

  /// Target Dart SDK version, when known.
  final String? dartVersion;

  /// Resolved target platform (e.g. `android-arm64`), when known.
  final String? targetPlatform;

  /// App run mode (`debug`/`profile`/`release`), when known.
  final String? mode;

  /// The command line that spawned the app, when `radar_ci` spawned it.
  final String? cmdLine;

  /// Free-form operator note (`--notes`).
  final String? notes;

  /// App-owned package names used to scope leak analysis.
  final List<String> projectPackages;

  /// How [projectPackages] was resolved: `flag`, `io-detect`, or `none`.
  final String projectPackagesSource;

  /// Whether the run reached its planned end. `false` marks a partial
  /// artifact flushed after an abort or interrupt.
  final bool completed;

  /// Why the run ended early, when [completed] is false (e.g.
  /// `'interrupted'`); null on a clean run.
  final String? abortReason;

  /// Creates run metadata.
  const RunMetadata({
    required this.startedAt,
    this.flutterVersion,
    this.dartVersion,
    this.targetPlatform,
    this.mode,
    this.cmdLine,
    this.notes,
    this.projectPackages = const [],
    this.projectPackagesSource = 'none',
    this.completed = true,
    this.abortReason,
  });

  /// Restores metadata from [toJson] output. Tolerates absent optionals;
  /// a legacy doc without `completed` reads as a completed run.
  factory RunMetadata.fromJson(Map<String, Object?> json) => RunMetadata(
    startedAt: DateTime.parse(json['startedAt'] as String),
    flutterVersion: json['flutterVersion'] as String?,
    dartVersion: json['dartVersion'] as String?,
    targetPlatform: json['targetPlatform'] as String?,
    mode: json['mode'] as String?,
    cmdLine: json['cmdLine'] as String?,
    notes: json['notes'] as String?,
    projectPackages: [
      for (final name in json['projectPackages'] as List<Object?>? ?? const [])
        name as String,
    ],
    projectPackagesSource: json['projectPackagesSource'] as String? ?? 'none',
    completed: json['completed'] as bool? ?? true,
    abortReason: json['abortReason'] as String?,
  );

  /// Serialises this metadata to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'startedAt': startedAt.toUtc().toIso8601String(),
    if (flutterVersion != null) 'flutterVersion': flutterVersion,
    if (dartVersion != null) 'dartVersion': dartVersion,
    if (targetPlatform != null) 'targetPlatform': targetPlatform,
    if (mode != null) 'mode': mode,
    if (cmdLine != null) 'cmdLine': cmdLine,
    if (notes != null) 'notes': notes,
    'projectPackages': projectPackages,
    'projectPackagesSource': projectPackagesSource,
    'completed': completed,
    if (abortReason != null) 'abortReason': abortReason,
  };

  /// Returns a copy with the run-completion fields replaced.
  RunMetadata copyWith({bool? completed, String? abortReason}) => RunMetadata(
    startedAt: startedAt,
    flutterVersion: flutterVersion,
    dartVersion: dartVersion,
    targetPlatform: targetPlatform,
    mode: mode,
    cmdLine: cmdLine,
    notes: notes,
    projectPackages: projectPackages,
    projectPackagesSource: projectPackagesSource,
    completed: completed ?? this.completed,
    abortReason: abortReason ?? this.abortReason,
  );
}

/// A labelled instant with an allocation snapshot and optional heap capture.
@immutable
final class RunCheckpoint {
  /// Host wall-clock microseconds since epoch.
  final int tMicros;

  /// `'start'`, `'cp1'`…`'cpN'`, `'end'`, or a user `--mark` label.
  final String label;

  /// className → live instance count, for the top classes by retained size.
  final Map<String, int> allocationTopN;

  /// Path to the full heap snapshot file, when one was taken here.
  final String? snapshotPath;

  /// Path to the analysis JSON, when the snapshot was analysed.
  final String? analysisPath;

  /// Capture outcome: `'ok'` (allocation profile captured; any requested
  /// snapshot succeeded), `'partial'` (profile captured but a requested
  /// snapshot/analysis failed), or `'failed'` (the profile RPC itself
  /// failed — [allocationTopN] is empty). Distinguishes an un-requested
  /// snapshot (`ok`, null paths) from a failed one.
  final String captureStatus;

  /// Human-readable reason when [captureStatus] is not `'ok'`; null otherwise.
  final String? captureError;

  /// Creates a checkpoint.
  const RunCheckpoint({
    required this.tMicros,
    required this.label,
    required this.allocationTopN,
    this.snapshotPath,
    this.analysisPath,
    this.captureStatus = 'ok',
    this.captureError,
  });

  /// Restores a checkpoint from [toJson] output. A legacy checkpoint without
  /// `captureStatus` reads as `'ok'`.
  factory RunCheckpoint.fromJson(Map<String, Object?> json) => RunCheckpoint(
    tMicros: (json['tMicros'] as num).toInt(),
    label: json['label'] as String,
    allocationTopN: {
      for (final entry
          in (json['allocationTopN'] as Map<Object?, Object?>? ?? const {})
              .entries)
        entry.key as String: (entry.value as num).toInt(),
    },
    snapshotPath: json['snapshotPath'] as String?,
    analysisPath: json['analysisPath'] as String?,
    captureStatus: json['captureStatus'] as String? ?? 'ok',
    captureError: json['captureError'] as String?,
  );

  /// Serialises this checkpoint to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'tMicros': tMicros,
    'label': label,
    'allocationTopN': allocationTopN,
    if (snapshotPath != null) 'snapshotPath': snapshotPath,
    if (analysisPath != null) 'analysisPath': analysisPath,
    'captureStatus': captureStatus,
    if (captureError != null) 'captureError': captureError,
  };
}

/// The interchange artifact of a headless `radar_ci run`.
///
/// Carries the sampled memory [series] (radar_trace types, gap-aware), the
/// [checkpoints] with allocation profiles and optional heap captures, and the
/// descriptive [metadata]. Serialises to a `run.json` that downstream verbs
/// (`assess`, `diff`) read.
@immutable
final class RadarRunDocument {
  /// The schema version of this document.
  final int schemaVersion;

  /// Descriptive run context.
  final RunMetadata metadata;

  /// One [MetricSeries] per tracked metric.
  final List<MetricSeries> series;

  /// Ordered checkpoints from `start` to `end`.
  final List<RunCheckpoint> checkpoints;

  /// Creates a run document (always the current [schemaVersion]).
  const RadarRunDocument({
    required this.metadata,
    required this.series,
    required this.checkpoints,
  }) : schemaVersion = kRadarRunDocumentSchemaVersion;

  /// Restores a run document from [toJson] output.
  ///
  /// Tolerates an absent `schemaVersion` (legacy v1) and absent collections.
  /// Throws [FormatException] on a non-numeric or newer-than-supported
  /// `schemaVersion`, so an unreadable document never masquerades as v1.
  factory RadarRunDocument.fromJson(Map<String, Object?> json) {
    final version = json['schemaVersion'];
    if (version != null) {
      if (version is! num) {
        throw FormatException(
          'RadarRunDocument schemaVersion must be numeric, got: $version',
        );
      }
      if (version > kRadarRunDocumentSchemaVersion) {
        throw FormatException(
          'unsupported RadarRunDocument schemaVersion $version — '
          'this reader supports <= $kRadarRunDocumentSchemaVersion',
        );
      }
    }
    return RadarRunDocument(
      metadata: RunMetadata.fromJson(json['metadata'] as Map<String, Object?>),
      series: [
        for (final s in json['series'] as List<Object?>? ?? const [])
          MetricSeries.fromJson(s as Map<String, Object?>),
      ],
      checkpoints: [
        for (final c in json['checkpoints'] as List<Object?>? ?? const [])
          RunCheckpoint.fromJson(c as Map<String, Object?>),
      ],
    );
  }

  /// Serialises this document to a JSON-encodable map carrying
  /// `'schemaVersion': 1`.
  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'metadata': metadata.toJson(),
    'series': [for (final s in series) s.toJson()],
    'checkpoints': [for (final c in checkpoints) c.toJson()],
  };
}
