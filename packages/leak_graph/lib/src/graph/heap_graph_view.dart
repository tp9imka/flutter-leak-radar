/// Core graph-view abstraction for heap snapshot analysis.
///
/// [HeapGraphView] is the seam between heap-loading adapters (e.g. a VM
/// service adapter) and the analysis algorithms (BFS, path extraction). Code
/// that only needs to traverse a graph depends on this interface; code that
/// builds one depends on a concrete implementation.
library;

/// Read-only view over a heap object graph.
abstract interface class HeapGraphView {
  /// Object id of the GC root that all paths originate from.
  int get rootId;

  /// Total number of nodes in the graph.
  int get nodeCount;

  /// Returns the node with the given [id].
  ///
  /// Throws [StateError] if [id] is not present in the graph.
  HeapNode node(int id);
}

/// A single object in the heap graph.
final class HeapNode {
  final int id;
  final String className;

  /// Library that declared this object's class, e.g. `package:app/src/foo.dart`.
  final Uri libraryUri;

  /// Shallow (own) byte size reported by the VM.
  final int shallowSize;

  /// Outgoing reference edges from this node.
  final List<HeapEdge> edges;

  const HeapNode({
    required this.id,
    required this.className,
    required this.libraryUri,
    required this.shallowSize,
    required this.edges,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is HeapNode && other.id == id);

  @override
  int get hashCode => id.hashCode;
}

/// A directed reference from one heap object to another.
final class HeapEdge {
  final int targetId;

  /// Named field on the referencing object, if known.
  final String? field;

  /// List or array index, if this edge comes from a positional slot.
  final int? index;

  const HeapEdge({required this.targetId, this.field, this.index});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HeapEdge &&
          other.targetId == targetId &&
          other.field == field &&
          other.index == index);

  @override
  int get hashCode => Object.hash(targetId, field, index);
}
