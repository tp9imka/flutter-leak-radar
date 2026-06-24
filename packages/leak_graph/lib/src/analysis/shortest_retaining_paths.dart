import 'dart:collection';

import '../graph/heap_graph_view.dart';

/// One step in a retaining path from the GC root to a heap object.
///
/// [nodeId] is the object reached at this step. [field] and [index] are the
/// edge label on the reference that leads INTO [nodeId] from its parent.
final class PathLink {
  final int nodeId;
  final String? field;
  final int? index;

  const PathLink({required this.nodeId, this.field, this.index});
}

/// BFS-computed shortest retaining paths from the GC root to every reachable
/// node in a [HeapGraphView].
///
/// Paths are oriented root → object (sentinel excluded). Each [PathLink]
/// carries the edge label into that node from its parent. BFS guarantees the
/// shortest path is found first.
final class ShortestRetainingPaths {
  final Map<int, int> _parent;
  final Map<int, HeapEdge> _parentEdge;
  final int _rootId;

  ShortestRetainingPaths._(this._parent, this._parentEdge, this._rootId);

  /// Runs iterative BFS from [graph.rootId] and returns the computed paths.
  factory ShortestRetainingPaths.compute(HeapGraphView graph) {
    final parent = <int, int>{};
    final parentEdge = <int, HeapEdge>{};
    final visited = <int>{graph.rootId};
    final queue = Queue<int>()..add(graph.rootId);

    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      for (final edge in graph.node(current).edges) {
        final target = edge.targetId;
        if (visited.contains(target)) continue;
        visited.add(target);
        parent[target] = current;
        parentEdge[target] = edge;
        queue.add(target);
      }
    }

    return ShortestRetainingPaths._(parent, parentEdge, graph.rootId);
  }

  /// Whether [nodeId] is reachable from the GC root.
  bool isReachable(int nodeId) =>
      nodeId == _rootId || _parent.containsKey(nodeId);

  /// Returns the path from the first GC-root child to [nodeId], inclusive.
  ///
  /// Returns `null` if [nodeId] is not reachable. The sentinel root itself is
  /// excluded from the returned list.
  List<PathLink>? pathTo(int nodeId) {
    if (nodeId == _rootId) return [];
    if (!_parent.containsKey(nodeId)) return null;

    final links = <PathLink>[];
    var current = nodeId;
    while (_parent.containsKey(current)) {
      final edge = _parentEdge[current]!;
      links.add(
        PathLink(nodeId: current, field: edge.field, index: edge.index),
      );
      current = _parent[current]!;
    }
    return links.reversed.toList();
  }
}
