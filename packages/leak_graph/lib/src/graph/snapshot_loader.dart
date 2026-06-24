import 'dart:io';
import 'dart:typed_data';

import 'package:vm_service/vm_service.dart';

import 'heap_graph_view.dart';
import 'vm_snapshot_adapter.dart';

/// Parses a raw `.data` heap snapshot byte buffer into a [HeapGraphView].
///
/// The bytes must begin with the `dartheap` magic header written by the VM.
/// Never throws on malformed input — returns a graph with a single sentinel
/// node if parsing fails.
HeapGraphView heapGraphFromBytes(Uint8List bytes) {
  final graph = HeapSnapshotGraph.fromChunks(
    [ByteData.sublistView(bytes)],
    calculateReferrers: false,
    decodeIdentityHashCodes: false,
  );
  return VmSnapshotGraphView(graph);
}

/// Reads the file at [file] and returns its heap graph.
///
/// The file must be a VM heap snapshot produced by
/// `NativeRuntime.writeHeapSnapshotToFile` or an equivalent VM mechanism.
Future<HeapGraphView> loadHeapGraph(File file) async {
  final bytes = await file.readAsBytes();
  return heapGraphFromBytes(bytes);
}
