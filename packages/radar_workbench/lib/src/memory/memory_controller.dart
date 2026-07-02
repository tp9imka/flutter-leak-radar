import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:leak_graph/leak_graph.dart';

import '../capture/snapshot_bundle.dart';
import '../core/radar_connection.dart';
import '../core/snapshot_source.dart';
import '../session/snapshot_store.dart';

/// The two snapshots chosen for a diff, ordered oldest → newest.
typedef DiffPair = ({SnapshotBundle baseline, SnapshotBundle comparison});

/// Owns the list of captured heap snapshots and the diff selection.
///
/// Replaces the old A/B-only `DiffController`: any number of snapshots can be
/// captured and kept, each can be exported, and the user picks *any two* to
/// diff. Held on `RadarSession` so its state survives DevTools tab switches.
class MemoryController extends ChangeNotifier {
  MemoryController({
    required SnapshotSource snapshotSource,
    required RadarConnection connection,
  }) : _snapshotSource = snapshotSource,
       _connection = connection {
    // [canCapture] derives from the connection, which often becomes ready AFTER
    // first paint (the main isolate wires up asynchronously). Forward the
    // connection's changes so views listening to this controller re-read
    // [canCapture] and (re-)enable the capture toolbar without a manual
    // re-navigation.
    _connection.addListener(notifyListeners);
  }

  final SnapshotSource _snapshotSource;
  final RadarConnection _connection;
  static const _log = 'leakRadarDevTools.memory';

  /// Upper bound on how many recent snapshots are persisted, to stay within
  /// durable-store limits. In-memory capture stays unbounded.
  static const _maxPersistedSnapshots = 8;

  final List<SnapshotBundle> _snapshots = [];
  final List<int> _selected = []; // ids chosen for diff, max 2
  int _nextId = 1;
  int? _focusedId;
  bool _capturing = false;
  String? _error;

  /// True once this session was rehydrated from a durable store (used by the
  /// UI to show a subtle "restored" hint).
  bool restoredFromDisk = false;

  /// All captures, oldest first.
  List<SnapshotBundle> get snapshots => List.unmodifiable(_snapshots);

  /// Ids currently selected for diffing, in selection order.
  List<int> get selectedIds => List.unmodifiable(_selected);

  /// The explicitly-focused snapshot id for the single-snapshot views
  /// (histogram / retaining paths), or null to fall back to the diff pair /
  /// latest. Set by hosts (e.g. the desktop app) that let the user pick an
  /// arbitrary dump to inspect; unused by DevTools (which leaves it null).
  int? get focusedId => _focusedId;

  /// The most recent snapshots to persist (capped at [_maxPersistedSnapshots]).
  List<SnapshotBundle> get persistableSnapshots {
    if (_snapshots.length <= _maxPersistedSnapshots) {
      return List.unmodifiable(_snapshots);
    }
    return List.unmodifiable(
      _snapshots.sublist(_snapshots.length - _maxPersistedSnapshots),
    );
  }

  bool get capturing => _capturing;
  String? get error => _error;
  bool get hasSnapshots => _snapshots.isNotEmpty;

  /// True when a VM service connection and main isolate are both available.
  bool get canCapture =>
      _connection.vmService != null && _connection.isolateRef != null;

  bool isSelected(int id) => _selected.contains(id);

  /// The two selected snapshots ordered oldest→newest (baseline→comparison),
  /// or null when fewer than two are selected.
  DiffPair? get pair {
    if (_selected.length < 2) return null;
    final a = _byId(_selected[0]);
    final b = _byId(_selected[1]);
    if (a == null || b == null) return null;
    final aFirst = a.capturedAt.isBefore(b.capturedAt);
    return (baseline: aFirst ? a : b, comparison: aFirst ? b : a);
  }

  /// Most recently captured snapshot, or null.
  SnapshotBundle? get latest => _snapshots.isEmpty ? null : _snapshots.last;

  /// Snapshot shown by the single-snapshot views (histogram, retaining paths):
  /// the comparison of the selected pair if two are chosen, else the latest.
  SnapshotBundle? get focused =>
      (_focusedId == null ? null : _byId(_focusedId!)) ??
      pair?.comparison ??
      latest;

  SnapshotBundle? get _singleSelected =>
      _selected.length == 1 ? _byId(_selected.first) : null;

  /// Snapshot populating the diff table's "after" / absolute column: the
  /// comparison of the selected pair, or — when exactly one snapshot is
  /// selected — that snapshot shown against an empty baseline. Null when
  /// nothing is selected.
  SnapshotBundle? get comparison => pair?.comparison ?? _singleSelected;

  /// True when exactly one snapshot is selected, so [diff] is that snapshot
  /// against an empty baseline (an absolute "show everything" view) rather than
  /// a delta between two snapshots.
  bool get comparingAgainstEmpty => pair == null && _singleSelected != null;

  /// Ranked class diff for the current selection: growth between the two
  /// selected snapshots, or — when a single snapshot is selected — that
  /// snapshot against an empty baseline (every class shown at its full count).
  /// Null when nothing is selected. Computed on demand from the histograms.
  List<ClassCountDiff>? get diff {
    final p = pair;
    if (p != null) {
      return computeDiff(p.baseline.histogram, p.comparison.histogram);
    }
    final only = _singleSelected;
    if (only != null) return computeDiff(const [], only.histogram);
    return null;
  }

  SnapshotBundle? _byId(int id) {
    for (final s in _snapshots) {
      if (s.id == id) return s;
    }
    return null;
  }

  SnapshotBundle? byId(int id) => _byId(id);

  /// Captures a heap snapshot, appends it to the list, and (for the first two
  /// captures) auto-selects it so a diff appears without extra taps.
  Future<void> capture({String? label}) async {
    if (!canCapture) {
      _error = 'Not connected to a running app.';
      notifyListeners();
      return;
    }
    _capturing = true;
    _error = null;
    notifyListeners();

    final id = _nextId++;
    try {
      final bundle = await _snapshotSource.capture(
        label: label ?? 'Snapshot $id',
      );
      _snapshots.add(bundle.copyWith(id: id));
      if (_selected.length < 2) _selected.add(id);
      developer.log('Captured snapshot $id', name: _log);
    } catch (e, s) {
      developer.log('capture failed', name: _log, error: e, stackTrace: s);
      _error = 'Capture failed: $e';
    } finally {
      _capturing = false;
      notifyListeners();
    }
  }

  /// Appends a pre-built, already-analyzed [bundle] (e.g. imported from a heap
  /// dump file) without going through the VM service. Assigns the next session
  /// id, auto-selects it while fewer than two are selected (so a diff appears
  /// without extra taps, matching [capture]), notifies listeners, and returns
  /// the stored id-assigned bundle.
  SnapshotBundle addBundle(SnapshotBundle bundle) {
    final id = _nextId++;
    final stored = bundle.copyWith(id: id);
    _snapshots.add(stored);
    if (_selected.length < 2) _selected.add(id);
    notifyListeners();
    return stored;
  }

  /// Sets [focusedId] (or clears it with null) and notifies.
  void focusOn(int? id) {
    _focusedId = id;
    notifyListeners();
  }

  /// Toggles [id] in the diff selection (max two). Selecting a third drops the
  /// oldest selection.
  void toggleSelection(int id) {
    if (_selected.contains(id)) {
      _selected.remove(id);
    } else {
      if (_selected.length >= 2) _selected.removeAt(0);
      _selected.add(id);
    }
    notifyListeners();
  }

  void remove(int id) {
    _snapshots.removeWhere((s) => s.id == id);
    _selected.remove(id);
    notifyListeners();
  }

  void clearAll() {
    _snapshots.clear();
    _selected.clear();
    _error = null;
    restoredFromDisk = false;
    notifyListeners();
  }

  /// Replaces the current state with a previously persisted [session]. Ids and
  /// selection are taken from the session; [_nextId] resumes past the highest
  /// restored id. No-op for an empty session. Notifies listeners once.
  void rehydrate(PersistedSession session) {
    if (session.bundles.isEmpty) return;
    _snapshots
      ..clear()
      ..addAll(session.bundles);
    final ids = {for (final s in _snapshots) s.id};
    _selected
      ..clear()
      ..addAll(session.selectedIds.where(ids.contains).take(2));
    _nextId = (ids.isEmpty ? 0 : ids.reduce((a, b) => a > b ? a : b)) + 1;
    restoredFromDisk = true;
    notifyListeners();
  }

  /// Appends a pre-built bundle without touching the VM service. Test-only:
  /// lets widget/logic tests populate the list without a live connection.
  @visibleForTesting
  void debugAdd(SnapshotBundle bundle) {
    _snapshots.add(bundle);
    notifyListeners();
  }

  /// Requests a GC cycle via [VmService.getAllocationProfile] with
  /// `reset: true` (available without special VM flags). No-op when not
  /// connected.
  Future<void> forceGc() async {
    final svc = _connection.vmService;
    final iso = _connection.isolateRef;
    if (svc == null || iso == null) return;
    try {
      await svc.getAllocationProfile(iso.id!, reset: true);
    } catch (e, s) {
      developer.log('forceGc failed', name: _log, error: e, stackTrace: s);
    }
  }

  @override
  void dispose() {
    _connection.removeListener(notifyListeners);
    super.dispose();
  }
}
