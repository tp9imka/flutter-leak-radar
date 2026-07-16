import 'package:leak_graph/leak_graph.dart';
import 'package:test/test.dart';

void main() {
  group('JSON round-trips', () {
    test('GraphHop', () {
      const withField = GraphHop(className: 'A', field: 'f');
      const withIndex = GraphHop(className: 'List', index: 3);
      const bare = GraphHop(className: 'Root');

      for (final hop in [withField, withIndex, bare]) {
        expect(GraphHop.fromJson(hop.toJson()), equals(hop));
      }
    });

    test('GraphHop preserves libraryUri across JSON (equality ignores it)', () {
      final hop = GraphHop(
        className: 'A',
        field: 'f',
        libraryUri: Uri.parse('package:app/a.dart'),
      );
      final decoded = GraphHop.fromJson(hop.toJson());
      expect(decoded, equals(hop));
      expect(decoded.libraryUri, Uri.parse('package:app/a.dart'));
    });

    test('GraphRetainingPath', () {
      const path = GraphRetainingPath(
        hops: [
          GraphHop(className: '_Timer'),
          GraphHop(className: 'List', index: 0),
          GraphHop(className: 'HomeState', field: '_owner'),
        ],
        rootKind: RootKind.timer,
      );

      expect(GraphRetainingPath.fromJson(path.toJson()), equals(path));
    });

    test('ClassCount', () {
      final count = ClassCount(
        className: 'Foo',
        libraryUri: Uri.parse('package:app/foo.dart'),
        instanceCount: 4,
        shallowBytes: 64,
      );

      expect(ClassCount.fromJson(count.toJson()), equals(count));
    });

    test('GraphLeakCluster', () {
      const path = GraphRetainingPath(
        hops: [
          GraphHop(className: '_Timer'),
          GraphHop(className: 'HomeState'),
        ],
        rootKind: RootKind.timer,
      );
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

      expect(GraphLeakCluster.fromJson(cluster.toJson()), equals(cluster));
    });

    test('GraphLeakCluster with leafClassName + anchorHopIndex', () {
      const path = GraphRetainingPath(
        hops: [
          GraphHop(className: '_Timer'),
          GraphHop(className: '_LeakyScreenState', field: '_callback'),
          GraphHop(className: '_ControllerSubscription', field: '_sub'),
        ],
        rootKind: RootKind.timer,
      );
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
      expect(decoded, equals(cluster));
      expect(decoded.leafClassName, '_ControllerSubscription');
      expect(decoded.anchorHopIndex, 1);
    });

    test('GraphLeakCluster with a null libraryUri', () {
      const path = GraphRetainingPath(
        hops: [GraphHop(className: 'Foo')],
        rootKind: RootKind.staticOrGlobal,
      );
      const cluster = GraphLeakCluster(
        className: 'Foo',
        libraryUri: null,
        instanceCount: 1,
        retainedShallowBytes: 16,
        representativePath: path,
        rootKind: RootKind.staticOrGlobal,
        confidence: LeakConfidence.heuristic,
        signature: 'Foo',
      );

      expect(GraphLeakCluster.fromJson(cluster.toJson()), equals(cluster));
    });

    test('GraphAnalysisStats', () {
      const stats = GraphAnalysisStats(
        totalObjects: 100,
        reachableObjects: 42,
        leakCandidates: 5,
        clusters: 2,
        suppressedByAppFilter: 3,
        suppressedByLiveTree: 1,
        warnings: ['node 7 missing'],
      );

      expect(GraphAnalysisStats.fromJson(stats.toJson()), equals(stats));
    });

    test('ClassRootProfile with a representative path', () {
      const profile = ClassRootProfile(
        className: 'HomeState',
        libraryUri: null,
        totalInstances: 3,
        retainedShallowBytes: 384,
        byRoot: {RootKind.timer: 2, RootKind.liveTree: 1},
        representativePath: GraphRetainingPath(
          hops: [
            GraphHop(className: '_Timer'),
            GraphHop(className: 'HomeState'),
          ],
          rootKind: RootKind.timer,
        ),
      );

      expect(ClassRootProfile.fromJson(profile.toJson()), equals(profile));
    });

    test('ClassRootProfile without a representative path', () {
      final profile = ClassRootProfile(
        className: 'Widget',
        libraryUri: Uri.parse('package:flutter/widgets.dart'),
        totalInstances: 10,
        retainedShallowBytes: 160,
        byRoot: const {RootKind.liveTree: 10},
      );

      expect(ClassRootProfile.fromJson(profile.toJson()), equals(profile));
    });

    test('GraphAnalysisResult with clusters and classRootProfiles', () {
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
        instanceCount: 2,
        retainedShallowBytes: 256,
        representativePath: path,
        rootKind: RootKind.timer,
        confidence: LeakConfidence.heuristic,
        signature: '_Timer>HomeState',
      );
      const stats = GraphAnalysisStats(
        totalObjects: 10,
        reachableObjects: 8,
        leakCandidates: 2,
        clusters: 1,
        suppressedByAppFilter: 0,
        warnings: [],
      );
      const profile = ClassRootProfile(
        className: 'HomeState',
        libraryUri: null,
        totalInstances: 2,
        retainedShallowBytes: 256,
        byRoot: {RootKind.timer: 2},
        representativePath: path,
      );
      const result = GraphAnalysisResult(
        clusters: [cluster],
        stats: stats,
        classRootProfiles: [profile],
      );

      final decoded = GraphAnalysisResult.fromJson(result.toJson());

      expect(decoded, equals(result));
      expect(decoded.classRootProfiles, equals(result.classRootProfiles));
    });

    test('GraphAnalysisResult without classRootProfiles key defaults to '
        'empty (backward compatible with older exports)', () {
      const stats = GraphAnalysisStats(
        totalObjects: 1,
        reachableObjects: 0,
        leakCandidates: 0,
        clusters: 0,
        suppressedByAppFilter: 0,
        warnings: [],
      );
      const result = GraphAnalysisResult(clusters: [], stats: stats);
      final json = result.toJson()..remove('classRootProfiles');

      final decoded = GraphAnalysisResult.fromJson(json);

      expect(decoded.classRootProfiles, isEmpty);
    });

    test('GraphAnalysisResult carries resolvedAppPackages across JSON', () {
      const stats = GraphAnalysisStats(
        totalObjects: 1,
        reachableObjects: 1,
        leakCandidates: 0,
        clusters: 0,
        suppressedByAppFilter: 0,
        warnings: [],
      );
      const result = GraphAnalysisResult(
        clusters: [],
        stats: stats,
        resolvedAppPackages: ['my_app', 'my_widgets'],
      );

      final decoded = GraphAnalysisResult.fromJson(result.toJson());

      expect(decoded, equals(result));
      expect(decoded.resolvedAppPackages, ['my_app', 'my_widgets']);
    });

    test('GraphAnalysisResult without resolvedAppPackages key defaults to '
        'empty (backward compatible with older exports)', () {
      const stats = GraphAnalysisStats(
        totalObjects: 1,
        reachableObjects: 0,
        leakCandidates: 0,
        clusters: 0,
        suppressedByAppFilter: 0,
        warnings: [],
      );
      const result = GraphAnalysisResult(clusters: [], stats: stats);
      final json = result.toJson()..remove('resolvedAppPackages');

      final decoded = GraphAnalysisResult.fromJson(json);

      expect(decoded.resolvedAppPackages, isEmpty);
    });
  });
}
