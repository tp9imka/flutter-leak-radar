import 'package:radar_native/radar_native.dart';
import 'package:radar_trace/radar_trace.dart';
import 'package:test/test.dart';

MetricSeries series(String name, String unit, {int n = 4}) => MetricSeries(
  name: name,
  unit: unit,
  samples: [
    for (var i = 0; i < n; i++)
      MetricSample(tMicros: i * 1000000, value: i.toDouble()),
  ],
  gaps: const [
    SeriesGap(startMicros: 500000, endMicros: 700000, reason: 'test gap'),
  ],
);

void main() {
  group('TriageMark', () {
    test('JSON round-trips', () {
      const mark = TriageMark(tMicros: 42, label: 'reconnect');
      final back = TriageMark.fromJson(mark.toJson());
      expect(back, mark);
      expect(back.tMicros, 42);
      expect(back.label, 'reconnect');
    });

    test('value equality', () {
      expect(
        const TriageMark(tMicros: 1, label: 'a'),
        const TriageMark(tMicros: 1, label: 'a'),
      );
      expect(
        const TriageMark(tMicros: 1, label: 'a'),
        isNot(const TriageMark(tMicros: 2, label: 'a')),
      );
    });
  });

  group('TriageTimeline', () {
    test('JSON round-trips columns + marks', () {
      final timeline = TriageTimeline(
        columns: {
          TriageColumn.javaHeapKb: series('java', 'kb'),
          TriageColumn.threads: series('threads', 'count'),
        },
        marks: const [TriageMark(tMicros: 10, label: 'start')],
      );
      final back = TriageTimeline.fromJson(timeline.toJson());
      expect(back.columns.keys, unorderedEquals(timeline.columns.keys));
      expect(back.marks, timeline.marks);
      expect(
        back.columns[TriageColumn.javaHeapKb]!.samples,
        timeline.columns[TriageColumn.javaHeapKb]!.samples,
      );
      expect(back.columns[TriageColumn.threads]!.unit, 'count');
    });

    test('carries schemaVersion 1', () {
      const timeline = TriageTimeline();
      expect(timeline.toJson()['schemaVersion'], 1);
      expect(TriageTimeline.schemaVersion, 1);
    });

    test('an absent column key means never measured — round-trip preserves '
        'absence (never fabricated as an empty series)', () {
      final timeline = TriageTimeline(
        columns: {TriageColumn.javaHeapKb: series('java', 'kb')},
      );
      final back = TriageTimeline.fromJson(timeline.toJson());
      expect(back.columns.containsKey(TriageColumn.javaHeapKb), isTrue);
      expect(back.columns.containsKey(TriageColumn.graphicsKb), isFalse);
      expect(back.columns.length, 1);
    });

    test('preserves declared gaps through the round-trip', () {
      final timeline = TriageTimeline(
        columns: {TriageColumn.nativePssKb: series('native', 'kb')},
      );
      final back = TriageTimeline.fromJson(timeline.toJson());
      expect(
        back.columns[TriageColumn.nativePssKb]!.gaps.single.reason,
        'test gap',
      );
    });

    test('fromJson throws on an unknown column name', () {
      expect(
        () => TriageTimeline.fromJson({
          'schemaVersion': 1,
          'columns': {'notAColumn': series('x', 'kb').toJson()},
          'marks': const <Object?>[],
        }),
        throwsFormatException,
      );
    });

    test('fromJson throws on an unsupported (newer) schemaVersion', () {
      expect(
        () => TriageTimeline.fromJson({
          'schemaVersion': 99,
          'columns': const <String, Object?>{},
        }),
        throwsFormatException,
      );
    });

    test('fromJson tolerates absent columns/marks as empty', () {
      final back = TriageTimeline.fromJson(const {'schemaVersion': 1});
      expect(back.columns, isEmpty);
      expect(back.marks, isEmpty);
    });
  });
}
