import 'dart:async';
import 'dart:developer' as developer;

import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/foundation.dart';
import 'package:vm_service/vm_service.dart';

/// Phase of the extension's connection to the target app's VM service.
enum ExtensionConnectionPhase { connecting, connected, disconnected }

/// Snapshot of the extension's VM service connection state.
final class ExtensionConnectionState {
  final ExtensionConnectionPhase phase;

  /// Human-readable VM name from [VM.name], null when not yet connected.
  final String? vmName;

  /// Human-readable isolate name, null when not yet connected.
  final String? isolateName;

  const ExtensionConnectionState({
    required this.phase,
    this.vmName,
    this.isolateName,
  });
}

/// Watches [serviceManager] for a live [VmService] connection and the main
/// isolate, surfacing connection state for the UI and providing the
/// [vmService] + [isolateRef] handles that capture operations need.
///
/// Call [init] once after construction (typically in [State.initState]).
class ConnectionStateNotifier extends ChangeNotifier {
  static const _log = 'leakRadarDevTools.connection';

  ExtensionConnectionState _state = const ExtensionConnectionState(
    phase: ExtensionConnectionPhase.connecting,
  );

  VmService? _vmService;
  IsolateRef? _isolateRef;

  ExtensionConnectionState get state => _state;

  /// The connected [VmService], or null before connection.
  VmService? get vmService => _vmService;

  /// The main isolate ref, or null before connection.
  IsolateRef? get isolateRef => _isolateRef;

  VoidCallback? _isolateListener;

  /// Starts watching [serviceManager] for connection events.
  ///
  /// Safe to call multiple times — subsequent calls are no-ops.
  Future<void> init() async {
    if (_isolateListener != null) return;

    final initial = serviceManager.service;
    if (initial != null) {
      await _onServiceConnected(initial);
    }

    // Watch for future isolate connect/disconnect events.
    final isolateManager = serviceManager.isolateManager;
    _isolateListener = () {
      final ref = isolateManager.mainIsolate.value;
      final svc = serviceManager.service;
      if (ref != null && svc != null) {
        _applyConnected(svc, ref);
      } else {
        _applyDisconnected();
      }
    };
    isolateManager.mainIsolate.addListener(_isolateListener!);
  }

  Future<void> _onServiceConnected(VmService service) async {
    try {
      final vm = await service.getVM();
      final ref = serviceManager.isolateManager.mainIsolate.value;
      if (ref != null) {
        _applyConnected(service, ref, vmName: vm.name);
      } else {
        developer.log(
          'VM connected but main isolate not yet available',
          name: _log,
        );
      }
    } catch (e, s) {
      developer.log('getVM failed', name: _log, error: e, stackTrace: s);
      _applyDisconnected();
    }
  }

  void _applyConnected(VmService service, IsolateRef ref, {String? vmName}) {
    _vmService = service;
    _isolateRef = ref;
    _state = ExtensionConnectionState(
      phase: ExtensionConnectionPhase.connected,
      vmName: vmName,
      isolateName: ref.name,
    );
    notifyListeners();
  }

  void _applyDisconnected() {
    _vmService = null;
    _isolateRef = null;
    _state = const ExtensionConnectionState(
      phase: ExtensionConnectionPhase.disconnected,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    final isolateManager = serviceManager.isolateManager;
    if (_isolateListener != null) {
      isolateManager.mainIsolate.removeListener(_isolateListener!);
    }
    super.dispose();
  }
}
