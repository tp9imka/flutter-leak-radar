import 'package:leak_graph/leak_graph.dart';

/// Synthetic heap graph for use in tests — build any topology by hand.
///
/// No device or VM connection is required. All analysis tests should build
/// their fixture graphs via [InMemoryHeapGraph.of] so they run entirely
/// in-process without I/O.
final class InMemoryHeapGraph implements HeapGraphView {
  final Map<int, HeapNode> _nodes;

  @override
  final int rootId;

  const InMemoryHeapGraph._(this._nodes, this.rootId);

  /// Constructs a graph from a map of [nodes] keyed by their [HeapNode.id].
  ///
  /// [rootId] defaults to 0, matching the most common synthetic fixture shape.
  factory InMemoryHeapGraph.of(Map<int, HeapNode> nodes, {int rootId = 0}) =>
      InMemoryHeapGraph._(Map.unmodifiable(nodes), rootId);

  @override
  int get nodeCount => _nodes.length;

  @override
  HeapNode node(int id) {
    final n = _nodes[id];
    if (n == null) throw StateError('No node with id $id in graph');
    return n;
  }
}
