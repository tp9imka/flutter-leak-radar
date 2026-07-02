import 'package:flutter/foundation.dart';
import 'package:radar_workbench/radar_workbench.dart';
import 'package:vm_service/vm_service.dart';

/// The offline desktop connection: permanently disconnected. Phase 3 replaces
/// this with a live `VmServiceUriConnection`. Never notifies (its state is
/// constant), but implements [Listenable] via [ChangeNotifier] so consumers
/// (e.g. [MemoryController], `ConnectionBar`) can subscribe uniformly.
class DisconnectedRadarConnection extends ChangeNotifier
    implements RadarConnection {
  @override
  RadarConnectionState get state =>
      const RadarConnectionState(phase: RadarConnectionPhase.disconnected);

  @override
  VmService? get vmService => null;

  @override
  IsolateRef? get isolateRef => null;
}
