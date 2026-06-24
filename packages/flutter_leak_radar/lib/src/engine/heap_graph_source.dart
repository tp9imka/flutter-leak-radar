// lib/src/engine/heap_graph_source.dart
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:leak_graph/leak_graph.dart';
import 'package:vm_service/vm_service.dart';

import 'heap_snapshot_file.dart';
import 'vm_heap_probe.dart';

/// Acquires a live [HeapGraphView] for analysis.
///
/// Implementations must never throw. Return `null` when the graph is
/// unavailable or exceeds the caller-specified size limit.
abstract interface class HeapGraphSource {
  /// Returns a [HeapGraphView] with at most [maxObjects] nodes, or `null`.
  ///
  /// The [maxObjects] guard prevents OOM on large heaps; callers choose a
  /// budget appropriate for their analysis pass.
  Future<HeapGraphView?> acquire({required int maxObjects});
}

/// Acquires a heap graph via the live [VmHeapProbe] connection.
///
/// Primary path: [HeapSnapshotGraph.getSnapshot] over the active VM service.
/// Fallback path: [writeHeapSnapshotFile] → read bytes → [heapGraphFromBytes].
///
/// Returns `null` — never throws — when:
/// - the VM service / isolate id is not available;
/// - any error occurs during acquisition;
/// - `graph.nodeCount > maxObjects`.
final class VmHeapGraphSource implements HeapGraphSource {
  const VmHeapGraphSource(this._probe);

  final VmHeapProbe _probe;

  @override
  Future<HeapGraphView?> acquire({required int maxObjects}) async {
    try {
      final view = await _tryLive() ?? await _tryFileFallback();
      if (view == null) return null;
      if (view.nodeCount >= maxObjects) return null;
      return view;
    } catch (_) {
      return null;
    }
  }

  Future<HeapGraphView?> _tryLive() async {
    try {
      final (service, isolateId) = _probe.internalConnection;
      if (service == null || isolateId == null) return null;
      final isolateRef = IsolateRef(id: isolateId);
      final graph = await HeapSnapshotGraph.getSnapshot(
        service,
        isolateRef,
        calculateReferrers: false,
        decodeObjectData: true,
        decodeExternalProperties: false,
        decodeIdentityHashCodes: false,
      );
      return VmSnapshotGraphView(graph);
    } catch (_) {
      return null;
    }
  }

  Future<HeapGraphView?> _tryFileFallback() async {
    try {
      final path = await writeHeapSnapshotFile();
      if (path == null) return null;
      final bytes = await File(path).readAsBytes();
      return heapGraphFromBytes(Uint8List.fromList(bytes));
    } catch (e) {
      developer.log(
        'VmHeapGraphSource file fallback failed: $e',
        name: 'flutter_leak_radar.heap_graph_source',
      );
      return null;
    }
  }
}
