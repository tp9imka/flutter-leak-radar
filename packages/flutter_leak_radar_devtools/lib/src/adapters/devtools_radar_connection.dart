import 'package:flutter/foundation.dart';
import 'package:radar_workbench/radar_workbench.dart';
import 'package:vm_service/vm_service.dart';

import '../connection/connection_state_notifier.dart';

/// Adapts the DevTools [ConnectionStateNotifier] to the workbench's
/// [RadarConnection] interface, mapping the extension's phase enum + state.
class DevToolsRadarConnection extends ChangeNotifier
    implements RadarConnection {
  DevToolsRadarConnection(this._inner) {
    _inner.addListener(notifyListeners);
  }

  final ConnectionStateNotifier _inner;

  @override
  RadarConnectionState get state {
    final s = _inner.state;
    return RadarConnectionState(
      phase: switch (s.phase) {
        ExtensionConnectionPhase.connecting => RadarConnectionPhase.connecting,
        ExtensionConnectionPhase.connected => RadarConnectionPhase.connected,
        ExtensionConnectionPhase.disconnected =>
          RadarConnectionPhase.disconnected,
      },
      vmName: s.vmName,
      isolateName: s.isolateName,
    );
  }

  @override
  VmService? get vmService => _inner.vmService;

  @override
  IsolateRef? get isolateRef => _inner.isolateRef;

  @override
  void dispose() {
    _inner.removeListener(notifyListeners);
    super.dispose();
  }
}
