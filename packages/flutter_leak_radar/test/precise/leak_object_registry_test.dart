// test/precise/leak_object_registry_test.dart
import 'package:flutter_leak_radar/src/model/leak_kind.dart';
import 'package:flutter_leak_radar/src/precise/force_gc.dart';
import 'package:flutter_leak_radar/src/precise/gc_support.dart';
import 'package:flutter_leak_radar/src/precise/leak_object_registry.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeGc implements GcCounter {
  int value = 0;
  @override
  int get currentGcCount => value;
}

void main() {
  test('disposed object still alive after N GC cycles -> notGced', () {
    final gc = FakeGc();
    final reg = LeakObjectRegistry(
      gcCounter: gc,
      disposalGrace: Duration.zero,
      clock: () => DateTime(2026),
    );
    final obj = Object();
    reg.track(obj, tag: 'Thing');
    reg.markDisposed(obj);
    gc.value += 3;
    final leaks = reg.collectLeaks(
      gcCycles: 3,
      now: DateTime(2026).add(const Duration(seconds: 10)),
    );
    expect(leaks.single.kind, LeakKind.notGced);
    expect(leaks.single.tag, 'Thing');
    expect(leaks.single.severity, LeakSeverity.critical);
  });

  test('disposed but not enough GC cycles -> no leak yet', () {
    final gc = FakeGc();
    final reg = LeakObjectRegistry(
      gcCounter: gc,
      disposalGrace: Duration.zero,
      clock: () => DateTime(2026),
    );
    final obj = Object();
    reg.track(obj, tag: 'Thing');
    reg.markDisposed(obj);
    gc.value += 1;
    expect(reg.collectLeaks(gcCycles: 3, now: DateTime(2026)), isEmpty);
  });

  test('markDisposed on an untracked object is a silent no-op', () {
    final reg = LeakObjectRegistry(gcCounter: FakeGc());
    reg.markDisposed(Object()); // must not throw
    expect(reg.trackedCount, 0);
  });

  test('clear empties the registry', () {
    final reg = LeakObjectRegistry(gcCounter: FakeGc());
    reg.track(Object(), tag: 'A');
    expect(reg.trackedCount, 1);
    reg.clear();
    expect(reg.trackedCount, 0);
  });

  test(
    'aggregates leaked instances of one class+tag into a single finding',
    () {
      final gc = FakeGc();
      final reg = LeakObjectRegistry(
        gcCounter: gc,
        disposalGrace: Duration.zero,
        clock: () => DateTime(2026),
      );
      for (final o in [Object(), Object(), Object()]) {
        reg.track(o, tag: 'LeakyScreen');
        reg.markDisposed(o);
      }
      gc.value += 3;
      final leaks = reg.collectLeaks(
        gcCycles: 3,
        now: DateTime(2026).add(const Duration(seconds: 10)),
      );
      expect(leaks, hasLength(1));
      expect(leaks.single.liveCount, 3);
      expect(leaks.single.tag, 'LeakyScreen');
      expect(leaks.single.kind, LeakKind.notGced);
    },
  );

  test('distinct tags produce separate aggregated findings', () {
    final gc = FakeGc();
    final reg = LeakObjectRegistry(
      gcCounter: gc,
      disposalGrace: Duration.zero,
      clock: () => DateTime(2026),
    );
    final a1 = Object(), a2 = Object(), b1 = Object();
    reg
      ..track(a1, tag: 'A')
      ..markDisposed(a1)
      ..track(a2, tag: 'A')
      ..markDisposed(a2)
      ..track(b1, tag: 'B')
      ..markDisposed(b1);
    gc.value += 3;
    final leaks = reg.collectLeaks(
      gcCycles: 3,
      now: DateTime(2026).add(const Duration(seconds: 10)),
    );
    expect(leaks, hasLength(2));
    final byTag = {for (final l in leaks) l.tag: l.liveCount};
    expect(byTag['A'], 2);
    expect(byTag['B'], 1);
  });

  group('notDisposed — Finalizer-based detection', () {
    test(
      'GCed without markDisposed -> notDisposed finding',
      () async {
        final reg = LeakObjectRegistry(disposalGrace: Duration.zero);
        // Track and immediately release — do not hold a strong reference.
        reg.track(Object(), tag: 'LeakyWidget');
        await forceGc(fullGcCycles: 3);
        final leaks = reg.collectLeaks();
        final notDisposed = leaks
            .where((l) => l.kind == LeakKind.notDisposed)
            .toList();
        expect(notDisposed, hasLength(1));
        expect(notDisposed.single.tag, 'LeakyWidget');
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'properly disposed object not reported as notDisposed',
      () async {
        final reg = LeakObjectRegistry(disposalGrace: Duration.zero);
        final obj = Object();
        reg.track(obj, tag: 'GoodWidget');
        reg.markDisposed(obj);
        // obj still in scope — but even if GCed, disposedGc is set.
        await forceGc(fullGcCycles: 3);
        final leaks = reg.collectLeaks();
        final notDisposed = leaks
            .where((l) => l.kind == LeakKind.notDisposed)
            .toList();
        expect(notDisposed, isEmpty);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'notDisposed findings accumulate before collectLeaks drains them',
      () async {
        final reg = LeakObjectRegistry(disposalGrace: Duration.zero);
        // Track two objects with same tag, never dispose — let them GC.
        reg.track(Object(), tag: 'LeakyScreen');
        reg.track(Object(), tag: 'LeakyScreen');
        await forceGc(fullGcCycles: 3);
        final leaks = reg.collectLeaks();
        final notDisposed = leaks
            .where((l) => l.kind == LeakKind.notDisposed)
            .toList();
        expect(notDisposed, hasLength(1));
        expect(notDisposed.single.liveCount, 2);
        expect(notDisposed.single.tag, 'LeakyScreen');
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test('clear also resets pending notDisposed list', () async {
      final reg = LeakObjectRegistry(disposalGrace: Duration.zero);
      reg.track(Object(), tag: 'Forgotten');
      await forceGc(fullGcCycles: 3);
      // Drain any pending findings, then clear.
      reg.collectLeaks();
      reg.clear();
      // A second collectLeaks after clear should return nothing.
      expect(reg.collectLeaks(), isEmpty);
    });
  });

  group('disposalGrace — wall-clock enforcement', () {
    test('not reported as leak while within grace period', () {
      final gc = FakeGc();
      final baseTime = DateTime(2026);
      final reg = LeakObjectRegistry(
        gcCounter: gc,
        disposalGrace: const Duration(seconds: 5),
        clock: () => baseTime,
      );
      final obj = Object();
      reg.track(obj, tag: 'Widget');
      reg.markDisposed(obj);
      gc.value += 3;
      final leaks = reg.collectLeaks(
        gcCycles: 3,
        now: baseTime.add(const Duration(seconds: 3)),
      );
      expect(leaks, isEmpty);
    });

    test('reported as notGced once past grace period', () {
      final gc = FakeGc();
      final baseTime = DateTime(2026);
      final reg = LeakObjectRegistry(
        gcCounter: gc,
        disposalGrace: const Duration(seconds: 5),
        clock: () => baseTime,
      );
      final obj = Object();
      reg.track(obj, tag: 'Widget');
      reg.markDisposed(obj);
      gc.value += 3;
      final leaks = reg.collectLeaks(
        gcCycles: 3,
        now: baseTime.add(const Duration(seconds: 5)),
      );
      expect(leaks.single.kind, LeakKind.notGced);
    });

    test('both GC cycles and grace must be satisfied', () {
      final gc = FakeGc();
      final baseTime = DateTime(2026);
      final reg = LeakObjectRegistry(
        gcCounter: gc,
        disposalGrace: const Duration(seconds: 2),
        clock: () => baseTime,
      );
      final obj = Object();
      reg.track(obj, tag: 'Widget');
      reg.markDisposed(obj);

      // Enough time elapsed but not enough GC cycles.
      gc.value += 1;
      expect(
        reg.collectLeaks(
          gcCycles: 3,
          now: baseTime.add(const Duration(seconds: 5)),
        ),
        isEmpty,
      );

      // Enough GC cycles but not enough time elapsed.
      gc.value += 2;
      expect(
        reg.collectLeaks(
          gcCycles: 3,
          now: baseTime.add(const Duration(seconds: 1)),
        ),
        isEmpty,
      );

      // Both satisfied — leak must be reported.
      expect(
        reg.collectLeaks(
          gcCycles: 3,
          now: baseTime.add(const Duration(seconds: 5)),
        ),
        hasLength(1),
      );
    });
  });
}
