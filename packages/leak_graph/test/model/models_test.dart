import 'package:leak_graph/leak_graph.dart';
import 'package:test/test.dart';

void main() {
  test('RootKind.isLeakProne marks holders, not liveTree/other', () {
    expect(RootKind.timer.isLeakProne, isTrue);
    expect(RootKind.stream.isLeakProne, isTrue);
    expect(RootKind.closure.isLeakProne, isTrue);
    expect(RootKind.finalizer.isLeakProne, isTrue);
    expect(RootKind.staticOrGlobal.isLeakProne, isTrue);
    expect(RootKind.liveTree.isLeakProne, isFalse);
    expect(RootKind.other.isLeakProne, isFalse);
  });

  test('GraphHop equality and toJson omit null fields', () {
    const a = GraphHop(className: 'A', field: 'f');
    const b = GraphHop(className: 'A', field: 'f');
    expect(a, equals(b));
    expect(a.hashCode, equals(b.hashCode));
    expect(a.toJson(), {'className': 'A', 'field': 'f'});
    expect(const GraphHop(className: 'A').toJson(), {'className': 'A'});
  });

  test('GraphLeakCluster carries count, bytes, confidence, signature', () {
    const path = GraphRetainingPath(
        hops: [GraphHop(className: '_Timer'), GraphHop(className: 'HomeState')],
        rootKind: RootKind.timer);
    const c = GraphLeakCluster(
        className: 'HomeState', libraryUri: null, instanceCount: 3,
        retainedShallowBytes: 480, representativePath: path,
        rootKind: RootKind.timer, confidence: LeakConfidence.heuristic,
        signature: '_Timer>HomeState');
    expect(c.instanceCount, 3);
    expect(c.confidence, LeakConfidence.heuristic);
    expect(c.toJson()['signature'], '_Timer>HomeState');
  });
}
