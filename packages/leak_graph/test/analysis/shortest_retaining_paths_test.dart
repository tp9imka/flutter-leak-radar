import 'package:leak_graph/leak_graph.dart';
import 'package:test/test.dart';

import '../support/in_memory_heap_graph.dart';

HeapNode _node(int id, List<HeapEdge> edges) => HeapNode(
  id: id,
  className: 'C$id',
  libraryUri: Uri.parse('package:test/test.dart'),
  shallowSize: 0,
  edges: edges,
);

void main() {
  group('ShortestRetainingPaths', () {
    test('picks the shortest root path when multiple exist', () {
      // Graph: 0(root) -> 1 -> 2 -> 3 ; and shortcut 0 -> 3 directly.
      final graph = InMemoryHeapGraph.of({
        0: _node(0, [
          const HeapEdge(targetId: 1, field: 'a'),
          const HeapEdge(targetId: 3, field: 'shortcut'),
        ]),
        1: _node(1, [const HeapEdge(targetId: 2, field: 'b')]),
        2: _node(2, [const HeapEdge(targetId: 3, field: 'c')]),
        3: _node(3, []),
      });

      final paths = ShortestRetainingPaths.compute(graph);

      final nodeIds = paths.pathTo(3)!.map((l) => l.nodeId).toList();
      expect(nodeIds, equals([3]));
    });

    test('unreachable node returns null and isReachable false', () {
      final graph = InMemoryHeapGraph.of({
        0: _node(0, [const HeapEdge(targetId: 1, field: 'x')]),
        1: _node(1, []),
        99: _node(99, []),
      });

      final paths = ShortestRetainingPaths.compute(graph);

      expect(paths.pathTo(99), isNull);
      expect(paths.isReachable(99), isFalse);
    });

    test('path links carry the edge label into each node', () {
      // Graph: 0 -> 1 (field:'alpha') -> 2 (index:7)
      final graph = InMemoryHeapGraph.of({
        0: _node(0, [const HeapEdge(targetId: 1, field: 'alpha')]),
        1: _node(1, [const HeapEdge(targetId: 2, index: 7)]),
        2: _node(2, []),
      });

      final paths = ShortestRetainingPaths.compute(graph);
      final path = paths.pathTo(2)!;

      expect(path.length, equals(2));
      expect(path[0].nodeId, equals(1));
      expect(path[0].field, equals('alpha'));
      expect(path[0].index, isNull);
      expect(path[1].nodeId, equals(2));
      expect(path[1].field, isNull);
      expect(path[1].index, equals(7));
    });

    test('direct child of root has a single-link path', () {
      final graph = InMemoryHeapGraph.of({
        0: _node(0, [const HeapEdge(targetId: 1, field: 'ref')]),
        1: _node(1, []),
      });

      final paths = ShortestRetainingPaths.compute(graph);
      final path = paths.pathTo(1)!;

      expect(path.length, equals(1));
      expect(path[0].nodeId, equals(1));
      expect(path[0].field, equals('ref'));
    });

    test('isReachable true for nodes on known path', () {
      final graph = InMemoryHeapGraph.of({
        0: _node(0, [const HeapEdge(targetId: 1)]),
        1: _node(1, [const HeapEdge(targetId: 2)]),
        2: _node(2, []),
      });

      final paths = ShortestRetainingPaths.compute(graph);

      expect(paths.isReachable(1), isTrue);
      expect(paths.isReachable(2), isTrue);
    });

    test('rootKindOf propagates the first leak-prone kind down the path', () {
      HeapNode n(int id, String cls, List<HeapEdge> edges) => HeapNode(
        id: id,
        className: cls,
        libraryUri: Uri.parse('package:test/test.dart'),
        shallowSize: 0,
        edges: edges,
      );
      // 0(Root) -> 1(Foo) -> 2(_Timer) -> 3(LeakyState)
      //         -> 4(Library) -> 5(Global)
      final graph = InMemoryHeapGraph.of({
        0: n(0, 'Root', const [HeapEdge(targetId: 1), HeapEdge(targetId: 4)]),
        1: n(1, 'Foo', const [HeapEdge(targetId: 2)]),
        2: n(2, '_Timer', const [HeapEdge(targetId: 3)]),
        3: n(3, 'LeakyState', const []),
        4: n(4, 'Library', const [HeapEdge(targetId: 5)]),
        5: n(5, 'Global', const []),
      });

      final paths = ShortestRetainingPaths.compute(graph);

      expect(paths.rootKindOf(1), RootKind.other); // Foo: not leak-prone
      expect(paths.rootKindOf(2), RootKind.timer); // _Timer
      expect(paths.rootKindOf(3), RootKind.timer); // inherits timer
      expect(paths.rootKindOf(4), RootKind.staticOrGlobal); // Library root
      expect(paths.rootKindOf(5), RootKind.staticOrGlobal); // inherits
    });
  });
}
