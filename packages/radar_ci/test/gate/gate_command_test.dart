import 'dart:convert';

import 'package:leak_graph/leak_graph.dart';
import 'package:radar_ci/radar_ci.dart';
import 'package:radar_ci/radar_ci_io.dart';
import 'package:radar_native/radar_native.dart';
import 'package:radar_trace/radar_trace.dart';
import 'package:test/test.dart';

import '../support/fixtures.dart';

/// A deterministic assessment carrying [verdict], used to drive the gate
/// without depending on assessSeries' numeric thresholds.
SeriesAssessment fake(SeriesVerdict verdict) => SeriesAssessment(
  verdict: verdict,
  slopePerHour: verdict == SeriesVerdict.monotonicGrowth ? 5000000.0 : null,
  batchDeltaPerHour: verdict == SeriesVerdict.monotonicGrowth
      ? 4800000.0
      : null,
  samplesAssessed: verdict == SeriesVerdict.insufficientData ? 4 : 15,
  samplesTotal: 18,
  detail: 'fake ${verdict.name}',
);

/// Builds an `assess` seam mapping each gated series name to a fixed verdict.
SeriesAssessment Function(MetricSeries) assessAs(
  Map<String, SeriesVerdict> byName,
) =>
    (series) => fake(byName[series.name] ?? SeriesVerdict.plateau);

/// The three gated series, present but with values that the real assessor is
/// never asked about (an injected `assess` overrides).
List<MetricSeries> gatedSeries() => [
  for (final name in kGatedSignals)
    MetricSeries(
      name: name,
      unit: 'bytes',
      samples: const [MetricSample(tMicros: 0, value: 1)],
    ),
];

String encodeAnalysis(GraphAnalysisResult a) => jsonEncode(a.toJson());

String encodeBaseline(GraphAnalysisResult a) => jsonEncode(
  LeakBaseline.fromResult(a, createdAt: DateTime.utc(2026)).toJson(),
);

/// A baseline JSON stamped with an incomparable (future) schema version.
String encodeFutureBaseline() => jsonEncode(<String, Object?>{
  'schemaVersion': 999,
  'createdAt': DateTime.utc(2026).toIso8601String(),
  'clusters': const <Object?>[],
});

void main() {
  group('runGate — series growth verdict (condition a)', () {
    test('monotonicGrowth on a gated signal fails the gate (exit 3)', () async {
      final files = InMemoryFiles({
        'run.json': jsonEncode(runDoc(series: gatedSeries()).toJson()),
      });
      final out = StringBuffer();
      final code = await runGate(
        ['run.json'],
        out: out,
        err: StringBuffer(),
        readText: files.read,
        assess: assessAs({'dart.heap.used': SeriesVerdict.monotonicGrowth}),
      );
      expect(code, GateExit.gateFailed);
      expect(out.toString(), contains('GATE FAILED'));
      expect(out.toString(), contains('dart.heap.used: monotonicGrowth'));
    });

    test(
      'plateau/noisy/insufficientData never fail the gate (exit 0)',
      () async {
        final files = InMemoryFiles({
          'run.json': jsonEncode(runDoc(series: gatedSeries()).toJson()),
        });
        final out = StringBuffer();
        final code = await runGate(
          ['run.json'],
          out: out,
          err: StringBuffer(),
          readText: files.read,
          assess: assessAs({
            'dart.heap.used': SeriesVerdict.plateau,
            'dart.external': SeriesVerdict.noisy,
            'process.rss': SeriesVerdict.insufficientData,
          }),
        );
        expect(code, GateExit.ok);
        expect(out.toString(), contains('GATE PASSED'));
        expect(out.toString(), contains('process.rss: insufficientData'));
      },
    );

    test('real assessSeries certifies a growth series (exit 3)', () async {
      final files = InMemoryFiles({
        'run.json': jsonEncode(
          runDoc(
            series: [
              growthSeries('dart.heap.used'),
              flatSeries('dart.external'),
              flatSeries('process.rss'),
            ],
          ).toJson(),
        ),
      });
      final out = StringBuffer();
      final code = await runGate(
        ['run.json'],
        out: out,
        err: StringBuffer(),
        readText: files.read,
      );
      expect(code, GateExit.gateFailed);
      expect(out.toString(), contains('dart.heap.used: monotonicGrowth'));
    });
  });

  group('runGate — baseline new project-anchor clusters (condition b)', () {
    test('a NEW project-anchor cluster fails the gate (exit 3)', () async {
      final current = analysis(
        clusters: [
          cluster(signature: 'a>b', className: 'Leaky', package: 'my_app'),
        ],
      );
      final empty = analysis(clusters: const []);
      final files = InMemoryFiles({
        'run.json': jsonEncode(
          runDoc(
            series: gatedSeries(),
            analysisPath: 'end.analysis.json',
          ).toJson(),
        ),
        'end.analysis.json': encodeAnalysis(current),
        'base.json': encodeBaseline(empty),
      });
      final out = StringBuffer();
      final code = await runGate(
        ['run.json', '--baseline', 'base.json'],
        out: out,
        err: StringBuffer(),
        readText: files.read,
        assess: assessAs(const {}),
      );
      expect(code, GateExit.gateFailed);
      expect(out.toString(), contains('baseline: FAIL'));
      expect(out.toString(), contains('Leaky'));
    });

    test('a known cluster present in the baseline passes (exit 0)', () async {
      final current = analysis(
        clusters: [
          cluster(signature: 'a>b', className: 'Leaky', package: 'my_app'),
        ],
      );
      final files = InMemoryFiles({
        'run.json': jsonEncode(
          runDoc(
            series: gatedSeries(),
            analysisPath: 'end.analysis.json',
          ).toJson(),
        ),
        'end.analysis.json': encodeAnalysis(current),
        'base.json': encodeBaseline(current),
      });
      final out = StringBuffer();
      final code = await runGate(
        ['run.json', '--baseline', 'base.json'],
        out: out,
        err: StringBuffer(),
        readText: files.read,
        assess: assessAs(const {}),
      );
      expect(code, GateExit.ok);
      expect(out.toString(), contains('baseline: ok'));
    });

    test('a NEW dependency cluster does NOT fail the gate (exit 0)', () async {
      final current = analysis(
        clusters: [
          cluster(signature: 'x>y', className: 'DepLeak', package: 'some_dep'),
        ],
      );
      final files = InMemoryFiles({
        'run.json': jsonEncode(
          runDoc(
            series: gatedSeries(),
            analysisPath: 'end.analysis.json',
          ).toJson(),
        ),
        'end.analysis.json': encodeAnalysis(current),
        'base.json': encodeBaseline(analysis(clusters: const [])),
      });
      final out = StringBuffer();
      final code = await runGate(
        ['run.json', '--baseline', 'base.json'],
        out: out,
        err: StringBuffer(),
        readText: files.read,
        assess: assessAs(const {}),
      );
      expect(code, GateExit.ok);
      expect(out.toString(), contains('baseline: ok'));
    });

    test(
      '--min-confidence confirmed ignores a new heuristic cluster',
      () async {
        final current = analysis(
          clusters: [
            cluster(signature: 'a>b', className: 'Leaky', package: 'my_app'),
          ],
        );
        final files = InMemoryFiles({
          'run.json': jsonEncode(
            runDoc(
              series: gatedSeries(),
              analysisPath: 'end.analysis.json',
            ).toJson(),
          ),
          'end.analysis.json': encodeAnalysis(current),
          'base.json': encodeBaseline(analysis(clusters: const [])),
        });
        final out = StringBuffer();
        final code = await runGate(
          [
            'run.json',
            '--baseline',
            'base.json',
            '--min-confidence',
            'confirmed',
          ],
          out: out,
          err: StringBuffer(),
          readText: files.read,
          assess: assessAs(const {}),
        );
        expect(code, GateExit.ok);
      },
    );
  });

  group('runGate — refusals (exit 2, never a silent pass)', () {
    test('a partial run refuses without --allow-partial', () async {
      final files = InMemoryFiles({
        'run.json': jsonEncode(
          runDoc(
            series: gatedSeries(),
            completed: false,
            abortReason: 'interrupted',
          ).toJson(),
        ),
      });
      final out = StringBuffer();
      final code = await runGate(
        ['run.json'],
        out: out,
        err: StringBuffer(),
        readText: files.read,
        assess: assessAs({'dart.heap.used': SeriesVerdict.monotonicGrowth}),
      );
      expect(code, GateExit.toolFailure);
      expect(out.toString(), contains('partial'));
      expect(out.toString(), isNot(contains('GATE PASSED')));
    });

    test('--allow-partial lets a partial run be gated', () async {
      final files = InMemoryFiles({
        'run.json': jsonEncode(
          runDoc(series: gatedSeries(), completed: false).toJson(),
        ),
      });
      final code = await runGate(
        ['run.json', '--allow-partial'],
        out: StringBuffer(),
        err: StringBuffer(),
        readText: files.read,
        assess: assessAs(const {}),
      );
      expect(code, GateExit.ok);
    });

    test('an incomparable baseline refuses, never flags all-NEW', () async {
      final current = analysis(
        clusters: [
          cluster(signature: 'a>b', className: 'Leaky', package: 'my_app'),
        ],
      );
      final files = InMemoryFiles({
        'run.json': jsonEncode(
          runDoc(
            series: gatedSeries(),
            analysisPath: 'end.analysis.json',
          ).toJson(),
        ),
        'end.analysis.json': encodeAnalysis(current),
        'base.json': encodeFutureBaseline(),
      });
      final out = StringBuffer();
      final code = await runGate(
        ['run.json', '--baseline', 'base.json'],
        out: out,
        err: StringBuffer(),
        readText: files.read,
        assess: assessAs(const {}),
      );
      expect(code, GateExit.toolFailure);
      expect(out.toString(), contains('not comparable'));
      expect(out.toString(), isNot(contains('FAIL')));
    });

    test('a baseline-dependent threshold without a baseline refuses', () async {
      final current = analysis(clusters: const []);
      final files = InMemoryFiles({
        'run.json': jsonEncode(
          runDoc(
            series: gatedSeries(),
            analysisPath: 'end.analysis.json',
          ).toJson(),
        ),
        'end.analysis.json': encodeAnalysis(current),
      });
      final out = StringBuffer();
      final code = await runGate(
        ['run.json', '--max-new-clusters', '0'],
        out: out,
        err: StringBuffer(),
        readText: files.read,
        assess: assessAs(const {}),
      );
      expect(code, GateExit.toolFailure);
      expect(out.toString(), contains('baseline'));
    });

    test('a threshold gate with no heap analysis refuses', () async {
      final files = InMemoryFiles({
        'run.json': jsonEncode(runDoc(series: gatedSeries()).toJson()),
      });
      final out = StringBuffer();
      final code = await runGate(
        ['run.json', '--max-total-clusters', '0'],
        out: out,
        err: StringBuffer(),
        readText: files.read,
        assess: assessAs(const {}),
      );
      expect(code, GateExit.toolFailure);
      expect(out.toString(), contains('no heap analysis'));
    });

    test('an unreadable run.json is a tool failure', () async {
      final code = await runGate(
        ['missing.json'],
        out: StringBuffer(),
        err: StringBuffer(),
        readText: InMemoryFiles().read,
      );
      expect(code, GateExit.toolFailure);
    });

    test('a newer-schema run.json refuses rather than misreading', () async {
      final files = InMemoryFiles({
        'run.json': jsonEncode(<String, Object?>{
          'schemaVersion': 99,
          'metadata': {'startedAt': DateTime.utc(2026).toIso8601String()},
          'series': const <Object?>[],
          'checkpoints': const <Object?>[],
        }),
      });
      final code = await runGate(
        ['run.json'],
        out: StringBuffer(),
        err: StringBuffer(),
        readText: files.read,
      );
      expect(code, GateExit.toolFailure);
    });
  });

  group('runGate — byte-absolute thresholds & baseline write', () {
    test(
      '--max-total-clusters is evaluable without a baseline (exit 3)',
      () async {
        final current = analysis(
          clusters: [
            cluster(signature: 'a', className: 'A', package: 'my_app'),
            cluster(signature: 'b', className: 'B', package: 'my_app'),
          ],
        );
        final files = InMemoryFiles({
          'run.json': jsonEncode(
            runDoc(
              series: gatedSeries(),
              analysisPath: 'end.analysis.json',
            ).toJson(),
          ),
          'end.analysis.json': encodeAnalysis(current),
        });
        final out = StringBuffer();
        final code = await runGate(
          ['run.json', '--max-total-clusters', '1'],
          out: out,
          err: StringBuffer(),
          readText: files.read,
          assess: assessAs(const {}),
        );
        expect(code, GateExit.gateFailed);
        expect(out.toString(), contains('threshold: FAIL'));
      },
    );

    test(
      '--write-baseline persists a baseline from the last analysis',
      () async {
        final current = analysis(
          clusters: [
            cluster(signature: 'a>b', className: 'Leaky', package: 'my_app'),
          ],
        );
        final files = InMemoryFiles({
          'run.json': jsonEncode(
            runDoc(
              series: gatedSeries(),
              analysisPath: 'end.analysis.json',
            ).toJson(),
          ),
          'end.analysis.json': encodeAnalysis(current),
        });
        final code = await runGate(
          ['run.json', '--write-baseline', 'out.baseline.json'],
          out: StringBuffer(),
          err: StringBuffer(),
          readText: files.read,
          writeText: files.write,
          assess: assessAs(const {}),
        );
        expect(code, GateExit.ok);
        final written = LeakBaseline.fromJson(
          jsonDecode(files.store['out.baseline.json']!) as Map<String, Object?>,
        );
        expect(written.clustersBySignature.keys, contains('a>b'));
      },
    );

    test('an invalid threshold value is a usage error (exit 1)', () async {
      final files = InMemoryFiles({
        'run.json': jsonEncode(runDoc(series: gatedSeries()).toJson()),
      });
      final code = await runGate(
        ['run.json', '--max-total-clusters', 'notanumber'],
        out: StringBuffer(),
        err: StringBuffer(),
        readText: files.read,
      );
      expect(code, GateExit.usage);
    });
  });

  group('runGate — captureStatus-aware analysis selection', () {
    test('a failed final capture with an earlier analysis notes staleness but '
        'still evaluates the cluster gate', () async {
      final current = analysis(
        clusters: [
          cluster(signature: 'a>b', className: 'Leaky', package: 'my_app'),
        ],
      );
      final run = runDocWith(
        series: gatedSeries(),
        checkpoints: [
          checkpoint(
            label: 'cp1',
            analysisPath: 'cp1.analysis.json',
            tMicros: 1000000000000,
          ),
          checkpoint(
            label: 'end',
            captureStatus: 'partial',
            captureError: 'heap snapshot failed: reset',
            tMicros: 1000000060000,
          ),
        ],
      );
      final files = InMemoryFiles({
        'run.json': jsonEncode(run.toJson()),
        'cp1.analysis.json': encodeAnalysis(current),
        'base.json': encodeBaseline(analysis(clusters: const [])),
      });
      final out = StringBuffer();
      final code = await runGate(
        ['run.json', '--baseline', 'base.json'],
        out: out,
        err: StringBuffer(),
        readText: files.read,
        assess: assessAs(const {}),
      );
      // Gate still evaluates condition (b) against the earlier analysis.
      expect(code, GateExit.gateFailed);
      expect(out.toString(), contains('baseline: FAIL'));
      // ...but honestly names the stale checkpoint and the final failure.
      expect(out.toString(), contains('cluster gate'));
      expect(out.toString(), contains("'cp1'"));
      expect(out.toString(), contains('heap snapshot failed'));
    });

    test('all captures failed (no analysis anywhere) refuses exit 2', () async {
      final run = runDocWith(
        series: gatedSeries(),
        checkpoints: [
          checkpoint(
            label: 'end',
            captureStatus: 'failed',
            captureError: 'allocation profile failed',
          ),
        ],
      );
      final files = InMemoryFiles({
        'run.json': jsonEncode(run.toJson()),
        'base.json': encodeBaseline(analysis(clusters: const [])),
      });
      final out = StringBuffer();
      final code = await runGate(
        ['run.json', '--baseline', 'base.json'],
        out: out,
        err: StringBuffer(),
        readText: files.read,
        assess: assessAs(const {}),
      );
      expect(code, GateExit.toolFailure);
      expect(out.toString(), contains('no heap analysis'));
    });

    test(
      '--write-baseline on a failing gate warns about known clusters',
      () async {
        final current = analysis(
          clusters: [
            cluster(signature: 'a>b', className: 'Leaky', package: 'my_app'),
          ],
        );
        final files = InMemoryFiles({
          'run.json': jsonEncode(
            runDoc(
              series: gatedSeries(),
              analysisPath: 'end.analysis.json',
            ).toJson(),
          ),
          'end.analysis.json': encodeAnalysis(current),
        });
        final err = StringBuffer();
        final code = await runGate(
          ['run.json', '--write-baseline', 'out.baseline.json'],
          out: StringBuffer(),
          err: err,
          readText: files.read,
          writeText: files.write,
          assess: assessAs({'dart.heap.used': SeriesVerdict.monotonicGrowth}),
        );
        expect(code, GateExit.gateFailed);
        expect(files.store.containsKey('out.baseline.json'), isTrue);
        expect(err.toString(), contains('FAILING run'));
      },
    );
  });

  group('runGate — native lane (--gate-native, opt-in)', () {
    Future<(int, String)> runNative(
      RadarRunDocument run,
      List<String> extraArgs,
    ) async {
      final files = InMemoryFiles({'run.json': jsonEncode(run.toJson())});
      final out = StringBuffer();
      final code = await runGate(
        ['run.json', ...extraArgs],
        out: out,
        err: StringBuffer(),
        readText: files.read,
        // Dart lanes are plateau, isolating the native gate.
        assess: assessAs(const {}),
      );
      return (code, out.toString());
    }

    test('a growing native column fails the gate with --gate-native', () async {
      final run = runDoc(
        series: gatedSeries(),
        nativeTimeline: nativeTimeline(
          growing: {TriageColumn.nativePssKb},
          flat: {TriageColumn.threads},
        ),
      );
      final (code, output) = await runNative(run, ['--gate-native']);
      expect(code, GateExit.gateFailed);
      expect(output, contains('GATE FAILED'));
      expect(output, contains('native nativePssKb: monotonicGrowth (FAIL)'));
      // A flat native column reads ok, never a fabricated fail.
      expect(output, contains('native threads: plateau (ok)'));
    });

    test(
      'the same growth does NOT fail without --gate-native (opt-in)',
      () async {
        final run = runDoc(
          series: gatedSeries(),
          nativeTimeline: nativeTimeline(growing: {TriageColumn.nativePssKb}),
        );
        final (code, output) = await runNative(run, const []);
        expect(code, GateExit.ok);
        expect(output, contains('GATE PASSED'));
        // Native columns aren't gated, so no native line is emitted.
        expect(output, isNot(contains('native nativePssKb')));
      },
    );

    test('a not-measured native column never fails --gate-native', () async {
      final run = runDoc(
        series: gatedSeries(),
        nativeTimeline: nativeTimeline(short: {TriageColumn.nativePssKb}),
      );
      final (code, output) = await runNative(run, ['--gate-native']);
      expect(code, GateExit.ok);
      expect(output, contains('GATE PASSED'));
      expect(
        output,
        contains('native nativePssKb: insufficientData (not measured)'),
      );
    });

    test('--gate-native with no native lane refuses (exit 2, never silent '
        'pass)', () async {
      final run = runDoc(series: gatedSeries());
      final (code, output) = await runNative(run, ['--gate-native']);
      expect(code, GateExit.toolFailure);
      expect(output, contains('⛔ gate not evaluated'));
      expect(output, contains('no native lane'));
      expect(output, isNot(contains('GATE PASSED')));
    });
  });

  group('evaluateVerdictGate (pure)', () {
    test('growth alone fails; no baseline needed', () {
      final result = evaluateVerdictGate(
        series: [
          SeriesGateOutcome(
            name: 'dart.heap.used',
            series: null,
            assessment: fake(SeriesVerdict.monotonicGrowth),
          ),
        ],
      );
      expect(result.passed, isFalse);
      expect(result.growthSignals, contains('dart.heap.used'));
    });

    test('a comparable baseline with only known clusters passes', () {
      final current = analysis(
        clusters: [
          cluster(signature: 'a>b', className: 'Leaky', package: 'my_app'),
        ],
      );
      final baseline = LeakBaseline.fromResult(
        current,
        createdAt: DateTime.utc(2026),
      );
      final result = evaluateVerdictGate(
        series: const [],
        analysis: current,
        comparison: compareToBaseline(current, baseline),
      );
      expect(result.passed, isTrue);
      expect(result.newProjectClusters, isEmpty);
      expect(result.baselineCompared, isTrue);
    });
  });
}
