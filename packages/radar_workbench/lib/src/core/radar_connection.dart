import 'package:flutter/foundation.dart';
import 'package:vm_service/vm_service.dart';

/// Phase of a host's connection to a target app's VM service.
enum ConnectionPhase { connecting, connected, disconnected }

/// Immutable snapshot of a [RadarConnection]'s state.
@immutable
final class ConnectionState {
  const ConnectionState({required this.phase, this.vmName, this.isolateName});
  final ConnectionPhase phase;
  final String? vmName;
  final String? isolateName;
}

/// The single seam between a host (DevTools / desktop) and the workbench.
///
/// Exposes the live [vmService] + main [isolateRef] handles that capture and
/// service-extension calls need, and notifies listeners on connect/disconnect.
/// Implementations: `DevToolsRadarConnection` (over serviceManager) and the
/// desktop's `VmServiceUriConnection` (over a direct ws:// client).
abstract interface class RadarConnection implements Listenable {
  ConnectionState get state;
  VmService? get vmService;
  IsolateRef? get isolateRef;
}
