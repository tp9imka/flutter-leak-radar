import 'package:leak_graph/leak_graph.dart';
import 'package:test/test.dart';

GraphLeakCluster _cluster({
  required String className,
  required String signature,
  int instanceCount = 2,
  int retainedShallowBytes = 100,
  LeakConfidence confidence = LeakConfidence.heuristic,
  List<GraphHop>? hops,
}) => GraphLeakCluster(
  className: className,
  libraryUri: null,
  instanceCount: instanceCount,
  retainedShallowBytes: retainedShallowBytes,
  representativePath: GraphRetainingPath(
    hops:
        hops ?? [GraphHop(className: '_Timer'), GraphHop(className: className)],
    rootKind: RootKind.timer,
  ),
  rootKind: RootKind.timer,
  confidence: confidence,
  signature: signature,
);

GraphAnalysisResult _result(List<GraphLeakCluster> clusters) =>
    GraphAnalysisResult(
      clusters: clusters,
      stats: GraphAnalysisStats(
        totalObjects: 0,
        reachableObjects: 0,
        leakCandidates: 0,
        clusters: clusters.length,
        suppressedByAppFilter: 0,
        warnings: const [],
      ),
    );

void main() {
  group('LeakBaseline round-trip', () {
    test('fromResult captures each cluster keyed by signature', () {
      final result = _result([
        _cluster(className: 'A', signature: 'r>A', instanceCount: 3),
        _cluster(className: 'B', signature: 'r>B', retainedShallowBytes: 40),
      ]);
      final createdAt = DateTime.utc(2026, 7, 17, 12);
      final baseline = LeakBaseline.fromResult(result, createdAt: createdAt);

      expect(baseline.schemaVersion, kLeakBaselineSchemaVersion);
      expect(baseline.clustersBySignature.keys, containsAll(['r>A', 'r>B']));
      expect(baseline.clustersBySignature['r>A']!.instanceCount, 3);
      expect(baseline.clustersBySignature['r>B']!.retainedShallowBytes, 40);
    });

    test('toJson/fromJson preserve all fields', () {
      final baseline = LeakBaseline.fromResult(
        _result([_cluster(className: 'A', signature: 'r>A', instanceCount: 5)]),
        createdAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
      );
      final decoded = LeakBaseline.fromJson(baseline.toJson());

      expect(decoded.schemaVersion, baseline.schemaVersion);
      expect(decoded.createdAt, baseline.createdAt);
      expect(decoded.clustersBySignature['r>A']!.instanceCount, 5);
      expect(decoded.clustersBySignature['r>A']!.className, 'A');
    });

    test('fromJson tolerates a missing schemaVersion (legacy → v1)', () {
      final json = LeakBaseline.fromResult(
        _result([_cluster(className: 'A', signature: 'r>A')]),
        createdAt: DateTime.utc(2026),
      ).toJson()..remove('schemaVersion');
      final decoded = LeakBaseline.fromJson(json);
      expect(decoded.schemaVersion, kLeakBaselineSchemaVersion);
    });
  });

  group('isBaselineComparable', () {
    test('current version and absent (defaulted) version are comparable', () {
      expect(isBaselineComparable(kLeakBaselineSchemaVersion), isTrue);
    });
    test('newer major version is not comparable', () {
      expect(isBaselineComparable(kLeakBaselineSchemaVersion + 1), isFalse);
    });
    test('nonsensically older version is not comparable', () {
      expect(isBaselineComparable(0), isFalse);
    });
  });

  group('compareToBaseline novelty', () {
    LeakBaseline baselineWith(List<GraphLeakCluster> clusters) =>
        LeakBaseline.fromResult(
          _result(clusters),
          createdAt: DateTime.utc(2026),
        );

    test('unchanged cluster classifies as known with zero deltas', () {
      final baseline = baselineWith([
        _cluster(
          className: 'A',
          signature: 'r>A',
          instanceCount: 4,
          retainedShallowBytes: 80,
        ),
      ]);
      final current = _result([
        _cluster(
          className: 'A',
          signature: 'r>A',
          instanceCount: 4,
          retainedShallowBytes: 80,
        ),
      ]);
      final cmp = compareToBaseline(current, baseline);
      expect(cmp.baselineComparable, isTrue);
      final d = cmp.deltas.single;
      expect(d.novelty, ClusterNovelty.known);
      expect(d.instanceDelta, 0);
      expect(d.bytesDelta, 0);
      expect(d.nearestKnownSignature, isNull);
    });

    test('grown cluster reports positive deltas', () {
      final baseline = baselineWith([
        _cluster(
          className: 'A',
          signature: 'r>A',
          instanceCount: 4,
          retainedShallowBytes: 80,
        ),
      ]);
      final current = _result([
        _cluster(
          className: 'A',
          signature: 'r>A',
          instanceCount: 9,
          retainedShallowBytes: 200,
        ),
      ]);
      final d = compareToBaseline(current, baseline).deltas.single;
      expect(d.novelty, ClusterNovelty.grown);
      expect(d.instanceDelta, 5);
      expect(d.bytesDelta, 120);
    });

    test('new cluster reports full count as growth', () {
      final baseline = baselineWith([
        _cluster(className: 'A', signature: 'root>A>B'),
      ]);
      final current = _result([
        _cluster(
          className: 'Z',
          signature: 'zzz>Z',
          instanceCount: 7,
          retainedShallowBytes: 70,
        ),
      ]);
      final d = compareToBaseline(current, baseline).deltas.single;
      expect(d.novelty, ClusterNovelty.newCluster);
      expect(d.instanceDelta, 7);
      expect(d.bytesDelta, 70);
    });

    test('gone lists baseline clusters absent from the current run', () {
      final baseline = baselineWith([
        _cluster(className: 'A', signature: 'r>A'),
        _cluster(className: 'Gone', signature: 'r>Gone'),
      ]);
      final current = _result([_cluster(className: 'A', signature: 'r>A')]);
      final cmp = compareToBaseline(current, baseline);
      expect(cmp.gone.map((c) => c.signature), ['r>Gone']);
    });
  });

  group('nearestKnownSignature', () {
    test('reports the highest-overlap signature when overlap >= 0.5', () {
      // current A>B>C vs A>B (2/3 = 0.667) and A>B>D (2/4 = 0.5); A>B wins.
      final hit = nearestKnownSignature('A>B>C', ['A>B', 'A>B>D']);
      expect(hit, 'A>B');
    });

    test('returns null when the best overlap is below 0.5', () {
      // A>B>C>D vs X>Y overlap 0; vs A>Z overlap 1/5 = 0.2.
      final miss = nearestKnownSignature('A>B>C>D', ['X>Y', 'A>Z']);
      expect(miss, isNull);
    });

    test('breaks ties lexicographically', () {
      // current A>B; candidates B>A and A>Q both share exactly 1 token,
      // union 3 → Jaccard 0.333? No: choose two with equal 0.5 overlap.
      // A>B vs A>C : inter {A}=1, union {A,B,C}=3 -> 0.333 (<0.5, excluded).
      // Use A>B>C vs C>B>Z and A>B>Y: each shares 2, union 4 -> 0.5 tie.
      final tie = nearestKnownSignature('A>B>C', ['C>B>Z', 'A>B>Y']);
      expect(tie, 'A>B>Y'); // lexicographically smaller of the two
    });

    test('honours token multisets (repeated hops)', () {
      // A>A>B vs A>B : target multiset {A:2,B:1}; cand {A:1,B:1}
      // inter = min = A:1,B:1 = 2; union = max = A:2,B:1 = 3 -> 0.667.
      final hit = nearestKnownSignature('A>A>B', ['A>B']);
      expect(hit, 'A>B');
    });

    test('returns null against an empty known set', () {
      expect(nearestKnownSignature('A>B', const []), isNull);
    });
  });

  group('new cluster nearestKnownSignature wiring', () {
    test('populates nearest signature for a new cluster above threshold', () {
      final baseline = LeakBaseline.fromResult(
        _result([_cluster(className: 'A', signature: 'A>B')]),
        createdAt: DateTime.utc(2026),
      );
      final current = _result([_cluster(className: 'A2', signature: 'A>B>C')]);
      final d = compareToBaseline(current, baseline).deltas.single;
      expect(d.novelty, ClusterNovelty.newCluster);
      expect(d.nearestKnownSignature, 'A>B');
    });

    test('leaves nearest signature null for a new cluster below threshold', () {
      final baseline = LeakBaseline.fromResult(
        _result([_cluster(className: 'A', signature: 'A>B>C>D')]),
        createdAt: DateTime.utc(2026),
      );
      final current = _result([_cluster(className: 'Z', signature: 'X>Y')]);
      final d = compareToBaseline(current, baseline).deltas.single;
      expect(d.nearestKnownSignature, isNull);
    });
  });

  group('evaluateGate thresholds', () {
    LeakBaseline baselineWith(List<GraphLeakCluster> clusters) =>
        LeakBaseline.fromResult(
          _result(clusters),
          createdAt: DateTime.utc(2026),
        );

    test('maxTotalClusters fires independently of any baseline', () {
      final cmp = BaselineComparison.withoutBaseline(
        _result([
          _cluster(className: 'A', signature: 'r>A'),
          _cluster(className: 'B', signature: 'r>B'),
          _cluster(className: 'C', signature: 'r>C'),
        ]),
      );
      final gate = evaluateGate(cmp, const GateOptions(maxTotalClusters: 2));
      expect(gate.passed, isFalse);
      expect(gate.violations, isNotEmpty);
    });

    test('maxTotalClusters passes at the limit', () {
      final cmp = BaselineComparison.withoutBaseline(
        _result([_cluster(className: 'A', signature: 'r>A')]),
      );
      expect(
        evaluateGate(cmp, const GateOptions(maxTotalClusters: 1)).passed,
        isTrue,
      );
    });

    test('maxNewClusters fires only on new clusters', () {
      final baseline = baselineWith([
        _cluster(className: 'A', signature: 'r>A'),
      ]);
      final current = _result([
        _cluster(className: 'A', signature: 'r>A'),
        _cluster(className: 'N1', signature: 'r>N1'),
        _cluster(className: 'N2', signature: 'r>N2'),
      ]);
      final cmp = compareToBaseline(current, baseline);
      expect(
        evaluateGate(cmp, const GateOptions(maxNewClusters: 1)).passed,
        isFalse,
      );
      expect(
        evaluateGate(cmp, const GateOptions(maxNewClusters: 2)).passed,
        isTrue,
      );
    });

    test('maxClassGrowthInstances fires on known-cluster growth', () {
      final baseline = baselineWith([
        _cluster(className: 'A', signature: 'r>A', instanceCount: 2),
      ]);
      final current = _result([
        _cluster(className: 'A', signature: 'r>A', instanceCount: 12),
      ]);
      final cmp = compareToBaseline(current, baseline);
      expect(
        evaluateGate(cmp, const GateOptions(maxClassGrowthInstances: 5)).passed,
        isFalse,
      );
      expect(
        evaluateGate(
          cmp,
          const GateOptions(maxClassGrowthInstances: 20),
        ).passed,
        isTrue,
      );
    });

    test('maxHeapGrowthBytes compares total shallow bytes to baseline', () {
      final baseline = baselineWith([
        _cluster(className: 'A', signature: 'r>A', retainedShallowBytes: 100),
      ]);
      final current = _result([
        _cluster(className: 'A', signature: 'r>A', retainedShallowBytes: 100),
        _cluster(className: 'B', signature: 'r>B', retainedShallowBytes: 500),
      ]);
      final cmp = compareToBaseline(current, baseline);
      expect(cmp.heapGrowthBytes, 500);
      expect(
        evaluateGate(cmp, const GateOptions(maxHeapGrowthBytes: 400)).passed,
        isFalse,
      );
      expect(
        evaluateGate(cmp, const GateOptions(maxHeapGrowthBytes: 600)).passed,
        isTrue,
      );
    });

    test('minConfidence excludes lower-confidence clusters from counts', () {
      final cmp = BaselineComparison.withoutBaseline(
        _result([
          _cluster(
            className: 'A',
            signature: 'r>A',
            confidence: LeakConfidence.heuristic,
          ),
          _cluster(
            className: 'B',
            signature: 'r>B',
            confidence: LeakConfidence.confirmed,
          ),
        ]),
      );
      // Only 1 cluster is confirmed, so a max of 1 passes at confirmed.
      final gate = evaluateGate(
        cmp,
        const GateOptions(
          maxTotalClusters: 1,
          minConfidence: LeakConfidence.confirmed,
        ),
      );
      expect(gate.passed, isTrue);
      // At heuristic, both count, so max of 1 fails.
      final gate2 = evaluateGate(cmp, const GateOptions(maxTotalClusters: 1));
      expect(gate2.passed, isFalse);
    });

    test('combined thresholds accumulate all violations', () {
      final baseline = baselineWith([
        _cluster(
          className: 'A',
          signature: 'r>A',
          instanceCount: 2,
          retainedShallowBytes: 100,
        ),
      ]);
      final current = _result([
        _cluster(
          className: 'A',
          signature: 'r>A',
          instanceCount: 20,
          retainedShallowBytes: 100,
        ),
        _cluster(className: 'N', signature: 'r>N', retainedShallowBytes: 900),
      ]);
      final cmp = compareToBaseline(current, baseline);
      final gate = evaluateGate(
        cmp,
        const GateOptions(
          maxNewClusters: 0,
          maxClassGrowthInstances: 5,
          maxHeapGrowthBytes: 100,
          maxTotalClusters: 1,
        ),
      );
      expect(gate.passed, isFalse);
      expect(gate.violations.length, 4);
    });

    test('no thresholds → always passes', () {
      final cmp = BaselineComparison.withoutBaseline(
        _result([_cluster(className: 'A', signature: 'r>A')]),
      );
      expect(evaluateGate(cmp, const GateOptions()).passed, isTrue);
    });
  });

  group('evaluateGate refuses baseline-dependent gates without a baseline', () {
    test('throws StateError on a non-comparable comparison', () {
      final cmp = BaselineComparison.withoutBaseline(
        _result([_cluster(className: 'A', signature: 'r>A')]),
      );
      expect(
        () => evaluateGate(cmp, const GateOptions(maxNewClusters: 0)),
        throwsStateError,
      );
      expect(
        () => evaluateGate(cmp, const GateOptions(maxHeapGrowthBytes: 0)),
        throwsStateError,
      );
    });

    test(
      'baseline-independent total gate still runs on a non-comparable cmp',
      () {
        final cmp = BaselineComparison.withoutBaseline(
          _result([_cluster(className: 'A', signature: 'r>A')]),
        );
        expect(
          () => evaluateGate(cmp, const GateOptions(maxTotalClusters: 5)),
          returnsNormally,
        );
      },
    );
  });
}
