import 'package:leak_graph/leak_graph.dart';
import 'package:test/test.dart';
import '../support/in_memory_heap_graph.dart';

HeapNode n(int id, String cls, List<int> targets) => HeapNode(
  id: id,
  className: cls,
  libraryUri: Uri.parse('package:app/a.dart'),
  shallowSize: 8,
  edges: [for (final t in targets) HeapEdge(targetId: t)],
);

void main() {
  test('no anchor -> hasAnchor false, nothing reachable', () {
    final g = InMemoryHeapGraph.of({
      0: n(0, 'Root', [1]),
      1: n(1, 'Foo', []),
    });
    final r = LiveTreeReachability.compute(g);
    expect(r.hasAnchor, isFalse);
    expect(r.isReachable(1), isFalse);
  });

  test('marks nodes reachable from a WidgetsBinding anchor', () {
    // 0(Root) -> 1(WidgetsFlutterBinding) -> 2(HomeState); and 0 -> 3(Leaked)
    final g = InMemoryHeapGraph.of({
      0: n(0, 'Root', [1, 3]),
      1: n(1, 'WidgetsFlutterBinding', [2]),
      2: n(2, 'HomeState', []),
      3: n(3, 'Leaked', []),
    });
    final r = LiveTreeReachability.compute(g);
    expect(r.hasAnchor, isTrue);
    expect(r.isReachable(2), isTrue); // under the live tree
    expect(r.isReachable(3), isFalse); // not under the live tree
  });

  test('does not traverse THROUGH leak-prone retainers (Timer boundary)', () {
    // 0(Root) -> 1(WidgetsFlutterBinding) -> 2(_Timer) -> 3(LeakedState)
    //                                     -> 4(ChildState)  [normal edge, live]
    final g = InMemoryHeapGraph.of({
      0: n(0, 'Root', [1]),
      1: n(1, 'WidgetsFlutterBinding', [2, 4]),
      2: n(2, '_Timer', [3]),
      3: n(3, 'LeakedState', []),
      4: n(4, 'ChildState', []),
    });
    final r = LiveTreeReachability.compute(g);
    expect(r.hasAnchor, isTrue);
    expect(r.isReachable(4), isTrue); // owned directly by the binding → live
    expect(r.isReachable(2), isTrue); // the _Timer node itself is reached…
    expect(
      r.isReachable(3),
      isFalse,
      reason: 'BFS must not pass through a _Timer to reach what it retains',
    );
  });
}
