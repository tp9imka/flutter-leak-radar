import 'package:leak_graph/leak_graph.dart';
import 'package:test/test.dart';

import '../support/in_memory_heap_graph.dart';

final _appUri = Uri.parse('package:my_app/src/home.dart');
final _dartCore = Uri.parse('dart:core');

/// Root -> ProviderA -> [Listener, Listener]   (two list elements: one shape,
///                                               array indices collapse to `[]`)
/// Root -> ProviderB -> Listener                (a distinct path shape)
InMemoryHeapGraph _twoPathGraph() => InMemoryHeapGraph.of({
  0: HeapNode(
    id: 0,
    className: 'Root',
    libraryUri: _dartCore,
    shallowSize: 0,
    edges: const [HeapEdge(targetId: 1), HeapEdge(targetId: 4)],
  ),
  1: HeapNode(
    id: 1,
    className: 'ProviderA',
    libraryUri: _appUri,
    shallowSize: 16,
    edges: const [
      HeapEdge(targetId: 2, index: 0),
      HeapEdge(targetId: 3, index: 1),
    ],
  ),
  2: HeapNode(
    id: 2,
    className: 'Listener',
    libraryUri: _appUri,
    shallowSize: 10,
    edges: const [],
  ),
  3: HeapNode(
    id: 3,
    className: 'Listener',
    libraryUri: _appUri,
    shallowSize: 10,
    edges: const [],
  ),
  4: HeapNode(
    id: 4,
    className: 'ProviderB',
    libraryUri: _appUri,
    shallowSize: 16,
    edges: const [HeapEdge(targetId: 5, field: '_c')],
  ),
  5: HeapNode(
    id: 5,
    className: 'Listener',
    libraryUri: _appUri,
    shallowSize: 10,
    edges: const [],
  ),
});

void main() {
  const analyzer = GraphLeakAnalyzer();

  group('GraphLeakAnalyzer.analyze classPathDistributions', () {
    test('groups a class\'s instances by their distinct shortest paths', () {
      final result = analyzer.analyze(
        _twoPathGraph(),
        const GraphAnalysisOptions(appPackages: ['my_app']),
      );

      final dist = result.classPathDistributions.singleWhere(
        (d) => d.className == 'Listener',
      );
      expect(dist.totalInstances, 3);
      expect(dist.sampledInstances, 3);
      expect(dist.isSampled, isFalse);
      expect(dist.otherPathCount, 0);
      expect(dist.paths, hasLength(2));

      // Buckets sorted most-shared first.
      final viaA = dist.paths.first;
      expect(viaA.instanceCount, 2);
      expect(viaA.shallowBytes, 20);
      expect(viaA.path.hops.last.className, 'Listener');
      expect(viaA.path.hops.any((h) => h.className == 'ProviderA'), isTrue);

      final viaB = dist.paths[1];
      expect(viaB.instanceCount, 1);
      expect(viaB.path.hops.any((h) => h.className == 'ProviderB'), isTrue);
    });

    test('classPathDistributions survive a JSON round-trip', () {
      final result = analyzer.analyze(
        _twoPathGraph(),
        const GraphAnalysisOptions(appPackages: ['my_app']),
      );
      final restored = GraphAnalysisResult.fromJson(result.toJson());
      expect(
        restored.classPathDistributions,
        result.classPathDistributions,
      );
    });
  });

  group('buildClassPathDistributions bounds', () {
    test('caps instances sampled per class and flags the partial result', () {
      // Root -> Holder -> Item x5, all via list indices (one path shape).
      final graph = InMemoryHeapGraph.of({
        0: HeapNode(
          id: 0,
          className: 'Root',
          libraryUri: _dartCore,
          shallowSize: 0,
          edges: const [HeapEdge(targetId: 1)],
        ),
        1: HeapNode(
          id: 1,
          className: 'Holder',
          libraryUri: _appUri,
          shallowSize: 16,
          edges: const [
            HeapEdge(targetId: 2, index: 0),
            HeapEdge(targetId: 3, index: 1),
            HeapEdge(targetId: 4, index: 2),
            HeapEdge(targetId: 5, index: 3),
            HeapEdge(targetId: 6, index: 4),
          ],
        ),
        for (var id = 2; id <= 6; id++)
          id: HeapNode(
            id: id,
            className: 'Item',
            libraryUri: _appUri,
            shallowSize: 8,
            edges: const [],
          ),
      });
      final paths = ShortestRetainingPaths.compute(graph);
      final dists = buildClassPathDistributions(
        graph,
        paths,
        perClassInstanceCap: 3,
      );

      final item = dists.singleWhere((d) => d.className == 'Item');
      expect(item.totalInstances, 5);
      expect(item.sampledInstances, 3); // cap hit
      expect(item.isSampled, isTrue);
      // Array indices collapse to one signature -> a single bucket.
      expect(item.paths, hasLength(1));
      expect(item.paths.single.instanceCount, 3);
    });

    test('rolls path buckets beyond the cap into otherPathCount', () {
      // Four distinct container classes, each holding one Leaf -> four buckets.
      final nodes = <int, HeapNode>{};
      final rootEdges = <HeapEdge>[];
      var nextId = 1;
      for (var c = 0; c < 4; c++) {
        final containerId = nextId++;
        final leafId = nextId++;
        nodes[containerId] = HeapNode(
          id: containerId,
          className: 'Container$c',
          libraryUri: _appUri,
          shallowSize: 16,
          edges: [HeapEdge(targetId: leafId, field: '_leaf')],
        );
        nodes[leafId] = HeapNode(
          id: leafId,
          className: 'Leaf',
          libraryUri: _appUri,
          shallowSize: 8,
          edges: const [],
        );
        rootEdges.add(HeapEdge(targetId: containerId));
      }
      nodes[0] = HeapNode(
        id: 0,
        className: 'Root',
        libraryUri: _dartCore,
        shallowSize: 0,
        edges: rootEdges,
      );
      final graph = InMemoryHeapGraph.of(nodes, rootId: 0);
      final paths = ShortestRetainingPaths.compute(graph);
      final dists = buildClassPathDistributions(
        graph,
        paths,
        maxBucketsPerClass: 2,
      );

      final leaf = dists.singleWhere((d) => d.className == 'Leaf');
      expect(leaf.totalInstances, 4);
      expect(leaf.sampledInstances, 4);
      expect(leaf.paths, hasLength(2));
      expect(leaf.otherPathCount, 2); // 4 buckets - 2 kept
    });
  });
}
