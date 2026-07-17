import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:radar_ci/radar_ci.dart';
import 'package:radar_native/radar_native.dart';
import 'package:radar_native_host/radar_native_host.dart';
import 'package:radar_trace/radar_trace.dart';

/// Reads a file's contents as a string. Injected in tests to avoid real IO;
/// defaults to `dart:io`.
typedef FileReader = Future<String> Function(String path);

/// Where an imported artifact came from.
enum MonitorSourceKind {
  /// A native `session_dir/timeline.json` (Lane A `TriageTimeline`).
  session,

  /// A `radar_ci` `run.json` (Dart-VM memory `MetricSeries`).
  run,
}

/// Import lifecycle of the Device Monitor pane.
enum MonitorState {
  /// Nothing imported yet.
  idle,

  /// An import is in flight.
  loading,

  /// An artifact imported and is ready to render.
  ready,

  /// The last import failed; [DeviceMonitorController.errorMessage] says why.
  error,
}

/// One plotted metric plus its growth assessment — the unit a chart line and a
/// verdict chip render from.
@immutable
final class MonitorSeries {
  /// Creates a monitor series.
  const MonitorSeries({
    required this.label,
    required this.series,
    required this.assessment,
    this.column,
  });

  /// Display label (the Lane A column name, or the run.json series name).
  final String label;

  /// The gap-aware samples to plot.
  final MetricSeries series;

  /// The growth verdict + slopes for this series.
  final SeriesAssessment assessment;

  /// The Lane A column this came from, or null for a run.json series.
  final TriageColumn? column;
}

/// The analyzed, render-ready form of one imported artifact.
@immutable
final class MonitorAnalysis {
  /// Creates an analysis.
  const MonitorAnalysis({
    required this.label,
    required this.kind,
    required this.series,
    required this.marks,
    required this.settleWindow,
    required this.summary,
    required this.bucket,
    required this.provenance,
    required this.session,
    this.aborted = false,
  });

  /// Display label (session dir name, or run.json file name).
  final String label;

  /// What kind of artifact this came from.
  final MonitorSourceKind kind;

  /// The plotted series, in a stable declaration order.
  final List<MonitorSeries> series;

  /// Checkpoint / event marks for the chart.
  final List<({int tMicros, String label})> marks;

  /// The settle (warm-up) window to shade, or null when there are no samples.
  final ({int startMicros, int endMicros})? settleWindow;

  /// The one-line router summary (session) or run summary.
  final String summary;

  /// The dominant Lane A leak bucket, or null for a run.json (no router).
  final TriageBucket? bucket;

  /// Provenance context, when known.
  final SessionProvenance? provenance;

  /// The reusable triage session (session kind only) — the compare model's
  /// input. Null for a run.json.
  final TriageSession? session;

  /// Whether the source artifact ended early — a run.json with
  /// `completed: false`, or a native session whose `endReason` is a known
  /// non-completed value (`interrupted`/`error`). Thinner evidence, surfaced
  /// with emphasis rather than reading a clean green off an early exit.
  final bool aborted;
}

/// Drives the Device Monitor's import-first surface: imports a native session
/// timeline OR a radar_ci run, analyzes it with the shared triage/assess
/// engine, and (for two native sessions) exposes the C4 compare model.
///
/// Never throws into its callers — a bad file sets [state] to
/// [MonitorState.error] with a human [errorMessage] rather than crashing or
/// rendering fabricated data.
class DeviceMonitorController extends ChangeNotifier {
  /// Creates a controller. Inject [readFile] in tests; [options] tunes the
  /// shared assessment (defaults follow the field-proven methodology).
  DeviceMonitorController({
    FileReader? readFile,
    AssessOptions options = const AssessOptions(),
  }) : _readFile = readFile ?? _defaultReader,
       _options = options;

  final FileReader _readFile;
  final AssessOptions _options;

  MonitorState _state = MonitorState.idle;
  String? _errorMessage;
  String? _comparisonError;
  MonitorAnalysis? _primary;
  MonitorAnalysis? _comparison;

  /// The import lifecycle state.
  MonitorState get state => _state;

  /// A human-readable reason the last primary import failed, or null.
  String? get errorMessage => _errorMessage;

  /// A human-readable reason the last comparison import was refused, or null.
  String? get comparisonError => _comparisonError;

  /// The primary imported artifact, or null.
  MonitorAnalysis? get primary => _primary;

  /// The comparison artifact, or null.
  MonitorAnalysis? get comparison => _comparison;

  /// The assessment options in effect.
  AssessOptions get options => _options;

  /// Whether a session-vs-session compare is possible (the primary is a native
  /// session).
  bool get canCompare => _primary?.session != null;

  /// The per-column before→after comparison, or null unless both sides are
  /// native sessions. Reuses radar_native_host's C4 compare model.
  List<ColumnComparison>? get compareColumnsList {
    final before = _primary?.session;
    final after = _comparison?.session;
    if (before == null || after == null) return null;
    return compareColumns(before, after);
  }

  /// Imports [path] as the primary artifact (session timeline or run.json),
  /// clearing any prior comparison.
  Future<void> importPrimary(String path) async {
    _state = MonitorState.loading;
    _errorMessage = null;
    _comparisonError = null;
    notifyListeners();
    try {
      final analysis = await _load(path);
      _primary = analysis;
      _comparison = null;
      _state = MonitorState.ready;
    } catch (error) {
      _primary = null;
      _comparison = null;
      _errorMessage = _humanError(error);
      _state = MonitorState.error;
    }
    notifyListeners();
  }

  /// Imports [path] as the comparison against the primary session. Refused
  /// (without destroying the primary) when there is no primary session or the
  /// file is not a native session timeline.
  Future<void> importComparison(String path) async {
    if (_primary?.session == null) {
      _comparisonError = 'Import a native session first to compare against.';
      notifyListeners();
      return;
    }
    _comparisonError = null;
    notifyListeners();
    try {
      final analysis = await _load(path);
      if (analysis.session == null) {
        _comparisonError =
            'Compare needs a native session timeline — a radar_ci run.json '
            'cannot be compared here.';
        notifyListeners();
        return;
      }
      _comparison = analysis;
    } catch (error) {
      _comparisonError = _humanError(error);
    }
    notifyListeners();
  }

  /// Clears all imported state back to idle.
  void clear() {
    _primary = null;
    _comparison = null;
    _errorMessage = null;
    _comparisonError = null;
    _state = MonitorState.idle;
    notifyListeners();
  }

  Future<MonitorAnalysis> _load(String path) async {
    final content = await _readFile(path);
    final Object? decoded;
    try {
      decoded = jsonDecode(content);
    } on FormatException catch (e) {
      throw FormatException('not valid JSON — ${e.message}');
    }
    if (decoded is! Map) {
      throw const FormatException('root JSON value is not an object');
    }
    final json = decoded.cast<String, Object?>();

    // Positive markers: run.json always carries `metadata`; a session timeline
    // carries `columns`/`marks`. Anything else is unrecognized (never guessed).
    if (json.containsKey('metadata')) {
      return _analyzeRun(RadarRunDocument.fromJson(json), path);
    }
    if (json.containsKey('columns') || json.containsKey('marks')) {
      final timeline = TriageTimeline.fromJson(json);
      return _analyzeSession(timeline, path, await _readProvenance(path));
    }
    throw const FormatException(
      'unrecognized file: neither a native session timeline (columns/marks) '
      'nor a radar_ci run (metadata)',
    );
  }

  MonitorAnalysis _analyzeSession(
    TriageTimeline timeline,
    String path,
    SessionProvenance? provenance,
  ) {
    final label = _sessionLabel(path);
    final verdict = triage(timeline, _options);
    final session = TriageSession(
      label: label,
      timeline: timeline,
      verdict: verdict,
      provenance: provenance,
    );
    final series = [
      for (final a in verdict.assessments)
        if (timeline.columns[a.column] != null)
          MonitorSeries(
            label: a.column.name,
            series: timeline.columns[a.column]!,
            assessment: a.assessment,
            column: a.column,
          ),
    ];
    return MonitorAnalysis(
      label: label,
      kind: MonitorSourceKind.session,
      series: series,
      marks: [
        for (final m in timeline.marks) (tMicros: m.tMicros, label: m.label),
      ],
      settleWindow: _settleWindow(series),
      summary: verdict.summary,
      bucket: verdict.bucket,
      provenance: provenance,
      session: session,
      aborted: _sessionEndedEarly(provenance),
    );
  }

  /// A session ended early when it recorded any `endReason` other than
  /// `completed` (`interrupted`, `error`, or any other future value). An
  /// absent reason is never guessed to be an abort (best-effort provenance),
  /// so only a genuinely recorded non-completed reason escalates.
  bool _sessionEndedEarly(SessionProvenance? provenance) {
    final reason = provenance?.endReason;
    return reason != null && reason != 'completed';
  }

  MonitorAnalysis _analyzeRun(RadarRunDocument doc, String path) {
    final native = doc.nativeTimeline;
    final series = [
      for (final s in doc.series)
        MonitorSeries(
          label: s.name,
          series: s,
          assessment: assessSeries(s, _options),
          column: null,
        ),
      // A `--native-package` co-drive carries a native timeline alongside the
      // Dart series — surface its columns as plotted, assessed series rather
      // than dropping them and mislabelling the run "Dart VM memory". Full
      // native-lane router analysis / compare is a follow-up.
      if (native != null)
        for (final entry in native.columns.entries)
          MonitorSeries(
            label: entry.key.name,
            series: entry.value,
            assessment: assessSeries(entry.value, _options),
            column: entry.key,
          ),
    ];
    return MonitorAnalysis(
      label: _fileLabel(path),
      kind: MonitorSourceKind.run,
      series: series,
      marks: [
        for (final c in doc.checkpoints) (tMicros: c.tMicros, label: c.label),
      ],
      settleWindow: _settleWindow(series),
      summary: _runSummary(doc),
      bucket: null,
      provenance: _runProvenance(doc.metadata),
      session: null,
      aborted: !doc.metadata.completed,
    );
  }

  /// Reads a session's sibling `meta.json` for provenance, best-effort: any
  /// missing or malformed meta is honest context, never a gate — it degrades
  /// to null rather than failing the import.
  Future<SessionProvenance?> _readProvenance(String timelinePath) async {
    try {
      final metaPath = p.join(p.dirname(timelinePath), 'meta.json');
      final decoded = jsonDecode(await _readFile(metaPath));
      if (decoded is! Map) return null;
      return SessionProvenance.fromMetaJson(decoded.cast<String, Object?>());
    } catch (_) {
      return null;
    }
  }

  /// The settle window to shade: from the earliest sample across all series to
  /// [AssessOptions.settle] later. Null when nothing was sampled.
  ({int startMicros, int endMicros})? _settleWindow(List<MonitorSeries> s) {
    int? minMicros;
    for (final m in s) {
      for (final sample in m.series.samples) {
        if (minMicros == null || sample.tMicros < minMicros) {
          minMicros = sample.tMicros;
        }
      }
    }
    if (minMicros == null) return null;
    return (
      startMicros: minMicros,
      endMicros: minMicros + _options.settle.inMicroseconds,
    );
  }

  String _runSummary(RadarRunDocument doc) {
    final n = doc.series.length;
    final meta = doc.metadata;
    final ended = meta.completed
        ? 'completed'
        : 'ended early${meta.abortReason != null ? ': ${meta.abortReason}' : ''}';
    final native = doc.nativeTimeline;
    final lane = native == null
        ? '$n metric series (Dart VM memory)'
        : '$n Dart VM series + native lane '
              '(${native.columns.length} column'
              '${native.columns.length == 1 ? '' : 's'})';
    return 'radar_ci run — $lane, $ended';
  }

  SessionProvenance _runProvenance(RunMetadata m) => SessionProvenance(
    package: m.projectPackages.isEmpty ? null : m.projectPackages.join(', '),
    device: m.targetPlatform,
    endReason: m.completed ? 'completed' : (m.abortReason ?? 'interrupted'),
  );

  String _sessionLabel(String path) {
    final base = p.basename(path);
    if (base == 'timeline.json') return p.basename(p.dirname(path));
    return base;
  }

  String _fileLabel(String path) => p.basename(path);

  String _humanError(Object error) =>
      error is FormatException ? error.message : error.toString();

  static Future<String> _defaultReader(String path) =>
      File(path).readAsString();
}
