import 'package:leak_graph/leak_graph.dart';
import 'package:test/test.dart';

void main() {
  final timerHop = const GraphHop(className: '_Timer');
  final listHop = const GraphHop(className: 'List', index: 4);
  final stateHop = const GraphHop(className: 'HomeState', field: 'state');

  group('pathSignature', () {
    test('normalizes fields and array indices', () {
      expect(
        pathSignature([timerHop, listHop, stateHop]),
        '_Timer>List[]>HomeState.state',
      );
    });

    test('collapses array index to []', () {
      final hops = [
        const GraphHop(className: 'List', index: 0),
        const GraphHop(className: 'Obj'),
      ];
      expect(pathSignature(hops), 'List[]>Obj');
    });

    test('omits field when null and index when null', () {
      final hops = [
        const GraphHop(className: 'A'),
        const GraphHop(className: 'B', field: 'x'),
      ];
      expect(pathSignature(hops), 'A>B.x');
    });

    test('truncates to last maxDepth hops', () {
      final hops = List.generate(15, (i) => GraphHop(className: 'C$i'));
      final sig = pathSignature(hops, maxDepth: 3);
      expect(sig, 'C12>C13>C14');
    });
  });

  group('clusterLeaks', () {
    GraphRetainingPath makePath(List<GraphHop> hops) =>
        GraphRetainingPath(hops: hops, rootKind: RootKind.timer);

    LeakRecord makeRecord({
      String className = 'MyWidget',
      int shallowSize = 100,
      required List<GraphHop> hops,
    }) {
      final path = makePath(hops);
      return LeakRecord(
        className: className,
        libraryUri: Uri.parse('package:app/my_widget.dart'),
        shallowSize: shallowSize,
        path: path,
        pathLibraries: const [],
        rootKind: RootKind.timer,
        signature: pathSignature(hops),
      );
    }

    final hopsA = [
      const GraphHop(className: '_Timer'),
      const GraphHop(className: 'List', index: 2),
      const GraphHop(className: 'MyWidget'),
    ];
    final hopsB = [
      const GraphHop(className: 'Stream'),
      const GraphHop(className: 'MyWidget'),
    ];

    test('groups same-signature leaks and sums bytes', () {
      final leaks = [
        makeRecord(shallowSize: 200, hops: hopsA),
        makeRecord(shallowSize: 300, hops: hopsA),
      ];
      final clusters = clusterLeaks(leaks);
      expect(clusters, hasLength(1));
      expect(clusters.first.instanceCount, 2);
      expect(clusters.first.retainedShallowBytes, 500);
    });

    test('drops clusters below minClusterSize', () {
      final leaks = [
        makeRecord(shallowSize: 100, hops: hopsA),
        makeRecord(shallowSize: 200, hops: hopsA),
        makeRecord(shallowSize: 50, hops: hopsB),
      ];
      final clusters = clusterLeaks(leaks, minClusterSize: 2);
      expect(clusters, hasLength(1));
      expect(clusters.first.instanceCount, 2);
    });

    test('drops all when every cluster is a singleton', () {
      final leaks = [
        makeRecord(shallowSize: 100, hops: hopsA),
        makeRecord(shallowSize: 50, hops: hopsB),
      ];
      expect(clusterLeaks(leaks, minClusterSize: 2), isEmpty);
    });

    test('ranks by instanceCount desc then bytes desc', () {
      final hopsC = [const GraphHop(className: 'C')];
      final hopsD = [const GraphHop(className: 'D')];
      final hopsE = [const GraphHop(className: 'E')];

      final leaks = [
        makeRecord(className: 'C', shallowSize: 10, hops: hopsC),
        makeRecord(className: 'C', shallowSize: 10, hops: hopsC),
        makeRecord(className: 'C', shallowSize: 10, hops: hopsC),
        makeRecord(className: 'D', shallowSize: 1000, hops: hopsD),
        makeRecord(className: 'D', shallowSize: 1000, hops: hopsD),
        makeRecord(className: 'E', shallowSize: 999, hops: hopsE),
        makeRecord(className: 'E', shallowSize: 999, hops: hopsE),
      ];

      final clusters = clusterLeaks(leaks, minClusterSize: 2);
      expect(clusters, hasLength(3));
      expect(clusters[0].className, 'C');
      expect(clusters[1].className, 'D');
      expect(clusters[2].className, 'E');
    });

    test('cluster fields match first record', () {
      final leaks = [
        makeRecord(shallowSize: 100, hops: hopsA),
        makeRecord(shallowSize: 200, hops: hopsA),
      ];
      final cluster = clusterLeaks(leaks).first;
      expect(cluster.className, 'MyWidget');
      expect(cluster.libraryUri, Uri.parse('package:app/my_widget.dart'));
      expect(cluster.rootKind, RootKind.timer);
      expect(cluster.confidence, LeakConfidence.heuristic);
      expect(cluster.signature, pathSignature(hopsA));
    });
  });
}
