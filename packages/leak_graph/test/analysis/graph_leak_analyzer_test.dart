import 'package:leak_graph/leak_graph.dart';
import 'package:test/test.dart';

import '../support/in_memory_heap_graph.dart';

// Graph for reachability tests:
//   0(Root) -> 1(WidgetsFlutterBinding) -> 2(_Timer) -> 3(_LeakyState)
//                                          [live-reachable AND timer-prone → suppressed]
//   0(Root) -> 4(_Timer) -> 5(_LeakyState)
//                           [NOT live-reachable, timer-prone → confirmed]
InMemoryHeapGraph _reachabilityGraph() => InMemoryHeapGraph.of({
  0: HeapNode(
    id: 0,
    className: 'Root',
    libraryUri: Uri.parse('dart:core'),
    shallowSize: 0,
    edges: const [HeapEdge(targetId: 1), HeapEdge(targetId: 4)],
  ),
  1: HeapNode(
    id: 1,
    className: 'WidgetsFlutterBinding',
    libraryUri: Uri.parse('package:flutter/src/binding.dart'),
    shallowSize: 48,
    edges: const [HeapEdge(targetId: 2, field: '_timer')],
  ),
  2: HeapNode(
    id: 2,
    className: '_Timer',
    libraryUri: Uri.parse('dart:async'),
    shallowSize: 64,
    edges: const [HeapEdge(targetId: 3, field: '_callback')],
  ),
  3: HeapNode(
    id: 3,
    className: '_LeakyState',
    libraryUri: Uri.parse('package:my_app/src/home.dart'),
    shallowSize: 128,
    edges: const [],
  ),
  4: HeapNode(
    id: 4,
    className: '_Timer',
    libraryUri: Uri.parse('dart:async'),
    shallowSize: 64,
    edges: const [HeapEdge(targetId: 5, field: '_callback')],
  ),
  5: HeapNode(
    id: 5,
    className: '_LeakyState',
    libraryUri: Uri.parse('package:my_app/src/home.dart'),
    shallowSize: 128,
    edges: const [],
  ),
});

// Graph without a live-tree anchor (no WidgetsFlutterBinding).
//   0(Root) -> 1(_Timer) -> 2(_LeakyState), 3(_LeakyState)
InMemoryHeapGraph _noAnchorGraph() => InMemoryHeapGraph.of({
  0: HeapNode(
    id: 0,
    className: 'Root',
    libraryUri: Uri.parse('dart:core'),
    shallowSize: 0,
    edges: const [HeapEdge(targetId: 1)],
  ),
  1: HeapNode(
    id: 1,
    className: '_Timer',
    libraryUri: Uri.parse('dart:async'),
    shallowSize: 64,
    edges: const [HeapEdge(targetId: 2), HeapEdge(targetId: 3)],
  ),
  2: HeapNode(
    id: 2,
    className: '_LeakyState',
    libraryUri: Uri.parse('package:my_app/src/home.dart'),
    shallowSize: 128,
    edges: const [],
  ),
  3: HeapNode(
    id: 3,
    className: '_LeakyState',
    libraryUri: Uri.parse('package:my_app/src/home.dart'),
    shallowSize: 128,
    edges: const [],
  ),
});

// root(0) -> _Timer(1) -> List(2) -> HomeState(3), HomeState(4)
InMemoryHeapGraph _timerGraph() => InMemoryHeapGraph.of({
  0: HeapNode(
    id: 0,
    className: 'Root',
    libraryUri: Uri.parse('dart:core'),
    shallowSize: 0,
    edges: const [HeapEdge(targetId: 1)],
  ),
  1: HeapNode(
    id: 1,
    className: '_Timer',
    libraryUri: Uri.parse('dart:async'),
    shallowSize: 64,
    edges: const [HeapEdge(targetId: 2, field: '_list')],
  ),
  2: HeapNode(
    id: 2,
    className: 'List',
    libraryUri: Uri.parse('dart:core'),
    shallowSize: 32,
    edges: const [
      HeapEdge(targetId: 3, index: 0),
      HeapEdge(targetId: 4, index: 1),
    ],
  ),
  3: HeapNode(
    id: 3,
    className: 'HomeState',
    libraryUri: Uri.parse('package:my_app/src/home.dart'),
    shallowSize: 128,
    edges: const [],
  ),
  4: HeapNode(
    id: 4,
    className: 'HomeState',
    libraryUri: Uri.parse('package:my_app/src/home.dart'),
    shallowSize: 128,
    edges: const [],
  ),
});

// root(0) -> SomeWidget(1) -> SomeState(2): RootKind.other
InMemoryHeapGraph _nonLeakProneGraph() => InMemoryHeapGraph.of({
  0: HeapNode(
    id: 0,
    className: 'Root',
    libraryUri: Uri.parse('dart:core'),
    shallowSize: 0,
    edges: const [HeapEdge(targetId: 1)],
  ),
  1: HeapNode(
    id: 1,
    className: 'SomeWidget',
    libraryUri: Uri.parse('package:flutter/src/widgets.dart'),
    shallowSize: 48,
    edges: const [HeapEdge(targetId: 2, field: 'state')],
  ),
  2: HeapNode(
    id: 2,
    className: 'SomeState',
    libraryUri: Uri.parse('package:my_app/src/some.dart'),
    shallowSize: 96,
    edges: const [],
  ),
});

// _Timer -> FrameworkClass in package:flutter only (no app packages)
InMemoryHeapGraph _flutterOnlyLeakGraph() => InMemoryHeapGraph.of({
  0: HeapNode(
    id: 0,
    className: 'Root',
    libraryUri: Uri.parse('dart:core'),
    shallowSize: 0,
    edges: const [HeapEdge(targetId: 1)],
  ),
  1: HeapNode(
    id: 1,
    className: '_Timer',
    libraryUri: Uri.parse('dart:async'),
    shallowSize: 64,
    edges: const [HeapEdge(targetId: 2, field: '_callback')],
  ),
  2: HeapNode(
    id: 2,
    className: 'FrameworkClass',
    libraryUri: Uri.parse('package:flutter/src/widgets.dart'),
    shallowSize: 80,
    edges: const [],
  ),
});

void main() {
  const analyzer = GraphLeakAnalyzer();

  group('GraphLeakAnalyzer', () {
    test('flags an app class retained via a Timer, clustered by count', () {
      final graph = _timerGraph();
      final result = analyzer.analyze(
        graph,
        const GraphAnalysisOptions(appPackages: ['my_app']),
      );

      expect(result.clusters, hasLength(1));
      final cluster = result.clusters.first;
      expect(cluster.className, 'HomeState');
      expect(cluster.rootKind, RootKind.timer);
      expect(cluster.instanceCount, 2);
      // All 4 reachable non-root nodes are leak-prone (timer path);
      // _Timer and List are in dart: URIs, suppressed by app filter.
      expect(result.stats.leakCandidates, 4);
      expect(result.stats.suppressedByAppFilter, 2);
    });

    test('does not flag objects whose root is not leak-prone', () {
      final graph = _nonLeakProneGraph();
      final result = analyzer.analyze(
        graph,
        const GraphAnalysisOptions(appPackages: ['my_app']),
      );

      expect(result.clusters, isEmpty);
      expect(result.stats.leakCandidates, 0);
    });

    test('app filter suppresses flutter-only leaks by default', () {
      final graph = _flutterOnlyLeakGraph();
      // autoDetect will find only 'flutter' which is in sdkDenylist → no app
      // packages → everything suppressed.
      final result = analyzer.analyze(graph);

      expect(result.clusters, isEmpty);
      expect(result.stats.suppressedByAppFilter, greaterThan(0));
    });

    test('app filter disabled keeps flutter-only leaks', () {
      final graph = _flutterOnlyLeakGraph();
      final result = analyzer.analyze(
        graph,
        const GraphAnalysisOptions(disableAppFilter: true, minClusterSize: 1),
      );

      // Both _Timer (the retainer) and FrameworkClass (the retained) are
      // flagged when the app filter is off and minClusterSize=1.
      expect(result.clusters, hasLength(2));
      expect(
        result.clusters.any((c) => c.className == 'FrameworkClass'),
        isTrue,
      );
      expect(result.stats.suppressedByAppFilter, 0);
    });

    test('stats report totals and suppressed counts', () {
      final graph = _timerGraph();
      final result = analyzer.analyze(
        graph,
        const GraphAnalysisOptions(appPackages: ['my_app']),
      );

      expect(result.stats.totalObjects, graph.nodeCount);
      // nodes 1,2,3,4 reachable; root 0 excluded from non-root processing
      expect(result.stats.reachableObjects, 4);
      // All 4 non-root reachable nodes classify as timer (leak-prone).
      expect(result.stats.leakCandidates, 4);
      expect(result.stats.clusters, 1);
      // _Timer(dart:async) and List(dart:core) suppressed; HomeState×2 kept.
      expect(result.stats.suppressedByAppFilter, 2);
    });

    test(
      'leak-prone retainers are a boundary: a State retained only via a _Timer '
      'under the live tree is NOT suppressed',
      () {
        final graph = _reachabilityGraph();
        final result = analyzer.analyze(
          graph,
          const GraphAnalysisOptions(
            appPackages: ['my_app'],
            confirmWithReachability: true,
            minClusterSize: 1,
          ),
        );

        // The live-tree BFS stops at _Timer (node 2), so node 3 (_LeakyState
        // retained ONLY via that _Timer under the binding) is NOT live-reachable.
        // Both node 3 and node 5 are timer-rooted, app-relevant, and not
        // live-dominated → confirmed leaks; nothing is suppressed. Their
        // retaining paths differ (node 3 via the binding, node 5 standalone),
        // so they form two clusters. Previously the unbounded BFS flooded
        // through _Timer and wrongly suppressed node 3 — the false negative
        // this guards against.
        expect(result.clusters, hasLength(2));
        expect(
          result.clusters.every((c) => c.className == '_LeakyState'),
          isTrue,
        );
        expect(
          result.clusters.every(
            (c) => c.confidence == LeakConfidence.confirmed,
          ),
          isTrue,
        );
        expect(result.stats.suppressedByLiveTree, 0);
      },
    );

    test('no live anchor degrades to heuristic, no suppression', () {
      final graph = _noAnchorGraph();
      final result = analyzer.analyze(
        graph,
        const GraphAnalysisOptions(
          appPackages: ['my_app'],
          confirmWithReachability: true,
        ),
      );

      // hasAnchor is false → no suppression, heuristic confidence.
      expect(result.clusters, hasLength(1));
      expect(result.clusters.first.confidence, LeakConfidence.heuristic);
      expect(result.stats.suppressedByLiveTree, 0);
    });
  });
}
