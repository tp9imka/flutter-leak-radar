import 'package:radar_trace/radar_trace.dart';
import 'package:test/test.dart';

void main() {
  group('Tracer.trace — sync', () {
    test('returns body result', () {
      final t = Tracer();
      final result = t.trace('op', () => 42);
      expect(result, 42);
    });

    test('records a span after body completes', () {
      final t = Tracer();
      t.trace('my.op', () => 'x');
      final snap = t.snapshot();
      expect(snap.stats.length, 1);
      final key = TraceKey(name: 'my.op', category: null);
      expect(snap.stats[key]!.count, 1);
    });

    test('records status=error when body throws, and rethrows', () {
      final t = Tracer();
      expect(
        () => t.trace('fail.op', () => throw Exception('boom')),
        throwsA(isA<Exception>()),
      );
      final key = TraceKey(name: 'fail.op', category: null);
      expect(t.snapshot().stats[key]!.errorCount, 1);
    });

    test('still returns result when recorder.record has an issue', () {
      // Use a recorder at maxKeys=1 — record() will be called but drop.
      final rec = TraceRecorder(maxKeys: 1);
      // Fill the single key slot so any new key is dropped.
      rec.record(
        Span(
          spanId: SpanId.generate(),
          parentId: null,
          traceId: SpanId.generate(),
          name: 'blocker',
          category: null,
          startMicros: 0,
          durationMicros: 1,
          status: SpanStatus.ok,
          attributes: const {},
        ),
      );
      final t = Tracer(recorder: rec);
      // This call's key 'new.op' is new; it will be dropped.
      final result = t.trace('new.op', () => 'safe');
      // The host must still get the result.
      expect(result, 'safe');
    });

    test('uses category in TraceKey', () {
      final t = Tracer();
      t.trace('db.query', () {}, category: 'db');
      final key = TraceKey(name: 'db.query', category: 'db');
      expect(t.snapshot().stats[key], isNotNull);
    });
  });

  group('Tracer.traceAsync — async', () {
    test('returns future result', () async {
      final t = Tracer();
      final result = await t.traceAsync('async.op', () async => 'hello');
      expect(result, 'hello');
    });

    test('records span after future completes', () async {
      final t = Tracer();
      await t.traceAsync('async.op', () async {});
      final key = TraceKey(name: 'async.op', category: null);
      expect(t.snapshot().stats[key]!.count, 1);
    });

    test('records status=error when future throws, and rethrows', () async {
      final t = Tracer();
      await expectLater(
        () => t.traceAsync('async.fail', () async => throw Exception('boom')),
        throwsA(isA<Exception>()),
      );
      final key = TraceKey(name: 'async.fail', category: null);
      expect(t.snapshot().stats[key]!.errorCount, 1);
    });
  });

  group('Tracer — Zone-based async nesting', () {
    test('nested sync trace sets parentId correctly', () {
      late Span inner;
      final rec = _CapturingRecorder();
      final t = Tracer(recorder: rec);

      t.trace('outer', () {
        t.trace('inner', () {});
      });

      final outerSpan = rec.spans.firstWhere((s) => s.name == 'outer');
      inner = rec.spans.firstWhere((s) => s.name == 'inner');

      expect(inner.parentId, equals(outerSpan.spanId));
      expect(inner.traceId, equals(outerSpan.traceId));
    });

    test('nested async trace sets parentId across await boundary', () async {
      final rec = _CapturingRecorder();
      final t = Tracer(recorder: rec);

      await t.traceAsync('outer', () async {
        await Future<void>.delayed(Duration.zero);
        await t.traceAsync('inner', () async {});
      });

      final outerSpan = rec.spans.firstWhere((s) => s.name == 'outer');
      final innerSpan = rec.spans.firstWhere((s) => s.name == 'inner');

      expect(innerSpan.parentId, equals(outerSpan.spanId));
      expect(innerSpan.traceId, equals(outerSpan.traceId));
    });

    test(
      'sibling traces are independent children of the same parent',
      () async {
        final rec = _CapturingRecorder();
        final t = Tracer(recorder: rec);

        await t.traceAsync('root', () async {
          await t.traceAsync('child.a', () async {});
          await t.traceAsync('child.b', () async {});
        });

        final root = rec.spans.firstWhere((s) => s.name == 'root');
        final childA = rec.spans.firstWhere((s) => s.name == 'child.a');
        final childB = rec.spans.firstWhere((s) => s.name == 'child.b');

        expect(childA.parentId, equals(root.spanId));
        expect(childB.parentId, equals(root.spanId));
        expect(childA.spanId, isNot(equals(childB.spanId)));
      },
    );

    test('top-level trace has null parentId', () {
      final rec = _CapturingRecorder();
      final t = Tracer(recorder: rec);
      t.trace('root', () {});
      final root = rec.spans.first;
      expect(root.parentId, isNull);
      expect(root.traceId, equals(root.spanId));
    });
  });

  group('Tracer.start — manual span handle', () {
    test('stop() records span with status=ok', () {
      final t = Tracer();
      final handle = t.start('manual.op');
      handle.stop();
      final key = TraceKey(name: 'manual.op', category: null);
      final stats = t.snapshot().stats[key]!;
      expect(stats.count, 1);
      expect(stats.errorCount, 0);
    });

    test('fail() records span with status=error', () {
      final t = Tracer();
      final handle = t.start('manual.op');
      handle.fail(Exception('boom'));
      final key = TraceKey(name: 'manual.op', category: null);
      expect(t.snapshot().stats[key]!.errorCount, 1);
    });

    test('duration is > 0 after some time', () async {
      final rec = _CapturingRecorder();
      final t = Tracer(recorder: rec);
      final handle = t.start('timed.op');
      await Future<void>.delayed(const Duration(milliseconds: 1));
      handle.stop();
      final span = rec.spans.first;
      expect(span.durationMicros, greaterThan(0));
    });
  });

  group('Tracer — disabled recorder (no-op)', () {
    test('trace still returns body result when recorder is disabled', () {
      final t = Tracer(recorder: TraceRecorder(enabled: false));
      expect(t.trace('op', () => 99), 99);
      expect(t.snapshot().stats, isEmpty);
    });

    test('traceAsync still returns body result when disabled', () async {
      final t = Tracer(recorder: TraceRecorder(enabled: false));
      expect(await t.traceAsync('op', () async => 99), 99);
    });
  });

  group('Tracer — monotonic timing', () {
    test('duration is non-negative', () {
      final rec = _CapturingRecorder();
      final t = Tracer(recorder: rec);
      t.trace('op', () {});
      expect(rec.spans.first.durationMicros, greaterThanOrEqualTo(0));
    });

    test('startMicros come from a shared clock — a later span starts later', () {
      final rec = _CapturingRecorder();
      final t = Tracer(recorder: rec);
      t.trace('first', () {
        // Burn ≥100µs of monotonic time inside the first span.
        final spin = Stopwatch()..start();
        while (spin.elapsedMicroseconds < 100) {}
      });
      t.trace('second', () {});
      final first = rec.spans.firstWhere((s) => s.name == 'first');
      final second = rec.spans.firstWhere((s) => s.name == 'second');
      // Pre-fix every span's startMicros was ≈0 (a per-span stopwatch); with the
      // shared clock the second span starts strictly after the first's start.
      expect(second.startMicros, greaterThan(first.startMicros));
    });
  });
}

/// Test helper: extends [TraceRecorder] to capture all recorded spans
/// while delegating actual aggregation to the parent implementation.
final class _CapturingRecorder extends TraceRecorder {
  final spans = <Span>[];

  @override
  void record(Span span) {
    spans.add(span);
    super.record(span);
  }
}
