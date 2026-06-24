import 'package:vm_service/vm_service.dart';

import 'heap_graph_view.dart';

/// Wraps a [HeapSnapshotGraph] as a [HeapGraphView] with contiguous 0-based
/// node ids mapping 1:1 to [HeapSnapshotGraph.objects] indices.
///
/// [rootId] is always 0 (the sentinel object at `objects[0]`). The analyzer
/// iterates `0..nodeCount-1` and calls [node(i)] for each, so ids must never
/// be remapped.
final class VmSnapshotGraphView implements HeapGraphView {
  final HeapSnapshotGraph _graph;

  VmSnapshotGraphView(this._graph);

  @override
  int get rootId => 0;

  @override
  int get nodeCount => _graph.objects.length;

  @override
  HeapNode node(int id) {
    if (id < 0 || id >= _graph.objects.length) {
      throw StateError('Node id $id out of range [0, ${_graph.objects.length})');
    }
    final obj = _graph.objects[id];
    final klass = obj.klass;
    return HeapNode(
      id: id,
      className: klass.name.isEmpty ? '<unknown>' : klass.name,
      libraryUri: klass.libraryUri,
      shallowSize: obj.shallowSize < 0 ? 0 : obj.shallowSize,
      edges: _buildEdges(obj, klass),
    );
  }

  List<HeapEdge> _buildEdges(
    HeapSnapshotObject obj,
    HeapSnapshotClass klass,
  ) {
    final refs = obj.references;
    if (refs.isEmpty) return const [];

    final isArray = obj.data is HeapSnapshotObjectLengthData;

    if (isArray) {
      return List<HeapEdge>.generate(
        refs.length,
        (i) => HeapEdge(targetId: refs[i], index: i),
        growable: false,
      );
    }

    // Build a lookup from reference-slot index → field name for instance objects.
    final fieldByIndex = <int, String>{};
    for (final f in klass.fields) {
      fieldByIndex[f.index] = f.name;
    }

    return List<HeapEdge>.generate(
      refs.length,
      (i) => HeapEdge(targetId: refs[i], field: fieldByIndex[i]),
      growable: false,
    );
  }
}
