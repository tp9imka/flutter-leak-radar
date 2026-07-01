import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:leak_graph/leak_graph.dart';

import '../capture/snapshot_bundle.dart';
import '../capture/snapshot_service.dart';
import '../connection/connection_state_notifier.dart';

/// The two snapshots chosen for a diff, ordered oldest → newest.
typedef DiffPair = ({SnapshotBundle baseline, SnapshotBundle comparison});

/// Owns the list of captured heap snapshots and the diff selection.
///
/// Replaces the old A/B-only `DiffController`: any number of snapshots can be
/// captured and kept, each can be exported, and the user picks *any two* to
/// diff. Held on `RadarSession` so its state survives DevTools tab switches.
class MemoryController extends ChangeNotifier {
  MemoryController({
    required SnapshotService service,
    required ConnectionStateNotifier connection,
  }) : _service = service,
       _connection = connection;

  final SnapshotService _service;
  final ConnectionStateNotifier _connection;
  static const _log = 'leakRadarDevTools.memory';

  final List<SnapshotBundle> _snapshots = [];
  final List<int> _selected = []; // ids chosen for diff, max 2
  int _nextId = 1;
  bool _capturing = false;
  String? _error;

  /// All captures, oldest first.
  List<SnapshotBundle> get snapshots => List.unmodifiable(_snapshots);

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
  SnapshotBundle? get focused => pair?.comparison ?? latest;

  /// Ranked class-growth diff for the selected pair; null unless two snapshots
  /// are selected. Computed on demand from the two histograms.
  List<ClassCountDiff>? get diff {
    final p = pair;
    if (p == null) return null;
    return computeDiff(p.baseline.histogram, p.comparison.histogram);
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
      final bundle = await _service.capture(
        vmService: _connection.vmService!,
        isolateRef: _connection.isolateRef!,
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
}
