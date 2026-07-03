import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:radar_workbench/radar_workbench.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

/// The desktop's live connection to a target app's VM service over a
/// `ws://` URI — the connected-mode counterpart to
/// `DisconnectedRadarConnection`. Desktop UI calls [connect] with a VM
/// service URI (as printed by `flutter run`) to attach, and [disconnect] to
/// tear it down; both are outside the [RadarConnection] interface since
/// only this seam's own owner drives them.
final class VmServiceUriConnection extends ChangeNotifier
    implements RadarConnection {
  VmServiceUriConnection({Future<VmService> Function(String wsUri)? connect})
    : _connectFn = connect ?? vmServiceConnectUri;

  final Future<VmService> Function(String wsUri) _connectFn;

  RadarConnectionState _state = const RadarConnectionState(
    phase: RadarConnectionPhase.disconnected,
  );
  VmService? _vmService;
  IsolateRef? _isolateRef;
  String? _lastError;

  @override
  RadarConnectionState get state => _state;

  @override
  VmService? get vmService => _vmService;

  @override
  IsolateRef? get isolateRef => _isolateRef;

  /// The error from the most recent failed [connect], or null.
  String? get lastError => _lastError;

  /// Connects to [wsUri], fetches the VM, and picks the main isolate.
  ///
  /// Notifies listeners through `connecting` then `connected`. On failure —
  /// including a VM with no isolates — sets [lastError] and notifies
  /// `disconnected` instead. A no-op while already connecting or connected;
  /// call [disconnect] first to retry against a different URI.
  Future<void> connect(String wsUri) async {
    if (_state.phase != RadarConnectionPhase.disconnected) return;

    _lastError = null;
    _state = const RadarConnectionState(phase: RadarConnectionPhase.connecting);
    notifyListeners();

    try {
      final svc = await _connectFn(wsUri);
      final vm = await svc.getVM();
      final isolates = vm.isolates ?? const <IsolateRef>[];
      final isolate = isolates.firstWhere(
        (ref) => ref.name == 'main',
        orElse: () => isolates.isNotEmpty
            ? isolates.first
            : throw StateError('VM at $wsUri has no isolates'),
      );

      _vmService = svc;
      _isolateRef = isolate;
      _state = RadarConnectionState(
        phase: RadarConnectionPhase.connected,
        vmName: vm.name,
        isolateName: isolate.name,
      );
      notifyListeners();

      unawaited(svc.onDone.then((_) => _applyDisconnected()));
    } catch (e) {
      _lastError = e.toString();
      _applyDisconnected();
    }
  }

  /// Tears down a live connection: disposes the VM service, clears the
  /// handles, and notifies `disconnected`. Safe to call when already
  /// disconnected.
  Future<void> disconnect() async {
    await _vmService?.dispose();
    _applyDisconnected();
  }

  void _applyDisconnected() {
    _vmService = null;
    _isolateRef = null;
    _state = const RadarConnectionState(
      phase: RadarConnectionPhase.disconnected,
    );
    notifyListeners();
  }
}
