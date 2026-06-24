import 'dart:convert';

import 'package:leak_graph/leak_graph.dart';
import 'package:test/test.dart';

GraphAnalysisResult _singleClusterResult() {
  const path = GraphRetainingPath(
    hops: [
      GraphHop(className: '_Timer'),
      GraphHop(className: 'HomeState'),
    ],
    rootKind: RootKind.timer,
  );
  const cluster = GraphLeakCluster(
    className: 'HomeState',
    libraryUri: null,
    instanceCount: 3,
    retainedShallowBytes: 384,
    representativePath: path,
    rootKind: RootKind.timer,
    confidence: LeakConfidence.heuristic,
    signature: 'sig',
  );
  const stats = GraphAnalysisStats(
    totalObjects: 10,
    reachableObjects: 5,
    leakCandidates: 3,
    clusters: 1,
    suppressedByAppFilter: 0,
    warnings: [],
  );
  return const GraphAnalysisResult(clusters: [cluster], stats: stats);
}

void main() {
  group('renderReport', () {
    test('lists count, bytes, rootKind and path for each cluster', () {
      final result = _singleClusterResult();
      final report = renderReport(result);

      expect(report, contains('× 3'));
      expect(report, contains('HomeState'));
      expect(report, contains('[Timer]'));
      expect(report, contains('384 B'));
      expect(report, contains('_Timer'));
    });

    test('respects top parameter by suppressing extra clusters', () {
      const stats = GraphAnalysisStats(
        totalObjects: 10,
        reachableObjects: 10,
        leakCandidates: 5,
        clusters: 5,
        suppressedByAppFilter: 0,
        warnings: [],
      );

      const path = GraphRetainingPath(
        hops: [
          GraphHop(className: '_Timer'),
          GraphHop(className: 'LeakedObj'),
        ],
        rootKind: RootKind.timer,
      );

      final clusters = List.generate(
        5,
        (i) => GraphLeakCluster(
          className: 'LeakedObj$i',
          libraryUri: null,
          instanceCount: i + 1,
          retainedShallowBytes: (i + 1) * 100,
          representativePath: path,
          rootKind: RootKind.timer,
          confidence: LeakConfidence.heuristic,
          signature: 'sig$i',
        ),
      );

      final result = GraphAnalysisResult(clusters: clusters, stats: stats);
      final report = renderReport(result, top: 2);

      expect(report, contains('LeakedObj0'));
      expect(report, contains('LeakedObj1'));
      expect(report, isNot(contains('LeakedObj2')));
    });

    test('includes header with total cluster count', () {
      final result = _singleClusterResult();
      final report = renderReport(result);

      expect(report, contains('1'));
    });

    test('includes confidence label heuristic for heuristic clusters', () {
      final result = _singleClusterResult();
      final report = renderReport(result);

      expect(report, contains('heuristic'));
    });

    test('includes confidence label confirmed for confirmed clusters', () {
      const path = GraphRetainingPath(
        hops: [
          GraphHop(className: '_Timer'),
          GraphHop(className: 'Foo'),
        ],
        rootKind: RootKind.timer,
      );
      const cluster = GraphLeakCluster(
        className: 'Foo',
        libraryUri: null,
        instanceCount: 1,
        retainedShallowBytes: 100,
        representativePath: path,
        rootKind: RootKind.timer,
        confidence: LeakConfidence.confirmed,
        signature: 'sig2',
      );
      const stats = GraphAnalysisStats(
        totalObjects: 1,
        reachableObjects: 1,
        leakCandidates: 1,
        clusters: 1,
        suppressedByAppFilter: 0,
        warnings: [],
      );
      const result = GraphAnalysisResult(clusters: [cluster], stats: stats);
      final report = renderReport(result);

      expect(report, contains('confirmed'));
    });
  });

  group('renderJson', () {
    test('output is valid JSON with a clusters array', () {
      final result = _singleClusterResult();
      final json = renderJson(result);
      final decoded = jsonDecode(json) as Map<String, Object?>;

      expect(decoded['clusters'], isA<List<Object?>>());
    });

    test('output can be parsed with jsonDecode', () {
      final result = _singleClusterResult();
      final json = renderJson(result);

      expect(() => jsonDecode(json), returnsNormally);
    });

    test('clusters array has correct length', () {
      final result = _singleClusterResult();
      final json = renderJson(result);
      final decoded = jsonDecode(json) as Map<String, Object?>;

      expect((decoded['clusters'] as List).length, 1);
    });
  });
}
