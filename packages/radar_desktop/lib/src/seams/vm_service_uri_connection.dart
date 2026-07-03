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

  /// Bumped on every [connect], [disconnect], and [dispose] so an in-flight
  /// [connect] can tell whether it is still the current attempt once its
  /// awaits resolve — a disconnect or dispose that raced ahead of it wins.
  int _generation = 0;
  bool _disposed = false;

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
  ///
  /// If [disconnect] or [dispose] runs while this call is still awaiting the
  /// underlying connect, the newly-opened [VmService] is disposed instead of
  /// being adopted, so a stale socket can never resurrect a torn-down state.
  Future<void> connect(String wsUri) async {
    if (_state.phase != RadarConnectionPhase.disconnected) return;

    _lastError = null;
    _state = const RadarConnectionState(phase: RadarConnectionPhase.connecting);
    _notify();
    final gen = ++_generation;

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

      if (gen != _generation || _disposed) {
        await svc.dispose();
        return;
      }

      _vmService = svc;
      _isolateRef = isolate;
      _state = RadarConnectionState(
        phase: RadarConnectionPhase.connected,
        vmName: vm.name,
        isolateName: isolate.name,
      );
      _notify();

      unawaited(
        svc.onDone.then((_) {
          if (gen == _generation) _applyDisconnected();
        }),
      );
    } catch (e) {
      if (gen == _generation) {
        _lastError = e.toString();
        _applyDisconnected();
      }
    }
  }

  /// Tears down a live connection: disposes the VM service, clears the
  /// handles, and notifies `disconnected`. Safe to call when already
  /// disconnected.
  ///
  /// Bumps the generation first, so the outgoing [VmService]'s `onDone`
  /// continuation (registered under the old generation) becomes a no-op and
  /// this method's own [_applyDisconnected] call is the only notification.
  Future<void> disconnect() async {
    ++_generation;
    final svc = _vmService;
    _applyDisconnected();
    await svc?.dispose();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    unawaited(_vmService?.dispose());
    _vmService = null;
    _isolateRef = null;
    super.dispose();
  }

  void _applyDisconnected() {
    _vmService = null;
    _isolateRef = null;
    _state = const RadarConnectionState(
      phase: RadarConnectionPhase.disconnected,
    );
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
