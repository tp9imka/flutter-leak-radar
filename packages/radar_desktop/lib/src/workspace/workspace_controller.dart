import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:radar_workbench/radar_workbench.dart';

import '../seams/desktop_snapshot_exporter.dart';
import '../seams/disconnected_connection.dart';
import '../seams/file_snapshot_store.dart';
import '../seams/offline_snapshot_source.dart';
import 'desktop_project_context.dart';
import 'dump_meta.dart';

export 'desktop_project_context.dart';
export 'dump_meta.dart';

/// Owns the offline workspace: a `radar_workbench` [MemoryController] (built
/// with the offline seams) plus desktop-only state — the multi-dump trend
/// selection, recent files, and the "analyzing…" flag. Screens read
/// [memory] for the reused views and this controller for workspace actions.
class WorkspaceController extends ChangeNotifier {
  WorkspaceController({
    SnapshotAnalyzer analyzer = const SnapshotAnalyzer(),
    FileSnapshotStore? store,
  }) : _analyzer = analyzer,
       _store = store ?? FileSnapshotStore() {
    _connection = DisconnectedRadarConnection();
    memory = MemoryController(
      snapshotSource: const OfflineSnapshotSource(),
      connection: _connection,
    );
  }

  final SnapshotAnalyzer _analyzer;
  late final DisconnectedRadarConnection _connection;
  final DesktopSnapshotExporter _exporter = const DesktopSnapshotExporter();
  final FileSnapshotStore _store;

  /// The reused workbench controller — pass to `ClassHistogramView`,
  /// `RetainingPathsView`, `DiffTable`, etc.
  late final MemoryController memory;

  final Map<int, DumpMeta> _meta = {};
  final List<int> _trend = [];
  final List<String> _recent = [];
  bool _analyzing = false;
  String? _analyzingName;

  /// Cross-session leak triage. [_triage] is the in-session display store (the
  /// loaded baseline + ACKs) the cluster/diff views read; [_diskTriage] is the
  /// accumulating mirror folded on each save so `firstSeen` is pinned.
  TriageStore _triage = TriageStore.empty;
  TriageStore _diskTriage = TriageStore.empty;
  String? _restoreRefusal;

  String? _projectRoot;
  DesktopProjectContext _projectContext = DesktopProjectContext();

  bool get analyzing => _analyzing;
  String? get analyzingName => _analyzingName;
  List<int> get trendSelection => List.unmodifiable(_trend);
  List<String> get recentPaths => List.unmodifiable(_recent);
  int? get activeDumpId => memory.focusedId;

  /// The in-session triage baseline the cluster/diff views compare against.
  TriageStore get triage => _triage;

  /// Non-null when the stored session was refused (written by a newer build);
  /// the shell surfaces it and persistence is suppressed until [startNewSession].
  String? get restoreRefusal => _restoreRefusal;

  /// Applies an explicit triage change (an ACK) and persists it.
  void updateTriage(TriageStore next) {
    _triage = next;
    notifyListeners();
    unawaited(_persist());
  }

  /// Clears a [restoreRefusal] by dropping the unreadable stored session, so
  /// persistence resumes fresh.
  Future<void> startNewSession() async {
    await _store.clear();
    _restoreRefusal = null;
    notifyListeners();
  }

  /// The chosen on-disk project folder used to resolve "yours" attribution and
  /// open hop sources in an editor. Null until the user picks one.
  String? get projectRoot => _projectRoot;

  /// The desktop project identity fed to `RetainingPathsView` — detection +
  /// source opening for the current [projectRoot].
  ProjectContext get projectContext => _projectContext;

  /// Points the project context at [root] (or clears it with null), rebuilding
  /// the context so the paths view re-resolves attribution and opening.
  void setProjectRoot(String? root) {
    _projectRoot = root;
    _projectContext = DesktopProjectContext(projectRoot: root);
    notifyListeners();
  }

  /// Dumps in capture order (matches `memory.snapshots`). Tolerant of a
  /// snapshot whose metadata hasn't been written yet: [addExisting] calls
  /// `memory.addBundle` (which notifies listeners) before `_meta[id]` is set,
  /// so a listener reading [dumps] in that window must not null-assert.
  List<DumpMeta> get dumps => [
    for (final s in memory.snapshots)
      if (_meta[s.id] case final m?) m,
  ];

  /// Adds an already-analyzed bundle (the connection-free core of import).
  /// Assigns metadata, appends to [memory], focuses it, and returns the stored
  /// bundle. Used directly by tests and by [importBytes]/restore.
  SnapshotBundle addExisting(
    SnapshotBundle bundle, {
    required DumpSource source,
  }) {
    final stored = memory.addBundle(bundle);
    _meta[stored.id] = DumpMeta(
      id: stored.id,
      label: stored.label,
      source: source,
      capturedAt: stored.capturedAt,
      classCount: stored.histogram.length,
      retainedBytes: stored.shallowBytes,
    );
    memory.focusOn(stored.id);
    notifyListeners();
    unawaited(_persist());
    return stored;
  }

  /// Imports raw `.dartheap` bytes: analyze off-thread, then add to the
  /// workspace. Surfaces [analyzing] while in flight. Never throws (the
  /// analyzer returns a failed bundle on error).
  Future<void> importBytes(
    Uint8List bytes, {
    required String label,
    String? recentPath,
  }) async {
    _analyzing = true;
    _analyzingName = label;
    notifyListeners();
    try {
      final bundle = await _analyzer.fromBytes(bytes, label: label);
      addExisting(bundle, source: DumpSource.file);
      if (recentPath != null) {
        _recent
          ..remove(recentPath)
          ..insert(0, recentPath);
        if (_recent.length > 8) _recent.removeLast();
      }
    } finally {
      _analyzing = false;
      _analyzingName = null;
      notifyListeners();
    }
  }

  /// Makes [id] the active dump for the histogram / retaining-paths views.
  void openDump(int id) => memory.focusOn(id);

  /// Sets the compare pair to exactly (a, b) via the memory 2-way selection.
  void selectComparePair(int a, int b) {
    // Clear then select the two (toggleSelection caps at 2, FIFO).
    for (final id in memory.selectedIds.toList()) {
      memory.toggleSelection(id);
    }
    memory.toggleSelection(a);
    memory.toggleSelection(b);
  }

  void toggleTrendSelection(int id) {
    if (_trend.contains(id)) {
      _trend.remove(id);
    } else {
      _trend.add(id);
    }
    notifyListeners();
  }

  void removeDump(int id) {
    memory.remove(id);
    _meta.remove(id);
    _trend.remove(id);
    notifyListeners();
    unawaited(_persist());
  }

  void clearAll() {
    memory.clearAll();
    _meta.clear();
    _trend.clear();
    notifyListeners();
    unawaited(_persist());
  }

  /// Serializes the current workspace (bundles + the memory view + the folded
  /// triage mirror) for persistence. Dump metadata is recomputed from the
  /// bundles on rehydrate.
  PersistedSession toSession() => PersistedSession(
    bundles: memory.snapshots,
    selectedIds: memory.selectedIds,
    view: RadarView.snapshotDiff,
    triage: _diskTriage,
  );

  /// Restores a persisted session into an EMPTY controller (rebuilds meta
  /// from the bundles). Used by both file-open and auto-restore.
  void rehydrate(PersistedSession session) {
    // memory.rehydrate preserves the bundles' ids; rebuild the row metadata
    // from the restored snapshots.
    memory.rehydrate(session);
    _triage = session.triage;
    _diskTriage = session.triage;
    _meta.clear();
    for (final s in memory.snapshots) {
      _meta[s.id] = DumpMeta(
        id: s.id,
        label: s.label,
        source: DumpSource.file,
        capturedAt: s.capturedAt,
        classCount: s.histogram.length,
        retainedBytes: s.shallowBytes,
      );
    }
    notifyListeners();
    unawaited(_persist());
  }

  /// Exports [id]'s bundle as a shareable report via the desktop exporter.
  Future<void> exportDump(int id) async {
    final bundle = memory.byId(id);
    if (bundle != null) await _exporter.export(bundle);
  }

  bool _restored = false;

  /// Auto-restore the last session on launch. Idempotent: a second call (e.g.
  /// the shell re-running it after an injected pre-restore) is a no-op.
  Future<void> restore() async {
    if (_restored) return;
    _restored = true;
    final session = await _store.restore();
    _restoreRefusal = _store.restoreRefusal;
    if (session != null && session.bundles.isNotEmpty) {
      rehydrate(session);
    } else {
      // Seed the triage baseline even when there are no bundles to rehydrate,
      // so a triage-only session (fixes recorded, dumps pruned) is not dropped
      // — symmetric with RadarSession.attachStore and the DTD restore.
      if (session != null) {
        _triage = session.triage;
        _diskTriage = session.triage;
      }
      // Surface a refusal (or the seeded triage) without a bundle set.
      notifyListeners();
    }
  }

  /// Persists the current session. Called explicitly after the mutations
  /// that change the bundle *set* ([addExisting], [removeDump], [clearAll],
  /// [rehydrate]) — not after pure view-state changes like [openDump] or
  /// [selectComparePair] — so a multi-MB session isn't re-serialized on every
  /// memory notification. Skips empty sessions so a fresh, not-yet-restored
  /// controller never clobbers a previously saved one.
  Future<void> _persist() async {
    if (memory.snapshots.isEmpty) return;
    final focused = memory.focused;
    _diskTriage = foldSessionTriage(
      diskStore: _diskTriage,
      displayStore: _triage,
      // Null (no focused snapshot) skips the fold — see [foldSessionTriage].
      classNameBySignature: focused == null
          ? null
          : classNamesBySignature(focused),
      now: DateTime.now(),
    );
    await _store.persist(toSession());
  }

  /// Saves the workspace to a user-chosen `.radarworkspace` file.
  Future<void> saveWorkspace() async {
    final loc = await getSaveLocation(
      suggestedName: 'workspace.radarworkspace',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Radar Workspace', extensions: ['radarworkspace']),
      ],
    );
    if (loc == null) return;
    await _store.persistAtPath(toSession(), loc.path);
  }

  /// Opens a `.radarworkspace` file the user picks and rehydrates from it.
  Future<void> openWorkspace() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Radar Workspace', extensions: ['radarworkspace']),
      ],
    );
    if (file == null) return;
    final session = await _store.restoreFromPath(file.path);
    if (session != null && session.bundles.isNotEmpty) rehydrate(session);
  }

  @override
  void dispose() {
    memory.dispose();
    _connection.dispose();
    super.dispose();
  }
}
