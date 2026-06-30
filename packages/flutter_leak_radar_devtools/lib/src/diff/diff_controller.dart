import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:leak_graph/leak_graph.dart';

import '../capture/snapshot_bundle.dart';
import '../capture/snapshot_service.dart';
import '../connection/connection_state_notifier.dart';

/// Workflow phase for the capture→act→capture→diff loop.
enum CapturePhase {
  /// No snapshot captured yet.
  idle,

  /// Capturing the baseline (snapshot A).
  capturingA,

  /// Snapshot A captured; waiting for the user to act in the app.
  readyForB,

  /// Capturing the comparison (snapshot B).
  capturingB,

  /// Both snapshots captured; diff is available.
  done,
}

/// Manages the capture→act→capture→diff workflow.
///
/// Drives [SnapshotService.capture] for snapshot A and snapshot B, then
/// calls [computeDiff] to produce the ranked grew-class list.
class DiffController extends ChangeNotifier {
  final SnapshotService _snapshotService;
  final ConnectionStateNotifier _connection;

  static const _log = 'leakRadarDevTools.diff';

  DiffController({
    required SnapshotService snapshotService,
    required ConnectionStateNotifier connection,
  }) : _snapshotService = snapshotService,
       _connection = connection;

  SnapshotBundle? _snapshotA;
  SnapshotBundle? _snapshotB;
  List<ClassCountDiff>? _diff;
  CapturePhase _phase = CapturePhase.idle;
  String? _error;

  SnapshotBundle? get snapshotA => _snapshotA;
  SnapshotBundle? get snapshotB => _snapshotB;

  /// Ranked list of class growth deltas; null until both snapshots are done.
  List<ClassCountDiff>? get diff => _diff;

  CapturePhase get phase => _phase;

  /// Non-null when the last capture operation failed.
  String? get error => _error;

  /// True when a VM service connection and main isolate are both available.
  bool get canCapture =>
      _connection.vmService != null && _connection.isolateRef != null;

  /// Captures snapshot A (the baseline). Resets any existing diff state.
  Future<void> captureA() async {
    if (!canCapture) {
      _error = 'Not connected to a running app.';
      notifyListeners();
      return;
    }
    _snapshotA = null;
    _snapshotB = null;
    _diff = null;
    _error = null;
    _phase = CapturePhase.capturingA;
    notifyListeners();

    try {
      final bundle = await _snapshotService.capture(
        vmService: _connection.vmService!,
        isolateRef: _connection.isolateRef!,
        label: 'Baseline (A)',
      );
      _snapshotA = bundle;
      _phase = CapturePhase.readyForB;
      developer.log('Snapshot A captured', name: _log);
    } catch (e, s) {
      developer.log('captureA failed', name: _log, error: e, stackTrace: s);
      _error = 'Capture A failed: $e';
      _phase = CapturePhase.idle;
    }
    notifyListeners();
  }

  /// Captures snapshot B and computes the diff against A.
  Future<void> captureB() async {
    if (!canCapture || _snapshotA == null) {
      _error = 'Capture A first.';
      notifyListeners();
      return;
    }
    _snapshotB = null;
    _diff = null;
    _error = null;
    _phase = CapturePhase.capturingB;
    notifyListeners();

    try {
      final bundle = await _snapshotService.capture(
        vmService: _connection.vmService!,
        isolateRef: _connection.isolateRef!,
        label: 'Comparison (B)',
      );
      _snapshotB = bundle;
      _diff = computeDiff(_snapshotA!.histogram, bundle.histogram);
      _phase = CapturePhase.done;
      developer.log(
        'Snapshot B captured; diff has ${_diff!.length} entries',
        name: _log,
      );
    } catch (e, s) {
      developer.log('captureB failed', name: _log, error: e, stackTrace: s);
      _error = 'Capture B failed: $e';
      _phase = CapturePhase.readyForB;
    }
    notifyListeners();
  }

  /// Requests a GC cycle from the VM service.
  ///
  /// Uses [getAllocationProfile] with `reset: true` as a GC trigger since it
  /// is available without special VM flags. No-op when not connected.
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

  /// Resets to [CapturePhase.idle] so a new A→B cycle can begin.
  void reset() {
    _snapshotA = null;
    _snapshotB = null;
    _diff = null;
    _error = null;
    _phase = CapturePhase.idle;
    notifyListeners();
  }
}
