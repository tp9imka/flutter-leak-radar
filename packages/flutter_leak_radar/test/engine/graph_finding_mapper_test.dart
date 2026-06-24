import 'package:flutter_leak_radar/src/engine/graph_finding_mapper.dart';
import 'package:flutter_leak_radar/src/model/leak_kind.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_graph/leak_graph.dart';

void main() {
  group('mapGraphCluster', () {
    final cluster = GraphLeakCluster(
      className: '_LeakyState',
      libraryUri: Uri.parse('package:myapp/src/leaky.dart'),
      instanceCount: 3,
      retainedShallowBytes: 1024,
      rootKind: RootKind.timer,
      confidence: LeakConfidence.confirmed,
      signature: 'timer:_LeakyState',
      representativePath: const GraphRetainingPath(
        rootKind: RootKind.timer,
        hops: [
          GraphHop(className: 'Timer', field: '_callback'),
          GraphHop(className: '_LeakyState'),
        ],
      ),
    );

    test('kind is retainedByNonLiveRoot', () {
      final finding = mapGraphCluster(cluster);
      expect(finding.kind, LeakKind.retainedByNonLiveRoot);
    });

    test('liveCount matches instanceCount', () {
      final finding = mapGraphCluster(cluster);
      expect(finding.liveCount, 3);
    });

    test('severity is critical for confirmed + instanceCount >= 2', () {
      final finding = mapGraphCluster(cluster);
      expect(finding.severity, LeakSeverity.critical);
    });

    test('tag is the rootKind label', () {
      final finding = mapGraphCluster(cluster);
      expect(finding.tag, 'Timer');
    });

    test('retainingPath elements match hops', () {
      final finding = mapGraphCluster(cluster);
      final path = finding.retainingPath!;
      expect(path.elements.map((h) => h.objectType).toList(), [
        'Timer',
        '_LeakyState',
      ]);
    });

    test('retainingPath gcRootType is rootKind label', () {
      final finding = mapGraphCluster(cluster);
      expect(finding.retainingPath!.gcRootType, 'Timer');
    });

    test('severity is warning for heuristic confidence', () {
      final heuristic = GraphLeakCluster(
        className: '_LeakyState',
        libraryUri: null,
        instanceCount: 5,
        retainedShallowBytes: 512,
        rootKind: RootKind.timer,
        confidence: LeakConfidence.heuristic,
        signature: 'timer:_LeakyState',
        representativePath: const GraphRetainingPath(
          rootKind: RootKind.timer,
          hops: [GraphHop(className: 'Timer')],
        ),
      );
      final finding = mapGraphCluster(heuristic);
      expect(finding.severity, LeakSeverity.warning);
    });

    test('severity is warning for confirmed but instanceCount < 2', () {
      final single = GraphLeakCluster(
        className: '_LeakyState',
        libraryUri: null,
        instanceCount: 1,
        retainedShallowBytes: 128,
        rootKind: RootKind.timer,
        confidence: LeakConfidence.confirmed,
        signature: 'timer:_LeakyState',
        representativePath: const GraphRetainingPath(
          rootKind: RootKind.timer,
          hops: [GraphHop(className: 'Timer')],
        ),
      );
      final finding = mapGraphCluster(single);
      expect(finding.severity, LeakSeverity.warning);
    });

    test('library is stringified libraryUri', () {
      final finding = mapGraphCluster(cluster);
      expect(finding.library, 'package:myapp/src/leaky.dart');
    });

    test('library is null when libraryUri is null', () {
      final noUri = GraphLeakCluster(
        className: '_LeakyState',
        libraryUri: null,
        instanceCount: 3,
        retainedShallowBytes: 0,
        rootKind: RootKind.timer,
        confidence: LeakConfidence.confirmed,
        signature: 'timer:_LeakyState',
        representativePath: const GraphRetainingPath(
          rootKind: RootKind.timer,
          hops: [GraphHop(className: 'Timer')],
        ),
      );
      final finding = mapGraphCluster(noUri);
      expect(finding.library, isNull);
    });

    test('growth is always 0', () {
      final finding = mapGraphCluster(cluster);
      expect(finding.growth, 0);
    });

    test('className matches cluster className', () {
      final finding = mapGraphCluster(cluster);
      expect(finding.className, '_LeakyState');
    });
  });
}
