// test/engine/vm_connection_test.dart
import 'package:flutter_leak_radar/src/analysis/leak_analyzer.dart';
import 'package:flutter_leak_radar/src/config/suspect_set.dart';
import 'package:flutter_leak_radar/src/engine/class_sample.dart';
import 'package:flutter_leak_radar/src/engine/heap_probe.dart';
import 'package:flutter_leak_radar/src/engine/leak_engine.dart';
import 'package:flutter_leak_radar/src/engine/vm_service_status.dart';
import 'package:flutter_leak_radar/src/model/retaining_path.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_heap_probe.dart';

/// A VM-backed probe whose connection state is scripted, for the engine's
/// vmConnected / reconnectVm surface.
class _FakeVmProbe implements HeapProbe, VmConnectable {
  _FakeVmProbe({this.connected = false});

  bool connected;
  int reconnectCalls = 0;

  @override
  bool get isConnected => connected;

  @override
  VmServiceStatus get vmStatus =>
      connected ? const VmConnected() : const VmDisabled();

  @override
  Future<bool> reconnect() async {
    reconnectCalls++;
    connected = true;
    return true;
  }

  @override
  Future<bool> get isAvailable async => true;

  @override
  Future<HeapSnapshot> capture({required bool forceGc}) async =>
      HeapSnapshot(samples: const [], capturedAt: DateTime(2026));

  @override
  Future<RetainingPathView?> retainingPath(
    String className, {
    int maxInstances = 10,
  }) async => null;

  @override
  Future<void> dispose() async {}
}

void main() {
  test('vmConnected is null for a non-VM-backed probe', () async {
    final engine = LeakEngine(
      probe: FakeHeapProbe([]),
      analyzer: LeakAnalyzer(SuspectSet.empty()),
    );
    await engine.start();
    expect(engine.vmConnected, isNull);
    await engine.stop();
  });

  test(
    'vmConnected reflects the probe; reconnectVm connects and rescans',
    () async {
      final probe = _FakeVmProbe(connected: false);
      final engine = LeakEngine(
        probe: probe,
        analyzer: LeakAnalyzer(SuspectSet.empty()),
      );
      await engine.start();
      expect(engine.vmConnected, isFalse);

      final ok = await engine.reconnectVm();

      expect(ok, isTrue);
      expect(engine.vmConnected, isTrue);
      expect(probe.reconnectCalls, 1);
      expect(
        engine.latest?.trigger,
        'reconnect',
        reason: 'reconnectVm rescans so the latest report refreshes',
      );
      await engine.stop();
    },
  );
}
