import 'package:leak_graph/leak_graph.dart';
import 'package:test/test.dart';

import '../support/in_memory_heap_graph.dart';

void main() {
  HeapNode n(int id, String cls, List<HeapEdge> edges) => HeapNode(
    id: id,
    className: cls,
    libraryUri: Uri.parse('package:app/a.dart'),
    shallowSize: 0,
    edges: edges,
  );

  test('retainingPathForClass returns the path to a reachable instance', () {
    // 0(Root) -> 1(Holder) -> 2(Target)
    final graph = InMemoryHeapGraph.of({
      0: n(0, 'Root', const [HeapEdge(targetId: 1, field: 'holder')]),
      1: n(1, 'Holder', const [HeapEdge(targetId: 2, field: 'target')]),
      2: n(2, 'Target', const []),
    });

    final path = retainingPathForClass(graph, 'Target');
    expect(path, isNotNull);
    expect(
      path!.hops.map((h) => h.className),
      containsAllInOrder(['Holder', 'Target']),
    );
  });

  test('retainingPathForClass returns null for an absent class', () {
    final graph = InMemoryHeapGraph.of({
      0: n(0, 'Root', const [HeapEdge(targetId: 1)]),
      1: n(1, 'Holder', const []),
    });
    expect(retainingPathForClass(graph, 'Missing'), isNull);
  });
}
