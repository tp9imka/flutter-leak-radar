import 'package:leak_graph/leak_graph.dart';
import 'package:test/test.dart';

import '../support/in_memory_heap_graph.dart';

final _appUri = Uri.parse('package:my_app/src/home.dart');
final _dartAsync = Uri.parse('dart:async');
final _dartCore = Uri.parse('dart:core');
final _flutterUri = Uri.parse('package:flutter/src/binding.dart');

// Graph mixing all three interesting cases:
//   0(Root) -> 1(WidgetsFlutterBinding) -> 2(LiveState)   [promoted to liveTree]
//   0(Root) -> 3(_Timer) -> 4(LeakyState)                 [stays timer]
//   0(Root) -> 5(_Timer) -> 6(MixedState)
//   1(WidgetsFlutterBinding) -> 7(MixedState)             [2nd instance, live]
InMemoryHeapGraph _mixedRootKindGraph() => InMemoryHeapGraph.of({
  0: HeapNode(
    id: 0,
    className: 'Root',
    libraryUri: _dartCore,
    shallowSize: 0,
    edges: const [
      HeapEdge(targetId: 1),
      HeapEdge(targetId: 3),
      HeapEdge(targetId: 5),
    ],
  ),
  1: HeapNode(
    id: 1,
    className: 'WidgetsFlutterBinding',
    libraryUri: _flutterUri,
    shallowSize: 48,
    edges: const [
      HeapEdge(targetId: 2, field: '_live'),
      HeapEdge(targetId: 7),
    ],
  ),
  2: HeapNode(
    id: 2,
    className: 'LiveState',
    libraryUri: _appUri,
    shallowSize: 32,
    edges: const [],
  ),
  3: HeapNode(
    id: 3,
    className: '_Timer',
    libraryUri: _dartAsync,
    shallowSize: 64,
    edges: const [HeapEdge(targetId: 4, field: '_callback')],
  ),
  4: HeapNode(
    id: 4,
    className: 'LeakyState',
    libraryUri: _appUri,
    shallowSize: 128,
    edges: const [],
  ),
  5: HeapNode(
    id: 5,
    className: '_Timer',
    libraryUri: _dartAsync,
    shallowSize: 64,
    edges: const [HeapEdge(targetId: 6, field: '_callback')],
  ),
  6: HeapNode(
    id: 6,
    className: 'MixedState',
    libraryUri: _appUri,
    shallowSize: 40,
    edges: const [],
  ),
  7: HeapNode(
    id: 7,
    className: 'MixedState',
    libraryUri: _appUri,
    shallowSize: 40,
    edges: const [],
  ),
});

void main() {
  const analyzer = GraphLeakAnalyzer();

  group('GraphLeakAnalyzer.analyze classRootProfiles', () {
    test('includes a liveTree-rooted class that clusters would filter out', () {
      final graph = _mixedRootKindGraph();
      final result = analyzer.analyze(
        graph,
        const GraphAnalysisOptions(appPackages: ['my_app']),
      );

      // LiveState is not leak-prone, so it never appears in clusters...
      expect(result.clusters.any((c) => c.className == 'LiveState'), isFalse);

      // ...but classRootProfiles is ungated by isLeakProne, so it must
      // still show up there.
      final live = result.classRootProfiles.singleWhere(
        (p) => p.className == 'LiveState',
      );
      expect(live.totalInstances, 1);
      expect(live.byRoot, {RootKind.liveTree: 1});
      expect(live.looksLive, isTrue);
    });

    test('groups instances by the RootKind of their closest root', () {
      final graph = _mixedRootKindGraph();
      final result = analyzer.analyze(
        graph,
        const GraphAnalysisOptions(appPackages: ['my_app']),
      );

      final leaky = result.classRootProfiles.singleWhere(
        (p) => p.className == 'LeakyState',
      );
      expect(leaky.totalInstances, 1);
      expect(leaky.byRoot, {RootKind.timer: 1});
      expect(leaky.looksLive, isFalse);

      // MixedState straddles both: one instance timer-retained, one
      // reachable from the live UI tree.
      final mixed = result.classRootProfiles.singleWhere(
        (p) => p.className == 'MixedState',
      );
      expect(mixed.totalInstances, 2);
      expect(mixed.byRoot, {RootKind.timer: 1, RootKind.liveTree: 1});
    });

    test('retainedShallowBytes is the sum of shallow bytes, per class', () {
      final graph = _mixedRootKindGraph();
      final result = analyzer.analyze(
        graph,
        const GraphAnalysisOptions(appPackages: ['my_app']),
      );

      final mixed = result.classRootProfiles.singleWhere(
        (p) => p.className == 'MixedState',
      );
      expect(mixed.retainedShallowBytes, 80);
    });

    test(
      'materializes a representativePath for every class in this small graph',
      () {
        final graph = _mixedRootKindGraph();
        final result = analyzer.analyze(
          graph,
          const GraphAnalysisOptions(appPackages: ['my_app']),
        );

        for (final profile in result.classRootProfiles) {
          expect(
            profile.representativePath,
            isNotNull,
            reason:
                '${profile.className} should have a path '
                '(small graph, well under the bound)',
          );
          expect(
            profile.representativePath!.hops.last.className,
            profile.className,
          );
        }
      },
    );

    test('does not require a live-tree anchor to run', () {
      // No WidgetsFlutterBinding anywhere in this graph.
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
          className: 'OrphanState',
          libraryUri: _appUri,
          shallowSize: 16,
          edges: const [],
        ),
      });

      final result = analyzer.analyze(graph);

      final orphan = result.classRootProfiles.singleWhere(
        (p) => p.className == 'OrphanState',
      );
      // No anchor found, no leak-prone ancestor -> stays "other", never
      // promoted to liveTree.
      expect(orphan.byRoot, {RootKind.other: 1});
      expect(orphan.looksLive, isFalse);
    });
  });

  group('GraphLeakAnalyzer.analyze classRootProfiles bound', () {
    test('a class list larger than the cap still produces profiles for every '
        'class, but only materializes paths for the top-N by count plus any '
        'class with a leak-prone instance', () {
      const bulkClassCount = 260;
      final nodes = <int, HeapNode>{};
      var nextId = 0;
      final rootId = nextId++;
      final rootEdges = <HeapEdge>[];

      for (var c = 0; c < bulkClassCount; c++) {
        final className = 'Bulk$c';
        for (var inst = 0; inst < 2; inst++) {
          final id = nextId++;
          nodes[id] = HeapNode(
            id: id,
            className: className,
            libraryUri: _appUri,
            shallowSize: 8,
            edges: const [],
          );
          rootEdges.add(HeapEdge(targetId: id));
        }
      }

      // An outlier class with a single, timer-retained instance: fewer
      // instances than every Bulk class (2 each), so it can never win a
      // spot in the top-N by instance count.
      final timerId = nextId++;
      final leakyId = nextId++;
      nodes[leakyId] = HeapNode(
        id: leakyId,
        className: 'LeakyOutlier',
        libraryUri: _appUri,
        shallowSize: 8,
        edges: const [],
      );
      nodes[timerId] = HeapNode(
        id: timerId,
        className: '_Timer',
        libraryUri: _dartAsync,
        shallowSize: 64,
        edges: [HeapEdge(targetId: leakyId, field: '_callback')],
      );
      rootEdges.add(HeapEdge(targetId: timerId));

      nodes[rootId] = HeapNode(
        id: rootId,
        className: 'Root',
        libraryUri: _dartCore,
        shallowSize: 0,
        edges: rootEdges,
      );

      final graph = InMemoryHeapGraph.of(nodes, rootId: rootId);
      final result = analyzer.analyze(graph);

      // One profile per distinct class: 260 Bulk classes + the outlier + the
      // _Timer that retains it (_Timer is itself a class with a leak-prone
      // instance — a timer retained directly by the GC root is its own
      // root).
      expect(result.classRootProfiles, hasLength(bulkClassCount + 2));

      final withPath = result.classRootProfiles.where(
        (p) => p.representativePath != null,
      );
      final withoutPath = result.classRootProfiles.where(
        (p) => p.representativePath == null,
      );

      // kMaxClassRootProfilePaths (250) Bulk classes are materialized by
      // rank, plus both leak-prone classes (_Timer, LeakyOutlier) via the
      // union rule: 252 total.
      expect(withPath, hasLength(kMaxClassRootProfilePaths + 2));
      expect(
        withoutPath,
        hasLength(bulkClassCount - kMaxClassRootProfilePaths),
      );

      final outlier = result.classRootProfiles.singleWhere(
        (p) => p.className == 'LeakyOutlier',
      );
      expect(outlier.representativePath, isNotNull);
      expect(outlier.byRoot, {RootKind.timer: 1});
    });
  });
}
