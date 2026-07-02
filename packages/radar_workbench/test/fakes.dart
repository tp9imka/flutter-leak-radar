import 'package:flutter/foundation.dart';
import 'package:radar_workbench/radar_workbench.dart';
import 'package:vm_service/vm_service.dart';

/// A [RadarConnection] whose state is driven directly by the test.
class FakeRadarConnection extends ChangeNotifier implements RadarConnection {
  FakeRadarConnection({
    ConnectionState state = const ConnectionState(
      phase: ConnectionPhase.disconnected,
    ),
    VmService? vmService,
    IsolateRef? isolateRef,
  }) : _state = state,
       _vmService = vmService,
       _isolateRef = isolateRef;

  ConnectionState _state;
  VmService? _vmService;
  IsolateRef? _isolateRef;

  @override
  ConnectionState get state => _state;
  @override
  VmService? get vmService => _vmService;
  @override
  IsolateRef? get isolateRef => _isolateRef;

  /// Test hook: mutate the connection and notify listeners.
  void set({
    ConnectionState? state,
    VmService? vmService,
    IsolateRef? isolateRef,
  }) {
    if (state != null) _state = state;
    _vmService = vmService;
    _isolateRef = isolateRef;
    notifyListeners();
  }
}

/// A [SnapshotSource] that returns queued bundles (or a failure).
class FakeSnapshotSource implements SnapshotSource {
  FakeSnapshotSource([this._next]);
  SnapshotBundle? _next;
  int captureCount = 0;

  void queue(SnapshotBundle bundle) => _next = bundle;

  @override
  Future<SnapshotBundle> capture({String label = ''}) async {
    captureCount++;
    return _next ??
        SnapshotBundle.failed(label: label, message: 'no bundle queued');
  }
}

/// A [SnapshotExporter] that records what it was asked to export.
class RecordingExporter implements SnapshotExporter {
  final List<SnapshotBundle> exported = [];
  @override
  Future<void> export(SnapshotBundle bundle, {String? suggestedName}) async {
    exported.add(bundle);
  }
}
