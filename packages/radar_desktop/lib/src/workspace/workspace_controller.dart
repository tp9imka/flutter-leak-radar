import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:radar_workbench/radar_workbench.dart';

import '../seams/desktop_snapshot_exporter.dart';
import '../seams/disconnected_connection.dart';
import '../seams/file_snapshot_store.dart';
import '../seams/offline_snapshot_source.dart';
import 'dump_meta.dart';

export 'dump_meta.dart';

/// Owns the offline workspace: a `radar_workbench` [MemoryController] (built
/// with the offline seams) plus desktop-only state — the multi-dump trend
/// selection, recent files, and the "analyzing…" flag. Screens read
/// [memory] for the reused views and this controller for workspace actions.
class WorkspaceController extends ChangeNotifier {
  WorkspaceController({SnapshotAnalyzer analyzer = const SnapshotAnalyzer()})
    : _analyzer = analyzer {
    _connection = DisconnectedRadarConnection();
    memory = MemoryController(
      snapshotSource: const OfflineSnapshotSource(),
      connection: _connection,
    );
    // Auto-persist on every memory change. The shell calls `restore()` before
    // any user mutation, so this never overwrites a good save with an empty
    // one; the `isEmpty` guard in `_persist` is extra insurance.
    memory.addListener(() => unawaited(_persist()));
  }

  final SnapshotAnalyzer _analyzer;
  late final DisconnectedRadarConnection _connection;
  final DesktopSnapshotExporter _exporter = const DesktopSnapshotExporter();
  final FileSnapshotStore _store = FileSnapshotStore();

  /// The reused workbench controller — pass to `ClassHistogramView`,
  /// `RetainingPathsView`, `DiffTable`, etc.
  late final MemoryController memory;

  final Map<int, DumpMeta> _meta = {};
  final List<int> _trend = [];
  final List<String> _recent = [];
  bool _analyzing = false;
  String? _analyzingName;

  bool get analyzing => _analyzing;
  String? get analyzingName => _analyzingName;
  List<int> get trendSelection => List.unmodifiable(_trend);
  List<String> get recentPaths => List.unmodifiable(_recent);
  int? get activeDumpId => memory.focusedId;

  /// Dumps in capture order (matches `memory.snapshots`).
  List<DumpMeta> get dumps => [for (final s in memory.snapshots) _meta[s.id]!];

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
  }

  void clearAll() {
    memory.clearAll();
    _meta.clear();
    _trend.clear();
    notifyListeners();
  }

  /// Serializes the current workspace (bundles + the memory view) for
  /// persistence. Dump metadata is recomputed from the bundles on rehydrate.
  PersistedSession toSession() => PersistedSession(
    bundles: memory.snapshots,
    selectedIds: memory.selectedIds,
    view: RadarView.snapshotDiff,
  );

  /// Restores a persisted session into an EMPTY controller (rebuilds meta
  /// from the bundles). Used by both file-open and auto-restore.
  void rehydrate(PersistedSession session) {
    // memory.rehydrate preserves the bundles' ids; rebuild the row metadata
    // from the restored snapshots.
    memory.rehydrate(session);
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
  }

  /// Exports [id]'s bundle as a shareable report via the desktop exporter.
  Future<void> exportDump(int id) async {
    final bundle = memory.byId(id);
    if (bundle != null) await _exporter.export(bundle);
  }

  /// Auto-restore the last session on launch.
  Future<void> restore() async {
    final session = await _store.restore();
    if (session != null && session.bundles.isNotEmpty) rehydrate(session);
  }

  /// Persists the current session (called after mutations via the [memory]
  /// listener). Skips empty sessions so a fresh, not-yet-restored controller
  /// never clobbers a previously saved one.
  Future<void> _persist() async {
    if (memory.snapshots.isEmpty) return;
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
