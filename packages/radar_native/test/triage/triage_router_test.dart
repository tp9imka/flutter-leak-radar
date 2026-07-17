import 'package:radar_native/radar_native.dart';
import 'package:radar_trace/radar_trace.dart';
import 'package:test/test.dart';

/// A clean linear ramp long enough to clear the 30s settle trim and earn a
/// growth verdict (>= ~12 assessed samples). [perStep] sets the slope:
/// slopePerHour == perStep * 720 for a 5s step.
MetricSeries ramp(
  String unit, {
  required double perStep,
  double start = 1000,
  int n = 60,
  int stepSec = 5,
}) => MetricSeries(
  name: unit,
  unit: unit,
  samples: [
    for (var i = 0; i < n; i++)
      MetricSample(tMicros: i * stepSec * 1000000, value: start + perStep * i),
  ],
);

/// A flat series (bounded plateau — not a leak).
MetricSeries flat(String unit) => ramp(unit, perStep: 0);

/// Too few samples to assess honestly -> insufficientData.
MetricSeries tiny(String unit) => MetricSeries(
  name: unit,
  unit: unit,
  samples: const [
    MetricSample(tMicros: 0, value: 1),
    MetricSample(tMicros: 40000000, value: 2),
    MetricSample(tMicros: 80000000, value: 3),
  ],
);

TriageVerdict triageOf(Map<TriageColumn, MetricSeries> columns) =>
    triage(TriageTimeline(columns: columns));

void main() {
  group('per-column assessment passthrough', () {
    test('assesses every measured column, matching assessSeries directly', () {
      final javaSeries = ramp('kb', perStep: 2);
      final verdict = triageOf({TriageColumn.javaHeapKb: javaSeries});
      expect(verdict.assessments, hasLength(1));
      final only = verdict.assessments.single;
      expect(only.column, TriageColumn.javaHeapKb);
      expect(only.assessment, assessSeries(javaSeries));
      expect(only.assessment.verdict, SeriesVerdict.monotonicGrowth);
    });

    test('assessments are ordered by TriageColumn declaration order', () {
      final verdict = triageOf({
        TriageColumn.threads: ramp('count', perStep: 1),
        TriageColumn.javaHeapKb: ramp('kb', perStep: 1),
      });
      expect(verdict.assessments.map((a) => a.column), [
        TriageColumn.javaHeapKb,
        TriageColumn.threads,
      ]);
    });
  });

  group('bucket routing', () {
    test('picks the dominant bytes bucket and names other growing buckets', () {
      final verdict = triageOf({
        TriageColumn.nativePssKb: ramp('kb', perStep: 4),
        TriageColumn.graphicsKb: ramp('kb', perStep: 1),
      });
      expect(verdict.bucket, TriageBucket.nativeMalloc);
      expect(verdict.summary, contains('nativeMalloc'));
      expect(verdict.summary, contains('graphics'));
    });

    test('rssAnonKb routes to nativeMalloc', () {
      final verdict = triageOf({
        TriageColumn.rssAnonKb: ramp('kb', perStep: 3),
      });
      expect(verdict.bucket, TriageBucket.nativeMalloc);
    });

    test('gfxBufferCount routes to graphics', () {
      final verdict = triageOf({
        TriageColumn.gfxBufferCount: ramp('count', perStep: 2),
      });
      expect(verdict.bucket, TriageBucket.graphics);
    });

    test('fdDmabuf routes to fd', () {
      final verdict = triageOf({
        TriageColumn.fdDmabuf: ramp('count', perStep: 2),
      });
      expect(verdict.bucket, TriageBucket.fd);
    });
  });

  group('count growth is named alongside a bytes primary', () {
    test('bytes bucket is primary; count growth is named in the summary', () {
      final verdict = triageOf({
        TriageColumn.nativePssKb: ramp('kb', perStep: 4),
        TriageColumn.threads: ramp('count', perStep: 2),
      });
      expect(verdict.bucket, TriageBucket.nativeMalloc);
      expect(verdict.summary, contains('thread'));
    });

    test('a numerically larger COUNT slope never outranks a bytes bucket for '
        'primary (families are never cross-compared)', () {
      // threads slope 720/h numerically dwarfs nativePss 72 kb/h, but bytes
      // must still win primary.
      final verdict = triageOf({
        TriageColumn.nativePssKb: ramp('kb', perStep: 0.1),
        TriageColumn.threads: ramp('count', perStep: 1),
      });
      expect(verdict.bucket, TriageBucket.nativeMalloc);
      expect(verdict.summary, contains('thread'));
    });
  });

  group('none verdict', () {
    test('all-flat columns -> none, no bucket named', () {
      final verdict = triageOf({
        TriageColumn.javaHeapKb: flat('kb'),
        TriageColumn.nativePssKb: flat('kb'),
      });
      expect(verdict.bucket, TriageBucket.none);
      expect(verdict.summary, 'no monotonic growth detected');
    });

    test('no columns measured -> none + insufficient-data summary', () {
      final verdict = triage(const TriageTimeline());
      expect(verdict.bucket, TriageBucket.none);
      expect(verdict.assessments, isEmpty);
      expect(verdict.summary, contains('insufficient data'));
    });
  });

  group('not-measured honesty', () {
    test('an absent column is never assessed as flat/zero', () {
      final verdict = triageOf({
        TriageColumn.javaHeapKb: ramp('kb', perStep: 2),
      });
      expect(verdict.assessments, hasLength(1));
      expect(
        verdict.assessments.map((a) => a.column),
        isNot(contains(TriageColumn.graphicsKb)),
      );
      expect(verdict.bucket, TriageBucket.javaHeap);
    });

    test('insufficientData columns are surfaced, never counted as flat', () {
      final verdict = triageOf({
        TriageColumn.javaHeapKb: ramp('kb', perStep: 2),
        TriageColumn.fdTotal: tiny('count'),
      });
      expect(verdict.bucket, TriageBucket.javaHeap);
      final fd = verdict.assessments.firstWhere(
        (a) => a.column == TriageColumn.fdTotal,
      );
      expect(fd.assessment.verdict, SeriesVerdict.insufficientData);
      expect(verdict.summary, contains('insufficient data'));
      expect(verdict.summary, contains('fdTotal'));
    });

    test('all-insufficient -> none + insufficient-data listing (not "no '
        'growth", which would imply the columns were flat)', () {
      final verdict = triageOf({
        TriageColumn.javaHeapKb: tiny('kb'),
        TriageColumn.threads: tiny('count'),
      });
      expect(verdict.bucket, TriageBucket.none);
      expect(verdict.summary, contains('insufficient data'));
      expect(verdict.summary, isNot(contains('no monotonic growth')));
      expect(verdict.summary, contains('javaHeapKb'));
      expect(verdict.summary, contains('threads'));
    });
  });

  group('corroborating columns are never primary', () {
    test('growth visible only in totalPssKb -> none bucket, but the aggregate '
        'growth is surfaced (never silently dropped)', () {
      final verdict = triageOf({
        TriageColumn.totalPssKb: ramp('kb', perStep: 3),
      });
      expect(verdict.bucket, TriageBucket.none);
      expect(verdict.summary, contains('totalPssKb'));
      expect(verdict.summary, isNot(equals('no monotonic growth detected')));
    });

    test('totalPssKb corroborates a real nativeMalloc primary', () {
      final verdict = triageOf({
        TriageColumn.nativePssKb: ramp('kb', perStep: 4),
        TriageColumn.totalPssKb: ramp('kb', perStep: 5),
      });
      expect(verdict.bucket, TriageBucket.nativeMalloc);
      expect(verdict.summary, contains('totalPssKb'));
    });
  });

  group('verdict JSON', () {
    test('toJson carries schemaVersion, bucket, assessments, summary', () {
      final verdict = triageOf({
        TriageColumn.javaHeapKb: ramp('kb', perStep: 2),
      });
      final json = verdict.toJson();
      expect(json['schemaVersion'], 1);
      expect(json['bucket'], 'javaHeap');
      expect(json['summary'], isA<String>());
      expect((json['assessments']! as List), hasLength(1));
    });

    test('TriageColumnAssessment round-trips', () {
      final assessment = TriageColumnAssessment(
        column: TriageColumn.nativePssKb,
        assessment: assessSeries(ramp('kb', perStep: 2)),
      );
      final back = TriageColumnAssessment.fromJson(assessment.toJson());
      expect(back, assessment);
    });
  });
}
