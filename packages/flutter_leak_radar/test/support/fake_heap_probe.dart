// test/support/fake_heap_probe.dart
import 'package:flutter_leak_radar/src/engine/class_sample.dart';
import 'package:flutter_leak_radar/src/engine/heap_probe.dart';
import 'package:flutter_leak_radar/src/model/retaining_path.dart';

/// Scriptable HeapProbe for engine/UI tests. Each [capture] returns the next
/// scripted snapshot (repeating the last one once exhausted).
class FakeHeapProbe implements HeapProbe {
  FakeHeapProbe(this._snapshots, {this.available = true, this.path});

  final List<HeapSnapshot> _snapshots;
  bool available;
  RetainingPathView? path;
  int captureCount = 0;
  int _index = 0;

  @override
  Future<bool> get isAvailable async => available;

  @override
  Future<HeapSnapshot> capture({required bool forceGc}) async {
    captureCount++;
    if (_snapshots.isEmpty) {
      return HeapSnapshot(samples: const [], capturedAt: DateTime.now());
    }
    final snap = _snapshots[_index];
    if (_index < _snapshots.length - 1) _index++;
    return snap;
  }

  @override
  Future<RetainingPathView?> retainingPath(
    String className, {
    int maxInstances = 10,
  }) async => path;

  @override
  Future<void> dispose() async {}
}
