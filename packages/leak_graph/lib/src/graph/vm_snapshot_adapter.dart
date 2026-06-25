import 'package:vm_service/vm_service.dart';

import 'heap_graph_view.dart';

/// Wraps a [HeapSnapshotGraph] as a [HeapGraphView] with contiguous 0-based
/// node ids mapping 1:1 to [HeapSnapshotGraph.objects] indices.
///
/// Node ids map 1:1 to `objects` indices (the analyzer iterates
/// `0..nodeCount-1`), so ids are never remapped. But [rootId] is NOT 0:
/// in a parsed snapshot `objects[0]` is a synthetic sentinel with no
/// successors — the real GC root is `objects[1]` (the `Root` pseudo-class).
/// Seeding the BFS from the sentinel reaches nothing (`reachable=0`), so
/// [rootId] resolves to the GC root instead.
final class VmSnapshotGraphView implements HeapGraphView {
  final HeapSnapshotGraph _graph;
  final int _rootId;

  /// Memoised [node] results — node metadata is materialised at most once per
  /// id, so the many re-fetches per node across the analysis pipeline become
  /// O(1) lookups instead of full rebuilds (the cause of the O(n·depth) cost).
  final List<HeapNode?> _nodeCache;

  /// Field-index → field-name map cached PER CLASS (keyed by class id), not per
  /// object: a few thousand classes vs hundreds of thousands of instances, so
  /// edge labelling stops re-scanning `klass.fields` per object.
  final Map<int, Map<int, String>> _fieldsByClass = <int, Map<int, String>>{};

  VmSnapshotGraphView(this._graph)
    : _rootId = _resolveRootId(_graph),
      _nodeCache = List<HeapNode?>.filled(_graph.objects.length, null);

  /// Resolves the GC-root node. `objects[0]` is the parser's empty sentinel, so
  /// the root is the `Root` pseudo-class object that follows it (conventionally
  /// `objects[1]`). Scans the first few objects for the `Root` class, falls
  /// back to index 1, and never returns the sentinel for a non-trivial graph.
  static int _resolveRootId(HeapSnapshotGraph graph) {
    final objects = graph.objects;
    if (objects.length <= 1) return 0;
    for (var i = 1; i < objects.length && i < 8; i++) {
      if (objects[i].klass.name == 'Root') return i;
    }
    return 1;
  }

  @override
  int get rootId => _rootId;

  @override
  int get nodeCount => _graph.objects.length;

  @override
  List<ClassCount> classHistogram() {
    final counts = <String, int>{};
    final bytes = <String, int>{};
    final libs = <String, Uri>{};
    for (final obj in _graph.objects) {
      final klass = obj.klass;
      final name = klass.name.isEmpty ? '<unknown>' : klass.name;
      counts[name] = (counts[name] ?? 0) + 1;
      bytes[name] =
          (bytes[name] ?? 0) + (obj.shallowSize < 0 ? 0 : obj.shallowSize);
      libs.putIfAbsent(name, () => klass.libraryUri);
    }
    return [
      for (final e in counts.entries)
        ClassCount(
          className: e.key,
          libraryUri: libs[e.key]!,
          instanceCount: e.value,
          shallowBytes: bytes[e.key]!,
        ),
    ];
  }

  @override
  HeapNode node(int id) {
    if (id < 0 || id >= _nodeCache.length) {
      throw StateError('Node id $id out of range [0, ${_nodeCache.length})');
    }
    final cached = _nodeCache[id];
    if (cached != null) return cached;
    final obj = _graph.objects[id];
    final klass = obj.klass;
    final built = HeapNode(
      id: id,
      className: klass.name.isEmpty ? '<unknown>' : klass.name,
      libraryUri: klass.libraryUri,
      shallowSize: obj.shallowSize < 0 ? 0 : obj.shallowSize,
      edges: _buildEdges(obj, klass),
    );
    _nodeCache[id] = built;
    return built;
  }

  List<HeapEdge> _buildEdges(HeapSnapshotObject obj, HeapSnapshotClass klass) {
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

    // Lookup from reference-slot index → field name, cached per class.
    final fieldByIndex = _fieldsByClass.putIfAbsent(obj.classId, () {
      final m = <int, String>{};
      for (final f in klass.fields) {
        m[f.index] = f.name;
      }
      return m;
    });

    return List<HeapEdge>.generate(
      refs.length,
      (i) => HeapEdge(targetId: refs[i], field: fieldByIndex[i]),
      growable: false,
    );
  }
}
