import 'package:radar_trace/radar_trace.dart';
import 'package:test/test.dart';

void main() {
  group('SpanKeyStatsSnapshot.toJson', () {
    late SpanKeyStats stats;

    setUp(() {
      stats = SpanKeyStats(
        key: const TraceKey(name: 'db.query', category: 'db'),
        outlierCapacity: 10,
      );
    });

    test('empty stats produces correct zero-value shape', () {
      final json = stats.snapshot().toJson();

      expect(json['name'], equals('db.query'));
      expect(json['category'], equals('db'));
      expect(json['count'], equals(0));
      expect(json['meanMicros'], equals(0));
      expect(json['maxMicros'], equals(0));
      expect(json['totalMicros'], equals(0));
      expect(json['p50'], isNull);
      expect(json['p95'], isNull);
      expect(json['p99'], isNull);
      expect(json['avgInterCallIntervalMicros'], isNull);
      expect(json['callsPerSecond'], isNull);
      expect(json['errorCount'], equals(0));
      expect(json['firstStartMicros'], equals(0));
      expect(json['lastStartMicros'], equals(0));
    });

    test('null category is serialised as null', () {
      final noCategory = SpanKeyStats(
        key: const TraceKey(name: 'startup', category: null),
        outlierCapacity: 5,
      );
      final json = noCategory.snapshot().toJson();

      expect(json['category'], isNull);
      expect(json['name'], equals('startup'));
    });

    test('percentiles p50/p95/p99 are present after recording spans', () {
      for (var i = 0; i < 100; i++) {
        stats.record(
          Span(
            spanId: SpanId.generate(),
            parentId: null,
            traceId: SpanId.generate(),
            name: 'db.query',
            category: 'db',
            startMicros: i * 1000,
            durationMicros: (i + 1) * 100,
            status: SpanStatus.ok,
            attributes: const {},
          ),
        );
      }
      final json = stats.snapshot().toJson();

      expect(json['p50'], isNotNull);
      expect(json['p95'], isNotNull);
      expect(json['p99'], isNotNull);
      // p99 >= p95 >= p50 (honest histogram ordering)
      expect(
        (json['p99'] as int) >= (json['p95'] as int),
        isTrue,
        reason: 'p99 must be >= p95',
      );
      expect(
        (json['p95'] as int) >= (json['p50'] as int),
        isTrue,
        reason: 'p95 must be >= p50',
      );
    });

    test('count, errorCount, meanMicros, totalMicros are accurate', () {
      final okSpan = Span(
        spanId: SpanId.generate(),
        parentId: null,
        traceId: SpanId.generate(),
        name: 'db.query',
        category: 'db',
        startMicros: 1000,
        durationMicros: 2000,
        status: SpanStatus.ok,
        attributes: const {},
      );
      final errSpan = Span(
        spanId: SpanId.generate(),
        parentId: null,
        traceId: SpanId.generate(),
        name: 'db.query',
        category: 'db',
        startMicros: 2000,
        durationMicros: 1000,
        status: SpanStatus.error,
        attributes: const {},
      );
      stats.record(okSpan);
      stats.record(errSpan);

      final json = stats.snapshot().toJson();

      expect(json['count'], equals(2));
      expect(json['errorCount'], equals(1));
      expect(json['totalMicros'], equals(3000));
      expect(json['meanMicros'], equals(1500));
      expect(json['firstStartMicros'], equals(1000));
      expect(json['lastStartMicros'], equals(2000));
      expect(json['avgInterCallIntervalMicros'], equals(1000));
      expect(json['callsPerSecond'], isNotNull);
    });

    test('maxMicros reflects the slowest span', () {
      for (final duration in [500, 1000, 3000, 200]) {
        stats.record(
          Span(
            spanId: SpanId.generate(),
            parentId: null,
            traceId: SpanId.generate(),
            name: 'db.query',
            category: 'db',
            startMicros: duration,
            durationMicros: duration,
            status: SpanStatus.ok,
            attributes: const {},
          ),
        );
      }
      final json = stats.snapshot().toJson();

      expect(json['maxMicros'], equals(3000));
    });

    test('toJson produces only JSON-encodable types', () {
      stats.record(
        Span(
          spanId: SpanId.generate(),
          parentId: null,
          traceId: SpanId.generate(),
          name: 'db.query',
          category: 'db',
          startMicros: 1000,
          durationMicros: 500,
          status: SpanStatus.ok,
          attributes: const {},
        ),
      );
      final json = stats.snapshot().toJson();

      // Verifies no Dart-specific types sneak through.
      for (final entry in json.entries) {
        final v = entry.value;
        expect(
          v == null || v is int || v is double || v is String || v is bool,
          isTrue,
          reason: 'field "${entry.key}" has non-JSON type ${v.runtimeType}',
        );
      }
    });
  });

  group('TraceSnapshot.toJson', () {
    test('empty snapshot produces correct shape', () {
      final snap = TraceSnapshot(stats: const {}, totalDropCount: 0);
      final json = snap.toJson();

      expect(json['totalDropCount'], equals(0));
      expect(json['keys'], isEmpty);
    });

    test('totalDropCount is forwarded', () {
      final snap = TraceSnapshot(stats: const {}, totalDropCount: 7);
      final json = snap.toJson();

      expect(json['totalDropCount'], equals(7));
    });

    test('keys list contains one entry per recorded key', () {
      final keyA = const TraceKey(name: 'op.a', category: 'cat');
      final keyB = const TraceKey(name: 'op.b', category: null);

      SpanKeyStats makeStats(TraceKey k) {
        final s = SpanKeyStats(key: k, outlierCapacity: 5);
        s.record(
          Span(
            spanId: SpanId.generate(),
            parentId: null,
            traceId: SpanId.generate(),
            name: k.name,
            category: k.category,
            startMicros: 1000,
            durationMicros: 200,
            status: SpanStatus.ok,
            attributes: const {},
          ),
        );
        return s;
      }

      final snap = TraceSnapshot(
        stats: {
          keyA: makeStats(keyA).snapshot(),
          keyB: makeStats(keyB).snapshot(),
        },
        totalDropCount: 0,
      );
      final json = snap.toJson();
      final keys = json['keys'] as List;

      expect(keys, hasLength(2));
      final names = keys.map((e) => (e as Map)['name']).toSet();
      expect(names, containsAll(['op.a', 'op.b']));
    });
  });
}
