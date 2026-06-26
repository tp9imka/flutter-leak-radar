import 'package:radar_trace/radar_trace.dart';
import 'package:test/test.dart';

void main() {
  group('SpanId', () {
    test('generate produces unique ids', () {
      final a = SpanId.generate();
      final b = SpanId.generate();
      expect(a, isNot(equals(b)));
    });

    test('equality and hashCode are value-based', () {
      const id = SpanId(42);
      expect(id, equals(const SpanId(42)));
      expect(id.hashCode, equals(const SpanId(42).hashCode));
    });
  });

  group('Span', () {
    test(
      'constructs with required fields and defensively copies attributes',
      () {
        final attrs = {'key': 'value'};
        final span = Span(
          spanId: SpanId.generate(),
          parentId: null,
          traceId: SpanId.generate(),
          name: 'test.op',
          category: 'db',
          startMicros: 1000,
          durationMicros: 500,
          status: SpanStatus.ok,
          attributes: attrs,
        );

        attrs['injected'] = 'bad';
        expect(span.attributes.containsKey('injected'), isFalse);
        expect(span.attributes['key'], 'value');
      },
    );

    test('attributes map is unmodifiable', () {
      final span = Span(
        spanId: SpanId.generate(),
        parentId: null,
        traceId: SpanId.generate(),
        name: 'op',
        category: null,
        startMicros: 0,
        durationMicros: 0,
        status: SpanStatus.ok,
        attributes: const {},
      );
      expect(() => span.attributes['x'] = 1, throwsUnsupportedError);
    });

    test('equality is value-based across all fields', () {
      final id = SpanId.generate();
      final traceId = SpanId.generate();
      final s1 = Span(
        spanId: id,
        parentId: null,
        traceId: traceId,
        name: 'op',
        category: null,
        startMicros: 100,
        durationMicros: 50,
        status: SpanStatus.ok,
        attributes: const {},
      );
      final s2 = Span(
        spanId: id,
        parentId: null,
        traceId: traceId,
        name: 'op',
        category: null,
        startMicros: 100,
        durationMicros: 50,
        status: SpanStatus.ok,
        attributes: const {},
      );
      expect(s1, equals(s2));
      expect(s1.hashCode, equals(s2.hashCode));
    });

    test('copyWith overrides only specified fields', () {
      final original = Span(
        spanId: SpanId.generate(),
        parentId: null,
        traceId: SpanId.generate(),
        name: 'op',
        category: null,
        startMicros: 100,
        durationMicros: 50,
        status: SpanStatus.ok,
        attributes: const {},
      );
      final copy = original.copyWith(
        status: SpanStatus.error,
        durationMicros: 200,
      );
      expect(copy.status, SpanStatus.error);
      expect(copy.durationMicros, 200);
      expect(copy.name, original.name);
      expect(copy.spanId, original.spanId);
    });

    test('copyWith can clear parentId to null', () {
      final parentSpanId = SpanId.generate();
      final original = Span(
        spanId: SpanId.generate(),
        parentId: parentSpanId,
        traceId: SpanId.generate(),
        name: 'child',
        category: null,
        startMicros: 100,
        durationMicros: 50,
        status: SpanStatus.ok,
        attributes: const {},
      );

      expect(original.parentId, equals(parentSpanId));

      final cleared = original.copyWith(parentId: null);
      expect(cleared.parentId, isNull);
      expect(cleared.spanId, original.spanId);
    });

    test('attributes hashCode is stable regardless of insertion order', () {
      final attrs1 = <String, Object?>{
        'a': 'value_a',
        'b': 'value_b',
        'c': 'value_c',
      };
      final span1 = Span(
        spanId: SpanId.generate(),
        parentId: null,
        traceId: SpanId.generate(),
        name: 'op',
        category: null,
        startMicros: 100,
        durationMicros: 50,
        status: SpanStatus.ok,
        attributes: attrs1,
      );

      // Create second map with different insertion order
      final attrs2 = <String, Object?>{
        'c': 'value_c',
        'a': 'value_a',
        'b': 'value_b',
      };
      final span2 = Span(
        spanId: span1.spanId,
        parentId: null,
        traceId: span1.traceId,
        name: 'op',
        category: null,
        startMicros: 100,
        durationMicros: 50,
        status: SpanStatus.ok,
        attributes: attrs2,
      );

      expect(span1, equals(span2));
      expect(span1.hashCode, equals(span2.hashCode));
    });
  });

  group('TraceKey', () {
    test('equality treats (name, category) as identity', () {
      const a = TraceKey(name: 'db.query', category: 'db');
      const b = TraceKey(name: 'db.query', category: 'db');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('null category differs from non-null', () {
      const a = TraceKey(name: 'op', category: null);
      const b = TraceKey(name: 'op', category: 'http');
      expect(a, isNot(equals(b)));
    });
  });
}
