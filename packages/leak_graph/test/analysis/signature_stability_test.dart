import 'package:leak_graph/leak_graph.dart';
import 'package:test/test.dart';

import '../support/in_memory_heap_graph.dart';

void main() {
  // PHASE TRIPWIRE. pathSignature output and GraphHop/GraphRetainingPath
  // ==/hashCode must be byte-identical before/after attribution landed —
  // Phase B baselines key on these signatures. If this test ever fails,
  // libraryUri (or any other attribution field) has leaked into equality or
  // the signature; that is a breaking change, not a fix. Never weaken it.
  group('signature + hop equality ignore libraryUri', () {
    test('pathSignature and hop equality ignore libraryUri', () {
      final hops = [
        GraphHop(className: 'MyBloc', field: '_subs'),
        GraphHop(className: '_List', index: 3),
        GraphHop(className: '_Closure'),
      ];
      expect(pathSignature(hops), 'MyBloc._subs>_List[]>_Closure');
      final withUri = GraphHop(
        className: 'MyBloc',
        field: '_subs',
        libraryUri: Uri.parse('package:app/bloc.dart'),
      );
      expect(withUri, GraphHop(className: 'MyBloc', field: '_subs'));
      expect(
        withUri.hashCode,
        GraphHop(className: 'MyBloc', field: '_subs').hashCode,
      );
      expect(
        pathSignature([withUri]),
        pathSignature([GraphHop(className: 'MyBloc', field: '_subs')]),
      );
    });

    test('GraphRetainingPath equality/hashCode ignore hop libraryUri', () {
      final withUris = GraphRetainingPath(
        hops: [
          GraphHop(
            className: 'MyBloc',
            field: '_subs',
            libraryUri: Uri.parse('package:app/bloc.dart'),
          ),
          GraphHop(className: '_List', index: 3),
        ],
        rootKind: RootKind.timer,
      );
      const withoutUris = GraphRetainingPath(
        hops: [
          GraphHop(className: 'MyBloc', field: '_subs'),
          GraphHop(className: '_List', index: 3),
        ],
        rootKind: RootKind.timer,
      );
      expect(withUris, withoutUris);
      expect(withUris.hashCode, withoutUris.hashCode);
    });
  });

  group('GraphHop libraryUri JSON', () {
    test(
      'round-trips libraryUri (equality ignores it, so assert the field)',
      () {
        final hop = GraphHop(
          className: 'A',
          field: 'f',
          libraryUri: Uri.parse('package:app/a.dart'),
        );
        final json = hop.toJson();
        expect(json['libraryUri'], 'package:app/a.dart');
        final decoded = GraphHop.fromJson(json);
        expect(decoded.libraryUri, Uri.parse('package:app/a.dart'));
        expect(decoded.className, 'A');
        expect(decoded.field, 'f');
      },
    );

    test('omits libraryUri from JSON when null', () {
      const hop = GraphHop(className: 'A', field: 'f');
      expect(hop.toJson().containsKey('libraryUri'), isFalse);
      expect(GraphHop.fromJson(hop.toJson()).libraryUri, isNull);
    });

    test('parses old JSON with no libraryUri key (absent -> null)', () {
      final decoded = GraphHop.fromJson(const {'className': 'A', 'field': 'f'});
      expect(decoded.libraryUri, isNull);
      expect(decoded.className, 'A');
    });
  });

  group('GraphLeakCluster leafClassName + anchorHopIndex JSON', () {
    const path = GraphRetainingPath(
      hops: [
        GraphHop(className: '_Timer'),
        GraphHop(className: '_LeakyScreenState', field: '_callback'),
        GraphHop(className: '_ControllerSubscription', field: '_sub'),
      ],
      rootKind: RootKind.timer,
    );

    test('round-trips with leafClassName + anchorHopIndex', () {
      final cluster = GraphLeakCluster(
        className: '_LeakyScreenState',
        libraryUri: Uri.parse('package:app/leaky.dart'),
        instanceCount: 2,
        retainedShallowBytes: 256,
        representativePath: path,
        rootKind: RootKind.timer,
        confidence: LeakConfidence.confirmed,
        signature: '_Timer>_LeakyScreenState._callback',
        leafClassName: '_ControllerSubscription',
        anchorHopIndex: 1,
      );
      final decoded = GraphLeakCluster.fromJson(cluster.toJson());
      expect(decoded, cluster);
      expect(decoded.leafClassName, '_ControllerSubscription');
      expect(decoded.anchorHopIndex, 1);
    });

    test('back-compat: absent leafClassName/anchorHopIndex parse to null', () {
      final cluster = GraphLeakCluster(
        className: 'HomeState',
        libraryUri: Uri.parse('package:app/home.dart'),
        instanceCount: 2,
        retainedShallowBytes: 256,
        representativePath: path,
        rootKind: RootKind.timer,
        confidence: LeakConfidence.confirmed,
        signature: '_Timer>HomeState',
      );
      final json = cluster.toJson()
        ..remove('leafClassName')
        ..remove('anchorHopIndex');
      final decoded = GraphLeakCluster.fromJson(json);
      expect(decoded.leafClassName, isNull);
      expect(decoded.anchorHopIndex, isNull);
      expect(decoded, cluster);
    });

    test('omits leafClassName/anchorHopIndex from JSON when null', () {
      final cluster = GraphLeakCluster(
        className: 'HomeState',
        libraryUri: Uri.parse('package:app/home.dart'),
        instanceCount: 2,
        retainedShallowBytes: 256,
        representativePath: path,
        rootKind: RootKind.timer,
        confidence: LeakConfidence.confirmed,
        signature: '_Timer>HomeState',
      );
      final json = cluster.toJson();
      expect(json.containsKey('leafClassName'), isFalse);
      expect(json.containsKey('anchorHopIndex'), isFalse);
    });

    test('equality distinguishes leafClassName + anchorHopIndex', () {
      GraphLeakCluster make({String? leaf, int? anchor}) => GraphLeakCluster(
        className: '_LeakyScreenState',
        libraryUri: Uri.parse('package:app/leaky.dart'),
        instanceCount: 2,
        retainedShallowBytes: 256,
        representativePath: path,
        rootKind: RootKind.timer,
        confidence: LeakConfidence.confirmed,
        signature: '_Timer>_LeakyScreenState._callback',
        leafClassName: leaf,
        anchorHopIndex: anchor,
      );
      expect(make(leaf: 'X', anchor: 1), make(leaf: 'X', anchor: 1));
      expect(make(leaf: 'X', anchor: 1) == make(leaf: 'Y', anchor: 1), isFalse);
      expect(make(leaf: 'X', anchor: 1) == make(leaf: 'X', anchor: 2), isFalse);
    });
  });

  group('clusterLeaks derives leaf + anchor from the first record', () {
    // The headline is the app owner (attributionClassName); the record's own
    // className is the internal leaf. anchorHopIndex is carried from the record.
    LeakRecord record({
      required String className,
      required String? attributionClassName,
      required int? anchorHopIndex,
      required int nodeId,
      int? attributionAnchorNodeId,
    }) {
      const hops = [
        GraphHop(className: '_Timer'),
        GraphHop(className: '_LeakyScreenState', field: '_callback'),
        GraphHop(className: '_ControllerSubscription', field: '_sub'),
      ];
      const path = GraphRetainingPath(hops: hops, rootKind: RootKind.timer);
      return LeakRecord(
        nodeId: nodeId,
        className: className,
        libraryUri: Uri.parse('dart:async'),
        shallowSize: 16,
        path: path,
        pathLibraries: const [],
        rootKind: RootKind.timer,
        signature: '_Timer>_LeakyScreenState._callback',
        attributionAnchorNodeId: attributionAnchorNodeId,
        attributionClassName: attributionClassName,
        attributionLibraryUri: Uri.parse('package:app/leaky.dart'),
        anchorHopIndex: anchorHopIndex,
      );
    }

    test('preserves the leaf class and anchor hop index on the cluster', () {
      final leaves = [
        record(
          className: '_ControllerSubscription',
          attributionClassName: '_LeakyScreenState',
          anchorHopIndex: 1,
          nodeId: 2,
          attributionAnchorNodeId: 3,
        ),
        record(
          className: '_Closure',
          attributionClassName: '_LeakyScreenState',
          anchorHopIndex: 1,
          nodeId: 6,
          attributionAnchorNodeId: 7,
        ),
      ];
      final cluster = clusterLeaks(leaves, minClusterSize: 2).single;
      expect(cluster.className, '_LeakyScreenState');
      expect(cluster.leafClassName, '_ControllerSubscription');
      expect(cluster.anchorHopIndex, 1);
    });

    test('leafClassName is null when the record has no attribution anchor', () {
      final leaves = [
        record(
          className: 'HomeState',
          attributionClassName: null,
          anchorHopIndex: null,
          nodeId: 2,
        ),
        record(
          className: 'HomeState',
          attributionClassName: null,
          anchorHopIndex: null,
          nodeId: 3,
        ),
      ];
      final cluster = clusterLeaks(leaves, minClusterSize: 2).single;
      expect(cluster.className, 'HomeState');
      expect(cluster.leafClassName, isNull);
      expect(cluster.anchorHopIndex, isNull);
    });
  });

  group('analyzer end-to-end anchor plumb-through', () {
    // root(0) -> _Timer(1) -> _LeakyScreenState(3, app) -> _CtrlSub(2, sdk).
    // Leaf id 2 < owner id 3 so the SDK-leaf record iterates first and becomes
    // group.first — proving the cluster keeps the leaf class distinct from the
    // headlined app owner.
    InMemoryHeapGraph leafAnchorGraph() => InMemoryHeapGraph.of({
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
        edges: const [HeapEdge(targetId: 3, field: '_callback')],
      ),
      2: HeapNode(
        id: 2,
        className: '_ControllerSubscription',
        libraryUri: Uri.parse('dart:async'),
        shallowSize: 16,
        edges: const [],
      ),
      3: HeapNode(
        id: 3,
        className: '_LeakyScreenState',
        libraryUri: Uri.parse('package:my_app/leaky.dart'),
        shallowSize: 128,
        edges: const [HeapEdge(targetId: 2, field: '_sub')],
      ),
    });

    test('cluster headlines the owner, keeps the leaf + anchor hop index', () {
      const analyzer = GraphLeakAnalyzer();
      final result = analyzer.analyze(
        leafAnchorGraph(),
        const GraphAnalysisOptions(appPackages: ['my_app'], minClusterSize: 1),
      );

      final cluster = result.clusters.single;
      expect(cluster.className, '_LeakyScreenState');
      expect(cluster.leafClassName, '_ControllerSubscription');
      expect(cluster.anchorHopIndex, 1);
      // The anchor hop index points at the headlined owner in the path.
      expect(
        cluster.representativePath.hops[cluster.anchorHopIndex!].className,
        '_LeakyScreenState',
      );
      // The hop at the anchor carries its library uri end-to-end.
      expect(
        cluster.representativePath.hops[cluster.anchorHopIndex!].libraryUri
            .toString(),
        'package:my_app/leaky.dart',
      );
    });
  });
}
