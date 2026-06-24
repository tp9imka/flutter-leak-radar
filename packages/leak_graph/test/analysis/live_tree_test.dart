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
}
