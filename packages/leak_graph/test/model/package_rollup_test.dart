import 'package:leak_graph/leak_graph.dart';
import 'package:test/test.dart';

void main() {
  group('PackageRollup', () {
    const rollup = PackageRollup(
      package: 'livekit_client',
      origin: ClassOrigin.dependency,
      classCount: 3,
      instanceCount: 42,
      shallowBytes: 1024,
      clusterCount: 2,
    );

    test('JSON round-trips', () {
      expect(PackageRollup.fromJson(rollup.toJson()), equals(rollup));
    });

    test('toJson serializes origin by name and keeps labeled fields', () {
      final json = rollup.toJson();
      expect(json['package'], 'livekit_client');
      expect(json['origin'], 'dependency');
      expect(json['classCount'], 3);
      expect(json['instanceCount'], 42);
      expect(json['shallowBytes'], 1024);
      expect(json['clusterCount'], 2);
    });

    test('equality distinguishes origin and each count', () {
      PackageRollup withOrigin(ClassOrigin origin) => PackageRollup(
        package: 'livekit_client',
        origin: origin,
        classCount: 3,
        instanceCount: 42,
        shallowBytes: 1024,
        clusterCount: 2,
      );
      expect(withOrigin(ClassOrigin.dependency), equals(rollup));
      expect(withOrigin(ClassOrigin.dartSdk) == rollup, isFalse);
      expect(
        rollup ==
            const PackageRollup(
              package: 'livekit_client',
              origin: ClassOrigin.dependency,
              classCount: 4,
              instanceCount: 42,
              shallowBytes: 1024,
              clusterCount: 2,
            ),
        isFalse,
      );
    });

    test('round-trips an (unknown) package with unknown origin', () {
      const unknown = PackageRollup(
        package: '(unknown)',
        origin: ClassOrigin.unknown,
        classCount: 1,
        instanceCount: 1,
        shallowBytes: 8,
        clusterCount: 1,
      );
      expect(PackageRollup.fromJson(unknown.toJson()), equals(unknown));
    });
  });

  group('GraphAnalysisResult schemaVersion + rollups + detection source', () {
    const stats = GraphAnalysisStats(
      totalObjects: 1,
      reachableObjects: 0,
      leakCandidates: 0,
      clusters: 0,
      suppressedByAppFilter: 0,
      warnings: [],
    );

    test('toJson stamps schemaVersion 2', () {
      const result = GraphAnalysisResult(clusters: [], stats: stats);
      expect(result.toJson()['schemaVersion'], 2);
    });

    test('fromJson tolerates an absent schemaVersion (legacy v1 export)', () {
      const result = GraphAnalysisResult(clusters: [], stats: stats);
      final json = result.toJson()..remove('schemaVersion');
      expect(GraphAnalysisResult.fromJson(json), equals(result));
    });

    test('round-trips anchorRollups, declaredRollups, appPackageSource', () {
      const anchor = PackageRollup(
        package: 'my_app',
        origin: ClassOrigin.project,
        classCount: 2,
        instanceCount: 2,
        shallowBytes: 144,
        clusterCount: 1,
      );
      const declared = PackageRollup(
        package: 'dart:core',
        origin: ClassOrigin.dartSdk,
        classCount: 1,
        instanceCount: 1,
        shallowBytes: 16,
        clusterCount: 1,
      );
      const result = GraphAnalysisResult(
        clusters: [],
        stats: stats,
        anchorRollups: [anchor],
        declaredRollups: [declared],
        appPackageSource: AppPackageSource.explicitConfig,
      );

      final decoded = GraphAnalysisResult.fromJson(result.toJson());

      expect(decoded, equals(result));
      expect(decoded.anchorRollups, [anchor]);
      expect(decoded.declaredRollups, [declared]);
      expect(decoded.appPackageSource, AppPackageSource.explicitConfig);
    });

    test('absent rollups/appPackageSource default to empty/null', () {
      final json = <String, Object?>{
        'clusters': <Object?>[],
        'stats': stats.toJson(),
      };
      final decoded = GraphAnalysisResult.fromJson(json);
      expect(decoded.anchorRollups, isEmpty);
      expect(decoded.declaredRollups, isEmpty);
      expect(decoded.appPackageSource, isNull);
    });

    test('appPackageSource round-trips every enum value', () {
      for (final source in AppPackageSource.values) {
        final result = GraphAnalysisResult(
          clusters: const [],
          stats: stats,
          appPackageSource: source,
        );
        expect(
          GraphAnalysisResult.fromJson(result.toJson()).appPackageSource,
          source,
        );
      }
    });
  });
}
