import 'package:leak_graph/leak_graph.dart';
import 'package:test/test.dart';

import '../support/in_memory_heap_graph.dart';

void main() {
  group('HeapGraphView', () {
    late InMemoryHeapGraph graph;

    setUp(() {
      // 3-node graph: root(0) → node(1) → node(2)
      graph = InMemoryHeapGraph.of({
        0: HeapNode(
          id: 0,
          className: 'Root',
          libraryUri: Uri.parse('dart:core'),
          shallowSize: 0,
          edges: [const HeapEdge(targetId: 1, field: 'child')],
        ),
        1: HeapNode(
          id: 1,
          className: 'Middle',
          libraryUri: Uri.parse('package:app/src/middle.dart'),
          shallowSize: 64,
          edges: [const HeapEdge(targetId: 2, field: 'leaf')],
        ),
        2: HeapNode(
          id: 2,
          className: 'Leaf',
          libraryUri: Uri.parse('package:app/src/leaf.dart'),
          shallowSize: 32,
          edges: [],
        ),
      }, rootId: 0);
    });

    test('nodeCount equals number of nodes', () {
      expect(graph.nodeCount, equals(3));
    });

    test('rootId is 0', () {
      expect(graph.rootId, equals(0));
    });

    test('node(1).edges.single.targetId equals 2', () {
      expect(graph.node(1).edges.single.targetId, equals(2));
    });

    test('node(2).className equals Leaf', () {
      expect(graph.node(2).className, equals('Leaf'));
    });

    test('HeapEdge field is preserved', () {
      expect(graph.node(0).edges.single.field, equals('child'));
    });

    test('HeapEdge index defaults to null', () {
      expect(graph.node(1).edges.single.index, isNull);
    });

    test('node lookup by unknown id throws StateError', () {
      expect(() => graph.node(99), throwsStateError);
    });
  });
}
