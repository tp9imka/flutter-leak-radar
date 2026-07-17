import 'dart:convert';

import 'package:leak_graph/leak_graph.dart';
import 'package:radar_ci/radar_ci.dart';
import 'package:radar_ci/radar_ci_io.dart';
import 'package:radar_trace/radar_trace.dart';
import 'package:test/test.dart';

import '../support/fixtures.dart';

List<MetricSeries> gatedSeries() => [
  for (final name in kGatedSignals)
    MetricSeries(
      name: name,
      unit: 'bytes',
      samples: const [MetricSample(tMicros: 0, value: 1)],
    ),
];

SeriesAssessment fake(SeriesVerdict verdict) => SeriesAssessment(
  verdict: verdict,
  slopePerHour: verdict == SeriesVerdict.monotonicGrowth ? 5000000.0 : null,
  batchDeltaPerHour: null,
  samplesAssessed: 15,
  samplesTotal: 18,
  detail: 'fake ${verdict.name}',
);

SeriesAssessment Function(MetricSeries) assessAs(
  Map<String, SeriesVerdict> byName,
) =>
    (series) => fake(byName[series.name] ?? SeriesVerdict.plateau);

void main() {
  group('runReport — markdown', () {
    test(
      'emits overall verdict, series table before details, clusters',
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
          'end.analysis.json': jsonEncode(current.toJson()),
        });
        final out = StringBuffer();
        final code = await runReport(
          ['run.json', '--format', 'md'],
          out: out,
          err: StringBuffer(),
          readText: files.read,
          assess: assessAs(const {}),
        );
        expect(code, ReportExit.ok);
        final text = out.toString();
        // 30-second contract: overall verdict is line 1.
        expect(text.split('\n').first, contains('overall:'));
        // Series table appears before any folded <details>.
        final seriesIdx = text.indexOf('### Memory series');
        final detailsIdx = text.indexOf('<details>');
        expect(seriesIdx, greaterThanOrEqualTo(0));
        expect(detailsIdx, greaterThanOrEqualTo(0));
        expect(seriesIdx, lessThan(detailsIdx));
        // Reuses the leak_graph renderer (features the project cluster).
        expect(text, contains('Leaky'));
        expect(text, contains('| dart.heap.used |'));
      },
    );

    test('overall verdict is FAIL when a gated signal grows', () async {
      final current = analysis(clusters: const []);
      final files = InMemoryFiles({
        'run.json': jsonEncode(
          runDoc(
            series: gatedSeries(),
            analysisPath: 'end.analysis.json',
          ).toJson(),
        ),
        'end.analysis.json': jsonEncode(current.toJson()),
      });
      final out = StringBuffer();
      await runReport(
        ['run.json'],
        out: out,
        err: StringBuffer(),
        readText: files.read,
        assess: assessAs({'process.rss': SeriesVerdict.monotonicGrowth}),
      );
      expect(out.toString().split('\n').first, contains('FAIL'));
      expect(out.toString(), contains('process.rss'));
    });

    test('degrades honestly when the run has no heap analysis', () async {
      final files = InMemoryFiles({
        'run.json': jsonEncode(runDoc(series: gatedSeries()).toJson()),
      });
      final out = StringBuffer();
      final code = await runReport(
        ['run.json'],
        out: out,
        err: StringBuffer(),
        readText: files.read,
        assess: assessAs(const {}),
      );
      expect(code, ReportExit.ok);
      expect(out.toString(), contains('no heap analysis'));
      expect(out.toString(), contains('### Memory series'));
    });

    test('an incomparable baseline degrades to a note (exit 0)', () async {
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
        'end.analysis.json': jsonEncode(current.toJson()),
        'base.json': jsonEncode(<String, Object?>{
          'schemaVersion': 999,
          'createdAt': DateTime.utc(2026).toIso8601String(),
          'clusters': const <Object?>[],
        }),
      });
      final out = StringBuffer();
      final code = await runReport(
        ['run.json', '--baseline', 'base.json'],
        out: out,
        err: StringBuffer(),
        readText: files.read,
        assess: assessAs(const {}),
      );
      // The report renders (never all-NEW); the gate verb is the enforcer.
      expect(code, ReportExit.ok);
      expect(out.toString(), contains('not comparable'));
      expect(out.toString(), isNot(contains('🆕')));
    });

    test('--out writes the report to a file', () async {
      final files = InMemoryFiles({
        'run.json': jsonEncode(runDoc(series: gatedSeries()).toJson()),
      });
      final code = await runReport(
        ['run.json', '--out', 'report.md'],
        out: StringBuffer(),
        err: StringBuffer(),
        readText: files.read,
        writeText: files.write,
        assess: assessAs(const {}),
      );
      expect(code, ReportExit.ok);
      expect(files.store['report.md'], contains('overall:'));
    });
  });

  group('runReport — json envelope', () {
    test('round-trips the run document and assessments', () async {
      final run = runDoc(series: gatedSeries());
      final files = InMemoryFiles({'run.json': jsonEncode(run.toJson())});
      final out = StringBuffer();
      final code = await runReport(
        ['run.json', '--format', 'json'],
        out: out,
        err: StringBuffer(),
        readText: files.read,
        assess: assessAs({'dart.heap.used': SeriesVerdict.plateau}),
      );
      expect(code, ReportExit.ok);
      final env = jsonDecode(out.toString()) as Map<String, Object?>;
      expect(env['schemaVersion'], 1);

      final rt = RadarRunDocument.fromJson(
        (env['run']! as Map).cast<String, Object?>(),
      );
      expect(rt.series.map((s) => s.name), containsAll(kGatedSignals));

      final assessments = (env['assessments']! as Map).cast<String, Object?>();
      final heap = SeriesAssessment.fromJson(
        (assessments['dart.heap.used']! as Map).cast<String, Object?>(),
      );
      expect(heap.verdict, SeriesVerdict.plateau);

      final gate = (env['gate']! as Map).cast<String, Object?>();
      expect(gate['passed'], isTrue);
    });

    test('json envelope carries comparison when a baseline is given', () async {
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
        'end.analysis.json': jsonEncode(current.toJson()),
        'base.json': jsonEncode(
          LeakBaseline.fromResult(
            analysis(clusters: const []),
            createdAt: DateTime.utc(2026),
          ).toJson(),
        ),
      });
      final out = StringBuffer();
      await runReport(
        ['run.json', '--baseline', 'base.json', '--format', 'json'],
        out: out,
        err: StringBuffer(),
        readText: files.read,
        assess: assessAs(const {}),
      );
      final env = jsonDecode(out.toString()) as Map<String, Object?>;
      final comparison = (env['comparison']! as Map).cast<String, Object?>();
      expect(comparison['baselineComparable'], isTrue);
      final gate = (env['gate']! as Map).cast<String, Object?>();
      expect(gate['newProjectAnchorClusterCount'], 1);
      expect(gate['passed'], isFalse);
    });
  });
}
