import 'package:flutter/material.dart';
import 'package:flutter_perf_radar/src/model/stall_record.dart';
import 'package:flutter_perf_radar/src/ui/stall_detail_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_trace/radar_trace.dart';

Span _span(
  String name, {
  required int start,
  required int dur,
  SpanStatus status = SpanStatus.ok,
}) => Span(
  spanId: SpanId.generate(),
  parentId: null,
  traceId: SpanId.generate(),
  name: name,
  category: null,
  startMicros: start,
  durationMicros: dur,
  status: status,
  attributes: const {},
);

void main() {
  // Detected at t=1_000_000µs after a 300ms block → window [700_000, 1_000_000].
  const stall = StallRecord(durationMicros: 300000, clockMicros: 1000000);

  group('spansOverlappingStall', () {
    test('returns spans overlapping the block window, slowest first', () {
      final spans = [
        _span('fast', start: 950000, dur: 5000),
        _span('getConversationRecords', start: 720000, dur: 280000),
        _span('before', start: 100000, dur: 50000), // ends 150k — no overlap
      ];
      final result = spansOverlappingStall(stall, spans);
      expect(result.map((s) => s.name), ['getConversationRecords', 'fast']);
    });

    test('excludes spans entirely before or after the window', () {
      final spans = [
        _span('after', start: 1000000, dur: 10000), // starts at blockEnd
        _span('before', start: 690000, dur: 5000), // ends 695k < blockStart
      ];
      expect(spansOverlappingStall(stall, spans), isEmpty);
    });
  });

  group('StallDetailScreen', () {
    testWidgets('lists the overlapping operations', (tester) async {
      final spans = [
        _span('getConversationRecords', start: 720000, dur: 280000),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: StallDetailScreen(stall: stall, candidateSpans: spans),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('getConversationRecords'), findsOneWidget);
      expect(find.textContaining('Overlapping operations'), findsOneWidget);
    });

    testWidgets('shows an honest empty state when nothing overlaps', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: StallDetailScreen(stall: stall)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining("wasn't traced"), findsOneWidget);
    });
  });
}
